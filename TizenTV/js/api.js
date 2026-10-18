/* Veylo TV — provider access: Xtream Codes API and M3U playlists.
 * Mirrors the iPhone app: lenient decoding, Uncategorized fallback, get.php → Xtream fallback. */
(function (global) {
  'use strict';

  var TIMEOUT = 30000;

  /** Identities tried when a provider refuses the TV's own browser engine (e.g. HTTP 451 / 884 / 403). */
  var AGENTS = ['VLC/3.0.21 LibVLC/3.0.21', 'IPTVSmartersPro', 'okhttp/4.12.0'];
  /** Hosts known to block the web engine → go straight to the native download path. */
  var blockedHosts = {};
  /** The identity that worked for a blocking provider (also given to the video player). */
  var State = { userAgent: '' };

  function hostKey(url) {
    var match = /^[a-z]+:\/\/([^\/?#]+)/i.exec(url || '');
    return match ? match[1].toLowerCase() : '';
  }

  function isBlockStatus(status) {
    return status === 451 || status === 884 || status === 403 || status === 406 || status === 456 ||
      status === 458 || status === 512 || status === 513 || (status >= 880 && status <= 899);
  }

  function hasNativeDownload() {
    return !!(global.tizen && global.tizen.download && global.tizen.DownloadRequest && global.tizen.filesystem);
  }

  function xhrText(url, timeout) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', url, true);
      xhr.timeout = timeout || TIMEOUT;
      xhr.onload = function () {
        if (xhr.status >= 200 && xhr.status < 300) return resolve(xhr.responseText);
        var error = new Error('HTTP status ' + xhr.status);
        error.status = xhr.status;
        reject(error);
      };
      xhr.onerror = function () {
        var error = new Error('Couldn’t reach the provider. Check the address and your internet.');
        error.status = 0;
        reject(error);
      };
      xhr.ontimeout = function () {
        var error = new Error('The provider took too long to answer.');
        error.status = -1;
        reject(error);
      };
      xhr.send();
    });
  }

  /** Reads a file the Download API saved in the app's private temp folder (text, or bytes when `binary`). */
  function readDownloaded(name, binary) {
    return new Promise(function (resolve, reject) {
      var fs = global.tizen.filesystem;
      var virtualPath = 'wgt-private-tmp/' + name;
      try {
        if (fs.openFile) {
          var handle = fs.openFile(virtualPath, 'r');
          var text = binary ? handle.readData() : handle.readString();
          handle.close();
          try { fs.deleteFile(virtualPath); } catch (e) { /* temp folder is cleaned anyway */ }
          return resolve(text);
        }
      } catch (e) { /* fall back to the older API below */ }
      fs.resolve(virtualPath, function (file) {
        if (binary) {
          file.openStream('r', function (stream) {
            try { var bytes = stream.readBytes(file.fileSize); stream.close(); resolve(new Uint8Array(bytes)); } catch (e) { reject(e); }
          }, function (err) { reject(err); });
          return;
        }
        file.readAsText(function (text) { resolve(text); }, function (err) { reject(err); }, 'UTF-8');
      }, function (err) { reject(err); }, 'r');
    });
  }

  /** Samsung's native downloader: no browser Origin and a chosen User-Agent. */
  function nativeText(url, agent, timeout, binary) {
    return new Promise(function (resolve, reject) {
      var name = 'veylo-' + Date.now() + '-' + Math.floor(Math.random() * 1e6) + '.txt';
      var finished = false;
      var timer = setTimeout(function () {
        if (finished) return;
        finished = true;
        try { global.tizen.download.cancel(id); } catch (e) {}
        reject(new Error('The provider took too long to answer.'));
      }, timeout || 90000);
      var id;
      try {
        var request = new global.tizen.DownloadRequest(url, 'wgt-private-tmp', name, 'ALL',
          { 'User-Agent': agent, 'Accept': '*/*' });
        id = global.tizen.download.start(request, {
          onprogress: function () {},
          onpaused: function () {},
          oncanceled: function () {
            if (finished) return;
            finished = true; clearTimeout(timer);
            reject(new Error('Download cancelled.'));
          },
          oncompleted: function () {
            if (finished) return;
            finished = true; clearTimeout(timer);
            readDownloaded(name, binary).then(resolve, function () { reject(new Error('Couldn’t read the provider’s answer.')); });
          },
          onfailed: function (downloadId, error) {
            if (finished) return;
            finished = true; clearTimeout(timer);
            reject(new Error('Provider refused the request' + (error && error.message ? ' (' + error.message + ')' : '') + '.'));
          }
        });
      } catch (e) {
        finished = true; clearTimeout(timer);
        reject(e);
      }
    });
  }

  /** Native download with each identity in turn until one is accepted. */
  function nativeWithAgents(url, timeout, binary) {
    var agents = State.userAgent ? [State.userAgent].concat(AGENTS.filter(function (a) { return a !== State.userAgent; })) : AGENTS;
    var index = 0;
    function attempt() {
      var agent = agents[index];
      return nativeText(url, agent, timeout, binary).then(function (text) {
        State.userAgent = agent;
        return text;
      }, function (error) {
        index += 1;
        if (index < agents.length) return attempt();
        throw error;
      });
    }
    return attempt();
  }

  /** Web request first; if the provider blocks the TV browser engine, retry natively as a known player. */
  function fetchText(url, timeout) {
    var host = hostKey(url);
    if (blockedHosts[host] && hasNativeDownload()) return nativeWithAgents(url, timeout);
    return xhrText(url, timeout).catch(function (error) {
      if (!isBlockStatus(error.status)) throw error;
      if (!hasNativeDownload()) {
        throw new Error('The provider blocked this TV app (HTTP ' + error.status + ').');
      }
      blockedHosts[host] = true;
      return nativeWithAgents(url, timeout).catch(function () {
        throw new Error('The provider blocked this TV app (HTTP ' + error.status + '), also when retrying as a media player.');
      });
    });
  }

  /** Bytes (for gzipped guides): web request first, native download for blocking providers. */
  function fetchBytes(url, timeout) {
    var host = hostKey(url);
    if (blockedHosts[host] && hasNativeDownload()) return nativeWithAgents(url, timeout, true);
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', url, true);
      xhr.responseType = 'arraybuffer';
      xhr.timeout = timeout || 120000;
      xhr.onload = function () {
        if (xhr.status >= 200 && xhr.status < 300) return resolve(new Uint8Array(xhr.response));
        var error = new Error('HTTP status ' + xhr.status);
        error.status = xhr.status;
        reject(error);
      };
      xhr.onerror = function () { var e = new Error('Couldn’t reach the guide link.'); e.status = 0; reject(e); };
      xhr.ontimeout = function () { var e = new Error('The guide took too long to download.'); e.status = -1; reject(e); };
      xhr.send();
    }).catch(function (error) {
      if (!isBlockStatus(error.status) || !hasNativeDownload()) throw error;
      blockedHosts[host] = true;
      return nativeWithAgents(url, timeout, true);
    });
  }

  function fetchJSON(url) {
    return fetchText(url).then(function (text) {
      try { return JSON.parse(text); } catch (e) { throw new Error('The provider sent an unexpected answer (not JSON).'); }
    });
  }

  function str(value) {
    if (value === null || value === undefined) return '';
    return String(value);
  }

  /** Arrays, or objects keyed by id, both become arrays (some panels send either). */
  function list(value) {
    if (Array.isArray(value)) return value;
    if (value && typeof value === 'object') {
      return Object.keys(value).map(function (k) { return value[k]; });
    }
    return [];
  }

  function trimSlash(url) { return url.replace(/\/+$/, ''); }

  function decodeBase64(text) {
    if (!text) return '';
    try {
      return decodeURIComponent(escape(global.atob(text)));
    } catch (e) {
      try { return global.atob(text); } catch (e2) { return text; }
    }
  }

  function quality(name) {
    var upper = ' ' + name.toUpperCase().replace(/[^A-Z0-9]+/g, ' ') + ' ';
    if (/ (4K|8K|UHD|2160P) /.test(upper)) return '4K';
    if (/ (FHD|1080P) /.test(upper)) return 'FHD';
    if (/ (HD|720P) /.test(upper)) return 'HD';
    return '';
  }

  /** Readable title: drops short tag prefixes ("UK: ", "CRIC ||") and quality marks. */
  function title(name) {
    var parts = name.split(/[|•┃│]/).map(function (s) { return s.trim(); }).filter(Boolean);
    while (parts.length > 1 && parts[0].length <= 6) parts.shift();
    var text = parts.join(' ');
    text = text.replace(/^[A-Z]{2,3}\s*[:\-]\s+/, '');
    text = text.replace(/[\(\[]?\b(4K|8K|UHD|FHD|HD|SD|HEVC|H\.?26[45]|2160P|1080P|720P|50 ?FPS|60 ?FPS)\b[\)\]]?/gi, ' ');
    text = text.replace(/\s{2,}/g, ' ').trim();
    if (text.length < 2) text = name.trim();
    // Title-case SHOUTING names, keep short acronyms.
    if (text === text.toUpperCase() && /[A-Z]{4,}/.test(text)) {
      text = text.split(' ').map(function (w) {
        if (w.length <= 3 || /\d/.test(w)) return w;
        return w.charAt(0) + w.slice(1).toLowerCase();
      }).join(' ');
    }
    return text;
  }

  function hash(text) {
    var h = 5381;
    for (var i = 0; i < text.length; i++) h = ((h << 5) + h + text.charCodeAt(i)) | 0;
    return (h >>> 0).toString(36);
  }

  function makeChannel(fields) {
    return {
      index: 0,
      key: fields.key,
      name: fields.name,
      title: title(fields.name),
      quality: quality(fields.name),
      category: fields.category || 'Uncategorized',
      logo: fields.logo || '',
      url: fields.url,
      altURL: fields.altURL || '',
      streamID: fields.streamID || null,
      epgID: fields.epgID || ''
    };
  }

  // MARK: Xtream

  function Xtream(server, username, password) {
    this.server = trimSlash(server.trim());
    this.username = username;
    this.password = password;
  }

  Xtream.prototype.endpoint = function (action, extra) {
    var url = this.server + '/player_api.php?username=' + encodeURIComponent(this.username) +
      '&password=' + encodeURIComponent(this.password);
    if (action) url += '&action=' + action;
    if (extra) url += extra;
    return url;
  };

  Xtream.prototype.authenticate = function () {
    return fetchJSON(this.endpoint()).then(function (data) {
      var info = data && data.user_info;
      if (!info || String(info.auth) !== '1') throw new Error('Wrong username or password.');
      return {
        status: str(info.status),
        expires: info.exp_date ? new Date(Number(info.exp_date) * 1000) : null,
        active: Number(info.active_cons) || 0,
        max: Number(info.max_connections) || 0
      };
    });
  };

  Xtream.prototype.streamURL = function (id, ext) {
    return this.server + '/live/' + encodeURIComponent(this.username) + '/' +
      encodeURIComponent(this.password) + '/' + id + '.' + ext;
  };

  Xtream.prototype.loadLive = function (format) {
    var self = this;
    var other = format === 'ts' ? 'm3u8' : 'ts';
    return Promise.all([
      fetchJSON(self.endpoint('get_live_streams')),
      fetchJSON(self.endpoint('get_live_categories')).catch(function () { return []; })
    ]).then(function (results) {
      var names = {};
      var order = [];
      list(results[1]).forEach(function (c) {
        if (!c) return;
        var id = str(c.category_id);
        var name = str(c.category_name) || 'Uncategorized';
        names[id] = name;
        order.push(name);
      });
      var channels = [];
      list(results[0]).forEach(function (s) {
        if (!s || s.stream_id === undefined || s.stream_id === null) return;
        var id = str(s.stream_id);
        channels.push(makeChannel({
          key: 'x:' + id,
          name: str(s.name) || ('Channel ' + id),
          category: names[str(s.category_id)] || 'Uncategorized',
          logo: str(s.stream_icon),
          url: self.streamURL(id, format),
          altURL: self.streamURL(id, other),
          streamID: id,
          epgID: str(s.epg_channel_id)
        }));
      });
      if (!channels.length) throw new Error('The provider returned no live channels.');
      return { channels: channels, order: order };
    });
  };

  /** Now/next per stream, kept until the current programme ends (max 10 min) and shared by
   *  concurrent callers — for blocked providers every request is a native download. */
  var epgCache = {};

  Xtream.prototype.shortEPG = function (streamID, limit) {
    limit = limit || 4;
    var key = this.server + '|' + streamID + '|' + limit;
    var hit = epgCache[key];
    var now = Date.now();
    if (hit && hit.until > now) {
      return hit.promise.then(function (items) {
        return items.filter(function (p) { return p.end > Date.now(); });
      });
    }
    var entry = { until: now + 10 * 60000 };
    entry.promise = this.loadShortEPG(streamID, limit).then(function (items) {
      if (items.length && items[0].end > now) entry.until = Math.min(entry.until, items[0].end);
      return items;
    }, function (error) {
      if (epgCache[key] === entry) delete epgCache[key];
      throw error;
    });
    epgCache[key] = entry;
    return entry.promise;
  };

  /** Now/next programmes for one channel (base64 titles). */
  Xtream.prototype.loadShortEPG = function (streamID, limit) {
    return fetchJSON(this.endpoint('get_short_epg', '&stream_id=' + streamID + '&limit=' + (limit || 4))).then(function (data) {
      var items = list(data && (data.epg_listings || data.listings));
      return items.map(function (p) {
        var start = Number(p.start_timestamp) ? Number(p.start_timestamp) * 1000 : Date.parse(str(p.start).replace(' ', 'T'));
        var end = Number(p.stop_timestamp) ? Number(p.stop_timestamp) * 1000 : Date.parse(str(p.end || p.stop).replace(' ', 'T'));
        return { title: decodeBase64(str(p.title)), desc: decodeBase64(str(p.description)), start: start, end: end };
      }).filter(function (p) { return p.title && p.end > Date.now(); })
        .sort(function (a, b) { return a.start - b.start; });
    });
  };

  // MARK: Movies & Series (Xtream)

  function num(value) {
    var n = parseFloat(value);
    return isNaN(n) ? 0 : n;
  }

  /** Poster links from panels come as "//host/x.jpg", with escaped slashes or as bare TMDB paths. */
  function image(url) {
    var u = str(url).trim().replace(/\\\//g, '/');
    if (!u) return '';
    if (u.indexOf('//') === 0) return 'http:' + u;
    if (/^\/[A-Za-z0-9]+\.(jpg|png|webp)$/i.test(u)) return 'https://image.tmdb.org/t/p/w342' + u;
    return /^https?:\/\//i.test(u) ? u : '';
  }

  function yearOf(text) {
    var m = /\b(19|20)\d{2}\b/.exec(str(text));
    return m ? m[0] : '';
  }

  /** Titles like "EN - The Movie (2021)" → "The Movie" (year kept separately). */
  function vodTitle(name) {
    var t = title(str(name));
    return t.replace(/\s*[\(\[]\s*(19|20)\d{2}\s*[\)\]]\s*$/, '').trim() || str(name);
  }

  function categoryMap(rows) {
    var names = {}, order = [];
    list(rows).forEach(function (c) {
      if (!c) return;
      var id = str(c.category_id);
      names[id] = str(c.category_name) || 'Uncategorized';
      order.push(id);
    });
    return { names: names, order: order };
  }

  function groupByCategory(items, cats) {
    var buckets = {};
    items.forEach(function (it) {
      var id = cats.names[it.categoryID] !== undefined ? it.categoryID : '';
      (buckets[id] = buckets[id] || []).push(it);
    });
    var out = [];
    cats.order.forEach(function (id) {
      if (buckets[id]) out.push({ id: id, name: cats.names[id], items: buckets[id] });
    });
    if (buckets['']) out.push({ id: '', name: 'Uncategorized', items: buckets[''] });
    return out;
  }

  /** {items, categories} for 'movie' or 'series'. */
  Xtream.prototype.loadLibrary = function (kind) {
    var self = this;
    var isMovie = kind === 'movie';
    return Promise.all([
      fetchJSON(self.endpoint(isMovie ? 'get_vod_streams' : 'get_series')),
      fetchJSON(self.endpoint(isMovie ? 'get_vod_categories' : 'get_series_categories')).catch(function () { return []; })
    ]).then(function (results) {
      var cats = categoryMap(results[1]);
      var items = [];
      list(results[0]).forEach(function (v) {
        if (!v) return;
        var id = str(isMovie ? v.stream_id : v.series_id);
        if (!id) return;
        var name = str(v.name) || str(v.title);
        items.push({
          kind: kind,
          id: id,
          name: name,
          title: vodTitle(name),
          year: str(v.year) || yearOf(name) || yearOf(v.releaseDate || v.release_date),
          rating: num(v.rating_5based) ? Math.round(num(v.rating_5based) * 20) / 10 : num(v.rating),
          poster: image(isMovie ? v.stream_icon : (v.cover || v.stream_icon)),
          plot: str(v.plot),
          genre: str(v.genre),
          added: num(v.added || v.last_modified),
          ext: str(v.container_extension) || 'mp4',
          categoryID: str(v.category_id)
        });
      });
      return { items: items, categories: groupByCategory(items, cats) };
    });
  };

  Xtream.prototype.vodURL = function (id, ext) {
    return this.server + '/movie/' + encodeURIComponent(this.username) + '/' +
      encodeURIComponent(this.password) + '/' + id + '.' + (ext || 'mp4');
  };

  Xtream.prototype.episodeURL = function (id, ext) {
    return this.server + '/series/' + encodeURIComponent(this.username) + '/' +
      encodeURIComponent(this.password) + '/' + id + '.' + (ext || 'mp4');
  };

  function durationSeconds(info) {
    if (num(info.duration_secs)) return num(info.duration_secs);
    var m = /^(\d+):(\d{2}):(\d{2})$/.exec(str(info.duration));
    if (m) return num(m[1]) * 3600 + num(m[2]) * 60 + num(m[3]);
    if (num(info.episode_run_time)) return num(info.episode_run_time) * 60;
    return 0;
  }

  /** Plot, cast, genre, duration and backdrop for one movie. */
  Xtream.prototype.movieInfo = function (id) {
    return fetchJSON(this.endpoint('get_vod_info', '&vod_id=' + encodeURIComponent(id))).then(function (data) {
      var info = (data && data.info) || {};
      var movie = (data && data.movie_data) || {};
      var backdrop = info.backdrop_path;
      if (Array.isArray(backdrop)) backdrop = backdrop[0];
      return {
        plot: str(info.plot || info.description),
        genre: str(info.genre),
        cast: str(info.cast || info.actors),
        director: str(info.director),
        year: yearOf(info.releasedate || info.release_date),
        rating: num(info.rating),
        duration: durationSeconds(info),
        backdrop: image(backdrop),
        poster: image(info.movie_image || info.cover_big),
        ext: str(movie.container_extension)
      };
    });
  };

  /** Seasons with episodes for one series. */
  Xtream.prototype.seriesInfo = function (id) {
    return fetchJSON(this.endpoint('get_series_info', '&series_id=' + encodeURIComponent(id))).then(function (data) {
      var info = (data && data.info) || {};
      var episodes = (data && data.episodes) || {};
      var seasons = [];
      var keys = Array.isArray(episodes) ? episodes.map(function (e, i) { return String(i); }) : Object.keys(episodes);
      keys.forEach(function (key) {
        var rows = list(episodes[key]);
        if (!rows.length) return;
        var number = num(key) || num(rows[0] && rows[0].season) || (seasons.length + 1);
        seasons.push({
          number: number,
          episodes: rows.filter(Boolean).map(function (e, i) {
            var ei = e.info || {};
            return {
              id: str(e.id),
              number: num(e.episode_num) || (i + 1),
              title: str(e.title) || ('Episode ' + (i + 1)),
              ext: str(e.container_extension) || 'mp4',
              plot: str(ei.plot),
              duration: durationSeconds(ei),
              image: image(ei.movie_image)
            };
          }).filter(function (e) { return e.id; }).sort(function (a, b) { return a.number - b.number; })
        });
      });
      seasons.sort(function (a, b) { return a.number - b.number; });
      var backdrop = info.backdrop_path;
      if (Array.isArray(backdrop)) backdrop = backdrop[0];
      return {
        plot: str(info.plot),
        genre: str(info.genre),
        cast: str(info.cast),
        year: yearOf(info.releaseDate || info.release_date),
        rating: num(info.rating),
        backdrop: image(backdrop),
        poster: image(info.cover),
        seasons: seasons
      };
    });
  };

  // MARK: M3U

  function attribute(name, line) {
    var match = new RegExp(name + '="([^"]*)"').exec(line);
    return match ? match[1] : '';
  }

  function parseM3U(text, baseURL) {
    var lines = text.replace(/﻿/g, '').split(/\r?\n/);
    var channels = [];
    var pending = null;
    var guide = '';
    lines.forEach(function (raw) {
      var line = raw.trim();
      if (!line) return;
      if (line.indexOf('#EXTM3U') === 0) {
        guide = attribute('url-tvg', line) || attribute('x-tvg-url', line);
      } else if (line.indexOf('#EXTINF:') === 0) {
        var comma = line.lastIndexOf(',');
        pending = {
          name: comma >= 0 ? line.slice(comma + 1).trim() : '',
          category: attribute('group-title', line),
          logo: attribute('tvg-logo', line),
          epgID: attribute('tvg-id', line)
        };
      } else if (line.charAt(0) !== '#') {
        var url = line;
        if (!/^https?:\/\//i.test(url) && baseURL) {
          url = baseURL.replace(/[^\/]*$/, '') + url;
        }
        if (/^https?:\/\//i.test(url)) {
          var info = pending || {};
          channels.push(makeChannel({
            key: 'm:' + hash(url),
            name: info.name || ('Channel ' + (channels.length + 1)),
            category: info.category || 'Uncategorized',
            logo: info.logo,
            url: url,
            epgID: info.epgID
          }));
        }
        pending = null;
      }
    });
    return { channels: channels, guideURL: guide };
  }

  /** `…/get.php?username=…&password=…` → Xtream login details. */
  function xtreamFromPlaylist(url) {
    var match = /^(https?:\/\/[^?#]*?)\/?get\.php\?(.*)$/i.exec(url.trim());
    if (!match) return null;
    var params = {};
    match[2].split('&').forEach(function (pair) {
      var bits = pair.split('=');
      params[decodeURIComponent(bits[0])] = decodeURIComponent((bits[1] || '').replace(/\+/g, ' '));
    });
    if (!params.username || !params.password) return null;
    return { server: match[1], username: params.username, password: params.password };
  }

  function loadM3U(url) {
    return fetchText(url.trim(), 90000).then(function (text) {
      if (text.indexOf('#EXTINF') < 0) throw new Error('This link is not an M3U playlist.');
      var parsed = parseM3U(text, url.trim());
      if (!parsed.channels.length) throw new Error('No playable channels found in the playlist.');
      var order = [];
      parsed.channels.forEach(function (c) { if (order.indexOf(c.category) < 0) order.push(c.category); });
      return { channels: parsed.channels, order: order, guideURL: parsed.guideURL };
    });
  }

  /** Connects a provider profile and returns {channels, categories, client, account}. */
  function connect(profile, format) {
    var job;
    if (profile.kind === 'xtream') {
      var api = new Xtream(profile.server, profile.username, profile.password);
      job = api.authenticate().then(function (account) {
        return api.loadLive(format).then(function (live) {
          live.client = api;
          live.account = account;
          return live;
        });
      });
    } else {
      job = loadM3U(profile.playlistURL).catch(function (error) {
        // A refused get.php link usually works through the Xtream API of the same account.
        var login = xtreamFromPlaylist(profile.playlistURL);
        if (!login) throw error;
        var api = new Xtream(login.server, login.username, login.password);
        return api.authenticate().then(function (account) {
          return api.loadLive(format).then(function (live) {
            live.client = api;
            live.account = account;
            return live;
          });
        });
      });
    }
    return job.then(function (result) {
      result.channels.forEach(function (c, i) { c.index = i; });
      result.categories = buildCategories(result.channels, result.order || []);
      return result;
    });
  }

  function buildCategories(channels, order) {
    var buckets = {};
    var seen = [];
    channels.forEach(function (c) {
      if (!buckets[c.category]) { buckets[c.category] = []; seen.push(c.category); }
      buckets[c.category].push(c);
    });
    var names = order.filter(function (n) { return buckets[n]; });
    seen.forEach(function (n) { if (names.indexOf(n) < 0 && n !== 'Uncategorized') names.push(n); });
    if (buckets.Uncategorized && names.indexOf('Uncategorized') < 0) names.push('Uncategorized');
    return names.map(function (n) { return { name: n, channels: buckets[n] }; });
  }

  global.VeyloAPI = {
    connect: connect,
    state: State,
    Xtream: Xtream,
    parseM3U: parseM3U,
    xtreamFromPlaylist: xtreamFromPlaylist,
    fetchBytes: fetchBytes,
    title: title
  };
})(window);

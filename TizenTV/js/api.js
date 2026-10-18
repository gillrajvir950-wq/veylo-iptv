/* Veylo TV — provider access: Xtream Codes API and M3U playlists.
 * Mirrors the iPhone app: lenient decoding, Uncategorized fallback, get.php → Xtream fallback. */
(function (global) {
  'use strict';

  var TIMEOUT = 30000;

  function fetchText(url, timeout) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open('GET', url, true);
      xhr.timeout = timeout || TIMEOUT;
      xhr.onload = function () {
        if (xhr.status >= 200 && xhr.status < 300) resolve(xhr.responseText);
        else reject(new Error('HTTP status ' + xhr.status));
      };
      xhr.onerror = function () { reject(new Error('Couldn’t reach the provider. Check the address and your internet.')); };
      xhr.ontimeout = function () { reject(new Error('The provider took too long to answer.')); };
      xhr.send();
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

  /** Now/next programmes for one channel (base64 titles). */
  Xtream.prototype.shortEPG = function (streamID) {
    return fetchJSON(this.endpoint('get_short_epg', '&stream_id=' + streamID + '&limit=4')).then(function (data) {
      var items = list(data && (data.epg_listings || data.listings));
      return items.map(function (p) {
        var start = Number(p.start_timestamp) ? Number(p.start_timestamp) * 1000 : Date.parse(str(p.start).replace(' ', 'T'));
        var end = Number(p.stop_timestamp) ? Number(p.stop_timestamp) * 1000 : Date.parse(str(p.end || p.stop).replace(' ', 'T'));
        return { title: decodeBase64(str(p.title)), start: start, end: end };
      }).filter(function (p) { return p.title && p.end > Date.now(); })
        .sort(function (a, b) { return a.start - b.start; });
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
    Xtream: Xtream,
    parseM3U: parseM3U,
    xtreamFromPlaylist: xtreamFromPlaylist,
    title: title
  };
})(window);

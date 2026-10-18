/* Veylo TV — XMLTV guide for M3U accounts (the playlist's url-tvg / x-tvg-url, or the EPG link saved
 * with the account). Plain or gzipped (pako inflate). Only channels in the playlist and the time from
 * 2 h ago to 36 h ahead are kept; the result is saved on the TV for 12 h. Chromium 76 compatible. */
(function (global) {
  'use strict';

  var FRESH = 12 * 3600 * 1000;
  var MAX_BYTES = 120 * 1024 * 1024;   // uncompressed guide size the TV can handle
  var BATCH = 4000;                     // programmes parsed before giving the TV a breather

  var X = { status: 'none', message: '', byId: null, byName: null, session: null, count: 0, updated: 0 };

  function norm(name) {
    return String(name || '').toLowerCase()
      .replace(/\b(hd|fhd|uhd|4k|sd|hevc|h265|1080p|720p)\b/g, '')
      .replace(/^[a-z]{2,3}\s*[:|\-]\s*/, '')
      .replace(/[^a-z0-9]+/g, '');
  }

  function entities(text) {
    return String(text || '').replace(/&(#x?[0-9a-f]+|amp|lt|gt|quot|apos);/gi, function (m, e) {
      var map = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
      if (map[e.toLowerCase()]) return map[e.toLowerCase()];
      var code = e.charAt(1).toLowerCase() === 'x' ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return isNaN(code) ? m : String.fromCharCode(code);
    }).replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1');
  }

  /** "20261018140000 +0200" → ms */
  function xmltvTime(value) {
    var m = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?/.exec(String(value || '').trim());
    if (!m) return NaN;
    var t = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0));
    if (m[7]) {
      var sign = m[7].charAt(0) === '-' ? -1 : 1;
      t -= sign * (parseInt(m[7].slice(1, 3), 10) * 60 + parseInt(m[7].slice(3, 5), 10)) * 60000;
    }
    return t;
  }

  function attr(tag, name) {
    var m = new RegExp(name + '="([^"]*)"').exec(tag);
    return m ? m[1] : '';
  }

  function decode(bytes) {
    if (bytes[0] === 0x1f && bytes[1] === 0x8b) {
      var n = bytes.length;
      var size = (bytes[n - 4] | (bytes[n - 3] << 8) | (bytes[n - 2] << 16) | (bytes[n - 1] << 24)) >>> 0;
      if (size > MAX_BYTES) throw new Error('The guide is too big for the TV (' + Math.round(size / 1048576) + ' MB).');
      if (!global.pako) throw new Error('Gzipped guides need pako.');
      bytes = global.pako.inflate(bytes);
    } else if (bytes.length > MAX_BYTES) {
      throw new Error('The guide is too big for the TV.');
    }
    return new TextDecoder('utf-8').decode(bytes);
  }

  /** Index of the programmes for the playlist's channels. Works in batches (setTimeout between
   *  them) so a big guide doesn't freeze the remote for seconds. Resolves {byId, nameToId}. */
  function parse(text, channels) {
    var wantedIds = {}, wantedNames = {};
    channels.forEach(function (c) {
      if (c.epgID) wantedIds[c.epgID] = true;
      wantedNames[norm(c.title)] = true;
      wantedNames[norm(c.name)] = true;
    });
    var nameToId = {};
    var keep = {};
    var reChannel = /<channel\b([^>]*)>([\s\S]*?)<\/channel>/g, m;
    while ((m = reChannel.exec(text))) {
      var id = entities(attr(m[1], 'id'));
      var reName = /<display-name[^>]*>([\s\S]*?)<\/display-name>/g, d;
      while ((d = reName.exec(m[2]))) {
        var key = norm(entities(d[1]));
        if (key && wantedNames[key] && !nameToId[key]) { nameToId[key] = id; keep[id] = true; }
      }
      if (wantedIds[id]) keep[id] = true;
    }
    var from = Date.now() - 2 * 3600000, to = Date.now() + 36 * 3600000;
    var byId = {};
    var reProg = /<programme\b([^>]*)>([\s\S]*?)<\/programme>/g;
    return new Promise(function (resolve) {
      function batch() {
        var p, n = 0;
        while (n < BATCH && (p = reProg.exec(text))) {
          n += 1;
          var ch = entities(attr(p[1], 'channel'));
          if (!keep[ch]) continue;
          var start = xmltvTime(attr(p[1], 'start')), end = xmltvTime(attr(p[1], 'stop'));
          if (!(end > from) || !(start < to)) continue;
          var title = /<title[^>]*>([\s\S]*?)<\/title>/.exec(p[2]);
          var desc = /<desc[^>]*>([\s\S]*?)<\/desc>/.exec(p[2]);
          (byId[ch] = byId[ch] || []).push({ title: entities(title ? title[1] : '').trim(), desc: entities(desc ? desc[1] : '').trim(), start: start, end: end });
        }
        if (n === BATCH) { setTimeout(batch, 0); return; }
        Object.keys(byId).forEach(function (k) { byId[k].sort(function (a, b) { return a.start - b.start; }); });
        resolve({ byId: byId, nameToId: nameToId });
      }
      batch();
    });
  }

  function apply(index, session) {
    X.byId = index.byId;
    X.byName = index.nameToId;
    X.count = Object.keys(index.byId).length;
    X.updated = index.t || Date.now();
    X.status = X.count ? 'ready' : 'empty';
    X.message = X.count ? '' : 'The guide has no programmes for these channels.';
    X.session = session;
  }

  /** Starts loading the guide for an M3U session (`url` = guide link). */
  function load(session, url, scope) {
    X.session = session;
    X.byId = null;
    X.byName = null;
    X.count = 0;
    if (!url) { X.status = 'none'; X.message = 'No guide link in this playlist.'; return; }
    X.status = 'loading';
    X.message = '';
    var key = scope + '|xmltv';
    var cache = global.VeyloLibrary && global.VeyloLibrary.cache;
    var cached = cache ? cache.get(key) : Promise.resolve(null);
    cached.then(function (saved) {
      if (X.session !== session) return null;
      if (saved && saved.url === url && Date.now() - saved.t < FRESH) { apply(saved, session); return null; }
      if (saved && saved.url === url) apply(saved, session);   // old copy while the new one loads
      return global.VeyloAPI.fetchBytes(url, 180000).then(function (bytes) {
        if (X.session !== session) return;
        // All channels, also the locked ones (their guide is needed once the PIN is entered).
        return parse(decode(bytes), session.allChannels || session.channels).then(function (index) {
          if (X.session !== session) return;
          index.t = Date.now();
          index.url = url;
          apply(index, session);
          if (cache) cache.put(key, index);
        });
      });
    }).catch(function (error) {
      if (X.session !== session) return;
      if (X.status !== 'ready') { X.status = 'error'; X.message = (error && error.message) || 'Couldn’t load the guide.'; }
    });
  }

  function lookup(channel) {
    if (!X.byId) return [];
    var id = channel.epgID && X.byId[channel.epgID] ? channel.epgID : (X.byName[norm(channel.title)] || X.byName[norm(channel.name)]);
    var list = (id && X.byId[id]) || [];
    var now = Date.now();
    return list.filter(function (p) { return p.end > now; });
  }

  global.VeyloXMLTV = {
    load: load,
    lookup: lookup,
    available: function () { return !!X.byId && X.session === (global.VeyloUI && global.VeyloUI.App.session); },
    status: function () { return X; },
    parse: parse,
    xmltvTime: xmltvTime
  };
})(window);

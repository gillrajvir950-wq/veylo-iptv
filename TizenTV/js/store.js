/* Veylo TV — local storage (this TV only).
 * Saved providers are stored only when the user ticks "Save this provider".
 * Nothing is ever sent anywhere except to the provider's own server. */
(function (global) {
  'use strict';

  var KEYS = {
    providers: 'veylo.tv.providers',
    active: 'veylo.tv.activeProvider',
    favorites: 'veylo.tv.favorites',
    recents: 'veylo.tv.recents',
    format: 'veylo.tv.format'
  };

  // Parsed values are cached in memory: lists ask "is this a favorite?" for every row they draw.
  var cache = {};

  function clone(value) { return value && typeof value === 'object' ? JSON.parse(JSON.stringify(value)) : value; }

  function read(key, fallback) {
    if (!cache.hasOwnProperty(key)) {
      try {
        var raw = global.localStorage.getItem(key);
        cache[key] = raw ? JSON.parse(raw) : undefined;
      } catch (e) {
        cache[key] = undefined;
      }
    }
    return cache[key] === undefined ? fallback : clone(cache[key]);
  }

  function write(key, value) {
    cache[key] = clone(value);
    try { global.localStorage.setItem(key, JSON.stringify(value)); } catch (e) { /* storage full or blocked */ }
  }

  function scoped(key) { return key + '.' + Store.scope; }

  function uid() {
    return 'p' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
  }

  /** Same server however it was typed ("HTTP://Host:80/" = "http://host:80"). */
  function sameServer(a, b) {
    function norm(s) { return String(s || '').trim().replace(/\/+$/, '').toLowerCase(); }
    return norm(a) === norm(b);
  }

  function matches(p, profile) {
    return p.kind === profile.kind && (profile.kind === 'xtream'
      ? (sameServer(p.server, profile.server) && p.username === profile.username)
      : String(p.playlistURL || '').trim() === String(profile.playlistURL || '').trim());
  }

  function hostOf(url) {
    var match = /^[a-z]+:\/\/([^\/:?#]+)/i.exec(url || '');
    return match ? match[1] : 'Provider';
  }

  var Store = {
    /** [{id, name, kind:'xtream'|'m3u', server, username, password, playlistURL, lastUsed}] */
    providers: function () { return read(KEYS.providers, []); },

    /** The saved account for these login details, if any. */
    matchProvider: function (profile) {
      return Store.providers().filter(function (p) { return matches(p, profile); })[0] || null;
    },

    saveProvider: function (profile) {
      var list = Store.providers();
      var index = -1;
      for (var i = 0; i < list.length; i++) {
        var p = list[i];
        var same = profile.id ? p.id === profile.id : matches(p, profile);
        if (same) { index = i; break; }
      }
      if (index >= 0) {
        profile.id = list[index].id;
        profile.name = profile.name || list[index].name;
        list[index] = profile;
      } else {
        profile.id = profile.id || uid();
        list.push(profile);
      }
      profile.name = profile.name || hostOf(profile.kind === 'xtream' ? profile.server : profile.playlistURL);
      profile.lastUsed = Date.now();
      write(KEYS.providers, list);
      return profile;
    },

    removeProvider: function (id) {
      write(KEYS.providers, Store.providers().filter(function (p) { return p.id !== id; }));
      if (Store.activeID() === id) Store.setActive(null);
    },

    renameProvider: function (id, name) {
      var list = Store.providers();
      list.forEach(function (p) { if (p.id === id && name) p.name = name; });
      write(KEYS.providers, list);
    },

    touch: function (id) {
      var list = Store.providers();
      list.forEach(function (p) { if (p.id === id) p.lastUsed = Date.now(); });
      write(KEYS.providers, list);
    },

    activeID: function () { return read(KEYS.active, null); },
    setActive: function (id) { write(KEYS.active, id); },
    active: function () {
      var id = Store.activeID();
      return Store.providers().filter(function (p) { return p.id === id; })[0] || null;
    },

    /** Favorites, recents, My List and resume points belong to one account: the same stream id
     *  is a different channel at another provider. `setScope` is called on every connect. */
    scope: 'default',
    setScope: function (id) {
      Store.scope = id || 'default';
      // One-time move of the pre-0.1.11 shared lists to the first account opened afterwards.
      var legacyFav = read(KEYS.favorites, null), legacyRec = read(KEYS.recents, null);
      if (legacyFav || legacyRec) {
        if (legacyFav && !read(scoped(KEYS.favorites), null)) write(scoped(KEYS.favorites), legacyFav);
        if (legacyRec && !read(scoped(KEYS.recents), null)) write(scoped(KEYS.recents), legacyRec);
        try { global.localStorage.removeItem(KEYS.favorites); global.localStorage.removeItem(KEYS.recents); } catch (e) {}
        delete cache[KEYS.favorites];
        delete cache[KEYS.recents];
      }
    },

    favorites: function () { return read(scoped(KEYS.favorites), []); },
    isFavorite: function (key) {
      var k = scoped(KEYS.favorites);
      var list = cache[k] === undefined ? Store.favorites() : cache[k];
      return !!list && list.indexOf(key) >= 0;
    },
    toggleFavorite: function (key) {
      var list = Store.favorites();
      var at = list.indexOf(key);
      if (at >= 0) list.splice(at, 1); else list.unshift(key);
      write(scoped(KEYS.favorites), list);
      return at < 0;
    },

    recents: function () { return read(scoped(KEYS.recents), []); },
    addRecent: function (key) {
      var list = Store.recents().filter(function (k) { return k !== key; });
      list.unshift(key);
      write(scoped(KEYS.recents), list.slice(0, 30));
    },

    /** My List for movies ('movie') or series ('series'): ids, newest first. */
    myList: function (kind) { return read(scoped('veylo.tv.mylist.' + kind), []); },
    inMyList: function (kind, id) { return Store.myList(kind).indexOf(String(id)) >= 0; },
    toggleMyList: function (kind, id) {
      var list = Store.myList(kind);
      var at = list.indexOf(String(id));
      if (at >= 0) list.splice(at, 1); else list.unshift(String(id));
      write(scoped('veylo.tv.mylist.' + kind), list);
      return at < 0;
    },

    /** Resume points: {key: {pos, dur, t, title, poster, kind, id}} (seconds), newest 300 kept. */
    progressAll: function () { return read(scoped('veylo.tv.vodProgress'), {}); },
    progress: function (key) { return Store.progressAll()[key] || null; },
    setProgress: function (key, entry) {
      var all = Store.progressAll();
      delete all[key];
      if (entry) {
        entry.t = Date.now();
        all[key] = entry;
      }
      var keys = Object.keys(all);
      while (keys.length > 300) delete all[keys.shift()];
      write(scoped('veylo.tv.vodProgress'), all);
    },

    /** Parental lock: PIN (whole TV), locked categories per account ("live:Name", "movie:Name"…). */
    pin: function () { return read('veylo.tv.pin', ''); },
    setPin: function (pin) { write('veylo.tv.pin', pin || ''); },
    lockedCats: function () { return read(scoped('veylo.tv.locked'), []); },
    toggleLockedCat: function (id) {
      var list = Store.lockedCats();
      var at = list.indexOf(id);
      if (at >= 0) list.splice(at, 1); else list.push(id);
      write(scoped('veylo.tv.locked'), list);
      return at < 0;
    },
    unlockedCats: function () { return read(scoped('veylo.tv.unlockedAdult'), []); },
    autoAdult: function () { return read('veylo.tv.autoAdult', true); },
    setAutoAdult: function (on) { write('veylo.tv.autoAdult', !!on); },
    preview: function () { return read('veylo.tv.preview', false); },
    setPreview: function (on) { write('veylo.tv.preview', !!on); },

    lastChannel: function () { return read(scoped('veylo.tv.lastChannel'), ''); },
    setLastChannel: function (key) { write(scoped('veylo.tv.lastChannel'), key); },
    autostart: function () { return read('veylo.tv.autostart', true); },
    /** Test switch for the dot over the video: shrinks the AVPlay <object> to 1 px in the corner. */
    avTest: function () { return read('veylo.tv.avTest', false); },
    setAVTest: function (on) { write('veylo.tv.avTest', !!on); },
    setAutostart: function (on) { write('veylo.tv.autostart', !!on); },

    /** 'ts' (default, like the iPhone app) or 'm3u8' for Xtream live streams. */
    format: function () { return read(KEYS.format, 'ts'); },
    setFormat: function (value) { write(KEYS.format, value); },

    hostOf: hostOf
  };

  global.VeyloStore = Store;
})(window);

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

  function uid() {
    return 'p' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
  }

  function hostOf(url) {
    var match = /^[a-z]+:\/\/([^\/:?#]+)/i.exec(url || '');
    return match ? match[1] : 'Provider';
  }

  var Store = {
    /** [{id, name, kind:'xtream'|'m3u', server, username, password, playlistURL, lastUsed}] */
    providers: function () { return read(KEYS.providers, []); },

    saveProvider: function (profile) {
      var list = Store.providers();
      var index = -1;
      for (var i = 0; i < list.length; i++) {
        var p = list[i];
        var same = profile.id ? p.id === profile.id
          : (p.kind === profile.kind && (profile.kind === 'xtream'
              ? (p.server === profile.server && p.username === profile.username)
              : p.playlistURL === profile.playlistURL));
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

    favorites: function () { return read(KEYS.favorites, []); },
    isFavorite: function (key) {
      var list = cache[KEYS.favorites] === undefined ? Store.favorites() : cache[KEYS.favorites];
      return !!list && list.indexOf(key) >= 0;
    },
    toggleFavorite: function (key) {
      var list = Store.favorites();
      var at = list.indexOf(key);
      if (at >= 0) list.splice(at, 1); else list.unshift(key);
      write(KEYS.favorites, list);
      return at < 0;
    },

    recents: function () { return read(KEYS.recents, []); },
    addRecent: function (key) {
      var list = Store.recents().filter(function (k) { return k !== key; });
      list.unshift(key);
      write(KEYS.recents, list.slice(0, 30));
    },

    /** 'ts' (default, like the iPhone app) or 'm3u8' for Xtream live streams. */
    format: function () { return read(KEYS.format, 'ts'); },
    setFormat: function (value) { write(KEYS.format, value); },

    hostOf: hostOf
  };

  global.VeyloStore = Store;
})(window);

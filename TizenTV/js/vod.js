/* Veylo TV — Movies & Series (Xtream VOD): library pages, detail screens and the VOD player.
 * Uses the shared screen helpers from js/app.js (window.VeyloUI). Written for Chromium 76 (Tizen 6). */
(function (global) {
  'use strict';

  var UI = global.VeyloUI;
  var Store = global.VeyloStore;
  var K = UI.K, esc = UI.esc, clamp = UI.clamp, toast = UI.toast;
  var COLS = 6;
  var POSTER_ROW = 372;

  function client() { return UI.App.session && UI.App.session.client; }

  function time(seconds) {
    seconds = Math.max(0, Math.round(seconds || 0));
    var h = Math.floor(seconds / 3600), m = Math.floor((seconds % 3600) / 60), s = seconds % 60;
    return (h ? h + ':' + (m < 10 ? '0' : '') : '') + m + ':' + (s < 10 ? '0' : '') + s;
  }

  function minutes(seconds) {
    if (!seconds) return '';
    var h = Math.floor(seconds / 3600), m = Math.round((seconds % 3600) / 60);
    return h ? h + ' h ' + m + ' min' : m + ' min';
  }

  function posterHTML(item, extraClass) {
    var fallback = '<div class="ptext">' + esc(item.title) + '</div>';
    return '<div class="pimg' + (extraClass || '') + '" data-fallback="' + esc(fallback) + '">' +
      (item.poster ? '<img decoding="async" loading="lazy" src="' + esc(item.poster) + '" onerror="this.parentNode.innerHTML=this.parentNode.getAttribute(\'data-fallback\')">' : fallback) +
      '</div>';
  }

  // ---------- Library data: saved on the TV (IndexedDB), refreshed in the background ----------
  var DB_NAME = 'veylo', DB_STORE = 'library';
  var FRESH = 12 * 3600 * 1000;
  var dbPromise = null;

  function db() {
    if (dbPromise) return dbPromise;
    dbPromise = new Promise(function (resolve, reject) {
      if (!global.indexedDB) { reject(new Error('no IndexedDB')); return; }
      var req = global.indexedDB.open(DB_NAME, 1);
      req.onupgradeneeded = function () { req.result.createObjectStore(DB_STORE); };
      req.onsuccess = function () { resolve(req.result); };
      req.onerror = function () { reject(req.error); };
    });
    dbPromise.catch(function () { dbPromise = null; });
    return dbPromise;
  }

  function cacheGet(key) {
    return db().then(function (d) {
      return new Promise(function (resolve) {
        try {
          var req = d.transaction(DB_STORE, 'readonly').objectStore(DB_STORE).get(key);
          req.onsuccess = function () { resolve(req.result || null); };
          req.onerror = function () { resolve(null); };
        } catch (e) { resolve(null); }
      });
    }).catch(function () { return null; });
  }

  function cachePut(key, value) {
    return db().then(function (d) {
      try { d.transaction(DB_STORE, 'readwrite').objectStore(DB_STORE).put(value, key); } catch (e) { /* storage full */ }
    }).catch(function () {});
  }

  function cacheClear() {
    return db().then(function (d) {
      try { d.transaction(DB_STORE, 'readwrite').objectStore(DB_STORE).clear(); } catch (e) {}
    }).catch(function () {});
  }

  function prepared(lib) {
    lib.byID = {};
    lib.items.forEach(function (it) { lib.byID[it.id] = it; });
    return lib;
  }

  function download(kind, key) {
    return client().loadLibrary(kind).then(function (lib) {
      cachePut(key, { t: Date.now(), items: lib.items, categories: lib.categories });
      return prepared(lib);
    });
  }

  function library(kind) {
    var session = UI.App.session;
    session.library = session.library || {};
    if (!session.library[kind]) {
      var key = Store.scope + '|' + kind;
      session.library[kind] = cacheGet(key).then(function (saved) {
        if (saved && saved.items && saved.items.length) {
          // Saved copy opens instantly; an old one is refreshed quietly for next time.
          if (Date.now() - saved.t > FRESH) {
            download(kind, key).then(function (fresh) {
              if (UI.App.session === session) session.library[kind] = Promise.resolve(fresh);
            }).catch(function () {});
          }
          return prepared({ items: saved.items, categories: saved.categories });
        }
        return download(kind, key);
      }).catch(function (error) {
        delete session.library[kind];
        throw error;
      });
    }
    return session.library[kind];
  }

  // ---------- Library page ----------
  var Lib = { kind: 'movie', focus: 'cats', sectionIndex: 1, col: 0, query: '', positions: {}, data: null };

  /** Category ids of this kind that are locked right now (PIN not entered this session). */
  function lockedIDs(kind, lib) {
    var ids = {};
    if (UI.App.unlocked) return ids;
    lib.categories.forEach(function (c) { if (UI.isLockedCat(kind, c.name)) ids[c.id] = true; });
    return ids;
  }

  function visibleItems(kind, lib, items) {
    var ids = lockedIDs(kind, lib);
    if (!Object.keys(ids).length) return items;
    return items.filter(function (it) { return !ids[it.categoryID]; });
  }

  function sectionsFor(kind, lib) {
    var locked = lockedIDs(kind, lib);
    var lockedCount = Object.keys(locked).length;
    var progress = Store.progressAll();
    var resume = [];
    Object.keys(progress).reverse().forEach(function (key) {
      var entry = progress[key];
      var prefix = kind === 'movie' ? 'm:' : 's:';
      if (key.indexOf(prefix) !== 0) return;
      var item = lib.byID[key.slice(2)];
      if (item) resume.push(item);
    });
    var mine = Store.myList(kind).map(function (id) { return lib.byID[id]; }).filter(Boolean);
    var all = visibleItems(kind, lib, lib.items);
    var recent = all.slice().sort(function (a, b) { return b.added - a.added; }).slice(0, 120);
    var sections = [
      { id: 'search', label: Lib.query ? 'Search: ' + Lib.query : 'Search', glyph: 'search', items: visibleItems(kind, lib, searchItems(lib)) },
      { id: 'all', label: kind === 'movie' ? 'All Movies' : 'All Series', glyph: '▤', items: all },
      { id: 'resume', label: 'Continue Watching', glyph: '▶', items: visibleItems(kind, lib, resume) },
      { id: 'mylist', label: 'My List', glyph: '♥', items: visibleItems(kind, lib, mine) },
      { id: 'recent', label: 'Recently Added', glyph: '✦', items: recent }
    ];
    if (lockedCount) sections.push({ id: 'locked', label: 'Locked (' + lockedCount + ')', glyph: '✱', items: [], locked: true });
    lib.categories.forEach(function (c) {
      if (locked[c.id]) return;
      sections.push({ id: 'c:' + c.id, label: global.VeyloAPI.title(c.name), glyph: '', items: c.items });
    });
    return sections;
  }

  function searchItems(lib) {
    var q = Lib.query.toLowerCase();
    if (!q) return [];
    var out = [];
    for (var i = 0; i < lib.items.length && out.length < 600; i++) {
      if (lib.items[i].name.toLowerCase().indexOf(q) >= 0) out.push(lib.items[i]);
    }
    return out;
  }

  function rowsOf(items) {
    var rows = [];
    for (var i = 0; i < items.length; i += COLS) rows.push(items.slice(i, i + COLS));
    return rows;
  }

  function show(kind) {
    Lib.returnTo = null;
    if (Lib.kind !== kind) { Lib.kind = kind; Lib.sectionIndex = 1; Lib.positions = {}; Lib.query = ''; Lib.col = 0; }
    var tab = kind === 'movie' ? 'movies' : 'series';
    var html =
      '<div class="backdrop"></div>' + UI.navHTML(tab) +
      '<div class="browser">' +
        '<div class="sidebar">' +
          '<input class="search-input" id="lib-search" type="text" autocomplete="off">' +
          '<div class="vlist" id="lib-cats"><div class="vlist-inner"></div></div>' +
        '</div>' +
        '<div class="content">' +
          '<div class="content-head"><h1 id="lib-title"></h1><div class="sub" id="lib-sub"></div></div>' +
          '<div class="lib-body"><div class="vlist" id="lib-grid"><div class="vlist-inner"></div></div></div>' +
          '<div class="hints">' +
            '<span><span class="key">▲</span>Menu</span>' +
            '<span><span class="key">OK</span>Details</span>' +
            '<span><span class="key">◀ ▶</span>Categories / Posters</span>' +
            '<span><span class="key yellow">&nbsp;</span>My List</span>' +
            '<span><span class="key">BACK</span>Back</span>' +
          '</div>' +
        '</div>' +
      '</div>';
    UI.setScreen('library', html, libraryKey);

    if (!client()) {
      document.getElementById('lib-title').textContent = kind === 'movie' ? 'Movies' : 'Series';
      document.querySelector('.lib-body').innerHTML = '<div class="empty">Movies and series need an Xtream Codes account.<br>' +
        'This provider was added as an M3U playlist.<br><span style="font-size:22px">Tip: add the same account as Xtream Codes in Settings › Accounts.</span></div>';
      Lib.data = null;
      Lib.focus = 'nav';
      UI.navFocus(true);
      return;
    }

    document.getElementById('lib-title').textContent = kind === 'movie' ? 'Movies' : 'Series';
    document.getElementById('lib-sub').textContent = 'Loading…';
    document.querySelector('#lib-grid .vlist-inner').innerHTML = '<div class="empty"><div class="spinner" style="margin:0 auto 26px"></div>Loading ' +
      (kind === 'movie' ? 'movies' : 'series') + '…</div>';
    Lib.focus = 'nav';
    UI.navFocus(true);
    var started = UI.App.screen;
    library(kind).then(function (lib) {
      if (UI.App.screen !== 'library' || Lib.kind !== kind) return;
      Lib.data = lib;
      build();
      if (UI.Nav.focused) { UI.navFocus(false); setFocus('cats'); }
    }, function (error) {
      if (UI.App.screen !== 'library' || Lib.kind !== kind) return;
      document.getElementById('lib-sub').textContent = '';
      document.querySelector('#lib-grid .vlist-inner').innerHTML = '<div class="empty">Couldn’t load ' +
        (kind === 'movie' ? 'movies' : 'series') + '.<br><span style="font-size:22px">' + esc((error && error.message) || '') +
        '</span><br>Press OK on the menu to try again.</div>';
    });
    return started;
  }

  function build() {
    var lib = Lib.data;
    Lib.sections = sectionsFor(Lib.kind, lib);
    if (Lib.sectionIndex >= Lib.sections.length || (Lib.sectionIndex === 0 && !Lib.query)) Lib.sectionIndex = 1;
    Lib.cats = new UI.VList(document.getElementById('lib-cats'), 74, function (section, i, focused) {
      var count = section.id === 'search' ? '' : section.items.length;
      return '<div class="cat' + (i === Lib.sectionIndex ? ' selected' : '') + (focused ? ' focused' : '') + '">' +
        UI.glyphHTML(section.glyph) + '<span class="label">' + esc(section.label) + '</span>' +
        '<span class="count">' + count + '</span></div>';
    }, 12);
    Lib.grid = new UI.VList(document.getElementById('lib-grid'), POSTER_ROW, function (row, i) {
      return '<div class="prow">' + row.map(function (item) {
        var p = Store.progress((item.kind === 'movie' ? 'm:' : 's:') + item.id);
        var bar = p && p.dur && item.kind === 'movie' ? '<div class="pbar"><div style="width:' + Math.round(p.pos / p.dur * 100) + '%"></div></div>' : '';
        var mine = Store.inMyList(item.kind, item.id) ? '<span class="pheart">♥</span>' : '';
        return '<div class="poster">' + posterHTML(item) + bar + mine +
          '<div class="ptitle">' + esc(item.title) + '</div>' +
          '<div class="pmeta">' + esc([item.year, item.rating ? '★ ' + item.rating : ''].filter(Boolean).join(' · ')) + '</div></div>';
      }).join('') + '</div>';
    }, 2);
    Lib.cats.focused = Lib.focus === 'cats';
    Lib.cats.setItems(Lib.sections, Lib.sectionIndex);
    openSection(Lib.sectionIndex);
    UI.App.onTypingDone = function (input) {
      Lib.query = input.value.trim();
      Lib.sections = sectionsFor(Lib.kind, Lib.data);
      Lib.sectionIndex = 0;
      Lib.cats.setItems(Lib.sections, 0);
      openSection(0);
      if (Lib.sections[0].items.length) setFocus('grid');
    };
  }

  function openSection(index) {
    Lib.sectionIndex = index;
    var section = Lib.sections[index];
    document.getElementById('lib-title').textContent = section.id === 'search'
      ? (Lib.query ? 'Results for “' + Lib.query + '”' : 'Search') : section.label;
    document.getElementById('lib-sub').textContent = section.id === 'search' && !Lib.query ? 'Press OK to type'
      : section.items.length.toLocaleString() + (Lib.kind === 'movie' ? ' movies' : ' series');
    var pos = Lib.positions[section.id] || 0;
    Lib.col = pos % COLS;
    Lib.grid.focused = Lib.focus === 'grid';
    Lib.grid.setItems(rowsOf(section.items), Math.floor(pos / COLS));
    if (!section.items.length) {
      var message = {
        search: Lib.query ? 'Nothing found.' : 'Press OK, type a title and press Done.',
        resume: 'What you start watching shows up here.',
        locked: 'These categories are locked.<br>Press OK and enter your PIN to show them.',
        mylist: 'Press the <b>yellow</b> button on a poster to add it to My List.'
      }[section.id] || 'Nothing here.';
      document.querySelector('#lib-grid .vlist-inner').innerHTML = '<div class="empty">' + message + '</div>';
    }
    applyCol();
  }

  /** Highlights the focused poster inside the focused row. */
  function applyCol() {
    var grid = document.getElementById('lib-grid');
    if (!grid) return;
    var old = grid.querySelectorAll('.poster.focused');
    Array.prototype.forEach.call(old, function (n) { n.classList.remove('focused'); });
    if (Lib.focus !== 'grid' || !Lib.grid.items.length) return;
    var row = Lib.grid.inner.children[Lib.grid.index - Lib.grid.bufStart];
    if (!row) return;
    var cells = row.querySelectorAll('.poster');
    Lib.col = clamp(Lib.col, 0, cells.length - 1);
    if (cells[Lib.col]) cells[Lib.col].classList.add('focused');
  }

  function currentItem() {
    var row = Lib.grid && Lib.grid.current();
    return row ? row[clamp(Lib.col, 0, row.length - 1)] : null;
  }

  function setFocus(where) {
    flush();
    Lib.focus = where;
    UI.navFocus(where === 'nav');
    if (!Lib.cats) return;
    Lib.cats.focused = where === 'cats';
    Lib.grid.focused = where === 'grid';
    Lib.cats.render();
    if (Lib.grid.items.length) Lib.grid.render();
    applyCol();
  }

  function flush() {
    if (!Lib.pending) return;
    clearTimeout(Lib.pending);
    Lib.pending = null;
    if (UI.App.screen !== 'library' || !Lib.cats) return;
    if (Lib.cats.index !== Lib.sectionIndex) {
      openSection(Lib.cats.index);
      Lib.cats.render();
    }
  }

  function rememberPosition() {
    var section = Lib.sections && Lib.sections[Lib.sectionIndex];
    if (section && Lib.grid) Lib.positions[section.id] = Lib.grid.index * COLS + Lib.col;
  }

  function libraryKey(key) {
    if (Lib.focus === 'nav' || !Lib.data) {
      return UI.navKey(key, function () {
        if (!Lib.data) { UI.navFocus(true); return; }
        setFocus(Lib.lastFocus || 'cats');
      });
    }
    if (Lib.focus === 'cats') {
      if (key === K.UP && Lib.cats.index === 0) { flush(); Lib.lastFocus = 'cats'; setFocus('nav'); return; }
      if (key === K.UP || key === K.DOWN) {
        if (Lib.cats.move(key === K.UP ? -1 : 1)) {
          if (!Lib.pending) rememberPosition();
          clearTimeout(Lib.pending);
          Lib.pending = setTimeout(flush, 250);
        }
        return;
      }
      flush();
      var section = Lib.sections[Lib.sectionIndex];
      if (key === K.RIGHT || key === K.ENTER) {
        if (section.locked && key === K.ENTER) {
          UI.unlock(function () { show(Lib.kind); });
          return;
        }
        if (section.id === 'search' && key === K.ENTER) {
          var input = document.getElementById('lib-search');
          input.value = Lib.query;
          input.focus();
          return;
        }
        if (Lib.grid.items.length) setFocus('grid');
        return;
      }
      if (key === K.BACK || key === K.ESC) { Lib.lastFocus = 'cats'; setFocus('nav'); return; }
      return false;
    }
    // Poster grid
    var row = Lib.grid.current() || [];
    if (key === K.LEFT) {
      if (Lib.col > 0) { Lib.col -= 1; applyCol(); } else { rememberPosition(); setFocus('cats'); }
      return;
    }
    if (key === K.RIGHT) {
      if (Lib.col < row.length - 1) { Lib.col += 1; applyCol(); }
      else if (Lib.grid.index < Lib.grid.items.length - 1) { Lib.col = 0; Lib.grid.move(1); applyCol(); }
      return;
    }
    if (key === K.UP) {
      if (Lib.grid.index === 0) { Lib.lastFocus = 'grid'; setFocus('nav'); return; }
      Lib.grid.move(-1); applyCol(); return;
    }
    if (key === K.DOWN) { Lib.grid.move(UI.App.held > 6 ? 2 : 1); applyCol(); return; }
    if (key === K.CH_UP || key === K.CH_DOWN) { Lib.grid.move(key === K.CH_UP ? -2 : 2); applyCol(); return; }
    if (key === K.ENTER) {
      var item = currentItem();
      if (!item) return;
      rememberPosition();
      if (item.kind === 'movie') showMovie(item); else showSeries(item);
      return;
    }
    if (key === K.YELLOW) {
      var it = currentItem();
      if (!it) return;
      var added = Store.toggleMyList(it.kind, it.id);
      toast(added ? '♥ Added to My List' : 'Removed from My List');
      Lib.grid.render();
      applyCol();
      return;
    }
    if (key === K.BACK || key === K.ESC) { rememberPosition(); setFocus('cats'); return; }
    return false;
  }

  function backToLibrary() {
    if (Lib.returnTo) { var back = Lib.returnTo; back(); return; }
    Lib.focus = 'grid';
    show(Lib.kind);
  }

  // ---------- Movie details ----------
  function showMovie(item) {
    var key = 'm:' + item.id;
    var p = Store.progress(key);
    var html =
      '<div class="detail-bg" id="detail-bg"></div><div class="detail-shade"></div>' +
      '<div class="detail">' +
        '<div class="detail-poster">' + posterHTML(item) + '</div>' +
        '<div class="detail-info">' +
          '<h1>' + esc(item.title) + '</h1>' +
          '<div class="detail-meta" id="detail-meta">' + esc([item.year, item.rating ? '★ ' + item.rating : '', item.genre].filter(Boolean).join('  ·  ')) + '</div>' +
          '<div class="detail-plot" id="detail-plot">' + esc(item.plot || '') + '</div>' +
          '<div class="detail-cast" id="detail-cast"></div>' +
          '<div class="detail-actions">' +
            (p && p.pos > 30
              ? '<div class="dbtn primary focusable" data-action="resume">▶ Resume ' + time(p.pos) + '</div>' +
                '<div class="dbtn focusable" data-action="start">↺ From the start</div>'
              : '<div class="dbtn primary focusable" data-action="start">▶ Play</div>') +
            '<div class="dbtn focusable" data-action="mylist">' + (Store.inMyList('movie', item.id) ? '♥ In My List' : '♡ My List') + '</div>' +
          '</div>' +
        '</div>' +
      '</div>';
    UI.setScreen('detail', html, function (k) {
      if (k === K.LEFT || k === K.RIGHT || k === K.UP || k === K.DOWN) { focus.move(k); return; }
      if (k === K.BACK || k === K.ESC) { backToLibrary(); return; }
      if (k === K.YELLOW) { toggle(); return; }
      if (k !== K.ENTER && k !== K.PLAY && k !== K.PLAY_PAUSE) return false;
      var action = focus.current() && focus.current().getAttribute('data-action');
      if (k !== K.ENTER) action = p && p.pos > 30 ? 'resume' : 'start';
      if (action === 'mylist') { toggle(); return; }
      if (action === 'resume' || action === 'start') {
        play({
          key: key, kind: 'movie', id: item.id, title: item.title, poster: item.poster,
          url: client().vodURL(item.id, Lib.info && Lib.info.ext || item.ext),
          start: action === 'resume' ? p.pos : 0,
          back: function () { showMovie(item); }
        });
      }
    });
    function toggle() {
      var added = Store.toggleMyList('movie', item.id);
      var node = document.querySelector('[data-action="mylist"]');
      if (node) node.textContent = added ? '♥ In My List' : '♡ My List';
      toast(added ? '♥ Added to My List' : 'Removed from My List');
    }
    var focus = new UI.FormFocus('.detail .focusable');
    Lib.info = null;
    client().movieInfo(item.id).then(function (info) {
      if (UI.App.screen !== 'detail') return;
      Lib.info = info;
      var meta = [info.year || item.year, info.rating || item.rating ? '★ ' + (info.rating || item.rating) : '', minutes(info.duration), info.genre || item.genre];
      document.getElementById('detail-meta').textContent = meta.filter(Boolean).join('  ·  ');
      if (info.plot) document.getElementById('detail-plot').textContent = info.plot;
      document.getElementById('detail-cast').textContent = [info.director ? 'Director: ' + info.director : '', info.cast ? 'Cast: ' + info.cast : ''].filter(Boolean).join('   ');
      if (info.backdrop) document.getElementById('detail-bg').style.backgroundImage = 'url("' + info.backdrop.replace(/"/g, '%22') + '")';
    }).catch(function () {});
  }

  // ---------- Series details ----------
  function showSeries(item, preset) {
    var S = { item: item, info: null, season: 0, zone: 'top' };
    var html =
      '<div class="detail-bg" id="detail-bg"></div><div class="detail-shade"></div>' +
      '<div class="series">' +
        '<div class="series-left">' +
          '<div class="detail-poster small">' + posterHTML(item) + '</div>' +
          '<h1>' + esc(item.title) + '</h1>' +
          '<div class="detail-meta" id="detail-meta">' + esc([item.year, item.rating ? '★ ' + item.rating : '', item.genre].filter(Boolean).join('  ·  ')) + '</div>' +
          '<div class="detail-plot" id="detail-plot">' + esc(item.plot || '') + '</div>' +
        '</div>' +
        '<div class="series-right">' +
          '<div class="seasons" id="seasons"><div class="dbtn focusable" data-action="mylist">' +
            (Store.inMyList('series', item.id) ? '♥ In My List' : '♡ My List') + '</div></div>' +
          '<div class="vlist" id="episodes"><div class="vlist-inner"><div class="empty"><div class="spinner" style="margin:0 auto 26px"></div>Loading episodes…</div></div></div>' +
        '</div>' +
      '</div>';
    var focus;
    UI.setScreen('detail', html, function (k) {
      if (k === K.BACK || k === K.ESC) {
        if (S.zone === 'eps') { setZone('top'); return; }
        backToLibrary();
        return;
      }
      if (S.zone === 'top') {
        if (k === K.LEFT || k === K.RIGHT || k === K.UP) { focus.move(k); return; }
        if (k === K.DOWN) { if (S.list && S.list.items.length) setZone('eps'); return; }
        if (k !== K.ENTER) return false;
        var node = focus.current();
        var action = node && node.getAttribute('data-action');
        if (action === 'mylist') {
          var added = Store.toggleMyList('series', item.id);
          node.textContent = added ? '♥ In My List' : '♡ My List';
          toast(added ? '♥ Added to My List' : 'Removed from My List');
        } else if (action === 'season') {
          selectSeason(Number(node.getAttribute('data-index')), 0);
          setZone('eps');
        }
        return;
      }
      // episodes
      if (k === K.UP && S.list.index === 0) { setZone('top'); return; }
      if (k === K.UP || k === K.DOWN) { S.list.move(k === K.UP ? -1 : 1); return; }
      if (k === K.CH_UP || k === K.CH_DOWN) { S.list.move(k === K.CH_UP ? -6 : 6); return; }
      if (k === K.ENTER || k === K.PLAY || k === K.PLAY_PAUSE) { playEpisode(S.list.index); return; }
      return false;
    });

    function setZone(zone) {
      S.zone = zone;
      if (S.list) { S.list.focused = zone === 'eps'; S.list.render(); }
      focus.items.forEach(function (n) { n.classList.toggle('focused', zone === 'top' && n === focus.current()); });
    }

    function episodes() { return (S.info && S.info.seasons[S.season] && S.info.seasons[S.season].episodes) || []; }

    function selectSeason(index, episodeIndex) {
      S.season = index;
      Array.prototype.forEach.call(document.querySelectorAll('#seasons [data-action="season"]'), function (n) {
        n.classList.toggle('active', Number(n.getAttribute('data-index')) === index);
      });
      S.list.setItems(episodes(), episodeIndex || 0);
    }

    function playEpisode(index) {
      var list = episodes();
      var ep = list[index];
      if (!ep) return;
      var key = 'e:' + ep.id;
      var p = Store.progress(key);
      var season = S.info.seasons[S.season];
      play({
        key: key, kind: 'episode', id: ep.id, seriesID: item.id,
        title: item.title, subtitle: 'S' + season.number + ' · E' + ep.number + (ep.title && !/^episode \d+$/i.test(ep.title) ? ' · ' + ep.title : ''),
        poster: item.poster, url: client().episodeURL(ep.id, ep.ext),
        start: p && p.pos > 30 && (!p.dur || p.pos < p.dur * 0.95) ? p.pos : 0,
        next: index + 1 < list.length ? function () { playEpisode(index + 1); } : null,
        back: function () { showSeries(item, { season: S.season, episode: index }); },
        onProgress: function (pos, dur) {
          // The series' own resume point = its last watched episode.
          Store.setProgress('s:' + item.id, { pos: pos, dur: dur, season: S.season, episode: index, title: item.title });
        }
      });
    }

    client().seriesInfo(item.id).then(function (info) {
      if (UI.App.screen !== 'detail') return;
      S.info = info;
      if (info.plot) document.getElementById('detail-plot').textContent = info.plot;
      var meta = [info.year || item.year, info.rating || item.rating ? '★ ' + (info.rating || item.rating) : '', info.genre || item.genre];
      document.getElementById('detail-meta').textContent = meta.filter(Boolean).join('  ·  ');
      if (info.backdrop) document.getElementById('detail-bg').style.backgroundImage = 'url("' + info.backdrop.replace(/"/g, '%22') + '")';
      var box = document.getElementById('seasons');
      box.innerHTML += info.seasons.map(function (s, i) {
        return '<div class="dbtn chip focusable" data-action="season" data-index="' + i + '">Season ' + s.number + '</div>';
      }).join('');
      focus = new UI.FormFocus('#seasons .focusable');
      S.list = new UI.VList(document.getElementById('episodes'), 112, function (ep, i, focused) {
        var p = Store.progress('e:' + ep.id);
        var pct = p && p.dur ? Math.round(p.pos / p.dur * 100) : 0;
        return '<div class="ep' + (focused ? ' focused' : '') + '">' +
          '<div class="ep-num">' + ep.number + '</div>' +
          '<div class="ep-info"><div class="ep-title">' + esc(ep.title) + '</div>' +
          '<div class="ep-meta">' + esc(minutes(ep.duration)) + (pct ? ' · ' + (pct >= 95 ? 'Watched' : pct + '% watched') : '') + '</div>' +
          (pct ? '<div class="bar"><div style="width:' + pct + '%"></div></div>' : '') + '</div></div>';
      }, 6);
      if (!info.seasons.length) {
        document.querySelector('#episodes .vlist-inner').innerHTML = '<div class="empty">No episodes found.</div>';
        setZone('top');
        return;
      }
      // Open where the viewer left off (or the season/episode coming back from the player).
      var last = Store.progress('s:' + item.id);
      var season = preset ? preset.season : (last && last.season < info.seasons.length ? last.season : 0);
      var episode = preset ? preset.episode : (last && last.season === season ? last.episode : 0);
      selectSeason(season, episode);
      focus.items.forEach(function (n, i) { if (n.getAttribute('data-index') === String(season)) focus.index = i; });
      setZone(preset || last ? 'eps' : 'top');
    }).catch(function (error) {
      if (UI.App.screen !== 'detail') return;
      document.querySelector('#episodes .vlist-inner').innerHTML = '<div class="empty">Couldn’t load the episodes.<br><span style="font-size:22px">' +
        esc((error && error.message) || '') + '</span></div>';
    });
    focus = new UI.FormFocus('#seasons .focusable');
  }

  // ---------- VOD player (Samsung AVPlay; seeking and resume) ----------
  var AGENTS = ['VLC/3.0.21 LibVLC/3.0.21', 'IPTVSmartersPro', 'okhttp/4.12.0', ''];
  var V = { media: null };

  function hasAVPlay() { return !!(global.webapis && global.webapis.avplay); }

  function play(media) {
    V.media = media;
    V.duration = 0;
    V.position = media.start || 0;
    V.seekTarget = null;
    V.paused = false;
    V.state = 'loading';
    V.agentIndex = 0;
    V.log = [];
    var html =
      '<div class="player vodp">' +
        '<div id="vod-overlay">' +
          '<div class="shade-top"></div><div class="shade-bottom"></div>' +
          '<div class="top"><div><div class="vod-title">' + esc(media.title) + '</div>' +
            (media.subtitle ? '<div class="vod-sub">' + esc(media.subtitle) + '</div>' : '') + '</div>' +
            '<span class="clock" id="vod-clock"></span></div>' +
          '<div class="vod-bar"><div class="vod-times"><span id="vod-pos">0:00</span><span id="vod-dur"></span></div>' +
            '<div class="track"><div class="fill" id="vod-fill"></div><div class="knob" id="vod-knob"></div></div></div>' +
          '<div class="hints">' +
            '<span><span class="key">◀ ▶</span>−10 s / +10 s</span>' +
            '<span><span class="key yellow">&nbsp;</span>Audio & subtitles</span>' +
            '<span><span class="key">⏯</span>Pause</span>' +
            (media.next ? '<span><span class="key">CH+</span>Next episode</span>' : '') +
            '<span><span class="key">BACK</span>Close</span>' +
          '</div>' +
        '</div>' +
        '<div class="status" id="vod-status"></div>' +
        '<div class="vod-subtitle" id="vod-subtitle"></div>' +
        '<div class="tracks hidden" id="tracks"></div>' +
      '</div>';
    V.tracks = { audio: [], text: [], audioIndex: -1, textIndex: -1 };
    V.tracksOpen = false;
    UI.setScreen('vodplayer', html, vodKey);
    UI.App.onVisibility = function (hidden) {
      if (UI.App.screen !== 'vodplayer') return;
      if (hidden) { save(); stopAV(); V.suspended = true; }
      else if (V.suspended) { V.suspended = false; V.media.start = V.position; open(); }
    };
    tickClock();
    clearInterval(V.clockTimer);
    V.clockTimer = setInterval(tickClock, 5000);
    clearInterval(V.saveTimer);
    V.saveTimer = setInterval(save, 10000);
    open();
  }

  function tickClock() {
    var c = document.getElementById('vod-clock');
    if (c) c.textContent = UI.clock(Date.now());
  }

  function status(text) {
    var box = document.getElementById('vod-status');
    if (box) { box.innerHTML = text; box.style.display = text ? '' : 'none'; }   // no leftover dot over the video
  }

  function showOverlay(stay) {
    var o = document.getElementById('vod-overlay');
    if (!o) return;
    o.classList.remove('hidden');
    clearTimeout(V.hideTimer);
    if (stay) return;
    V.hideTimer = setTimeout(function () {
      if (V.state === 'playing' && !V.paused && V.seekTarget === null) o.classList.add('hidden');
    }, 4000);
  }

  function drawBar() {
    var pos = V.seekTarget !== null ? V.seekTarget : V.position;
    var dur = V.duration;
    var pct = dur ? clamp(pos / dur, 0, 1) * 100 : 0;
    var fill = document.getElementById('vod-fill');
    if (!fill) return;
    fill.style.width = pct + '%';
    document.getElementById('vod-knob').style.left = pct + '%';
    document.getElementById('vod-pos').textContent = time(pos) + (V.seekTarget !== null ? '  ›' : '');
    document.getElementById('vod-dur').textContent = dur ? '−' + time(dur - pos) : '';
  }

  /** The identity Samsung's player last succeeded with on live TV first, else VLC first. */
  function agents() {
    var first = null;
    try {
      var m = JSON.parse(global.localStorage.getItem('veylo.tv.streamIdentity') || 'null');
      var map = { vlc: AGENTS[0], smarters: AGENTS[1], okhttp: AGENTS[2], tv: '' };
      if (m && map.hasOwnProperty(m.agent)) first = map[m.agent];
    } catch (e) {}
    if (first === null) return AGENTS;
    return [first].concat(AGENTS.filter(function (a) { return a !== first; }));
  }

  function open() {
    if (!V.media || UI.App.screen !== 'vodplayer') return;
    V.state = 'loading';
    status('<div class="spinner"></div>Loading…');
    showOverlay(true);
    var list = agents();
    var agent = list[V.agentIndex];
    V.gen = (V.gen || 0) + 1;
    var gen = V.gen;
    function live() { return gen === V.gen && UI.App.screen === 'vodplayer'; }
    clearTimeout(V.tryTimer);
    V.tryTimer = setTimeout(function () { if (live() && V.state === 'loading') fail('NO_PICTURE_25S'); }, 25000);
    if (!hasAVPlay()) return openHTML5(live);
    var av = global.webapis.avplay;
    try {
      av.open(V.media.url);
      av.setListener({
        onbufferingstart: function () { if (live() && V.state === 'playing') status('<div class="spinner"></div>Buffering…'); },
        onbufferingcomplete: function () { if (live() && V.state === 'playing') status(''); },
        oncurrentplaytime: function (ms) { if (live()) { V.position = ms / 1000; if (V.seekTarget === null) drawBar(); } },
        onstreamcompleted: function () { if (live()) finished(); },
        onerror: function (type) { if (live()) fail(type || 'PLAYER_ERROR'); },
        onsubtitlechange: function (duration, text) { if (live()) subtitle(text, duration); },
        onevent: function () {}
      });
      if (agent) { try { av.setStreamingProperty('USER_AGENT', agent); } catch (e) {} }
      av.setDisplayRect(0, 0, 1920, 1080);
      try { av.setDisplayMethod('PLAYER_DISPLAY_MODE_LETTER_BOX'); } catch (e) {}
      av.prepareAsync(function () {
        if (!live()) return;
        try {
          V.duration = (av.getDuration() || 0) / 1000;
          var start = V.media.start || 0;
          var begin = function () {
            if (!live()) return;
            av.play();
            started();
          };
          if (start > 5 && (!V.duration || start < V.duration - 10)) {
            av.seekTo(Math.floor(start * 1000), begin, begin);
          } else begin();
        } catch (e) { fail('PLAY_FAILED'); }
      }, function (error) { if (live()) fail((error && (error.name || error.message)) || 'PREPARE_FAILED'); });
    } catch (e) {
      fail((e && (e.name || e.message)) || 'OPEN_FAILED');
    }
  }

  function openHTML5(live) {
    var video = document.getElementById('html5-video');
    if (!video) return fail('NO_PLAYER');
    video.style.display = 'block';
    video.onloadedmetadata = function () {
      if (!live()) return;
      V.duration = video.duration || 0;
      if (V.media.start > 5) video.currentTime = V.media.start;
    };
    video.ontimeupdate = function () { if (live()) { V.position = video.currentTime; if (V.seekTarget === null) drawBar(); } };
    video.onplaying = function () { if (live()) started(); };
    video.onended = function () { if (live()) finished(); };
    video.onerror = function () { if (live()) fail('MEDIA_ERROR'); };
    video.src = V.media.url;
    var p = video.play();
    if (p && p.catch) p.catch(function () {});
  }

  function started() {
    clearTimeout(V.tryTimer);
    loadTracks();
    V.state = 'playing';
    status('');
    drawBar();
    showOverlay();
  }

  function fail(reason) {
    clearTimeout(V.tryTimer);
    if (!V.media) return;
    V.log.push((agents()[V.agentIndex] ? agents()[V.agentIndex].split('/')[0] : 'TV default') + ' → ' + reason);
    stopAV();
    if (V.state === 'playing') { V.media.start = V.position; V.agentIndex = 0; V.state = 'loading'; setTimeout(open, 2000); return; }
    if (V.agentIndex + 1 < agents().length) { V.agentIndex += 1; setTimeout(open, 800); return; }
    V.state = 'error';
    status('This title isn’t playing right now.<br><span style="font-size:24px;color:rgba(255,255,255,.6)">Press OK to retry · BACK to close</span>' +
      '<div class="attempts">' + V.log.map(esc).join('<br>') + '</div>');
    showOverlay(true);
  }

  function finished() {
    V.state = 'ended';
    if (V.media) Store.setProgress(V.media.key, null);
    stopAV();
    if (V.media.next) { toast('Next episode'); V.media.next(); return; }
    close();
  }

  function save() {
    var m = V.media;
    if (!m || V.state !== 'playing' && V.state !== 'loading') return;
    if (!V.duration || V.position < 10) return;
    if (V.position > V.duration * 0.95) { Store.setProgress(m.key, null); return; }
    Store.setProgress(m.key, { pos: Math.round(V.position), dur: Math.round(V.duration), kind: m.kind, id: m.id, title: m.title });
    if (m.kind === 'movie') return;
    if (m.onProgress) m.onProgress(Math.round(V.position), Math.round(V.duration));
  }

  function stopAV() {
    V.gen = (V.gen || 0) + 1;
    if (hasAVPlay()) {
      try {
        var av = global.webapis.avplay;
        var state = av.getState();
        if (state !== 'NONE' && state !== 'IDLE') av.stop();
        av.close();
      } catch (e) {}
    } else {
      var video = document.getElementById('html5-video');
      if (video) {
        video.onloadedmetadata = video.ontimeupdate = video.onplaying = video.onended = video.onerror = null;
        video.pause();
        video.removeAttribute('src');
        video.style.display = 'none';
      }
    }
  }

  function close() {
    save();
    stopAV();
    clearInterval(V.clockTimer);
    clearInterval(V.saveTimer);
    clearTimeout(V.seekTimer);
    clearTimeout(V.hideTimer);
    clearTimeout(V.tryTimer);
    UI.App.onVisibility = null;
    var back = V.media && V.media.back;
    V.media = null;
    if (back) back(); else backToLibrary();
  }

  function seekBy(seconds) {
    if (V.state !== 'playing' || !V.duration) return;
    // Held arrows speed up: 10 s steps, then 30 s, then 60 s.
    var now = Date.now();
    V.streak = now - (V.lastSeek || 0) < 450 ? (V.streak || 0) + 1 : 0;
    V.lastSeek = now;
    var step = V.streak > 12 ? 60 : V.streak > 4 ? 30 : 10;
    var base = V.seekTarget !== null ? V.seekTarget : V.position;
    V.seekTarget = clamp(base + (seconds > 0 ? step : -step), 0, Math.max(0, V.duration - 3));
    drawBar();
    showOverlay(true);
    clearTimeout(V.seekTimer);
    V.seekTimer = setTimeout(applySeek, 700);
  }

  function applySeek() {
    var target = V.seekTarget;
    if (target === null) return;
    var done = function () { V.position = target; V.seekTarget = null; drawBar(); showOverlay(); };
    if (hasAVPlay()) {
      try { global.webapis.avplay.seekTo(Math.floor(target * 1000), done, done); } catch (e) { done(); }
    } else {
      var video = document.getElementById('html5-video');
      if (video) video.currentTime = target;
      done();
    }
  }

  function togglePause() {
    if (V.state !== 'playing') return;
    if (hasAVPlay()) {
      var av = global.webapis.avplay;
      try {
        if (V.paused) av.play(); else av.pause();
      } catch (e) { return; }
    } else {
      var video = document.getElementById('html5-video');
      if (!video) return;
      if (V.paused) video.play(); else video.pause();
    }
    V.paused = !V.paused;
    if (V.paused) save();
    toast(V.paused ? 'Paused' : 'Playing');
    showOverlay(V.paused);
  }

  // ---------- Audio & subtitle tracks (Samsung player) ----------
  var LANGS = { eng: 'English', en: 'English', hin: 'Hindi', hi: 'Hindi', pan: 'Punjabi', pa: 'Punjabi', urd: 'Urdu', ur: 'Urdu',
    tam: 'Tamil', ta: 'Tamil', tel: 'Telugu', te: 'Telugu', mal: 'Malayalam', ml: 'Malayalam', ben: 'Bengali', bn: 'Bengali',
    mar: 'Marathi', guj: 'Gujarati', kan: 'Kannada', ara: 'Arabic', ar: 'Arabic', spa: 'Spanish', es: 'Spanish', fre: 'French',
    fra: 'French', fr: 'French', ger: 'German', deu: 'German', de: 'German', ita: 'Italian', it: 'Italian', tur: 'Turkish',
    por: 'Portuguese', rus: 'Russian', chi: 'Chinese', zho: 'Chinese', jpn: 'Japanese', kor: 'Korean', und: 'Unknown' };

  function trackLabel(extra, n, type) {
    var lang = '';
    try {
      var info = typeof extra === 'string' ? JSON.parse(extra) : (extra || {});
      lang = String(info.language || info.track_lang || info.lang || '').toLowerCase();
    } catch (e) {}
    return (LANGS[lang] || (lang ? lang.toUpperCase() : (type === 'AUDIO' ? 'Audio ' : 'Subtitle ') + n));
  }

  function loadTracks() {
    if (!hasAVPlay()) return;
    var av = global.webapis.avplay;
    var t = { audio: [], text: [], audioIndex: -1, textIndex: -1 };
    try {
      (av.getTotalTrackInfo() || []).forEach(function (track) {
        if (track.type === 'AUDIO') t.audio.push({ index: track.index, label: trackLabel(track.extra_info, t.audio.length + 1, 'AUDIO') });
        if (track.type === 'TEXT') t.text.push({ index: track.index, label: trackLabel(track.extra_info, t.text.length + 1, 'TEXT') });
      });
      (av.getCurrentStreamInfo() || []).forEach(function (s) { if (s.type === 'AUDIO') t.audioIndex = Number(s.index); });
      av.setSilentSubtitle(true);
    } catch (e) { /* older firmware */ }
    V.tracks = t;
  }

  function subtitle(text, duration) {
    var box = document.getElementById('vod-subtitle');
    if (!box || V.tracks.textIndex < 0) return;
    box.innerHTML = esc(String(text || '').replace(/<[^>]+>/g, '')).replace(/\n/g, '<br>');
    clearTimeout(V.subTimer);
    V.subTimer = setTimeout(function () { box.innerHTML = ''; }, Number(duration) || 3000);
  }

  function openTracks() {
    var t = V.tracks;
    var box = document.getElementById('tracks');
    if (!box) return;
    if (!t.audio.length && !t.text.length) { toast('No other audio or subtitles in this title'); return; }
    var html = '<h3>AUDIO</h3>' + (t.audio.length ? t.audio.map(function (a) {
      var on = a.index === t.audioIndex || (t.audioIndex < 0 && a === t.audio[0]);
      return '<div class="item focusable' + (on ? ' on' : '') + '" data-type="AUDIO" data-index="' + a.index + '">' + esc(a.label) + (on ? ' ✓' : '') + '</div>';
    }).join('') : '<div class="item">Only one</div>') +
      '<h3>SUBTITLES</h3><div class="item focusable' + (t.textIndex < 0 ? ' on' : '') + '" data-type="TEXT" data-index="-1">Off' + (t.textIndex < 0 ? ' ✓' : '') + '</div>' +
      t.text.map(function (x) {
        var on = x.index === t.textIndex;
        return '<div class="item focusable' + (on ? ' on' : '') + '" data-type="TEXT" data-index="' + x.index + '">' + esc(x.label) + (on ? ' ✓' : '') + '</div>';
      }).join('');
    box.innerHTML = html;
    box.classList.remove('hidden');
    V.tracksOpen = true;
    V.trackFocus = new UI.FormFocus('#tracks .focusable');
    showOverlay(true);
  }

  function closeTracks() {
    var box = document.getElementById('tracks');
    if (box) box.classList.add('hidden');
    V.tracksOpen = false;
    showOverlay();
  }

  function chooseTrack(node) {
    var type = node.getAttribute('data-type');
    var index = Number(node.getAttribute('data-index'));
    var av = global.webapis.avplay;
    try {
      if (type === 'AUDIO') { av.setSelectTrack('AUDIO', index); V.tracks.audioIndex = index; }
      else if (index < 0) { av.setSilentSubtitle(true); V.tracks.textIndex = -1; subtitle('', 1); }
      else { av.setSilentSubtitle(false); av.setSelectTrack('TEXT', index); V.tracks.textIndex = index; }
      toast(type === 'AUDIO' ? 'Audio: ' + node.textContent.replace(' ✓', '') : 'Subtitles: ' + node.textContent.replace(' ✓', ''));
    } catch (e) {
      toast('Couldn’t switch this track');
    }
    closeTracks();
  }

  function vodKey(key) {
    if (V.tracksOpen) {
      if (key === K.UP || key === K.DOWN || key === K.LEFT || key === K.RIGHT) { V.trackFocus.move(key); return; }
      if (key === K.ENTER) { var n = V.trackFocus.current(); if (n) chooseTrack(n); return; }
      if (key === K.BACK || key === K.ESC || key === K.YELLOW) { closeTracks(); return; }
      return false;
    }
    if (key === K.YELLOW || key === K.GREEN) { openTracks(); return; }
    switch (key) {
      case K.LEFT: seekBy(-1); return;
      case K.RIGHT: seekBy(1); return;
      case K.ENTER:
        if (V.state === 'error') { V.agentIndex = 0; V.log = []; open(); return; }
        if (V.seekTarget !== null) { clearTimeout(V.seekTimer); applySeek(); return; }
        togglePause();
        return;
      case K.PLAY_PAUSE: case K.PLAY: case K.PAUSE: togglePause(); return;
      case K.UP: case K.DOWN: case K.INFO: showOverlay(); return;
      case K.CH_UP:
        if (V.media && V.media.next) { save(); stopAV(); V.media.next(); }
        return;
      case K.STOP: case K.BACK: case K.ESC: close(); return;
      default: return false;
    }
  }

  global.VeyloLibrary = {
    show: show,
    cache: { get: cacheGet, put: cachePut },
    load: function (kind) { return client() ? library(kind) : Promise.reject(new Error('no Xtream')); },
    visible: function (kind, lib, items) { return visibleItems(kind, lib, items); },
    /** Opens a movie/series detail from elsewhere (Home); BACK returns there. */
    openItem: function (item, back) {
      Lib.kind = item.kind;
      Lib.returnTo = back || null;
      if (item.kind === 'movie') showMovie(item); else showSeries(item);
    },
    clearCache: function () {
      cacheClear();
      if (UI.App.session) UI.App.session.library = {};
    }
  };
})(window);

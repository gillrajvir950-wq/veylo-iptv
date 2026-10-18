/* Veylo TV — screens and remote navigation (Samsung Tizen, 1920×1080).
 * Written for the 2021 TV web engine (Chromium 76): no optional chaining, no nullish operator, no replace-all, no flex gap. */
(function (global) {
  'use strict';

  var Store = global.VeyloStore;
  var API = global.VeyloAPI;
  var Player = global.VeyloPlayer;
  var VERSION = '0.1.2';

  // ---------- Keys ----------
  var K = {
    LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, ENTER: 13,
    BACK: 10009, ESC: 27, BACKSPACE: 8,
    CH_UP: 427, CH_DOWN: 428,
    PLAY_PAUSE: 10252, PLAY: 415, PAUSE: 19, STOP: 413,
    RED: 403, GREEN: 404, YELLOW: 405, BLUE: 406, INFO: 457,
    IME_DONE: 65376, IME_CANCEL: 65385
  };

  function registerKeys() {
    try {
      var keys = ['ChannelUp', 'ChannelDown', 'MediaPlayPause', 'MediaPlay', 'MediaPause', 'MediaStop',
        'ColorF0Red', 'ColorF1Green', 'ColorF2Yellow', 'ColorF3Blue', 'Info',
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
      keys.forEach(function (k) {
        try { global.tizen.tvinputdevice.registerKey(k); } catch (e) { /* not supported on this model */ }
      });
    } catch (e) { /* browser */ }
  }

  function exitApp() {
    try { global.tizen.application.getCurrentApplication().exit(); } catch (e) { toast('Exit is only available on the TV'); }
  }

  // ---------- Helpers ----------
  function el(html) {
    var box = document.createElement('div');
    box.innerHTML = html.trim();
    return box.firstChild;
  }

  function esc(text) {
    return String(text === undefined || text === null ? '' : text)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function clock(time) {
    var d = new Date(time);
    var h = d.getHours(), m = d.getMinutes();
    return (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m;
  }

  function initials(title) {
    return esc(title.length > 18 ? title.slice(0, 18) + '…' : title);
  }

  function logoHTML(channel) {
    var fallback = '<div class="initials">' + initials(channel.title) + '</div>';
    if (!channel.logo) return '<div class="logo">' + fallback + '</div>';
    return '<div class="logo"><img src="' + esc(channel.logo) + '" onerror="this.parentNode.innerHTML=this.parentNode.getAttribute(\'data-fallback\')"></div>'
      .replace('<div class="logo">', '<div class="logo" data-fallback="' + esc(fallback) + '">');
  }

  var toastTimer = null;
  function toast(message) {
    var node = document.getElementById('toast');
    node.textContent = message;
    node.classList.remove('hidden');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { node.classList.add('hidden'); }, 2400);
  }

  function clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }

  // ---------- Virtual list (handles thousands of rows) ----------
  // Rows are laid out in normal flow (no absolute positions) and the list has a fixed height
  // from CSS: on the TV's older engine flex heights measured ~0, so rows piled up in one slot.
  function VList(container, rowHeight, renderRow, rows) {
    this.container = container;
    this.rows = rows || 8;
    this.inner = container.querySelector('.vlist-inner');
    this.rowHeight = rowHeight;
    this.renderRow = renderRow;
    this.items = [];
    this.index = 0;
    this.top = 0;
    this.focused = false;
  }

  VList.prototype.setItems = function (items, index) {
    this.items = items;
    this.index = clamp(index || 0, 0, Math.max(0, items.length - 1));
    this.top = 0;
    this.render();
  };

  VList.prototype.visibleCount = function () {
    var height = this.container.clientHeight;
    if (!height || height < this.rowHeight * 2) return this.rows;
    return Math.max(1, Math.floor(height / this.rowHeight));
  };

  VList.prototype.move = function (delta) {
    if (!this.items.length) return false;
    var next = clamp(this.index + delta, 0, this.items.length - 1);
    if (next === this.index) return false;
    this.index = next;
    this.render();
    return true;
  };

  VList.prototype.render = function () {
    var visible = this.visibleCount();
    if (this.index < this.top) this.top = this.index;
    if (this.index >= this.top + visible) this.top = this.index - visible + 1;
    this.top = clamp(this.top, 0, Math.max(0, this.items.length - visible));
    var end = Math.min(this.items.length, this.top + visible + 1);
    var html = '';
    for (var i = this.top; i < end; i++) {
      html += this.renderRow(this.items[i], i, i === this.index && this.focused, (i - this.top) * this.rowHeight);
    }
    // Replace the node instead of only its innerHTML so no old row paint can stay behind.
    var fresh = this.inner.cloneNode(false);
    fresh.innerHTML = html;
    this.container.replaceChild(fresh, this.inner);
    this.inner = fresh;
  };

  VList.prototype.current = function () { return this.items[this.index]; };

  // ---------- App state ----------
  var App = {
    screen: null,
    session: null,   // {profile, channels, categories, client, account}
    keyHandler: null,
    lastBack: 0
  };

  function setScreen(name, html, handler) {
    App.screen = name;
    App.keyHandler = handler;
    document.body.classList.toggle('playing', name === 'player');
    document.documentElement.classList.toggle('playing', name === 'player');
    var root = document.getElementById('app');
    root.innerHTML = html;
  }

  document.addEventListener('keydown', function (event) {
    var active = document.activeElement;
    var typing = active && (active.tagName === 'INPUT');
    if (typing) {
      // Text entry with the TV keyboard: only finish/cancel are ours.
      if (event.keyCode === K.IME_DONE || event.keyCode === K.ENTER || event.keyCode === K.IME_CANCEL ||
          event.keyCode === K.BACK || event.keyCode === K.ESC || event.keyCode === K.DOWN || event.keyCode === K.UP) {
        active.blur();
        if (App.onTypingDone) App.onTypingDone(active);
        event.preventDefault();
      }
      return;
    }
    if (App.keyHandler) {
      var handled = App.keyHandler(event.keyCode, event);
      if (handled !== false) event.preventDefault();
    }
  });

  document.addEventListener('visibilitychange', function () {
    if (App.screen !== 'player') return;
    if (document.hidden) Player.suspend(); else Player.restore();
  });

  // ---------- Simple focus manager for forms (login, settings) ----------
  function FormFocus(selector) {
    this.items = Array.prototype.slice.call(document.querySelectorAll(selector));
    this.index = 0;
    this.apply();
  }

  FormFocus.prototype.apply = function () {
    this.items.forEach(function (node, i) { node.classList.toggle('focused', i === this.index); }, this);
    var node = this.items[this.index];
    if (node && node.scrollIntoView) {
      try { node.scrollIntoView({ block: 'nearest' }); } catch (e) { /* old engine */ }
    }
  };

  /** Moves to the closest item in the arrow's direction (by on-screen position). */
  FormFocus.prototype.move = function (key) {
    var current = this.items[this.index];
    if (!current) return;
    var a = current.getBoundingClientRect();
    var ax = a.left + a.width / 2, ay = a.top + a.height / 2;
    var best = -1, bestScore = Infinity;
    this.items.forEach(function (node, i) {
      if (i === this.index || node.offsetParent === null) return;
      var b = node.getBoundingClientRect();
      var bx = b.left + b.width / 2, by = b.top + b.height / 2;
      var dx = bx - ax, dy = by - ay;
      var ok = (key === K.UP && dy < -4) || (key === K.DOWN && dy > 4) ||
               (key === K.LEFT && dx < -4) || (key === K.RIGHT && dx > 4);
      if (!ok) return;
      var main = (key === K.UP || key === K.DOWN) ? Math.abs(dy) : Math.abs(dx);
      var cross = (key === K.UP || key === K.DOWN) ? Math.abs(dx) : Math.abs(dy);
      var score = main + cross * 2.5;
      if (score < bestScore) { bestScore = score; best = i; }
    }, this);
    if (best >= 0) { this.index = best; this.apply(); }
  };

  FormFocus.prototype.current = function () { return this.items[this.index]; };

  // ---------- Login ----------
  function showLogin(errorText, prefill) {
    var saved = Store.providers().sort(function (a, b) { return (b.lastUsed || 0) - (a.lastUsed || 0); });
    var form = prefill || { kind: 'xtream', server: '', username: '', password: '', playlistURL: '', save: true };
    var html =
      '<div class="backdrop"></div>' +
      '<div class="login">' +
        '<div class="login-card">' +
          '<div class="brand"><img src="brand.png"><span>veylo</span></div>' +
          '<h1>Add your provider</h1>' +
          '<p class="sub">Use only streams you are authorized to access.</p>' +
          '<div class="tabs">' +
            '<div class="tab focusable' + (form.kind === 'xtream' ? ' active' : '') + '" data-action="kind" data-kind="xtream">Xtream Codes</div>' +
            '<div class="tab focusable' + (form.kind === 'm3u' ? ' active' : '') + '" data-action="kind" data-kind="m3u">M3U Playlist</div>' +
          '</div>' +
          (form.kind === 'xtream'
            ? field('server', 'Server URL (http://host:port)', form.server) +
              field('username', 'Username', form.username) +
              field('password', 'Password', form.password, 'password')
            : field('playlistURL', 'Playlist URL', form.playlistURL)) +
          '<div class="check focusable' + (form.save ? ' on' : '') + '" data-action="save"><div class="box">' + (form.save ? '✓' : '') + '</div><span>Save this provider on this TV</span></div>' +
          '<div class="button focusable" data-action="connect">Connect</div>' +
          (errorText ? '<div class="error">' + esc(errorText) + '</div>' : '') +
        '</div>' +
        (saved.length
          ? '<div class="saved"><h2>Saved providers</h2>' + saved.map(function (p) {
              return '<div class="saved-item focusable" data-action="open" data-id="' + esc(p.id) + '">' +
                '<div class="icon">' + esc(p.name.charAt(0).toUpperCase()) + '</div>' +
                '<div><div class="name">' + esc(p.name) + '</div><div class="meta">' +
                (p.kind === 'xtream' ? 'Xtream Codes' : 'M3U Playlist') + '</div></div></div>';
            }).join('') + '</div>'
          : '') +
      '</div>' +
      '<div class="foot">VEYLO TV · ' + VERSION + '</div>';

    function field(name, label, value, type) {
      return '<div class="field focusable" data-action="input" data-name="' + name + '">' +
        '<label>' + label + '</label>' +
        '<input name="' + name + '" type="' + (type || 'text') + '" value="' + esc(value) + '" autocomplete="off">' +
        '</div>';
    }

    function readForm() {
      Array.prototype.forEach.call(document.querySelectorAll('.login input'), function (input) {
        form[input.name] = input.value.trim();
      });
    }

    setScreen('login', html, function (key) {
      if (key === K.UP || key === K.DOWN || key === K.LEFT || key === K.RIGHT) { focus.move(key); return; }
      if (key === K.BACK || key === K.ESC) {
        if (App.session) { showBrowser(); return; }
        exitApp();
        return;
      }
      if (key !== K.ENTER) return false;
      var node = focus.current();
      var action = node && node.getAttribute('data-action');
      if (action === 'kind') {
        readForm();
        form.kind = node.getAttribute('data-kind');
        showLogin(null, form);
      } else if (action === 'input') {
        var input = node.querySelector('input');
        input.focus();
      } else if (action === 'save') {
        form.save = !form.save;
        node.classList.toggle('on', form.save);
        node.querySelector('.box').textContent = form.save ? '✓' : '';
      } else if (action === 'connect') {
        readForm();
        var profile = form.kind === 'xtream'
          ? { kind: 'xtream', server: form.server, username: form.username, password: form.password }
          : { kind: 'm3u', playlistURL: form.playlistURL };
        if (form.kind === 'xtream' && (!/^https?:\/\//i.test(form.server) || !form.username || !form.password)) {
          showLogin('Enter the server URL (starting with http://), username and password.', form);
          return;
        }
        if (form.kind === 'm3u' && !/^https?:\/\//i.test(form.playlistURL)) {
          showLogin('Enter the full playlist link (starting with http:// or https://).', form);
          return;
        }
        connect(profile, form.save, form);
      } else if (action === 'open') {
        var id = node.getAttribute('data-id');
        var chosen = Store.providers().filter(function (p) { return p.id === id; })[0];
        if (chosen) connect(chosen, true);
      }
    });

    App.onTypingDone = function () { readForm(); };
    var focus = new FormFocus('.login .focusable');
    if (errorText) {
      // After an error, stay on Connect so a retry is one press away.
      focus.items.forEach(function (node, i) { if (node.getAttribute('data-action') === 'connect') focus.index = i; });
      focus.apply();
    }
  }

  // ---------- Connecting ----------
  function showLoading(message) {
    setScreen('loading',
      '<div class="backdrop"></div><div class="loading">' +
      '<div class="brand"><img src="brand.png"></div><div class="spinner"></div>' +
      '<div class="msg">' + esc(message) + '</div></div>', function (key) {
        if (key === K.BACK || key === K.ESC) exitApp();
      });
  }

  function connect(profile, save, formState) {
    showLoading('Connecting to ' + (profile.name || Store.hostOf(profile.server || profile.playlistURL)) + '…');
    API.connect(profile, Store.format()).then(function (result) {
      var saved = profile;
      if (save) {
        saved = Store.saveProvider(profile);
        Store.setActive(saved.id);
      }
      App.session = {
        profile: saved,
        channels: result.channels,
        categories: result.categories,
        client: result.client || null,
        account: result.account || null
      };
      App.byKey = {};
      result.channels.forEach(function (c) { App.byKey[c.key] = c; });
      Browser.reset();
      showBrowser();
    }).catch(function (error) {
      var message = (error && error.message) || 'Couldn’t connect.';
      if (formState) showLogin(message, formState);
      else showLogin('Couldn’t open ' + (profile.name || 'the saved provider') + '. ' + message);
    });
  }

  // ---------- Browser (categories + channels) ----------
  var Browser = {
    sections: [],
    sectionIndex: 0,
    selected: 0,
    focus: 'list',
    query: '',
    catList: null,
    chList: null,
    epgTimer: null,
    numberBuffer: '',
    numberTimer: null,

    reset: function () {
      this.sectionIndex = 0;
      this.selected = 0;
      this.focus = 'list';
      this.query = '';
      this.positions = {};
    }
  };

  function buildSections() {
    var s = App.session;
    var favs = Store.favorites().map(function (k) { return App.byKey[k]; }).filter(Boolean);
    var recents = Store.recents().map(function (k) { return App.byKey[k]; }).filter(Boolean);
    var sections = [
      { id: 'search', label: Browser.query ? 'Search: ' + Browser.query : 'Search', glyph: '⌕', channels: searchResults() },
      { id: 'all', label: 'All Channels', glyph: '▤', channels: s.channels },
      { id: 'favorites', label: 'Favorites', glyph: '♥', channels: favs },
      { id: 'recent', label: 'Recently Watched', glyph: '↺', channels: recents }
    ];
    s.categories.forEach(function (c, i) {
      sections.push({ id: 'c' + i, label: API.title(c.name), glyph: '', channels: c.channels });
    });
    sections.push({ id: 'settings', label: 'Providers & Settings', glyph: '⚙', channels: [] });
    return sections;
  }

  function searchResults() {
    var q = Browser.query.toLowerCase();
    if (!q || !App.session) return [];
    var out = [];
    var all = App.session.channels;
    for (var i = 0; i < all.length && out.length < 500; i++) {
      if (all[i].name.toLowerCase().indexOf(q) >= 0) out.push(all[i]);
    }
    return out;
  }

  function showBrowser() {
    if (!App.session) { showLogin(); return; }
    Browser.sections = buildSections();
    if (Browser.selected === 0 && !Browser.query) Browser.selected = 1;
    if (Browser.sectionIndex === 0 && !Browser.query) Browser.sectionIndex = 1;

    var html =
      '<div class="backdrop"></div>' +
      '<div class="browser">' +
        '<div class="sidebar">' +
          '<div class="brand"><img src="brand.png"><span>veylo</span></div>' +
          '<input class="search-input" id="search-input" type="text" autocomplete="off">' +
          '<div class="vlist" id="cats"><div class="vlist-inner"></div></div>' +
        '</div>' +
        '<div class="content">' +
          '<div class="content-head"><h1 id="section-title"></h1><div class="sub" id="section-sub"></div></div>' +
          '<div class="content-body">' +
            '<div class="channels vlist" id="channels"><div class="vlist-inner"></div></div>' +
            '<div class="details"><div class="preview" id="preview"></div></div>' +
          '</div>' +
          '<div class="hints">' +
            '<span><span class="key">OK</span>Play</span>' +
            '<span><span class="key">◀ ▶</span>Categories / Channels</span>' +
            '<span><span class="key yellow">&nbsp;</span>Favorite</span>' +
            '<span><span class="key">0-9</span>Channel number</span>' +
            '<span><span class="key">BACK</span>' + (Browser.focus === 'list' ? 'Categories' : 'Exit') + '</span>' +
          '</div>' +
        '</div>' +
      '</div>';

    setScreen('browser', html, browserKey);

    Browser.catList = new VList(document.getElementById('cats'), 74, function (section, i, focused, y) {
      var count = section.id === 'settings' || section.id === 'search' ? '' : section.channels.length;
      return '<div class="cat' + (i === Browser.sectionIndex ? ' selected' : '') + (focused ? ' focused' : '') +
        '">' +
        '<span class="glyph">' + section.glyph + '</span>' +
        '<span class="label">' + esc(section.label) + '</span>' +
        '<span class="count">' + count + '</span></div>';
    }, 12);
    Browser.chList = new VList(document.getElementById('channels'), 112, function (channel, i, focused, y) {
      var fav = Store.isFavorite(channel.key);
      return '<div class="row' + (focused ? ' focused' : '') + '">' +
        '<div class="num">' + (i + 1) + '</div>' + logoHTML(channel) +
        '<div class="info"><div class="title">' + esc(channel.title) + '</div>' +
        '<div class="meta">' + esc(API.title(channel.category)) + '</div></div>' +
        (channel.quality ? '<span class="badge">' + channel.quality + '</span>' : '') +
        (fav ? '<span class="heart">♥</span>' : '') +
        '</div>';
    }, 8);

    Browser.catList.focused = Browser.focus === 'cats';
    Browser.chList.focused = Browser.focus === 'list';
    Browser.catList.setItems(Browser.sections, Browser.sectionIndex);
    openSection(Browser.sectionIndex, Browser.positions[Browser.sections[Browser.sectionIndex].id] || 0);

    App.onTypingDone = function (input) {
      Browser.query = input.value.trim();
      Browser.sections = buildSections();
      Browser.sectionIndex = 0;
      Browser.catList.setItems(Browser.sections, 0);
      openSection(0, 0);
      if (Browser.sections[0].channels.length) setBrowserFocus('list');
    };
  }

  function openSection(index, position) {
    Browser.sectionIndex = index;
    var section = Browser.sections[index];
    document.getElementById('section-title').textContent =
      section.id === 'search' ? (Browser.query ? 'Results for “' + Browser.query + '”' : 'Search') : section.label;
    var sub = section.id === 'settings' ? 'Press OK to open'
      : section.id === 'search' && !Browser.query ? 'Press OK to type'
      : section.channels.length.toLocaleString() + ' channels';
    document.getElementById('section-sub').textContent = sub;
    Browser.chList.setItems(section.channels, position || 0);
    var box = document.getElementById('channels').querySelector('.vlist-inner');
    if (!section.channels.length) {
      var message = {
        favorites: 'No favorites yet.<br>Press the <b>yellow</b> button on any channel to add it here.',
        recent: 'Channels you watch will show up here.',
        search: Browser.query ? 'Nothing found.' : 'Press OK, type a channel name and press Done.',
        settings: 'Switch providers, change the stream format or sign out.<br>Press OK to open.'
      }[section.id] || 'No channels here.';
      box.innerHTML = '<div class="empty">' + message + '</div>';
    }
    updatePreview();
  }

  function setBrowserFocus(where) {
    Browser.focus = where;
    Browser.catList.focused = where === 'cats';
    Browser.chList.focused = where === 'list';
    Browser.catList.render();
    if (Browser.chList.items.length) Browser.chList.render();
    var hint = document.querySelector('.hints > span:last-child');
    if (hint) hint.innerHTML = '<span class="key">BACK</span>' + (where === 'list' ? 'Categories' : 'Exit');
  }

  function updatePreview() {
    var box = document.getElementById('preview');
    if (!box) return;
    var channel = Browser.chList.current();
    if (!channel) {
      var acc = App.session && App.session.account;
      box.innerHTML = '<div class="cat-name">' + esc(App.session.profile.name || 'Provider') + '</div>' +
        '<h2>' + App.session.channels.length.toLocaleString() + ' live channels</h2>' +
        (acc && acc.expires ? '<div class="cat-name">Subscription until ' + acc.expires.toLocaleDateString() + '</div>' : '');
      return;
    }
    box.innerHTML = logoHTML(channel) +
      '<h2>' + esc(channel.title) + '</h2>' +
      '<div class="cat-name">' + esc(API.title(channel.category)) + (channel.quality ? ' · ' + channel.quality : '') + '</div>' +
      '<div class="epg" id="preview-epg"></div>';
    clearTimeout(Browser.epgTimer);
    if (App.session.client && channel.streamID) {
      var key = channel.key;
      Browser.epgTimer = setTimeout(function () {
        App.session.client.shortEPG(channel.streamID).then(function (list) {
          var current = Browser.chList && Browser.chList.current();
          if (!current || current.key !== key) return;
          var target = document.getElementById('preview-epg');
          if (target) target.innerHTML = epgHTML(list);
        }).catch(function () {});
      }, 450);
    }
  }

  function epgHTML(list) {
    if (!list || !list.length) return '';
    var now = Date.now();
    var html = '';
    var nextShown = false;
    list.slice(0, 2).forEach(function (p) {
      var live = p.start <= now && p.end > now;
      var progress = live ? Math.round((now - p.start) / (p.end - p.start) * 100) : 0;
      var label = live ? 'NOW' : (nextShown ? 'LATER' : 'NEXT');
      if (!live) nextShown = true;
      html += '<div class="slot"><div class="when' + (live ? ' now' : '') + '">' + label + '</div>' +
        '<div class="what">' + esc(p.title) + '</div>' +
        '<div class="time">' + clock(p.start) + ' – ' + clock(p.end) + '</div>' +
        (live ? '<div class="bar"><div style="width:' + progress + '%"></div></div>' : '') + '</div>';
    });
    return html;
  }

  function browserKey(key) {
    var section = Browser.sections[Browser.sectionIndex];
    if (key >= 48 && key <= 57 && Browser.chList.items.length) { numberEntry(key - 48); return; }

    if (Browser.focus === 'cats') {
      if (key === K.UP || key === K.DOWN) {
        if (Browser.catList.move(key === K.UP ? -1 : 1)) {
          Browser.positions[section.id] = Browser.chList.index;
          openSection(Browser.catList.index, Browser.positions[Browser.sections[Browser.catList.index].id] || 0);
        }
      } else if (key === K.RIGHT) {
        if (Browser.chList.items.length) setBrowserFocus('list');
      } else if (key === K.ENTER) {
        if (section.id === 'search') { openSearch(); return; }
        if (section.id === 'settings') { showSettings(); return; }
        if (Browser.chList.items.length) setBrowserFocus('list');
      } else if (key === K.BACK || key === K.ESC) {
        var now = Date.now();
        if (now - App.lastBack < 2000) { exitApp(); return; }
        App.lastBack = now;
        toast('Press Back again to exit Veylo');
      } else return false;
      return;
    }

    // Channel list
    if (key === K.UP || key === K.DOWN) {
      if (Browser.chList.move(key === K.UP ? -1 : 1)) updatePreview();
    } else if (key === K.CH_UP || key === K.CH_DOWN) {
      if (Browser.chList.move(key === K.CH_UP ? -Browser.chList.visibleCount() : Browser.chList.visibleCount())) updatePreview();
    } else if (key === K.LEFT || key === K.BACK || key === K.ESC) {
      setBrowserFocus('cats');
    } else if (key === K.ENTER || key === K.PLAY || key === K.PLAY_PAUSE) {
      var channel = Browser.chList.current();
      if (channel) {
        Browser.positions[section.id] = Browser.chList.index;
        showPlayer(section.channels, Browser.chList.index);
      }
    } else if (key === K.YELLOW) {
      toggleFavorite(Browser.chList.current());
      Browser.chList.render();
    } else return false;
  }

  function openSearch() {
    var input = document.getElementById('search-input');
    input.value = Browser.query;
    input.focus();
  }

  function toggleFavorite(channel) {
    if (!channel) return;
    var added = Store.toggleFavorite(channel.key);
    toast(added ? '♥ Added to Favorites' : 'Removed from Favorites');
    var favSection = null;
    Browser.sections.forEach(function (s) { if (s.id === 'favorites') favSection = s; });
    if (favSection) favSection.channels = Store.favorites().map(function (k) { return App.byKey[k]; }).filter(Boolean);
  }

  function numberEntry(digit) {
    Browser.numberBuffer = (Browser.numberBuffer + digit).slice(-5);
    toast('Channel ' + Browser.numberBuffer);
    clearTimeout(Browser.numberTimer);
    Browser.numberTimer = setTimeout(function () {
      var n = parseInt(Browser.numberBuffer, 10);
      Browser.numberBuffer = '';
      if (!n) return;
      var list = App.screen === 'player' ? PlayerScreen.lineup : Browser.chList.items;
      if (n > list.length) { toast('No channel ' + n + ' in this list'); return; }
      if (App.screen === 'player') {
        PlayerScreen.tune(n - 1);
      } else {
        Browser.chList.index = n - 1;
        setBrowserFocus('list');
        updatePreview();
      }
    }, 1400);
  }

  // ---------- Settings ----------
  function showSettings() {
    var s = App.session;
    var providers = Store.providers().sort(function (a, b) { return (b.lastUsed || 0) - (a.lastUsed || 0); });
    var acc = s && s.account;
    var html =
      '<div class="backdrop"></div><div class="settings">' +
      '<div class="brand"><img src="brand.png"><span>veylo</span></div>' +
      '<h1>Providers & Settings</h1>' +
      '<div class="columns"><div>' +
        '<div class="group"><h3>SAVED PROVIDERS</h3>' +
          providers.map(function (p) {
            var active = s && s.profile && s.profile.id === p.id;
            return '<div class="item focusable" data-action="switch" data-id="' + esc(p.id) + '">' + esc(p.name) +
              '<span class="value">' + (active ? 'Active' : (p.kind === 'xtream' ? 'Xtream' : 'M3U')) + '</span></div>';
          }).join('') +
          '<div class="item focusable" data-action="add">＋ Add provider</div>' +
        '</div>' +
      '</div><div>' +
        '<div class="group"><h3>PLAYBACK</h3>' +
          '<div class="item focusable" data-action="format">Live stream format<span class="value">' +
            (Store.format() === 'ts' ? 'MPEG-TS (recommended)' : 'HLS (m3u8)') + '</span></div>' +
        '</div>' +
        (acc ? '<div class="group"><h3>SUBSCRIPTION</h3>' +
          '<div class="item">Status<span class="value">' + esc(acc.status || 'Active') + '</span></div>' +
          '<div class="item">Expires<span class="value">' + (acc.expires ? acc.expires.toLocaleDateString() : 'Never') + '</span></div>' +
          (acc.max ? '<div class="item">Connections<span class="value">' + acc.active + ' of ' + acc.max + ' in use</span></div>' : '') +
          '</div>' : '') +
        '<div class="group"><h3>PROVIDER</h3>' +
          (s && s.profile && s.profile.id ? '<div class="item focusable" data-action="remove">Remove this provider from the TV</div>' : '') +
          '<div class="item focusable" data-action="signout">Sign out</div>' +
        '</div>' +
        '<div class="group"><h3>ABOUT</h3><div class="item">Version<span class="value">' + VERSION + '</span></div></div>' +
      '</div></div></div>';

    setScreen('settings', html, function (key) {
      if (key === K.UP || key === K.DOWN || key === K.LEFT || key === K.RIGHT) { focus.move(key); return; }
      if (key === K.BACK || key === K.ESC) { showBrowser(); return; }
      if (key !== K.ENTER) return false;
      var node = focus.current();
      var action = node && node.getAttribute('data-action');
      if (action === 'switch') {
        var id = node.getAttribute('data-id');
        var chosen = Store.providers().filter(function (p) { return p.id === id; })[0];
        if (chosen) { Store.setActive(chosen.id); Store.touch(chosen.id); connect(chosen, true); }
      } else if (action === 'add') {
        showLogin();
      } else if (action === 'format') {
        Store.setFormat(Store.format() === 'ts' ? 'm3u8' : 'ts');
        toast('Applies the next time you connect');
        showSettings();
      } else if (action === 'remove') {
        Store.removeProvider(s.profile.id);
        App.session = null;
        Store.setActive(null);
        showLogin('Provider removed from this TV.');
      } else if (action === 'signout') {
        Store.setActive(null);
        App.session = null;
        showLogin();
      }
    });
    var focus = new FormFocus('.settings .focusable');
  }

  // ---------- Player ----------
  var PlayerScreen = {
    lineup: [],
    index: 0,
    hideTimer: null,
    epgTimer: null,
    paused: false,
    state: 'loading',

    tune: function (index) {
      var count = this.lineup.length;
      if (!count) return;
      this.index = (index + count) % count;
      var channel = this.lineup[this.index];
      this.paused = false;
      Store.addRecent(channel.key);
      Player.play(channel.url, channel.altURL);
      this.renderInfo();
      this.showOverlay();
      this.loadEPG();
    },

    renderInfo: function () {
      var channel = this.lineup[this.index];
      var panel = document.getElementById('player-panel');
      if (!panel || !channel) return;
      panel.innerHTML = logoHTML(channel) +
        '<div style="flex:1;min-width:0">' +
          '<div class="num">' + (this.index + 1) + ' · ' + esc(API.title(channel.category)) + '</div>' +
          '<div class="name">' + esc(channel.title) + (channel.quality ? ' <span class="badge">' + channel.quality + '</span>' : '') +
          (Store.isFavorite(channel.key) ? ' <span class="heart">♥</span>' : '') + '</div>' +
          '<div class="epg" id="player-epg"></div>' +
        '</div>';
    },

    loadEPG: function () {
      clearTimeout(this.epgTimer);
      var channel = this.lineup[this.index];
      var client = App.session && App.session.client;
      if (!client || !channel || !channel.streamID) return;
      var self = this;
      this.epgTimer = setTimeout(function () {
        client.shortEPG(channel.streamID).then(function (list) {
          if (self.lineup[self.index] !== channel) return;
          var box = document.getElementById('player-epg');
          if (box) box.innerHTML = epgHTML(list);
        }).catch(function () {});
      }, 300);
    },

    setState: function (state) {
      this.state = state;
      var box = document.getElementById('player-status');
      if (!box) return;
      if (state === 'loading') {
        box.innerHTML = '<div class="spinner"></div>Loading…';
      } else if (state === 'error') {
        var code = Player.lastError ? '<div style="font-size:18px;color:rgba(255,255,255,.4);margin-top:14px">' + esc(Player.lastError) + '</div>' : '';
        box.innerHTML = 'This channel isn’t playing right now.<br><span style="font-size:24px;color:rgba(255,255,255,.6)">Press OK to retry · ▲▼ for another channel</span>' +
          '<div id="player-reason" style="font-size:24px;color:#ffd60a;margin-top:18px"></div>' + code;
        this.showOverlay(true);
        this.checkConnections();
      } else if (state === 'ended') {
        box.innerHTML = 'Stream ended.';
      } else {
        box.innerHTML = '';
      }
    },

    /** Most "plays once, then fails" cases are the provider's connection limit. */
    checkConnections: function () {
      var client = App.session && App.session.client;
      if (!client || !client.authenticate) return;
      var channel = this.lineup[this.index];
      client.authenticate().then(function (acc) {
        if (PlayerScreen.lineup[PlayerScreen.index] !== channel || PlayerScreen.state !== 'error') return;
        App.session.account = acc;
        var box = document.getElementById('player-reason');
        if (!box) return;
        if (acc.status && acc.status.toLowerCase() !== 'active') {
          box.textContent = 'Your subscription is ' + acc.status.toLowerCase() + '.';
        } else if (acc.max && acc.active >= acc.max) {
          box.textContent = 'All ' + acc.max + ' connection' + (acc.max === 1 ? '' : 's') +
            ' of your plan are in use. Close Veylo on other devices, wait a minute and press OK.';
        }
      }).catch(function () {});
    },

    showOverlay: function (stay) {
      var overlay = document.getElementById('player-overlay');
      if (!overlay) return;
      overlay.classList.remove('hidden');
      clearTimeout(this.hideTimer);
      if (stay) return;
      this.hideTimer = setTimeout(function () {
        if (PlayerScreen.state === 'playing' && !PlayerScreen.paused) overlay.classList.add('hidden');
      }, 5000);
    },

    tick: function () {
      var c = document.getElementById('player-clock');
      if (c) c.textContent = clock(Date.now());
    }
  };

  function showPlayer(lineup, index) {
    PlayerScreen.lineup = lineup.slice();
    var html =
      '<div class="player">' +
        '<div id="player-overlay">' +
          '<div class="shade-top"></div><div class="shade-bottom"></div>' +
          '<div class="top"><span class="live-pill">● LIVE</span><span class="clock" id="player-clock"></span></div>' +
          '<div class="panel" id="player-panel"></div>' +
          '<div class="hints">' +
            '<span><span class="key">▲▼</span>Channel</span>' +
            '<span><span class="key">0-9</span>Number</span>' +
            '<span><span class="key yellow">&nbsp;</span>Favorite</span>' +
            '<span><span class="key">⏯</span>Pause</span>' +
            '<span><span class="key">BACK</span>Channel list</span>' +
          '</div>' +
        '</div>' +
        '<div class="status" id="player-status"></div>' +
      '</div>';
    setScreen('player', html, playerKey);
    Player.onState = function (state) { PlayerScreen.setState(state); };
    PlayerScreen.tick();
    clearInterval(PlayerScreen.clockTimer);
    PlayerScreen.clockTimer = setInterval(PlayerScreen.tick, 15000);
    PlayerScreen.tune(index);
  }

  function leavePlayer() {
    Player.stop();
    clearInterval(PlayerScreen.clockTimer);
    clearTimeout(PlayerScreen.hideTimer);
    var section = Browser.sections[Browser.sectionIndex];
    if (section && section.channels.length && PlayerScreen.lineup.length) {
      var playing = PlayerScreen.lineup[PlayerScreen.index];
      var at = section.channels.indexOf(playing);
      if (at >= 0) Browser.positions[section.id] = at;
    }
    Browser.focus = 'list';
    showBrowser();
  }

  function playerKey(key) {
    if (key >= 48 && key <= 57) { numberEntry(key - 48); PlayerScreen.showOverlay(); return; }
    switch (key) {
      case K.UP: case K.CH_UP:
        PlayerScreen.tune(PlayerScreen.index - 1); return;
      case K.DOWN: case K.CH_DOWN:
        PlayerScreen.tune(PlayerScreen.index + 1); return;
      case K.ENTER: case K.INFO: case K.LEFT: case K.RIGHT:
        if (PlayerScreen.state === 'error' && key === K.ENTER) { PlayerScreen.tune(PlayerScreen.index); return; }
        var overlay = document.getElementById('player-overlay');
        if (overlay && !overlay.classList.contains('hidden') && key === K.ENTER) overlay.classList.add('hidden');
        else PlayerScreen.showOverlay();
        return;
      case K.PLAY_PAUSE: case K.PLAY: case K.PAUSE:
        PlayerScreen.paused = Player.togglePause();
        toast(PlayerScreen.paused ? 'Paused' : 'Playing');
        PlayerScreen.showOverlay(PlayerScreen.paused);
        return;
      case K.YELLOW:
        toggleFavorite(PlayerScreen.lineup[PlayerScreen.index]);
        PlayerScreen.renderInfo();
        PlayerScreen.loadEPG();
        PlayerScreen.showOverlay();
        return;
      case K.STOP: case K.BACK: case K.ESC:
        leavePlayer(); return;
      default:
        return false;
    }
  }

  // ---------- Start ----------
  function start() {
    registerKeys();
    var active = Store.active();
    if (active) connect(active, true);
    else showLogin();
  }

  global.VeyloApp = { start: start, version: VERSION };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})(window);

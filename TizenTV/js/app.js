/* Veylo TV — screens and remote navigation (Samsung Tizen, 1920×1080).
 * Written for the 2021 TV web engine (Chromium 76): no optional chaining, no nullish operator, no replace-all, no flex gap. */
(function (global) {
  'use strict';

  var Store = global.VeyloStore;
  var API = global.VeyloAPI;
  var Player = global.VeyloPlayer;
  var VERSION = '0.2.11';

  // ---------- Keys ----------
  var K = {
    LEFT: 37, UP: 38, RIGHT: 39, DOWN: 40, ENTER: 13,
    BACK: 10009, ESC: 27, BACKSPACE: 8,
    CH_UP: 427, CH_DOWN: 428,
    PLAY_PAUSE: 10252, PLAY: 415, PAUSE: 19, STOP: 413,
    RED: 403, GREEN: 404, YELLOW: 405, BLUE: 406, INFO: 457, PRECH: 10190,
    IME_DONE: 65376, IME_CANCEL: 65385
  };

  function registerKeys() {
    try {
      var keys = ['ChannelUp', 'ChannelDown', 'MediaPlayPause', 'MediaPlay', 'MediaPause', 'MediaStop',
        'ColorF0Red', 'ColorF1Green', 'ColorF2Yellow', 'ColorF3Blue', 'Info', 'PreviousChannel',
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
    return '<div class="logo"><img decoding="async" loading="lazy" src="' + esc(channel.logo) + '" onerror="this.parentNode.innerHTML=this.parentNode.getAttribute(\'data-fallback\')"></div>'
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

  // ---------- Top menu: Live TV · Movies · Series · Settings ----------
  var TABS = [
    { id: 'home', label: 'Home' },
    { id: 'live', label: 'Live TV' },
    { id: 'movies', label: 'Movies' },
    { id: 'series', label: 'Series' },
    { id: 'settings', label: 'Settings' }
  ];
  var Nav = { active: 'live', index: 0, focused: false };

  function navHTML(active) {
    Nav.active = active;
    Nav.focused = false;
    var who = App.session && App.session.profile ? (App.session.profile.name || '') : '';
    return '<div class="navbar"><div class="brand"><img src="brand.png"><span>veylo</span></div>' +
      '<div class="nav-tabs">' + TABS.map(function (t) {
        return '<div class="nav-tab' + (t.id === active ? ' active' : '') + '" data-tab="' + t.id + '">' + t.label + '</div>';
      }).join('') + '</div>' +
      '<div class="nav-right"><span class="who">' + esc(who) + '</span><em class="build">v' + VERSION + '</em>' +
      '<span class="clock" id="nav-clock">' + clock(Date.now()) + '</span></div></div>';
  }

  function navRender() {
    var tabs = document.querySelectorAll('.navbar .nav-tab');
    Array.prototype.forEach.call(tabs, function (node, i) {
      node.classList.toggle('focused', Nav.focused && i === Nav.index);
    });
  }

  function navFocus(on) {
    Nav.focused = on;
    if (on) TABS.forEach(function (t, i) { if (t.id === Nav.active) Nav.index = i; });
    navRender();
  }

  /** Keys while the menu is focused. `down` gives focus back to the page. */
  function navKey(key, down) {
    if (key === K.LEFT || key === K.RIGHT) {
      Nav.index = clamp(Nav.index + (key === K.LEFT ? -1 : 1), 0, TABS.length - 1);
      navRender();
      return;
    }
    if (key === K.ENTER) {
      var tab = TABS[Nav.index].id;
      if (tab === Nav.active) { navFocus(false); down(); } else openTab(tab);
      return;
    }
    if (key === K.DOWN) { navFocus(false); down(); return; }
    if (key === K.BACK || key === K.ESC) { askExit(); return; }
    return false;
  }

  function askExit() {
    var now = Date.now();
    if (now - App.lastBack < 2000) { exitApp(); return; }
    App.lastBack = now;
    toast('Press Back again to exit Veylo');
  }

  function openTab(id) {
    if (!App.session) { showLogin(); return; }
    if (id === 'live') { Browser.focus = 'cats'; showBrowser(); }
    else if (id === 'settings') showSettings();
    else if (id === 'home' && global.VeyloHome) global.VeyloHome.show();
    else if (global.VeyloLibrary) global.VeyloLibrary.show(id === 'movies' ? 'movie' : 'series');
  }

  setInterval(function () {
    var node = document.getElementById('nav-clock');
    if (node) node.textContent = clock(Date.now());
  }, 10000);

  // ---------- Parental lock ----------
  var ADULT = /\b(adult|adults|xxx|18\s*\+|\+\s*18|porn|erotic|for adults)\b/i;

  /** kind: 'live' | 'movie' | 'series'. Locked when a PIN exists and the category is chosen,
   *  or looks adult and automatic adult locking is on. */
  function isLockedCat(kind, name) {
    if (!Store.pin()) return false;
    var id = kind + ':' + name;
    var list = Store.lockedCats();
    if (list.indexOf(id) >= 0) return true;
    return Store.autoAdult() && ADULT.test(name) && list.indexOf('!' + id) < 0;
  }

  /** Hides locked live categories (and their channels) until the PIN is entered this session. */
  function applyLock() {
    var s = App.session;
    if (!s) return;
    if (!s.allChannels) { s.allChannels = s.channels; s.allCategories = s.categories; }
    s.hidden = {};
    s.lockedCount = 0;
    if (!Store.pin() || App.unlocked) {
      s.channels = s.allChannels;
      s.categories = s.allCategories;
    } else {
      var locked = s.allCategories.filter(function (c) { return isLockedCat('live', c.name); });
      locked.forEach(function (c) { c.channels.forEach(function (ch) { s.hidden[ch.key] = true; }); });
      s.lockedCount = locked.length;
      s.categories = s.allCategories.filter(function (c) { return locked.indexOf(c) < 0; });
      s.channels = s.lockedCount ? s.allChannels.filter(function (ch) { return !s.hidden[ch.key]; }) : s.allChannels;
    }
    s.countries = buildCountries(s.categories);
  }

  function isHidden(channel) {
    var s = App.session;
    return !!(s && s.hidden && s.hidden[channel.key]);
  }

  /** PIN pad over the current screen: digits from the remote, or ▲▼ to change and ◀▶ to move. */
  function askPIN(title, done, cancel) {
    var digits = [-1, -1, -1, -1];
    var at = 0;
    var saved = App.keyHandler;
    var box = document.createElement('div');
    box.className = 'pin-modal';
    document.body.appendChild(box);
    function draw(error) {
      box.innerHTML = '<div class="pin-card"><h2>' + esc(title) + '</h2><div class="pin-cells">' +
        digits.map(function (d, i) {
          return '<div class="pin-cell' + (i === at ? ' focused' : '') + '">' + (d < 0 ? '' : (i === at ? d : '•')) + '</div>';
        }).join('') + '</div>' +
        (error ? '<div class="pin-error">' + esc(error) + '</div>' : '') +
        '<div class="pin-hint">0–9 or ▲▼ to choose · ◀▶ move · OK confirm · BACK cancel</div></div>';
    }
    function close() {
      if (box.parentNode) box.parentNode.removeChild(box);
      App.keyHandler = saved;
    }
    function finish() {
      if (digits.some(function (d) { return d < 0; })) { draw('Enter all four digits'); return; }
      var pin = digits.join('');
      var result = done(pin);
      if (result === false) { digits = [-1, -1, -1, -1]; at = 0; draw('Wrong PIN'); return; }
      close();
    }
    App.keyHandler = function (key) {
      if (key >= 48 && key <= 57) {
        digits[at] = key - 48;
        if (at < 3) at += 1; else { draw(); finish(); return; }
        draw();
        return;
      }
      if (key === K.UP || key === K.DOWN) {
        var d = digits[at] < 0 ? 0 : digits[at];
        digits[at] = (d + (key === K.UP ? 1 : 9)) % 10;
        draw();
        return;
      }
      if (key === K.LEFT) { at = Math.max(0, at - 1); draw(); return; }
      if (key === K.RIGHT) { if (digits[at] < 0) digits[at] = 0; at = Math.min(3, at + 1); draw(); return; }
      if (key === K.ENTER) { finish(); return; }
      if (key === K.BACK || key === K.ESC) { close(); if (cancel) cancel(); return; }
      return false;
    };
    draw();
  }

  /** Asks for the PIN (if any) and unlocks locked content for this session. */
  function unlock(then) {
    if (!Store.pin() || App.unlocked) { then(); return; }
    askPIN('Enter your PIN', function (pin) {
      if (pin !== Store.pin()) return false;
      App.unlocked = true;
      applyLock();
      setTimeout(then, 0);
    });
  }

  // ---------- Countries (from the provider's own category names) ----------
  var COUNTRY_NAMES = {
    IN: 'India', PK: 'Pakistan', BD: 'Bangladesh', LK: 'Sri Lanka', NP: 'Nepal', AF: 'Afghanistan',
    UK: 'United Kingdom', IE: 'Ireland', US: 'USA', CA: 'Canada', AU: 'Australia', NZ: 'New Zealand',
    DE: 'Germany', AT: 'Austria', CH: 'Switzerland', FR: 'France', BE: 'Belgium', NL: 'Netherlands',
    ES: 'Spain', PT: 'Portugal', IT: 'Italy', PL: 'Poland', TR: 'Turkey', GR: 'Greece', RO: 'Romania',
    BG: 'Bulgaria', HU: 'Hungary', CZ: 'Czechia', SK: 'Slovakia', SE: 'Sweden', NO: 'Norway', DK: 'Denmark',
    FI: 'Finland', RU: 'Russia', UA: 'Ukraine', AL: 'Albania', EXYU: 'Ex-Yu', AR: 'Arabic', AE: 'UAE',
    SA: 'Saudi Arabia', QA: 'Qatar', KW: 'Kuwait', EG: 'Egypt', MA: 'Morocco', DZ: 'Algeria', TN: 'Tunisia',
    IL: 'Israel', IR: 'Iran', IQ: 'Iraq', KU: 'Kurdish', NG: 'Nigeria', ZA: 'South Africa', KE: 'Kenya',
    AFR: 'Africa', BR: 'Brazil', MX: 'Mexico', LAT: 'Latino', CO: 'Colombia', CL: 'Chile', PH: 'Philippines',
    ID: 'Indonesia', MY: 'Malaysia', SG: 'Singapore', TH: 'Thailand', VN: 'Vietnam', CN: 'China',
    HK: 'Hong Kong', TW: 'Taiwan', JP: 'Japan', KR: 'Korea', CAR: 'Caribbean'
  };
  var COUNTRY_ALIASES = { GB: 'UK', USA: 'US', UAE: 'AE', KSA: 'SA', ARB: 'AR', ARA: 'AR', YU: 'EXYU', IND: 'IN', PAK: 'PK', CAN: 'CA', GER: 'DE', DEU: 'DE', FRA: 'FR', ESP: 'ES', ITA: 'IT', TUR: 'TR', POR: 'PT', NED: 'NL', AUS: 'AU', BAN: 'BD' };
  var COUNTRY_WORDS = [
    [/\b(INDIA|INDIAN|HINDI|PUNJABI|TAMIL|TELUGU|MALAYALAM|MARATHI|BENGALI|BANGLA INDIA|GUJARATI|KANNADA|BHOJPURI)\b/, 'IN'],
    [/\b(PAKISTAN|PAKISTANI|URDU)\b/, 'PK'], [/\bBANGLADESH\b/, 'BD'], [/\bNEPAL\b/, 'NP'], [/\bSRI ?LANKA\b/, 'LK'],
    [/\b(UNITED KINGDOM|BRITISH|ENGLAND)\b/, 'UK'], [/\b(USA|AMERICA|AMERICAN)\b/, 'US'], [/\bCANADA\b/, 'CA'],
    [/\bAUSTRALIA\b/, 'AU'], [/\b(ARAB|ARABIC)\b/, 'AR'], [/\b(GERMANY|DEUTSCH)\b/, 'DE'], [/\bFRANCE\b/, 'FR'],
    [/\b(SPAIN|ESPANA)\b/, 'ES'], [/\bITALY\b/, 'IT'], [/\bTURK(EY|ISH)\b/, 'TR'], [/\bAFRICA\b/, 'AFR'],
    [/\b(LATINO|LATIN)\b/, 'LAT'], [/\bCARIBBEAN\b/, 'CAR'], [/\bAFGHAN/, 'AF']
  ];

  /** "IN| SPORTS", "|UK| News", "USA: Movies", "Hindi Movies" → country code ('' if none). */
  function countryOf(name) {
    var upper = String(name || '').toUpperCase();
    var m = /^[\s|\[\(]*([A-Z]{2,4})[\s]*[|\]\):\-•]/.exec(upper);
    if (m) {
      var code = COUNTRY_ALIASES[m[1]] || m[1];
      if (COUNTRY_NAMES[code]) return code;
    }
    for (var i = 0; i < COUNTRY_WORDS.length; i++) if (COUNTRY_WORDS[i][0].test(upper)) return COUNTRY_WORDS[i][1];
    return '';
  }

  /** Countries in the provider's category order, each with its categories and channels;
   *  null when the provider's names don't say (then the plain category list is shown). */
  function buildCountries(categories) {
    var byCode = {}, order = [], covered = 0;
    categories.forEach(function (c) {
      var code = countryOf(c.name);
      if (!code) {
        // Fall back to the channels' own prefixes ("UK: BBC One") when most of them agree.
        var votes = {}, best = '', bestCount = 0;
        c.channels.slice(0, 60).forEach(function (ch) {
          var v = countryOf(ch.name);
          if (!v) return;
          votes[v] = (votes[v] || 0) + 1;
          if (votes[v] > bestCount) { bestCount = votes[v]; best = v; }
        });
        if (best && bestCount >= Math.min(c.channels.length, 60) * 0.6) code = best;
      }
      if (code) covered += 1;
      code = code || 'OTHER';
      if (!byCode[code]) { byCode[code] = { code: code, name: COUNTRY_NAMES[code] || 'Other', categories: [], channels: [] }; order.push(code); }
      byCode[code].categories.push(c);
      byCode[code].channels = byCode[code].channels.concat(c.channels);
    });
    var real = order.filter(function (c) { return c !== 'OTHER'; });
    if (real.length < 2 || covered < categories.length * 0.3) return null;
    if (byCode.OTHER) { order = real.concat(['OTHER']); }
    return order.map(function (code) { return byCode[code]; });
  }

  // ---------- Virtual list (handles thousands of rows) ----------
  // A buffer of rows (a few screens' worth) is built at once and slid with a GPU transform;
  // moving the highlight only swaps one class. Rows are only rebuilt when the window leaves
  // the buffer (every ~2–3 screens), not on every key press.
  // The list has a fixed CSS height (older TV engines measured flex heights as ~0).
  function VList(container, rowHeight, renderRow, rows) {
    this.container = container;
    this.inner = container.querySelector('.vlist-inner');
    this.rowHeight = rowHeight;
    this.renderRow = renderRow;
    this.rows = rows || 8;
    this.items = [];
    this.index = 0;
    this.top = 0;
    this.bufStart = 0;
    this.bufEnd = 0;
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

  /** Keeps `index` inside the visible window; returns the window's first row. */
  VList.prototype.windowTop = function () {
    var visible = this.visibleCount();
    var top = this.top;
    if (this.index < top) top = this.index;
    if (this.index >= top + visible) top = this.index - visible + 1;
    return clamp(top, 0, Math.max(0, this.items.length - visible));
  };

  VList.prototype.move = function (delta) {
    if (!this.items.length) return false;
    var next = clamp(this.index + delta, 0, this.items.length - 1);
    if (next === this.index) return false;
    var old = this.index;
    this.index = next;
    var top = this.windowTop();
    var visible = this.visibleCount();
    // Window (plus the partly visible next row) still inside the built rows: just slide.
    if (top >= this.bufStart && Math.min(this.items.length, top + visible + 1) <= this.bufEnd) {
      var rows = this.inner.children;
      var a = rows[old - this.bufStart], b = rows[next - this.bufStart];
      if (b) {
        if (a) a.classList.remove('focused');
        if (this.focused) b.classList.add('focused');
        this.top = top;
        this.slide(true);
        return true;
      }
    }
    this.top = top;
    this.build(delta > 0 ? 1 : -1);
    return true;
  };

  VList.prototype.slide = function (animate) {
    var y = -(this.top - this.bufStart) * this.rowHeight;
    this.inner.style.transition = animate && !App.held ? '' : 'none';
    this.inner.style.transform = 'translate3d(0,' + y + 'px,0)';
    this.inner.style.webkitTransform = 'translate3d(0,' + y + 'px,0)';
  };

  /** Rebuilds the row buffer around the window, leaving more room in the direction of travel. */
  VList.prototype.build = function (direction) {
    var visible = this.visibleCount();
    var size = visible * 4;
    var start;
    if (direction > 0) start = this.top - 2;
    else if (direction < 0) start = this.top + visible + 2 - size;
    else start = this.top - visible;
    start = clamp(start, 0, Math.max(0, this.items.length - size));
    var end = Math.min(this.items.length, start + size);
    this.bufStart = start;
    this.bufEnd = end;
    var html = '';
    for (var i = start; i < end; i++) {
      html += this.renderRow(this.items[i], i, i === this.index && this.focused, 0);
    }
    // Replace the node instead of only its innerHTML so no old row paint can stay behind.
    var fresh = this.inner.cloneNode(false);
    fresh.innerHTML = html;
    this.container.replaceChild(fresh, this.inner);
    this.inner = fresh;
    this.slide(false);
  };

  /** Full redraw (focus changes, favorites, new section). */
  VList.prototype.render = function () {
    this.top = this.windowTop();
    this.build(0);
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
    if (global.VeyloGuide) global.VeyloGuide.unmount();
    if (Browser.pendingSection) { clearTimeout(Browser.pendingSection); Browser.pendingSection = null; }
    clearTimeout(Browser.previewTimer);
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
    if (event.repeat && App.lastKeyTime && Date.now() - App.lastKeyTime < 70) { event.preventDefault(); return; }
    App.lastKeyTime = Date.now();
    // Held arrow: count repeats (lists speed up and skip animations while held).
    App.held = event.repeat ? (App.held || 0) + 1 : 0;
    if (App.keyHandler) {
      var handled = App.keyHandler(event.keyCode, event);
      if (handled !== false) event.preventDefault();
    }
  });

  // In the background (Home, another source) the stream is stopped so it doesn't hold the
  // provider's connection or download data; it starts again when Veylo comes back.
  document.addEventListener('visibilitychange', function () {
    if (App.screen === 'player') {
      if (document.hidden) {
        PlayerScreen.suspended = true;
        clearTimeout(PlayerScreen.tuneTimer);
        Player.stop();
      } else if (PlayerScreen.suspended) {
        PlayerScreen.suspended = false;
        PlayerScreen.tune(PlayerScreen.index, true);
      }
      return;
    }
    if (App.onVisibility) App.onVisibility(document.hidden);
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
  function showLogin(errorText, prefill, options) {
    options = options || {};
    var adding = !!(options.adding || (prefill && prefill.adding));
    var saved = adding ? [] : Store.providers().sort(function (a, b) { return (b.lastUsed || 0) - (a.lastUsed || 0); });
    var form = prefill || { kind: 'xtream', server: '', username: '', password: '', playlistURL: '', name: '', save: true };
    form.adding = adding;
    var html =
      '<div class="backdrop"></div>' +
      '<div class="login">' +
        '<div class="login-card">' +
          '<div class="brand"><img src="brand.png"><span>veylo</span></div>' +
          '<h1>' + (adding ? 'Add another account' : 'Add your provider') + '</h1>' +
          '<p class="sub">Use only streams you are authorized to access.</p>' +
          '<div class="tabs">' +
            '<div class="tab focusable' + (form.kind === 'xtream' ? ' active' : '') + '" data-action="kind" data-kind="xtream">Xtream Codes</div>' +
            '<div class="tab focusable' + (form.kind === 'm3u' ? ' active' : '') + '" data-action="kind" data-kind="m3u">M3U Playlist</div>' +
          '</div>' +
          (form.kind === 'xtream'
            ? field('server', 'Server URL (http://host:port)', form.server) +
              field('username', 'Username', form.username) +
              field('password', 'Password', form.password, 'password')
            : field('playlistURL', 'Playlist URL', form.playlistURL) +
              field('epgURL', 'TV guide link (optional, XMLTV)', form.epgURL || '')) +
          field('name', 'Account name (optional, e.g. "Home" or "Sports")', form.name || '') +
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
        if (adding) { showAccounts(); return; }
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
        // "host:8080" typed without http:// is accepted (same as the phone apps).
        if (form.kind === 'xtream' && form.server && !/^[a-z][a-z0-9+.-]*:\/\//i.test(form.server.trim())) {
          form.server = 'http://' + form.server.trim();
        }
        var profile = form.kind === 'xtream'
          ? { kind: 'xtream', server: form.server, username: form.username, password: form.password }
          : { kind: 'm3u', playlistURL: form.playlistURL, epgURL: form.epgURL || '' };
        if (form.name) profile.name = form.name;
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

  /** `retries` (auto sign-in at app start): the TV's network is often not up yet right after
   *  power-on, so "couldn't reach" / timeouts are retried a few seconds later. */
  function connect(profile, save, formState, retries, autostart) {
    showLoading('Connecting to ' + (profile.name || Store.hostOf(profile.server || profile.playlistURL)) + '…');
    API.connect(profile, Store.format()).then(function (result) {
      var saved = profile;
      // An account saved earlier and typed again (e.g. with a new password) is updated even when
      // "Save this provider" was off, so the saved copy never keeps an old password.
      var known = !save && !profile.id ? Store.matchProvider(profile) : null;
      if (save || known) {
        if (known && !profile.name) profile.name = known.name;
        if (known && profile.kind === 'm3u' && !profile.epgURL) profile.epgURL = known.epgURL || '';
        saved = Store.saveProvider(profile);
        if (save) Store.setActive(saved.id);
      }
      App.session = {
        profile: saved,
        channels: result.channels,
        categories: result.categories,
        client: result.client || null,
        account: result.account || null
      };
      // Favorites, recents, My List and resume points are kept per account.
      Store.setScope(saved.id || ('host:' + Store.hostOf(profile.server || profile.playlistURL) + '|' + (profile.username || '')));
      App.unlocked = false;
      applyLock();
      // M3U accounts: TV guide from the playlist's XMLTV link (or the one saved with the account).
      if (!App.session.client && global.VeyloXMLTV) global.VeyloXMLTV.load(App.session, profile.epgURL || result.guideURL || '', Store.scope);
      App.byKey = {};
      result.channels.forEach(function (c) { App.byKey[c.key] = c; });
      Browser.reset();
      PlayerScreen.previous = null;
      if (global.VeyloHome) global.VeyloHome.show(); else showBrowser();
      if (autostart && Store.autostart()) startLastChannel();
    }).catch(function (error) {
      var offline = error && (error.status === 0 || error.status === -1);
      if (retries > 0 && offline) {
        showLoading('Waiting for the network…');
        setTimeout(function () {
          if (App.screen === 'loading') connect(profile, save, formState, retries - 1, autostart);
        }, 4000);
        return;
      }
      var message = (error && error.message) || 'Couldn’t connect.';
      if (formState) { showLogin(message, formState); return; }
      // Switching accounts while one is open: keep watching the current one.
      if (App.session && !autostart) {
        if (global.VeyloHome) global.VeyloHome.show(); else showBrowser();
        toast('Couldn’t open ' + (profile.name || 'that account') + ': ' + message);
        return;
      }
      // A saved account: its details stay in the form, so a new password or a retry is one step.
      showLogin('Couldn’t open ' + (profile.name || 'the saved provider') + '. ' + message, {
        kind: profile.kind || 'xtream', server: profile.server || '', username: profile.username || '',
        password: profile.password || '', playlistURL: profile.playlistURL || '', epgURL: profile.epgURL || '',
        name: profile.name || '', save: true
      });
    });
  }

  /** App start: the channel watched last (on this account) plays straight away. */
  function startLastChannel() {
    var key = Store.lastChannel();
    var channel = key && App.byKey[key];
    if (!channel || isHidden(channel)) return;   // a locked channel never starts without the PIN
    var cat = App.session.categories.filter(function (c) { return c.channels.indexOf(channel) >= 0; })[0];
    var lineup = cat ? cat.channels : App.session.channels;
    Browser.focus = 'list';
    showPlayer(lineup, lineup.indexOf(channel), cat ? API.title(cat.name) : 'All Channels');
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

    level: 'top',     // 'top' | 'country'
    country: null,    // country object while level === 'country'

    reset: function () {
      this.sectionIndex = 0;
      this.selected = 0;
      this.focus = 'list';
      this.query = '';
      this.positions = {};
      this.level = 'top';
      this.country = null;
    }
  };

  /** Sidebar icon. The search mark is drawn (the TV font has no magnifier character). */
  var SEARCH_ICON = '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round">' +
    '<circle cx="10.5" cy="10.5" r="6.5"/><line x1="15.5" y1="15.5" x2="21" y2="21"/></svg>';
  function glyphHTML(glyph, code) {
    return '<span class="glyph' + (code ? ' code' : '') + '">' + (glyph === 'search' ? SEARCH_ICON : esc(glyph)) + '</span>';
  }

  function buildSections() {
    var s = App.session;
    var favs = Store.favorites().map(function (k) { return App.byKey[k]; }).filter(function (c) { return c && !isHidden(c); });
    var recents = Store.recents().map(function (k) { return App.byKey[k]; }).filter(function (c) { return c && !isHidden(c); });
    var sections = [
      { id: 'search', label: Browser.query ? 'Search: ' + Browser.query : 'Search', glyph: 'search', channels: searchResults() },
      { id: 'all', label: 'All Channels', glyph: '▤', channels: s.channels },
      { id: 'favorites', label: 'Favorites', glyph: '♥', channels: favs },
      { id: 'recent', label: 'Recently Watched', glyph: '↺', channels: recents }
    ];
    if (s.countries && Browser.level === 'country' && Browser.country) {
      var country = Browser.country;
      var inside = [
        { id: 'back', label: 'All countries', glyph: '‹', type: 'back', channels: [] },
        { id: 'cn:' + country.code, label: 'All ' + country.name, glyph: country.code === 'OTHER' ? '…' : country.code, code: true, channels: country.channels }
      ];
      country.categories.forEach(function (c) {
        inside.push({ id: 'c:' + c.name, label: API.title(c.name), glyph: '', channels: c.channels });
      });
      return inside;
    }
    if (s.lockedCount) {
      sections.push({ id: 'locked', label: 'Locked (' + s.lockedCount + ')', glyph: '✱', type: 'locked', channels: [] });
    }
    if (s.countries) {
      s.countries.forEach(function (country) {
        sections.push({ id: 'country:' + country.code, label: country.name, glyph: country.code === 'OTHER' ? '…' : country.code,
          code: true, type: 'country', country: country, channels: country.channels });
      });
      return sections;
    }
    s.categories.forEach(function (c) {
      sections.push({ id: 'c:' + c.name, label: API.title(c.name), glyph: '', channels: c.channels });
    });
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
    if (Browser.sectionIndex >= Browser.sections.length) Browser.sectionIndex = 1;
    if (Browser.focus === 'nav') Browser.focus = 'cats';

    var html =
      '<div class="backdrop"></div>' + navHTML('live') +
      '<div class="browser">' +
        '<div class="sidebar">' +
          '<input class="search-input" id="search-input" type="text" autocomplete="off">' +
          '<div class="vlist" id="cats"><div class="vlist-inner"></div></div>' +
        '</div>' +
        '<div class="content">' +
          '<div class="content-head"><h1 id="section-title"></h1><div class="sub" id="section-sub"></div></div>' +
          '<div class="content-body' + (Browser.view === 'guide' ? ' guide-mode' : '') + '" id="content-body">' +
            '<div class="channels vlist" id="channels"><div class="vlist-inner"></div></div>' +
            '<div class="details"><div class="preview" id="preview"></div></div>' +
            '<div class="guide-host" id="guide-host"></div>' +
          '</div>' +
          '<div class="hints">' +
            '<span><span class="key">▲</span>Menu</span>' +
            '<span><span class="key">OK</span>Play</span>' +
            '<span><span class="key">◀ ▶</span>Categories / Channels</span>' +
            '<span><span class="key yellow">&nbsp;</span>Favorite</span>' +
            '<span><span class="key blue">&nbsp;</span>' + (Browser.view === 'guide' ? 'Channel list' : 'TV guide') + '</span>' +
            '<span><span class="key green">&nbsp;</span>Accounts</span>' +
            '<span><span class="key">BACK</span>' + (Browser.focus === 'list' ? 'Categories' : 'Menu') + '</span>' +
          '</div>' +
        '</div>' +
      '</div>';

    setScreen('browser', html, browserKey);

    Browser.catList = new VList(document.getElementById('cats'), 74, function (section, i, focused, y) {
      var count = section.id === 'search' || section.type === 'back' || section.type === 'locked' ? '' : section.channels.length;
      return '<div class="cat' + (i === Browser.sectionIndex ? ' selected' : '') + (focused ? ' focused' : '') +
        (section.type === 'back' ? ' back' : '') + '">' +
        glyphHTML(section.glyph, section.code) +
        '<span class="label">' + esc(section.label) + '</span>' +
        '<span class="count">' + count + '</span></div>';
    }, 12);
    Browser.chList = new VList(document.getElementById('channels'), 112, function (channel, i, focused, y) {
      var fav = Store.isFavorite(channel.key);
      // What's on now, straight in the channel list (the TV guide lives here).
      // Only what's already known while scrolling; the rest is fetched once the list rests.
      var guide = global.VeyloGuide && Browser.view !== 'guide' ? global.VeyloGuide.peek(channel) : null;
      var nn = guide ? global.VeyloGuide.nowNextHTML(guide) : '';
      return '<div class="row' + (focused ? ' focused' : '') + '" data-key="' + esc(channel.key) + '">' +
        '<div class="num">' + (i + 1) + '</div>' + logoHTML(channel) +
        '<div class="info"><div class="title">' + esc(channel.title) + '</div>' +
        '<div class="meta">' + (nn || esc(API.title(channel.category))) + '</div></div>' +
        (channel.quality ? '<span class="badge">' + channel.quality + '</span>' : '') +
        (fav ? '<span class="heart">♥</span>' : '') +
        '</div>';
    }, 8);

    Browser.catList.focused = Browser.focus === 'cats';
    Browser.chList.focused = Browser.focus === 'list';
    Browser.catList.setItems(Browser.sections, Browser.sectionIndex);
    openSection(Browser.sectionIndex, Browser.positions[Browser.sections[Browser.sectionIndex].id] || 0);

    // Results follow the typing (and deleting) while the TV keyboard is open.
    var searchInput = document.getElementById('search-input');
    searchInput.addEventListener('focus', function () {
      clearInterval(Browser.liveTimer);
      Browser.liveValue = searchInput.value;
      // Polled as well: not every TV keyboard sends 'input' events while typing.
      Browser.liveTimer = setInterval(checkLiveSearch, 250);
    });
    searchInput.addEventListener('input', checkLiveSearch);
    searchInput.addEventListener('blur', function () { clearInterval(Browser.liveTimer); clearTimeout(Browser.liveDelay); });

    App.onTypingDone = function (input) {
      clearInterval(Browser.liveTimer);
      clearTimeout(Browser.liveDelay);
      Browser.query = input.value.trim();
      Browser.sections = buildSections();
      Browser.sectionIndex = 0;
      Browser.catList.setItems(Browser.sections, 0);
      openSection(0, 0);
      if (Browser.sections[0].channels.length) setBrowserFocus('list');
    };
  }

  function checkLiveSearch() {
    var input = document.getElementById('search-input');
    if (!input || input.value === Browser.liveValue) return;
    Browser.liveValue = input.value;
    clearTimeout(Browser.liveDelay);
    Browser.liveDelay = setTimeout(liveSearch, 250);
  }

  /** Updates the Search row and its results without leaving the keyboard. */
  function liveSearch() {
    var input = document.getElementById('search-input');
    if (!input || App.screen !== 'browser' || !Browser.sections[0] || Browser.sections[0].id !== 'search') return;
    Browser.query = input.value.trim();
    var section = Browser.sections[0];
    section.label = Browser.query ? 'Search: ' + Browser.query : 'Search';
    section.channels = searchResults();
    Browser.sectionIndex = 0;
    Browser.catList.render();
    openSection(0, 0);
    if (!Browser.query) document.getElementById('section-sub').textContent = 'Type a channel name';
  }

  function openSection(index, position) {
    Browser.sectionIndex = index;
    var section = Browser.sections[index];
    document.getElementById('section-title').textContent =
      section.id === 'search' ? (Browser.query ? 'Results for “' + Browser.query + '”' : 'Search') : section.label;
    var sub = section.type === 'back' ? 'Press OK to go back' : section.type === 'locked' ? 'Press OK to unlock'
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
        back: 'Press OK to see all countries again.',
        locked: 'These categories are locked.<br>Press OK and enter your PIN to show them.'
      }[section.id] || 'No channels here.';
      box.innerHTML = '<div class="empty">' + message + '</div>';
    }
    if (Browser.view === 'guide') mountGuide(position || 0);
    else { updatePreview(); scheduleVisibleEPG(); }
  }

  function rowOnScreen(channel) {
    var list = Browser.chList;
    if (!list || App.screen !== 'browser' || Browser.view === 'guide') return false;
    var at = list.items.indexOf(channel);
    return at >= list.top - 1 && at <= list.top + list.visibleCount() + 1;
  }

  /** NOW lines are fetched only after the list has rested 0.5 s (nothing loads while scrolling). */
  function scheduleVisibleEPG() {
    clearTimeout(Browser.epgRowsTimer);
    Browser.epgRowsTimer = setTimeout(requestVisibleEPG, 500);
  }

  /** Asks the guide for the rows now on screen (rows slid into view weren't rebuilt). */
  function requestVisibleEPG() {
    var list = Browser.chList;
    if (!global.VeyloGuide || !list || Browser.view === 'guide') return;
    var end = Math.min(list.items.length, list.top + list.visibleCount() + 1);
    for (var i = list.top; i < end; i++) {
      var ch = list.items[i];
      var data = global.VeyloGuide.get(ch, rowOnScreen);
      if (data) {
        var node = document.querySelector('#channels .row[data-key="' + ch.key.replace(/"/g, '') + '"] .meta');
        var html = global.VeyloGuide.nowNextHTML(data);
        if (node && html && node.innerHTML !== html) node.innerHTML = html;
      }
    }
  }

  /** The time grid for the open section (same sidebar, other view of the same channels). */
  function mountGuide(index) {
    var host = document.getElementById('guide-host');
    var section = Browser.sections[Browser.sectionIndex];
    if (!host || !global.VeyloGuide) return;
    if (!section.channels.length) { global.VeyloGuide.unmount(); host.innerHTML = '<div class="empty">No channels here.</div>'; return; }
    global.VeyloGuide.mount(host, section.channels, {
      index: index,
      focused: Browser.focus === 'list',
      onWatch: function (i) {
        Browser.positions[section.id] = i;
        Browser.chList.index = i;
        showPlayer(section.channels, i, section.label);
      },
      onLeft: function () { Browser.chList.index = global.VeyloGuide.index(); setBrowserFocus('cats'); },
      onUp: function () { setBrowserFocus('nav'); }
    });
  }

  /** BLUE / INFO: channel list ⇄ TV guide grid. */
  function toggleGuideView() {
    flushSection();
    var section = Browser.sections[Browser.sectionIndex];
    if (Browser.view === 'guide') {
      Browser.positions[section.id] = global.VeyloGuide.index();
      Browser.view = 'list';
    } else {
      Browser.positions[section.id] = Browser.chList.index;
      Browser.view = 'guide';
    }
    showBrowser();
  }


  function flushSection() {
    if (!Browser.pendingSection) return;
    clearTimeout(Browser.pendingSection);
    Browser.pendingSection = null;
    if (App.screen !== 'browser') return;
    if (Browser.catList.index !== Browser.sectionIndex) {
      openSection(Browser.catList.index, Browser.positions[Browser.sections[Browser.catList.index].id] || 0);
      Browser.catList.render();   // moves the "selected" mark
    }
  }

  /** Preview (big logo + EPG) only when the highlight rests on a channel. */
  function schedulePreview() {
    clearTimeout(Browser.previewTimer);
    Browser.previewTimer = setTimeout(updatePreview, 160);
  }

  function setBrowserFocus(where) {
    flushSection();
    if (where !== 'nav') Browser.lastFocus = where;
    navFocus(where === 'nav');
    Browser.focus = where;
    Browser.catList.focused = where === 'cats';
    Browser.chList.focused = where === 'list';
    Browser.catList.render();
    if (Browser.view === 'guide') global.VeyloGuide.setFocused(where === 'list');
    else if (Browser.chList.items.length) Browser.chList.render();
    var hint = document.querySelector('.hints > span:last-child');
    if (hint) hint.innerHTML = '<span class="key">BACK</span>' + (where === 'list' ? 'Categories' : where === 'nav' ? 'Exit' : 'Menu');
  }

  function updatePreview() {
    clearTimeout(Browser.previewTimer);
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
    if (!App.session.client && global.VeyloXMLTV && global.VeyloXMLTV.available()) {
      var guide = global.VeyloXMLTV.lookup(channel);
      var spot = document.getElementById('preview-epg');
      if (spot) spot.innerHTML = epgHTML(guide);
    } else if (App.session.client && channel.streamID) {
      var key = channel.key;
      Browser.epgTimer = setTimeout(function () {
        App.session.client.shortEPG(channel.streamID).then(function (list) {
          var current = Browser.chList && Browser.chList.current();
          if (!current || current.key !== key) return;
          var target = document.getElementById('preview-epg');
          if (target) target.innerHTML = epgHTML(list);
        }).catch(function () {});
      }, 600);
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

  function enterCountry(country) {
    Browser.positions[Browser.sections[Browser.sectionIndex].id] = Browser.chList.index;
    Browser.level = 'country';
    Browser.country = country;
    Browser.sections = buildSections();
    Browser.catList.setItems(Browser.sections, 1);
    openSection(1, Browser.positions[Browser.sections[1].id] || 0);
    Browser.catList.render();
  }

  function leaveCountry() {
    var code = Browser.country && Browser.country.code;
    Browser.level = 'top';
    Browser.country = null;
    Browser.sections = buildSections();
    var at = 1;
    Browser.sections.forEach(function (s, i) { if (s.id === 'country:' + code) at = i; });
    Browser.catList.setItems(Browser.sections, at);
    openSection(at, Browser.positions[Browser.sections[at].id] || 0);
    Browser.catList.render();
  }

  function browserKey(key) {
    if (Browser.focus === 'nav') {
      return navKey(key, function () { setBrowserFocus(Browser.lastFocus || 'cats'); });
    }
    var section = Browser.sections[Browser.sectionIndex];
    if (key >= 48 && key <= 57 && Browser.chList.items.length) { numberEntry(key - 48); return; }
    if (key === K.GREEN) { showAccounts(); return; }
    if (key === K.BLUE || key === K.INFO) { toggleGuideView(); return; }
    if (Browser.view === 'guide' && Browser.focus === 'list') {
      if (key === K.BACK || key === K.ESC) { setBrowserFocus('cats'); return; }
      if (key === K.YELLOW) {
        var gch = section.channels[global.VeyloGuide.index()];
        toggleFavorite(gch);
        return;
      }
      if (global.VeyloGuide.key(key)) return;
      return false;
    }

    if (Browser.focus === 'cats') {
      if (key === K.UP && Browser.catList.index === 0) { flushSection(); setBrowserFocus('nav'); return; }
      if (key === K.UP || key === K.DOWN) {
        if (Browser.catList.move((key === K.UP ? -1 : 1) * (App.held > 6 ? 2 : 1))) {
          if (!Browser.pendingSection) Browser.positions[section.id] = Browser.chList.index;
          // Load the channels only once the highlight rests on a category.
          clearTimeout(Browser.pendingSection);
          Browser.pendingSection = setTimeout(flushSection, 220);
        }
        return;
      }
      flushSection();
      section = Browser.sections[Browser.sectionIndex];
      if (key === K.RIGHT) {
        if (Browser.chList.items.length) setBrowserFocus('list');
      } else if (key === K.ENTER) {
        if (section.id === 'search') { openSearch(); return; }
        if (section.type === 'back') { leaveCountry(); return; }
        if (section.type === 'locked') { unlock(function () { Browser.reset(); Browser.focus = 'cats'; showBrowser(); }); return; }
        if (section.type === 'country') { enterCountry(section.country); return; }
        if (Browser.chList.items.length) setBrowserFocus('list');
      } else if (key === K.BACK || key === K.ESC) {
        if (Browser.level === 'country') { leaveCountry(); return; }
        setBrowserFocus('nav');
      } else return false;
      return;
    }

    // Channel list
    if (key === K.UP && Browser.chList.index === 0) { setBrowserFocus('nav'); return; }
    if (key === K.UP || key === K.DOWN) {
      // Held ▲▼ speeds up: 1 row, then 2, then 4 per repeat.
      var stepRows = App.held > 12 ? 4 : App.held > 4 ? 2 : 1;
      if (Browser.chList.move(key === K.UP ? -stepRows : stepRows)) { schedulePreview(); scheduleVisibleEPG(); }
    } else if (key === K.CH_UP || key === K.CH_DOWN) {
      if (Browser.chList.move(key === K.CH_UP ? -Browser.chList.visibleCount() : Browser.chList.visibleCount())) { schedulePreview(); scheduleVisibleEPG(); }
    } else if (key === K.LEFT || key === K.BACK || key === K.ESC) {
      setBrowserFocus('cats');
    } else if (key === K.ENTER || key === K.PLAY || key === K.PLAY_PAUSE) {
      var channel = Browser.chList.current();
      if (channel) {
        Browser.positions[section.id] = Browser.chList.index;
        showPlayer(section.channels, Browser.chList.index, section.id === 'search' ? 'Search results' : section.label);
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

  // ---------- Accounts (saved providers) ----------
  function showAccounts(message) {
    var s = App.session;
    var activeID = s && s.profile && s.profile.id;
    var providers = Store.providers().sort(function (a, b) { return (b.lastUsed || 0) - (a.lastUsed || 0); });
    var confirmID = null;
    var confirmTimer = null;
    var renamingID = null;

    var rows = providers.map(function (p) {
      var active = p.id === activeID;
      return '<div class="acc-row">' +
        '<div class="acc-card focusable' + (active ? ' active' : '') + '" data-action="switch" data-id="' + esc(p.id) + '">' +
          '<div class="icon">' + esc((p.name || '?').charAt(0).toUpperCase()) + '</div>' +
          '<div class="text"><div class="name">' + esc(p.name) + '</div>' +
          '<div class="meta">' + (p.kind === 'xtream' ? 'Xtream Codes' : 'M3U Playlist') + '</div></div>' +
          (active ? '<span class="pill">WATCHING</span>' : '<span class="go">Switch ›</span>') +
        '</div>' +
        '<div class="acc-btn focusable" data-action="rename" data-id="' + esc(p.id) + '">Rename</div>' +
        '<div class="acc-btn danger focusable" data-action="remove" data-id="' + esc(p.id) + '">Remove</div>' +
      '</div>';
    }).join('');

    var html =
      '<div class="backdrop"></div><div class="accounts">' +
        '<div class="brand"><img src="brand.png"><span>veylo</span></div>' +
        '<h1>Accounts</h1>' +
        '<p class="sub">Save several providers on this TV and switch between them any time.</p>' +
        (message ? '<div class="acc-msg">' + esc(message) + '</div>' : '') +
        '<div class="acc-list">' + rows +
          '<div class="acc-row"><div class="acc-card add focusable" data-action="add">' +
            '<div class="icon">＋</div><div class="text"><div class="name">Add account</div>' +
            '<div class="meta">Xtream Codes or M3U playlist</div></div></div></div>' +
        '</div>' +
        (s && !activeID ? '<p class="sub small">The account you are watching isn’t saved. Add it here to switch back to it later.</p>' : '') +
        '<input class="search-input" id="rename-input" type="text" autocomplete="off">' +
      '</div>' +
      '<div class="hints acc-hints">' +
        '<span><span class="key">OK</span>Select</span>' +
        '<span><span class="key">◀ ▶</span>Rename / Remove</span>' +
        '<span><span class="key">BACK</span>' + (s ? 'Channels' : 'Login') + '</span>' +
      '</div>';

    setScreen('accounts', html, function (key) {
      if (key === K.UP || key === K.DOWN || key === K.LEFT || key === K.RIGHT) { focus.move(key); resetConfirm(); return; }
      if (key === K.BACK || key === K.ESC || key === K.GREEN) {
        var back = App.accountsBack;
        App.accountsBack = null;
        if (back && App.session) back();
        else if (App.session) showBrowser(); else showLogin();
        return;
      }
      if (key !== K.ENTER) return false;
      var node = focus.current();
      var action = node && node.getAttribute('data-action');
      var id = node && node.getAttribute('data-id');
      var chosen = Store.providers().filter(function (p) { return p.id === id; })[0];
      if (action === 'add') {
        showLogin(null, null, { adding: true });
      } else if (action === 'switch' && chosen) {
        if (chosen.id === activeID) { showBrowser(); return; }
        Store.setActive(chosen.id);
        Store.touch(chosen.id);
        connect(chosen, true);
      } else if (action === 'rename' && chosen) {
        renamingID = chosen.id;
        var input = document.getElementById('rename-input');
        input.value = chosen.name || '';
        input.focus();
      } else if (action === 'remove' && chosen) {
        if (confirmID !== chosen.id) {
          resetConfirm();
          confirmID = chosen.id;
          node.textContent = 'Press OK again';
          confirmTimer = setTimeout(resetConfirm, 3000);
          return;
        }
        Store.removeProvider(chosen.id);
        if (chosen.id === activeID) {
          App.session = null;
          var next = Store.providers()[0];
          if (next) { Store.setActive(next.id); connect(next, true); }
          else showLogin('Account removed from this TV.');
          return;
        }
        showAccounts('“' + chosen.name + '” removed from this TV.');
      }
    });

    function resetConfirm() {
      clearTimeout(confirmTimer);
      if (!confirmID) return;
      var nodes = document.querySelectorAll('.acc-btn.danger');
      Array.prototype.forEach.call(nodes, function (n) { n.textContent = 'Remove'; });
      confirmID = null;
    }

    App.onTypingDone = function (input) {
      var name = input.value.trim();
      if (renamingID && name) {
        Store.renameProvider(renamingID, name);
        if (App.session && App.session.profile && App.session.profile.id === renamingID) App.session.profile.name = name;
        var at = focus.index;
        showAccounts('Renamed to “' + name + '”.');
        App.restoreFocus && App.restoreFocus(at);
      }
      renamingID = null;
    };

    var focus = new FormFocus('.accounts .focusable');
    App.restoreFocus = function (index) { focus.index = clamp(index, 0, focus.items.length - 1); focus.apply(); };
    // Start on the account being watched (or "Add account" when none is saved).
    focus.items.forEach(function (node, i) { if (node.classList.contains('active')) focus.index = i; });
    focus.apply();
  }

  // ---------- Settings ----------
  function showSettings() {
    var s = App.session;
    var providers = Store.providers().sort(function (a, b) { return (b.lastUsed || 0) - (a.lastUsed || 0); });
    var acc = s && s.account;
    var html =
      '<div class="backdrop"></div>' + navHTML('settings') + '<div class="settings">' +
      '<h1>Settings</h1>' +
      '<div class="columns"><div>' +
        '<div class="group"><h3>ACCOUNTS</h3>' +
          providers.map(function (p) {
            var active = s && s.profile && s.profile.id === p.id;
            return '<div class="item focusable" data-action="switch" data-id="' + esc(p.id) + '">' + esc(p.name) +
              '<span class="value">' + (active ? 'Active' : (p.kind === 'xtream' ? 'Xtream' : 'M3U')) + '</span></div>';
          }).join('') +
          '<div class="item focusable" data-action="accounts">Manage accounts<span class="value">' + providers.length + ' saved</span></div>' +
          '<div class="item focusable" data-action="add">＋ Add account</div>' +
        '</div>' +
        (s && !s.client && global.VeyloXMLTV ? (function () {
          var st = global.VeyloXMLTV.status();
          var value = st.status === 'ready' ? st.count + ' channels · ' + clock(st.updated)
            : st.status === 'loading' ? 'Loading…' : st.status === 'none' ? 'No guide link' : esc(st.message || 'Not available');
          return '<div class="group"><h3>TV GUIDE</h3><div class="item">XMLTV guide<span class="value">' + value + '</span></div></div>';
        })() : '') +
        '<div class="group"><h3>PARENTAL LOCK</h3>' +
          '<div class="item focusable" data-action="pin">PIN<span class="value">' + (Store.pin() ? 'On' : 'Off') + '</span></div>' +
          (Store.pin() ? '<div class="item focusable" data-action="lockcats">Choose locked categories<span class="value">' +
            (Store.lockedCats().filter(function (x) { return x.charAt(0) !== '!'; }).length) + ' chosen</span></div>' +
            '<div class="item focusable" data-action="autoadult">Lock adult categories automatically<span class="value">' +
            (Store.autoAdult() ? 'On' : 'Off') + '</span></div>' : '') +
        '</div>' +
        '<div class="group"><h3>MOVIES & SERIES</h3><div class="item focusable" data-action="refreshlib">Reload movies & series</div></div>' +
        '<div class="group"><h3>ABOUT</h3><div class="item">Version<span class="value">Veylo TV ' + VERSION + '</span></div></div>' +
      '</div><div>' +
        '<div class="group"><h3>PLAYBACK</h3>' +
          '<div class="item focusable" data-action="autostart">Start with the last channel<span class="value">' +
            (Store.autostart() ? 'On' : 'Off') + '</span></div>' +
          '<div class="item focusable" data-action="avtest">Dot test (small video object)<span class="value">' +
            (Store.avTest() ? 'On' : 'Off') + '</span></div>' +

          '<div class="item focusable" data-action="engine">Player<span class="value">' +
            (Player.engineEnabled() ? 'Veylo engine (like iPhone)' : 'Samsung player') + '</span></div>' +
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
      '</div></div></div>';

    setScreen('settings', html, function (key) {
      if (key === K.UP || key === K.DOWN || key === K.LEFT || key === K.RIGHT) { focus.move(key); return; }
      if (key === K.BACK || key === K.ESC) { Browser.focus = 'cats'; showBrowser(); return; }
      if (key !== K.ENTER) return false;
      var node = focus.current();
      var tab = node && node.getAttribute('data-tab');
      if (tab) { if (tab !== 'settings') openTab(tab); return; }
      var action = node && node.getAttribute('data-action');
      if (action === 'switch') {
        var id = node.getAttribute('data-id');
        var chosen = Store.providers().filter(function (p) { return p.id === id; })[0];
        if (chosen && s && s.profile && s.profile.id === chosen.id) { showBrowser(); return; }
        if (chosen) { Store.setActive(chosen.id); Store.touch(chosen.id); connect(chosen, true); }
      } else if (action === 'add') {
        showLogin(null, null, { adding: true });
      } else if (action === 'accounts') {
        showAccounts();
      } else if (action === 'pin') {
        if (!Store.pin()) {
          askPIN('Choose a 4-digit PIN', function (first) {
            setTimeout(function () {
              askPIN('Enter the same PIN again', function (second) {
                if (second !== first) { toast('The PINs didn’t match'); return; }
                Store.setPin(first);
                App.unlocked = false;
                applyLock();
                toast('Parental lock on');
                setTimeout(showSettings, 0);
              });
            }, 0);
          });
        } else {
          askPIN('Enter your PIN to turn the lock off', function (pin) {
            if (pin !== Store.pin()) return false;
            Store.setPin('');
            App.unlocked = false;
            applyLock();
            toast('Parental lock off');
            setTimeout(showSettings, 0);
          });
        }
      } else if (action === 'lockcats') {
        unlock(showLockScreen);
      } else if (action === 'autoadult') {
        unlock(function () { Store.setAutoAdult(!Store.autoAdult()); applyLock(); showSettings(); });

      } else if (action === 'autostart') {
        Store.setAutostart(!Store.autostart());
        showSettings();
      } else if (action === 'avtest') {
        Store.setAVTest(!Store.avTest());
        applyAVTest();
        toast(Store.avTest() ? 'Dot test on — play a channel and check the centre' : 'Dot test off');
        showSettings();
      } else if (action === 'refreshlib') {
        if (global.VeyloLibrary) global.VeyloLibrary.clearCache();
        toast('Movies & series will reload');
      } else if (action === 'engine') {
        Player.setEngineEnabled(!Player.engineEnabled());
        toast(Player.engineEnabled() ? 'Veylo engine on — Samsung player is the backup' : 'Samsung player only');
        showSettings();
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
    var focus = new FormFocus('.navbar .nav-tab, .settings .focusable');
    // Start on the first setting, not on the menu.
    focus.items.forEach(function (node, i) { if (focus.index === 0 && node.classList.contains('focusable')) focus.index = i; });
    focus.apply();
  }

  /** Pick which categories the PIN protects (live, and movies/series once loaded). */
  function showLockScreen() {
    var s = App.session;
    var groups = [{ kind: 'live', title: 'LIVE TV', names: s.allCategories.map(function (c) { return c.name; }) }];
    var libs = s.library || {};
    var html = '<div class="backdrop"></div><div class="settings lockscreen"><h1>Locked categories</h1>' +
      '<p class="sub">OK locks or unlocks a category. Locked ones need the PIN once per app start.</p><div class="lock-list" id="lock-list"></div></div>' +
      '<div class="hints acc-hints"><span><span class="key">OK</span>Lock / unlock</span><span><span class="key">BACK</span>Done</span></div>';
    setScreen('lockcats', html, function (key) {
      if (key === K.UP || key === K.DOWN || key === K.LEFT || key === K.RIGHT) { focus.move(key); return; }
      if (key === K.BACK || key === K.ESC) { App.unlocked = false; applyLock(); showSettings(); return; }
      if (key !== K.ENTER) return false;
      var node = focus.current();
      if (!node) return;
      var kind = node.getAttribute('data-kind'), name = node.getAttribute('data-name');
      var id = kind + ':' + name;
      var on = isLockedCat(kind, name);
      // Adult categories locked automatically are switched off with a "!" entry.
      if (on) {
        if (Store.lockedCats().indexOf(id) >= 0) Store.toggleLockedCat(id); else Store.toggleLockedCat('!' + id);
      } else {
        if (Store.lockedCats().indexOf('!' + id) >= 0) Store.toggleLockedCat('!' + id); else Store.toggleLockedCat(id);
      }
      var now = isLockedCat(kind, name);
      node.classList.toggle('on', now);
      node.querySelector('.value').textContent = now ? 'Locked' : '';
    });
    function render(extra) {
      var list = groups.concat(extra || []);
      document.getElementById('lock-list').innerHTML = list.map(function (g) {
        return '<h3>' + g.title + '</h3>' + g.names.map(function (n) {
          var on = isLockedCat(g.kind, n);
          return '<div class="item focusable' + (on ? ' on' : '') + '" data-kind="' + g.kind + '" data-name="' + esc(n) + '">' +
            esc(API.title(n)) + '<span class="value">' + (on ? 'Locked' : '') + '</span></div>';
        }).join('');
      }).join('');
      focus = new FormFocus('#lock-list .focusable');
    }
    var focus;
    render();
    ['movie', 'series'].forEach(function (kind) {
      if (!libs[kind]) return;
      libs[kind].then(function (lib) {
        if (App.screen !== 'lockcats') return;
        groups.push({ kind: kind, title: kind === 'movie' ? 'MOVIES' : 'SERIES', names: lib.categories.map(function (c) { return c.name; }) });
        var at = focus ? focus.index : 0;
        render();
        focus.index = Math.min(at, focus.items.length - 1);
        focus.apply();
      }, function () {});
    });
  }

  // ---------- Player ----------
  var PlayerScreen = {
    lineup: [],
    index: 0,
    hideTimer: null,
    epgTimer: null,
    paused: false,
    state: 'loading',

    /** Zapping shows the channel at once but only opens the stream once the viewer rests on it
     *  (~0.7 s): every opened stream counts as a provider connection. */
    tune: function (index, immediate) {
      var count = this.lineup.length;
      if (!count) return;
      var next = (index + count) % count;
      if (this.lineup[this.index] && next !== this.index && this.started) this.previous = this.lineup[this.index];
      this.started = true;
      this.index = next;
      var channel = this.lineup[this.index];
      this.paused = false;
      Player.stop();   // frees the provider connection right away
      this.setState('loading');
      this.renderInfo();
      this.showOverlay();
      clearTimeout(this.tuneTimer);
      var self = this;
      var start = function () {
        if (self.lineup[self.index] !== channel || App.screen !== 'player') return;
        Store.addRecent(channel.key);
        Store.setLastChannel(channel.key);
        Player.play(channel.url, channel.altURL, { key: Store.scope + '|' + channel.key, uhd: channel.quality === '4K' });
        self.loadEPG();
      };
      if (immediate) start(); else this.tuneTimer = setTimeout(start, 700);
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
      var xmltv = !client && global.VeyloXMLTV && global.VeyloXMLTV.available();
      if (!channel || (!xmltv && (!client || !channel.streamID))) return;
      var self = this;
      this.epgTimer = setTimeout(function () {
        var source = xmltv ? Promise.resolve(global.VeyloXMLTV.lookup(channel)) : client.shortEPG(channel.streamID);
        source.then(function (list) {
          if (self.lineup[self.index] !== channel || App.screen !== 'player') return;
          var box = document.getElementById('player-epg');
          if (box) box.innerHTML = epgHTML(list);
          // Refresh when the current programme ends.
          var live = list.filter(function (p) { return p.start <= Date.now() && p.end > Date.now(); })[0];
          if (live) {
            self.epgTimer = setTimeout(function () { self.loadEPG(); }, Math.max(30000, live.end - Date.now() + 2000));
          }
        }).catch(function () {});
      }, 300);
    },

    setState: function (state, info) {
      var previous = this.state;
      this.state = state;
      var box = document.getElementById('player-status');
      if (!box) return;
      clearInterval(this.loadTimer);
      box.style.top = state === 'error' ? '18%' : '';
      // While the picture plays the box is taken out completely: on the TV an emptied box left a
      // small dot from the loading circle over the video (user video, 0.2.9).
      box.style.display = state === 'playing' || state === 'paused' || !state ? 'none' : '';
      if (state === 'buffering') {
        box.innerHTML = '<div class="spinner"></div>Buffering…';
      } else if (state === 'loading') {
        box.innerHTML = '<div class="spinner"></div>Loading…<div id="player-wait" style="font-size:22px;color:rgba(255,255,255,.55);margin-top:12px"></div>';
        var wait = function () {
          var c = Player.current, node = document.getElementById('player-wait');
          var a = Player.attempt();
          if (!node || !c || !c.since || !a) return;
          node.textContent = 'Try ' + (c.step + 1) + '/' + c.plan.length + ' · ' + a.format + ' · ' + a.agent.label +
            ' · ' + Math.round((Date.now() - c.since) / 1000) + ' s' +
            (c.step ? '  (total ' + Math.round((Date.now() - c.began) / 1000) + ' s)' : '');
        };
        wait();
        this.loadTimer = setInterval(wait, 1000);
      } else if (state === 'retry') {
        box.innerHTML = '<div class="spinner"></div>Connection lost — reconnecting in ' +
          info.seconds + ' s (' + info.attempt + '/' + info.total + ')' +
          '<div style="font-size:22px;color:rgba(255,255,255,.6);margin-top:12px">The provider stopped sending this channel.</div>' +
          '<div id="player-reason" style="font-size:22px;color:#ffd60a;margin-top:12px"></div>';
        this.checkConnections();
      } else if (state === 'error') {
        // What every try did — read it off a photo of the TV.
        var c = Player.current;
        var code = '';
        if (c && c.log && c.log.length) {
          code = '<div class="attempts">' + c.log.slice(-10).map(function (l) {
            return esc(l.format + ' · ' + l.agent + ' → ' + l.result + ' (' + l.seconds + ' s)');
          }).join('<br>') + (c.uaError ? '<br>Identity not applied: ' + esc(c.uaError) : '') + '</div>';
        } else if (Player.lastError) {
          code = '<div class="attempts">' + esc(Player.lastError) + '</div>';
        }
        box.innerHTML = 'This channel isn’t playing right now.<br><span style="font-size:24px;color:rgba(255,255,255,.6)">Press OK to retry · ▲▼ for another channel</span>' +
          '<div id="player-reason" style="font-size:24px;color:#ffd60a;margin-top:18px"></div>' + code;
        this.showOverlay(true);
        this.checkConnections();
      } else {
        box.innerHTML = '';
        // Started (often 10 s+ after tuning): start the overlay's hide countdown now.
        if (state === 'playing' && previous !== 'playing' && previous !== 'buffering') this.showOverlay();
      }
    },

    /** Most "plays once, then fails" cases are the provider's connection limit. */
    checkConnections: function () {
      var client = App.session && App.session.client;
      if (!client || !client.authenticate) return;
      var channel = this.lineup[this.index];
      client.authenticate().then(function (acc) {
        if (PlayerScreen.lineup[PlayerScreen.index] !== channel ||
            (PlayerScreen.state !== 'error' && PlayerScreen.state !== 'retry')) return;
        App.session.account = acc;
        var box = document.getElementById('player-reason');
        if (!box) return;
        if (acc.status && acc.status.toLowerCase() !== 'active') {
          box.textContent = 'Your subscription is ' + acc.status.toLowerCase() + '.';
        } else if (acc.max && acc.active >= acc.max) {
          box.textContent = 'All ' + acc.max + ' connection' + (acc.max === 1 ? '' : 's') +
            ' of your plan are in use. Close Veylo on other devices, wait a minute and press OK.';
        } else if (acc.max) {
          box.style.color = 'rgba(255,255,255,.55)';
          box.textContent = 'Connections: ' + acc.active + ' of ' + acc.max + ' in use';
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
    },

    /** Channel list over the video (OK): pick another channel without leaving the player. */
    openPanel: function () {
      var box = document.getElementById('chpanel');
      if (!box) return;
      box.classList.remove('hidden');
      this.panelOpen = true;
      var self = this;
      if (!this.panel) {
        this.panel = new VList(document.getElementById('chp-list'), 96, function (channel, i, focused) {
          return '<div class="chp-row' + (focused ? ' focused' : '') + (i === self.index ? ' playing' : '') + '">' +
            '<div class="num">' + (i + 1) + '</div>' + logoHTML(channel) +
            '<div class="info"><div class="title">' + esc(channel.title) + '</div></div>' +
            (channel.quality ? '<span class="badge">' + channel.quality + '</span>' : '') + '</div>';
        }, 9);
      }
      this.panel.focused = true;
      this.panel.setItems(this.lineup, this.index);
      var channel = this.lineup[this.index];
      document.getElementById('chp-head').textContent = this.title || (channel ? API.title(channel.category) : '');
      document.getElementById('player-overlay').classList.add('hidden');
    },

    closePanel: function () {
      var box = document.getElementById('chpanel');
      if (box) box.classList.add('hidden');
      this.panelOpen = false;
    },

    goPrevious: function () {
      if (!this.previous) { toast('No previous channel yet'); return; }
      var at = this.lineup.indexOf(this.previous);
      if (at < 0) {
        // The previous channel was in another list: switch the lineup to its category.
        var prev = this.previous;
        var cat = (App.session.categories || []).filter(function (c) { return c.channels.indexOf(prev) >= 0; })[0];
        this.lineup = cat ? cat.channels.slice() : App.session.channels.slice();
        this.title = cat ? API.title(cat.name) : 'All Channels';
        at = this.lineup.indexOf(prev);
        this.panel = null;
      }
      if (at < 0) { toast('No previous channel yet'); return; }
      this.tune(at, true);
    }
  };

  /** `back` (optional): where BACK returns to (Home, Guide); default the channel browser. */
  function showPlayer(lineup, index, title, back) {
    PlayerScreen.lineup = lineup.slice();
    PlayerScreen.title = title || '';
    PlayerScreen.back = back || null;
    var html =
      '<div class="player">' +
        '<div id="player-overlay">' +
          '<div class="shade-top"></div><div class="shade-bottom"></div>' +
          '<div class="top"><span class="live-pill">● LIVE</span><span class="build">v' + VERSION + '</span><span class="clock" id="player-clock"></span></div>' +
          '<div class="panel" id="player-panel"></div>' +
          '<div class="hints">' +
            '<span><span class="key">▲▼</span>Channel</span>' +
            '<span><span class="key">OK</span>Channel list</span>' +
            '<span><span class="key">◀▶</span>Info</span>' +
            '<span><span class="key">PRE-CH</span>Previous</span>' +
            '<span><span class="key yellow">&nbsp;</span>Favorite</span>' +
            '<span><span class="key">⏯</span>Pause</span>' +
            '<span><span class="key">BACK</span>Back</span>' +
          '</div>' +
        '</div>' +
        '<div class="status" id="player-status"></div>' +
        '<div class="chpanel hidden" id="chpanel"><div class="chp-head" id="chp-head"></div>' +
          '<div class="vlist" id="chp-list"><div class="vlist-inner"></div></div>' +
          '<div class="chp-hint">OK Watch · BACK Close</div></div>' +
      '</div>';
    setScreen('player', html, playerKey);
    PlayerScreen.panel = null;
    PlayerScreen.panelOpen = false;
    PlayerScreen.started = false;
    PlayerScreen.previous = PlayerScreen.previous || null;
    Player.onState = function (state, info) { PlayerScreen.setState(state, info); };
    PlayerScreen.tick();
    clearInterval(PlayerScreen.clockTimer);
    PlayerScreen.clockTimer = setInterval(PlayerScreen.tick, 5000);
    PlayerScreen.tune(index, true);
  }

  function leavePlayer() {
    clearTimeout(PlayerScreen.tuneTimer);
    clearInterval(PlayerScreen.loadTimer);
    Player.stop();
    clearInterval(PlayerScreen.clockTimer);
    clearTimeout(PlayerScreen.hideTimer);
    clearTimeout(PlayerScreen.epgTimer);
    var section = Browser.sections[Browser.sectionIndex];
    if (section && section.channels.length && PlayerScreen.lineup.length) {
      var playing = PlayerScreen.lineup[PlayerScreen.index];
      var at = section.channels.indexOf(playing);
      if (at >= 0) Browser.positions[section.id] = at;
    }
    if (PlayerScreen.back) { var back = PlayerScreen.back; PlayerScreen.back = null; back(); return; }
    Browser.focus = 'list';
    showBrowser();
  }

  function playerKey(key) {
    if (PlayerScreen.panelOpen) {
      var panel = PlayerScreen.panel;
      if (key === K.UP || key === K.DOWN) { panel.move(key === K.UP ? -1 : 1); return; }
      if (key === K.CH_UP || key === K.CH_DOWN) { panel.move(key === K.CH_UP ? -9 : 9); return; }
      if (key === K.ENTER) {
        PlayerScreen.closePanel();
        if (panel.index !== PlayerScreen.index) PlayerScreen.tune(panel.index, true);
        return;
      }
      if (key === K.BACK || key === K.ESC || key === K.LEFT || key === K.RIGHT) { PlayerScreen.closePanel(); return; }
      return false;
    }
    if (key >= 48 && key <= 57) { numberEntry(key - 48); PlayerScreen.showOverlay(); return; }
    if (key === K.PRECH || key === K.BLUE) { PlayerScreen.goPrevious(); return; }
    switch (key) {
      case K.UP: case K.CH_UP:
        PlayerScreen.tune(PlayerScreen.index - 1); return;
      case K.DOWN: case K.CH_DOWN:
        PlayerScreen.tune(PlayerScreen.index + 1); return;
      case K.ENTER:
        if (PlayerScreen.state === 'error' || PlayerScreen.state === 'retry') { PlayerScreen.tune(PlayerScreen.index, true); return; }
        PlayerScreen.openPanel();
        return;
      case K.INFO: case K.LEFT: case K.RIGHT:
        var overlay = document.getElementById('player-overlay');
        if (overlay && !overlay.classList.contains('hidden') && key === K.INFO) overlay.classList.add('hidden');
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
    if (global.VeyloGuide) {
      global.VeyloGuide.onData(function (channel) {
        if (App.screen !== 'browser' || Browser.view === 'guide') return;
        var row = document.querySelector('#channels .row[data-key="' + channel.key.replace(/"/g, '') + '"] .meta');
        var html = global.VeyloGuide.nowNextHTML(global.VeyloGuide.get(channel));
        if (row && html) row.innerHTML = html;
      });
    }
    if (global.VeyloEngine && global.VeyloEngine.cleanupTemp) global.VeyloEngine.cleanupTemp();
    applyAVTest();
    var active = Store.active();
    if (active) connect(active, true, null, 3, true);
    else showLogin();
  }

  /** Dot test: the AVPlay <object> shrinks to 1 px in the corner (the video itself keeps its
   *  full-screen display rect). If the dot disappears, the object was drawing it. */
  function applyAVTest() {
    document.documentElement.classList.toggle('av-test', !!Store.avTest());
  }

  global.VeyloApp = { start: start, version: VERSION };
  /** Shared pieces for the Movies & Series screens (js/vod.js). */
  global.VeyloUI = {
    K: K, App: App, Nav: Nav, esc: esc, clock: clock, clamp: clamp, toast: toast,
    VList: VList, FormFocus: FormFocus, setScreen: setScreen,
    navHTML: navHTML, navKey: navKey, navFocus: navFocus, openTab: openTab, askExit: askExit,
    showBrowser: function () { Browser.focus = 'cats'; showBrowser(); },
    showPlayer: showPlayer,
    askPIN: askPIN,
    unlock: unlock,
    isLockedCat: isLockedCat,
    isHidden: isHidden,
    logoHTML: logoHTML, glyphHTML: glyphHTML,
    epgHTML: epgHTML,
    toggleFavorite: toggleFavorite,
    /** `back`: where BACK returns (Home); default the channel browser. */
    showAccounts: function (back) { App.accountsBack = back || null; showAccounts(); }
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})(window);

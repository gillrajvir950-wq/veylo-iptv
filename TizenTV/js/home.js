/* Veylo TV — Home: shelves of what you watch (Continue Watching, favorite and recent channels,
 * newly added movies and series). Uses window.VeyloUI from js/app.js. Chromium 76 compatible. */
(function (global) {
  'use strict';

  var UI = global.VeyloUI;
  var Store = global.VeyloStore;
  var K = UI.K, esc = UI.esc, clamp = UI.clamp;
  var LIMIT = 24;

  var H = { shelves: [], row: 0, cols: {}, focus: 'shelves' };

  function session() { return UI.App.session; }

  function channelShelf(id, title, keys) {
    var byKey = UI.App.byKey || {};
    var items = keys.map(function (k) { return byKey[k]; }).filter(function (c) { return c && !UI.isHidden(c); }).slice(0, LIMIT);
    return items.length ? { id: id, title: title, type: 'channel', items: items } : null;
  }

  /** Shelves that need nothing but what's already on the TV. */
  function baseShelves() {
    var shelves = [];
    var s = session();
    var resume = resumeShelf(null);
    if (resume) shelves.push(resume);
    var fav = channelShelf('fav', 'Favorite channels', Store.favorites());
    if (fav) shelves.push(fav);
    var recent = channelShelf('recent', 'Recently watched', Store.recents());
    if (recent) shelves.push(recent);
    if (!fav && !recent && s && s.channels.length) {
      shelves.push({ id: 'start', title: 'Live channels', type: 'channel', items: s.channels.slice(0, LIMIT) });
    }
    return shelves;
  }

  /** Movies and series you started (needs the library lists for posters). */
  function resumeShelf(libs) {
    if (!libs) return null;
    var progress = Store.progressAll();
    var items = [];
    Object.keys(progress).reverse().forEach(function (key) {
      var kind = key.charAt(0) === 'm' ? 'movie' : key.charAt(0) === 's' ? 'series' : '';
      var lib = libs[kind];
      if (!lib || key.charAt(1) !== ':') return;
      var item = lib.byID[key.slice(2)];
      if (item && global.VeyloLibrary.visible(kind, lib, [item]).length && items.length < LIMIT) items.push({ item: item, progress: progress[key] });
    });
    return items.length ? { id: 'resume', title: 'Continue watching', type: 'resume', items: items } : null;
  }

  function cardHTML(shelf, entry) {
    if (shelf.type === 'channel') {
      return '<div class="hcard ch">' + UI.logoHTML(entry) + '<div class="htitle">' + esc(entry.title) + '</div></div>';
    }
    var item = shelf.type === 'resume' ? entry.item : entry;
    var p = shelf.type === 'resume' ? entry.progress : null;
    var bar = p && p.dur ? '<div class="pbar"><div style="width:' + Math.round(p.pos / p.dur * 100) + '%"></div></div>' : '';
    var fallback = '<div class="ptext">' + esc(item.title) + '</div>';
    return '<div class="hcard poster">' +
      '<div class="pimg" data-fallback="' + esc(fallback) + '">' +
        (item.poster ? '<img decoding="async" src="' + esc(item.poster) + '" onerror="this.parentNode.innerHTML=this.parentNode.getAttribute(\'data-fallback\')">' : fallback) +
      '</div>' + bar + '<div class="htitle">' + esc(item.title) + '</div></div>';
  }

  function show() {
    var s = session();
    var html =
      '<div class="backdrop"></div>' + UI.navHTML('home') +
      '<div class="home"><div class="home-inner" id="home-inner"></div></div>';
    UI.setScreen('home', html, homeKey);
    H.shelves = baseShelves();
    H.row = 0;
    H.cols = {};
    H.focus = H.shelves.length ? 'shelves' : 'nav';
    render();
    if (H.focus === 'nav') UI.navFocus(true);
    // Movie & series shelves come from the saved library lists (fast after the first time).
    if (s && s.client && global.VeyloLibrary && global.VeyloLibrary.load) {
      var libs = {};
      Promise.all(['movie', 'series'].map(function (kind) {
        return global.VeyloLibrary.load(kind).then(function (lib) { libs[kind] = lib; }, function () {});
      })).then(function () {
        if (UI.App.screen !== 'home' || session() !== s) return;
        var extra = [];
        var resume = resumeShelf(libs);
        if (resume) extra.push(resume);
        if (libs.movie) extra.push({ id: 'movies', title: 'Recently added movies', type: 'poster', items: newest(global.VeyloLibrary.visible('movie', libs.movie, libs.movie.items)) });
        if (libs.series) extra.push({ id: 'series', title: 'Recently added series', type: 'poster', items: newest(global.VeyloLibrary.visible('series', libs.series, libs.series.items)) });
        var focusedID = H.shelves[H.row] && H.shelves[H.row].id;
        // Continue Watching goes first; the rest after the channel shelves.
        H.shelves = (resume ? [resume] : []).concat(H.shelves, extra.filter(function (x) { return x !== resume; }));
        H.shelves.forEach(function (sh, i) { if (sh.id === focusedID) H.row = i; });
        if (H.focus === 'nav' && H.shelves.length) { /* stay on the menu */ }
        render();
      });
    }
  }

  function newest(items) {
    return items.slice().sort(function (a, b) { return b.added - a.added; }).slice(0, LIMIT);
  }

  function render() {
    var box = document.getElementById('home-inner');
    if (!box) return;
    if (!H.shelves.length) {
      box.innerHTML = '<div class="empty">Welcome to Veylo.<br>Open <b>Live TV</b> to start watching — your favorites, recent channels ' +
        'and what you’re in the middle of will show up here.</div>';
      return;
    }
    box.innerHTML = H.shelves.map(function (shelf, r) {
      return '<div class="shelf' + (shelf.type === 'channel' ? ' channels' : '') + '" data-row="' + r + '">' +
        '<h2>' + esc(shelf.title) + '</h2><div class="shelf-track"><div class="shelf-inner">' +
        shelf.items.map(function (entry) { return cardHTML(shelf, entry); }).join('') + '</div></div></div>';
    }).join('');
    apply();
  }

  /** Highlight + scroll: the focused shelf near the top, the focused card in view. */
  function apply() {
    var box = document.getElementById('home-inner');
    if (!box) return;
    var shelves = box.querySelectorAll('.shelf');
    Array.prototype.forEach.call(box.querySelectorAll('.hcard.focused'), function (n) { n.classList.remove('focused'); });
    H.row = clamp(H.row, 0, Math.max(0, H.shelves.length - 1));
    var shelfNode = shelves[H.row];
    if (!shelfNode) return;
    var top = Math.max(0, shelfNode.offsetTop - 30);
    box.style.transform = 'translate3d(0,' + (-top) + 'px,0)';
    var cards = shelfNode.querySelectorAll('.hcard');
    var col = clamp(H.cols[H.row] || 0, 0, cards.length - 1);
    H.cols[H.row] = col;
    if (H.focus === 'shelves' && cards[col]) cards[col].classList.add('focused');
    // Each shelf scrolls sideways so its own position stays visible.
    Array.prototype.forEach.call(shelves, function (node, r) {
      var inner = node.querySelector('.shelf-inner');
      var list = node.querySelectorAll('.hcard');
      var c = clamp(H.cols[r] || 0, 0, list.length - 1);
      var card = list[c];
      var shift = card ? Math.max(0, card.offsetLeft - 40) : 0;
      var maxShift = Math.max(0, inner.scrollWidth - node.clientWidth + 60);
      inner.style.transform = 'translate3d(' + (-Math.min(shift, maxShift)) + 'px,0,0)';
    });
  }

  function current() {
    var shelf = H.shelves[H.row];
    return shelf ? { shelf: shelf, entry: shelf.items[H.cols[H.row] || 0] } : null;
  }

  function open(target) {
    var shelf = target.shelf, entry = target.entry;
    if (!entry) return;
    if (shelf.type === 'channel') {
      UI.showPlayer(shelf.items, shelf.items.indexOf(entry), shelf.title, show);
      return;
    }
    var item = shelf.type === 'resume' ? entry.item : entry;
    if (global.VeyloLibrary && global.VeyloLibrary.openItem) global.VeyloLibrary.openItem(item, show);
  }

  function homeKey(key) {
    if (H.focus === 'nav') {
      return UI.navKey(key, function () {
        if (!H.shelves.length) { UI.navFocus(true); return; }
        H.focus = 'shelves';
        apply();
      });
    }
    var shelf = H.shelves[H.row];
    switch (key) {
      case K.UP:
        if (H.row === 0) { H.focus = 'nav'; apply(); UI.navFocus(true); return; }
        H.row -= 1; apply(); return;
      case K.DOWN:
        if (H.row < H.shelves.length - 1) { H.row += 1; apply(); }
        return;
      case K.LEFT:
        H.cols[H.row] = Math.max(0, (H.cols[H.row] || 0) - 1); apply(); return;
      case K.RIGHT:
        H.cols[H.row] = Math.min(shelf.items.length - 1, (H.cols[H.row] || 0) + 1); apply(); return;
      case K.ENTER: case K.PLAY: case K.PLAY_PAUSE:
        var t = current();
        if (t) open(t);
        return;
      case K.BACK: case K.ESC:
        H.focus = 'nav'; apply(); UI.navFocus(true); return;
      case K.GREEN:
        UI.showAccounts(); return;
      default:
        return false;
    }
  }

  global.VeyloHome = { show: show };
})(window);

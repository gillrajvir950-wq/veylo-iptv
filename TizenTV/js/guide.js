/* Veylo TV — programme guide for Live TV.
 *  • `get(channel)` / `nowNextHTML(list)` — cached NOW/NEXT for the channel list rows (fetched only for rows on screen).
 *  • `mount(host, channels, options)` — the time grid shown inside Live TV for the open category
 *    (BLUE / INFO toggles it); the Live TV sidebar stays, so the guide is the channel list in another view.
 * Programmes: Xtream short EPG, or the XMLTV guide for M3U accounts (js/xmltv.js). Chromium 76 compatible. */
(function (global) {
  'use strict';

  var UI = global.VeyloUI;
  var K = UI.K, esc = UI.esc;
  var HOUR = 3600 * 1000;
  var SPAN = 3 * HOUR;
  var WIDTH = 1090;
  var ROW = 96;

  // ---------- Programme data (shared by rows and grid) ----------
  var D = { session: null, data: {}, pending: {}, queue: [], running: 0, listeners: [] };

  function session() { return UI.App.session; }

  function reset() {
    if (D.session === session()) return;
    D.session = session();
    D.data = {};
    D.pending = {};
    D.queue = [];
  }

  function hasGuide() {
    var s = session();
    return !!(s && (s.client || (global.VeyloXMLTV && global.VeyloXMLTV.available())));
  }

  function fetchList(channel) {
    var s = session();
    if (s.client && channel.streamID) return s.client.shortEPG(channel.streamID, 24);
    if (global.VeyloXMLTV && global.VeyloXMLTV.available()) return Promise.resolve(global.VeyloXMLTV.lookup(channel));
    return Promise.resolve([]);
  }

  /** Cached programmes for a channel, or undefined (then fetched while `wanted(channel)` is true). */
  function get(channel, wanted) {
    reset();
    var list = D.data[channel.key];
    if (list && list.length && list[list.length - 1].end <= Date.now()) { delete D.data[channel.key]; list = undefined; }
    if (list === undefined && hasGuide() && !D.pending[channel.key]) {
      D.pending[channel.key] = wanted || function () { return true; };
      D.queue.push(channel);
      pump();
    }
    return list;
  }

  /** Two requests at a time (blocked providers go through the TV's native downloader). */
  function pump() {
    while (D.running < 2 && D.queue.length) {
      var channel = D.queue.shift();
      var wanted = D.pending[channel.key];
      if (!wanted || !wanted(channel)) { delete D.pending[channel.key]; continue; }
      D.running += 1;
      (function (ch, owner) {
        fetchList(ch).then(function (list) { if (D.session === owner) D.data[ch.key] = list || []; },
          function () { if (D.session === owner) D.data[ch.key] = []; })
          .then(function () {
            delete D.pending[ch.key];
            D.running -= 1;
            D.listeners.forEach(function (fn) { fn(ch); });
            pump();
          });
      })(channel, D.session);
    }
  }

  function onData(fn) { D.listeners.push(fn); }

  /** Row line for the channel list: "title · 23 min left" + progress + next, or '' when unknown. */
  function nowNextHTML(list) {
    if (!list || !list.length) return '';
    var now = Date.now();
    var cur = list.filter(function (p) { return p.start <= now && p.end > now; })[0];
    var next = list.filter(function (p) { return p.start > now; })[0];
    if (!cur && !next) return '';
    var html = '';
    if (cur) {
      var pct = Math.round((now - cur.start) / (cur.end - cur.start) * 100);
      var left = Math.max(1, Math.round((cur.end - now) / 60000));
      html += '<div class="nn-line"><span class="nn-now">' + esc(cur.title) + '</span><span class="nn-left"> · ' + left + ' min left</span></div>' +
        '<div class="nn-bar"><div style="width:' + pct + '%"></div></div>';
    } else if (next) {
      html += '<div class="nn-line"><span class="nn-left">Next ' + UI.clock(next.start) + ' </span><span class="nn-now">' + esc(next.title) + '</span></div>';
    }
    return html;
  }

  // ---------- Grid inside Live TV ----------
  var G = null;

  function floorHalfHour(t) { return Math.floor(t / (HOUR / 2)) * (HOUR / 2); }
  function x(t) { return (t - G.start) / SPAN * WIDTH; }

  function visible(channel) {
    if (!G || !G.list) return false;
    var at = G.list.items.indexOf(channel);
    return at >= G.list.top - 2 && at <= G.list.top + G.list.visibleCount() + 2;
  }

  function rowHTML(channel, i, isFocusedRow) {
    var list = get(channel, visible);
    var cells = '';
    if (!hasGuide()) cells = '<div class="gprog empty" style="left:0;width:' + WIDTH + 'px">No TV guide for this account</div>';
    else if (!list) cells = '<div class="gprog loading" style="left:0;width:' + WIDTH + 'px">…</div>';
    else {
      var end = G.start + SPAN;
      var shown = list.filter(function (p) { return p.end > G.start && p.start < end; });
      if (!shown.length) cells = '<div class="gprog empty" style="left:0;width:' + WIDTH + 'px">No guide information</div>';
      shown.forEach(function (p) {
        var left = Math.max(0, x(p.start)), right = Math.min(WIDTH, x(p.end));
        var live = p.start <= Date.now() && p.end > Date.now();
        var on = isFocusedRow && p.start <= G.focusTime && p.end > G.focusTime;
        cells += '<div class="gprog' + (live ? ' now' : '') + (on ? ' focused' : '') + '" data-s="' + p.start + '" data-e="' + p.end +
          '" style="left:' + left + 'px;width:' + Math.max(4, right - left - 6) + 'px">' + esc(p.title) + '</div>';
      });
    }
    return '<div class="grow' + (isFocusedRow ? ' focused' : '') + '">' +
      '<div class="gch"><span class="gnum">' + (i + 1) + '</span>' + UI.logoHTML(channel) + '<span class="gname">' + esc(channel.title) + '</span></div>' +
      '<div class="gline">' + cells + '</div></div>';
  }

  function timeline() {
    if (!G) return;
    var html = '';
    for (var t = G.start; t < G.start + SPAN; t += HOUR / 2) html += '<div class="gtick" style="left:' + x(t) + 'px">' + UI.clock(t) + '</div>';
    var now = Date.now();
    var times = document.getElementById('gtimes');
    if (times) times.innerHTML = html;
    var line = document.getElementById('gnowline');
    if (line) {
      line.style.display = now >= G.start && now < G.start + SPAN ? 'block' : 'none';
      line.style.left = (300 + x(now)) + 'px';
    }
  }

  function focusedProgramme() {
    var channel = G.list && G.list.current();
    var list = channel && D.data[channel.key];
    if (!list) return null;
    return list.filter(function (p) { return p.start <= G.focusTime && p.end > G.focusTime; })[0] || null;
  }

  function details() {
    var box = document.getElementById('gdetail');
    var channel = G && G.list && G.list.current();
    if (!box || !channel) return;
    var p = focusedProgramme();
    box.innerHTML = '<div class="gd-ch">' + esc(channel.title) + '</div>' +
      (p ? '<div class="gd-title">' + esc(p.title) + '</div><div class="gd-time">' + UI.clock(p.start) + ' – ' + UI.clock(p.end) +
        (p.start <= Date.now() && p.end > Date.now() ? '  ·  <span class="gd-live">ON NOW</span>' : '') + '</div>' +
        (p.desc ? '<div class="gd-desc">' + esc(p.desc) + '</div>' : '')
        : '<div class="gd-title">' + (!hasGuide() ? 'No TV guide for this account' : D.data[channel.key] ? 'No guide information' : 'Loading guide…') + '</div>');
  }

  function mark() {
    if (!G || !G.list) return;
    Array.prototype.forEach.call(G.list.inner.querySelectorAll('.gprog.focused'), function (n) { n.classList.remove('focused'); });
    var row = G.list.inner.children[G.list.index - G.list.bufStart];
    if (!row || !G.list.focused) return;
    Array.prototype.forEach.call(row.querySelectorAll('.gprog[data-s]'), function (n) {
      if (Number(n.getAttribute('data-s')) <= G.focusTime && Number(n.getAttribute('data-e')) > G.focusTime) n.classList.add('focused');
    });
  }

  function step(dir) {
    var channel = G.list.current();
    var list = (channel && D.data[channel.key]) || [];
    var cur = focusedProgramme();
    var target = cur ? list[list.indexOf(cur) + dir] : (dir > 0 ? list.filter(function (p) { return p.start > G.focusTime; })[0]
      : list.filter(function (p) { return p.end <= G.focusTime; }).pop());
    if (!target) {
      if (dir < 0 && G.focusTime - HOUR / 2 < Date.now() - HOUR / 2) return false;   // left edge → sidebar
      G.focusTime += dir * HOUR / 2;
    } else {
      G.focusTime = Math.max(target.start, Date.now() - HOUR) + 1;
    }
    if (G.focusTime < G.start || G.focusTime >= G.start + SPAN - HOUR / 4) {
      G.start = floorHalfHour(Math.max(Date.now() - HOUR / 2, G.focusTime - HOUR / 2));
      timeline();
      G.list.render();
    }
    mark();
    details();
    return true;
  }

  /** host: element to draw into. options: {index, focused, onWatch(index), onLeft(), onUp()}. */
  function mount(host, channels, options) {
    unmount();
    G = { options: options, start: floorHalfHour(Date.now() - HOUR / 2), focusTime: Date.now() };
    host.innerHTML =
      '<div class="gdetail" id="gdetail"></div>' +
      '<div class="gtimes-row"><div class="gtimes-pad"></div><div class="gtimes" id="gtimes"></div></div>' +
      '<div class="ggrid"><div class="vlist" id="grows"><div class="vlist-inner"></div></div><div class="gnowline" id="gnowline"></div></div>';
    G.list = new UI.VList(document.getElementById('grows'), ROW, rowHTML, 6);
    G.list.focused = !!options.focused;
    G.list.setItems(channels, options.index || 0);
    mark();
    timeline();
    details();
    G.tick = setInterval(function () { if (G && document.getElementById('gtimes')) timeline(); }, 30000);
  }

  function unmount() {
    if (G) { clearInterval(G.tick); clearTimeout(G.redraw); }
    G = null;
  }

  function setFocused(on) {
    if (!G) return;
    G.list.focused = on;
    G.list.render();
    mark();
  }

  /** Keys while the grid has focus; false = not handled. */
  function key(k) {
    if (!G) return false;
    switch (k) {
      case K.UP:
        if (G.list.index === 0) { G.options.onUp(); return true; }
        G.list.move(-1); mark(); details(); return true;
      case K.DOWN: G.list.move(1); mark(); details(); return true;
      case K.CH_UP: case K.CH_DOWN: G.list.move(k === K.CH_UP ? -6 : 6); mark(); details(); return true;
      case K.LEFT: if (!step(-1)) G.options.onLeft(); return true;
      case K.RIGHT: step(1); return true;
      case K.ENTER: case K.PLAY: case K.PLAY_PAUSE: G.options.onWatch(G.list.index); return true;
      default: return false;
    }
  }

  onData(function (channel) {
    if (!G || !visible(channel)) return;
    clearTimeout(G.redraw);
    G.redraw = setTimeout(function () { if (G) { G.list.render(); mark(); details(); } }, 120);
  });

  global.VeyloGuide = {
    get: get, onData: onData,
    /** Cached programmes only (no request). */
    peek: function (channel) { reset(); return D.data[channel.key]; }, nowNextHTML: nowNextHTML, hasGuide: hasGuide,
    mount: mount, unmount: unmount, key: key, setFocused: setFocused,
    index: function () { return G && G.list ? G.list.index : 0; },
    active: function () { return !!G; }
  };
})(window);

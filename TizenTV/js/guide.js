/* Veylo TV — TV Guide: a time grid of programmes for the channels of one category.
 * Programmes come from the provider's Xtream short EPG (fetched only for rows on screen) or,
 * for M3U accounts, from the playlist's XMLTV guide when js/xmltv.js has one. Chromium 76 compatible. */
(function (global) {
  'use strict';

  var UI = global.VeyloUI;
  var Store = global.VeyloStore;
  var K = UI.K, esc = UI.esc, clamp = UI.clamp;
  var HOUR = 3600 * 1000;
  var SPAN = 3 * HOUR;          // visible time range
  var WIDTH = 1180;             // px for SPAN
  var ROW = 96;

  var G = { focus: 'grid', cat: 1, start: 0, data: {}, pending: {}, queue: [], running: 0, focusTime: 0 };

  function session() { return UI.App.session; }

  function floorHalfHour(t) { return Math.floor(t / (HOUR / 2)) * (HOUR / 2); }

  function sections() {
    var s = session();
    var favs = Store.favorites().map(function (k) { return UI.App.byKey[k]; }).filter(function (c) { return c && !UI.isHidden(c); });
    var list = [{ id: 'fav', label: 'Favorites', channels: favs }, { id: 'all', label: 'All Channels', channels: s.channels }];
    s.categories.forEach(function (c) { list.push({ id: 'c:' + c.name, label: global.VeyloAPI.title(c.name), channels: c.channels }); });
    return list;
  }

  /** Programmes for a channel: Xtream short EPG, else the XMLTV guide (M3U). */
  function programmes(channel) {
    var s = session();
    if (s.client && channel.streamID) return s.client.shortEPG(channel.streamID, 24);
    if (global.VeyloXMLTV && global.VeyloXMLTV.available()) return Promise.resolve(global.VeyloXMLTV.lookup(channel));
    return Promise.resolve([]);
  }

  function request(channel) {
    var key = channel.key;
    if (G.data[key] || G.pending[key]) return;
    G.pending[key] = true;
    G.queue.push(channel);
    pump();
  }

  /** Two requests at a time (blocked providers go through the TV's native downloader). */
  function pump() {
    while (G.running < 2 && G.queue.length) {
      var channel = G.queue.shift();
      if (!isVisible(channel)) { delete G.pending[channel.key]; continue; }
      G.running += 1;
      (function (ch) {
        programmes(ch).then(function (list) { G.data[ch.key] = list || []; }, function () { G.data[ch.key] = []; })
          .then(function () {
            delete G.pending[ch.key];
            G.running -= 1;
            scheduleRender();
            pump();
          });
      })(channel);
    }
  }

  function isVisible(channel) {
    if (!G.list || UI.App.screen !== 'guide') return false;
    var at = G.list.items.indexOf(channel);
    return at >= G.list.top - 2 && at <= G.list.top + G.list.visibleCount() + 2;
  }

  function scheduleRender() {
    clearTimeout(G.renderTimer);
    G.renderTimer = setTimeout(function () {
      if (UI.App.screen !== 'guide' || !G.list) return;
      G.list.render();
      details();
    }, 120);
  }

  function x(t) { return (t - G.start) / SPAN * WIDTH; }

  function rowHTML(channel, i, focused) {
    var list = G.data[channel.key];
    request(channel);
    var cells = '';
    if (!list) cells = '<div class="gprog loading" style="left:0;width:' + WIDTH + 'px">…</div>';
    else {
      var end = G.start + SPAN;
      var shown = list.filter(function (p) { return p.end > G.start && p.start < end; });
      if (!shown.length) cells = '<div class="gprog empty" style="left:0;width:' + WIDTH + 'px">No guide information</div>';
      shown.forEach(function (p) {
        var left = Math.max(0, x(p.start)), right = Math.min(WIDTH, x(p.end));
        var live = p.start <= Date.now() && p.end > Date.now();
        var isFocused = focused && G.focus === 'grid' && p.start <= G.focusTime && p.end > G.focusTime;
        cells += '<div class="gprog' + (live ? ' now' : '') + (isFocused ? ' focused' : '') + '" data-s="' + p.start + '" data-e="' + p.end + '" style="left:' + left + 'px;width:' +
          Math.max(4, right - left - 6) + 'px">' + esc(p.title) + '</div>';
      });
    }
    return '<div class="grow' + (focused && G.focus === 'grid' ? ' focused' : '') + '">' +
      '<div class="gch"><span class="gnum">' + (i + 1) + '</span>' + UI.logoHTML(channel) + '<span class="gname">' + esc(channel.title) + '</span></div>' +
      '<div class="gline">' + cells + '</div></div>';
  }

  function timeline() {
    var html = '';
    for (var t = G.start; t < G.start + SPAN; t += HOUR / 2) {
      html += '<div class="gtick" style="left:' + x(t) + 'px">' + UI.clock(t) + '</div>';
    }
    var now = Date.now();
    if (now >= G.start && now < G.start + SPAN) html += '<div class="gnow" style="left:' + x(now) + 'px"></div>';
    var head = document.getElementById('gtimes');
    if (head) head.innerHTML = html;
    var line = document.getElementById('gnowline');
    if (line) {
      line.style.display = now >= G.start && now < G.start + SPAN ? 'block' : 'none';
      line.style.left = (300 + x(now)) + 'px';
    }
  }

  function show() {
    var s = session();
    var html =
      '<div class="backdrop"></div>' + UI.navHTML('guide') +
      '<div class="guide">' +
        '<div class="gside"><div class="vlist" id="gcats"><div class="vlist-inner"></div></div></div>' +
        '<div class="gmain">' +
          '<div class="gdetail" id="gdetail"></div>' +
          '<div class="gtimes-row"><div class="gtimes-pad"></div><div class="gtimes" id="gtimes"></div></div>' +
          '<div class="ggrid"><div class="vlist" id="grows"><div class="vlist-inner"></div></div><div class="gnowline" id="gnowline"></div></div>' +
          '<div class="hints"><span><span class="key">▲</span>Menu</span><span><span class="key">OK</span>Watch</span>' +
          '<span><span class="key">◀ ▶</span>Programmes</span><span><span class="key">CH±</span>Page</span><span><span class="key">BACK</span>Categories</span></div>' +
        '</div>' +
      '</div>';
    UI.setScreen('guide', html, guideKey);
    var noGuide = !s.client && !(global.VeyloXMLTV && global.VeyloXMLTV.available());
    G.sections = sections();
    G.cat = clamp(G.cat, 0, G.sections.length - 1);
    if (!G.sections[G.cat].channels.length) G.cat = 1;
    G.start = floorHalfHour(Date.now() - HOUR / 2);
    G.focusTime = Date.now();
    G.cats = new UI.VList(document.getElementById('gcats'), 74, function (sec, i, focused) {
      return '<div class="cat' + (i === G.cat ? ' selected' : '') + (focused ? ' focused' : '') + '"><span class="label">' + esc(sec.label) +
        '</span><span class="count">' + sec.channels.length + '</span></div>';
    }, 12);
    G.list = new UI.VList(document.getElementById('grows'), ROW, rowHTML, 7);
    G.focus = 'grid';
    G.cats.setItems(G.sections, G.cat);
    G.list.focused = true;
    G.list.setItems(G.sections[G.cat].channels, 0);
    timeline();
    details();
    clearInterval(G.tick);
    G.tick = setInterval(function () { if (UI.App.screen === 'guide') timeline(); else clearInterval(G.tick); }, 30000);
    if (noGuide) {
      document.getElementById('gdetail').innerHTML = '<div class="gd-title">No TV guide for this account yet</div>' +
        '<div class="gd-desc">This M3U playlist has no guide link. Add an EPG (XMLTV) link to the account in Settings › Accounts.</div>';
    }
  }

  function focusedProgramme() {
    var channel = G.list && G.list.current();
    var list = channel && G.data[channel.key];
    if (!list) return null;
    return list.filter(function (p) { return p.start <= G.focusTime && p.end > G.focusTime; })[0] || null;
  }

  function details() {
    var box = document.getElementById('gdetail');
    var channel = G.list && G.list.current();
    if (!box || !channel) return;
    var p = focusedProgramme();
    box.innerHTML = '<div class="gd-ch">' + esc(channel.title) + '</div>' +
      (p ? '<div class="gd-title">' + esc(p.title) + '</div><div class="gd-time">' + UI.clock(p.start) + ' – ' + UI.clock(p.end) +
        (p.start <= Date.now() && p.end > Date.now() ? '  ·  <span class="gd-live">ON NOW</span>' : '') + '</div>' +
        (p.desc ? '<div class="gd-desc">' + esc(p.desc) + '</div>' : '')
        : '<div class="gd-title">' + (G.data[channel.key] ? 'No guide information' : 'Loading guide…') + '</div>');
  }

  /** Moves the highlight to the previous/next programme (shifting the time window when needed). */
  function stepProgramme(dir) {
    var channel = G.list.current();
    var list = (channel && G.data[channel.key]) || [];
    var cur = focusedProgramme();
    var target = null;
    if (cur) {
      var at = list.indexOf(cur);
      target = list[at + dir] || null;
    } else {
      target = dir > 0 ? list.filter(function (p) { return p.start > G.focusTime; })[0] : list.filter(function (p) { return p.end <= G.focusTime; }).pop();
    }
    if (!target) {
      if (dir < 0 && G.focusTime - HOUR / 2 < Date.now() - HOUR) { setFocus('cats'); return; }
      G.focusTime += dir * HOUR / 2;
    } else {
      G.focusTime = Math.max(target.start, Date.now() - HOUR) + 1;
    }
    if (G.focusTime < G.start || G.focusTime >= G.start + SPAN - HOUR / 4) {
      G.start = floorHalfHour(Math.max(Date.now() - HOUR / 2, G.focusTime - HOUR / 2));
      timeline();
    }
    G.list.render();
    details();
  }

  /** Moves the programme highlight without rebuilding rows. */
  function mark() {
    var rows = G.list.inner.children;
    Array.prototype.forEach.call(G.list.inner.querySelectorAll('.gprog.focused'), function (n) { n.classList.remove('focused'); });
    var row = rows[G.list.index - G.list.bufStart];
    if (!row || G.focus !== 'grid') return;
    Array.prototype.forEach.call(row.querySelectorAll('.gprog[data-s]'), function (n) {
      if (Number(n.getAttribute('data-s')) <= G.focusTime && Number(n.getAttribute('data-e')) > G.focusTime) n.classList.add('focused');
    });
  }

  function setFocus(where) {
    flushCat();
    G.focus = where;
    UI.navFocus(where === 'nav');
    G.cats.focused = where === 'cats';
    G.list.focused = where === 'grid';
    G.cats.render();
    G.list.render();
  }

  function flushCat() {
    if (!G.catTimer) return;
    clearTimeout(G.catTimer);
    G.catTimer = null;
    if (G.cats.index !== G.cat) {
      G.cat = G.cats.index;
      G.queue = [];
      G.list.setItems(G.sections[G.cat].channels, 0);
      G.cats.render();
      details();
    }
  }

  function watch() {
    var channel = G.list.current();
    if (!channel) return;
    var sec = G.sections[G.cat];
    UI.showPlayer(sec.channels, G.list.index, sec.label, show);
  }

  function guideKey(key) {
    if (G.focus === 'nav') return UI.navKey(key, function () { setFocus(G.lastFocus || 'grid'); });
    if (G.focus === 'cats') {
      if (key === K.UP && G.cats.index === 0) { flushCat(); G.lastFocus = 'cats'; setFocus('nav'); return; }
      if (key === K.UP || key === K.DOWN) {
        if (G.cats.move(key === K.UP ? -1 : 1)) { clearTimeout(G.catTimer); G.catTimer = setTimeout(flushCat, 250); }
        return;
      }
      if (key === K.RIGHT || key === K.ENTER) { flushCat(); if (G.list.items.length) setFocus('grid'); return; }
      if (key === K.BACK || key === K.ESC) { G.lastFocus = 'cats'; setFocus('nav'); return; }
      return false;
    }
    switch (key) {
      case K.UP:
        if (G.list.index === 0) { G.lastFocus = 'grid'; setFocus('nav'); return; }
        G.list.move(-1); mark(); details(); return;
      case K.DOWN: G.list.move(1); mark(); details(); return;
      case K.CH_UP: case K.CH_DOWN:
        G.list.move(key === K.CH_UP ? -7 : 7); mark(); details(); return;
      case K.LEFT: stepProgramme(-1); return;
      case K.RIGHT: stepProgramme(1); return;
      case K.ENTER: case K.PLAY: case K.PLAY_PAUSE: watch(); return;
      case K.BACK: case K.ESC: setFocus('cats'); return;
      default: return false;
    }
  }

  global.VeyloGuide = { show: show };
})(window);

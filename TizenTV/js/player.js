/* Veylo TV — video playback.
 * On the Samsung TV this uses Samsung's AVPlay (webapis.avplay), which plays MPEG-TS and HLS.
 * In a normal browser (for testing) it falls back to an HTML5 <video>.
 *
 * Some providers hang or refuse the TV's own player but answer known IPTV players at once, so each
 * channel is tried with several player identities and both formats; the one that works is remembered. */
(function (global) {
  'use strict';

  function hasAVPlay() {
    return !!(global.webapis && global.webapis.avplay);
  }

  /** Identities the stream is requested with. Providers that refuse the TV's own player
   *  (it hangs or fails) usually answer a known IPTV player at once — the iPhone app plays
   *  instantly through VLC. '' = the TV's default identity. */
  var AGENTS = [
    { id: 'vlc', label: 'VLC', ua: 'VLC/3.0.21 LibVLC/3.0.21' },
    { id: 'smarters', label: 'IPTV Smarters', ua: 'IPTVSmartersPro' },
    { id: 'okhttp', label: 'okhttp', ua: 'okhttp/4.12.0' },
    { id: 'tv', label: 'TV default', ua: '' }
  ];
  /** A try that shows no picture within this time is given up for the next identity/format. */
  var ATTEMPT_TIMEOUT = 15000;
  /** Reconnect pauses after a stream that was playing drops. */
  var DROP_DELAYS = [3, 6, 10];
  var MEMORY_KEY = 'veylo.tv.streamIdentity';
  /** What worked per channel ({key: {agent, format}}), newest last, capped. */
  var CHANNEL_KEY = 'veylo.tv.channelTry';
  var CHANNEL_LIMIT = 400;

  function remembered() {
    try { return JSON.parse(global.localStorage.getItem(MEMORY_KEY) || 'null'); } catch (e) { return null; }
  }
  function remember(value, channelKey) {
    try { global.localStorage.setItem(MEMORY_KEY, JSON.stringify(value)); } catch (e) { /* storage blocked */ }
    if (!channelKey) return;
    try {
      var map = JSON.parse(global.localStorage.getItem(CHANNEL_KEY) || '{}');
      delete map[channelKey];
      map[channelKey] = value;
      var keys = Object.keys(map);
      while (keys.length > CHANNEL_LIMIT) delete map[keys.shift()];
      global.localStorage.setItem(CHANNEL_KEY, JSON.stringify(map));
    } catch (e) { /* storage blocked */ }
  }
  function channelMemory(channelKey) {
    if (!channelKey) return null;
    try { return JSON.parse(global.localStorage.getItem(CHANNEL_KEY) || '{}')[channelKey] || null; } catch (e) { return null; }
  }
  function agentByID(id) {
    for (var i = 0; i < AGENTS.length; i++) if (AGENTS[i].id === id) return AGENTS[i];
    return null;
  }
  function formatOf(url) { return /\.m3u8(\?|$)/i.test(url) ? 'HLS' : 'TS'; }

  var ENGINE_KEY = 'veylo.tv.engine';
  var ENGINE_TRIES = [
    { id: 'engine-web', label: 'Veylo engine', mode: 'web' },
    { id: 'engine-native', label: 'Veylo engine · VLC', mode: 'native' }
  ];

  /** The Veylo engine (js/engine.js) is on unless switched off in Settings. */
  function engineEnabled() {
    var engine = global.VeyloEngine;
    if (!engine || !engine.supported()) return false;
    try { return global.localStorage.getItem(ENGINE_KEY) !== 'off'; } catch (e) { return true; }
  }

  /** Engine tries (MPEG-TS only), the mode that worked last time first. */
  function engineTries(url, altURL, memory) {
    if (!engineEnabled()) return [];
    var ts = formatOf(url) === 'TS' ? url : (altURL && formatOf(altURL) === 'TS' ? altURL : '');
    if (!ts) return [];
    var tries = ENGINE_TRIES.filter(function (t) { return t.mode !== 'native' || global.VeyloEngine.hasNative(); });
    if (memory && memory.agent === 'engine-native') tries.reverse();
    return tries.map(function (t) { return { url: ts, agent: t, format: 'TS', engine: t.mode }; });
  }

  /** Ordered tries: what worked last time first, then the Veylo engine, then Samsung's player
   *  with every identity × format. */
  function buildPlan(url, altURL, options) {
    options = options || {};
    var urls = [url];
    if (altURL) urls.push(altURL);
    // This channel's own winner beats the last winner on any channel.
    var own = channelMemory(options.key);
    var memory = own || remembered();
    var agents = AGENTS.slice();
    var plan = [];
    var engine = engineTries(url, altURL, memory);
    // 4K channels are usually HEVC, which the engine can't play: Samsung's player first.
    var avplayWon = (memory && agentByID(memory.agent)) || (options.uhd && !own);
    if (!avplayWon) plan = plan.concat(engine);
    if (memory) {
      var known = agentByID(memory.agent);
      if (known) {
        agents = [known].concat(AGENTS.filter(function (a) { return a !== known; }));
        // The format that worked first, with the remembered identity.
        if (memory.format === 'HLS' && altURL && formatOf(altURL) === 'HLS') urls = [altURL, url];
        if (memory.format === 'TS' && altURL && formatOf(altURL) === 'TS') urls = [altURL, url];
      }
    }
    var samsung = [];
    agents.forEach(function (agent) {
      urls.forEach(function (u) { samsung.push({ url: u, agent: agent, format: formatOf(u) }); });
    });
    // Samsung's player won last time: its winning try first, then the engine, then the rest.
    if (avplayWon) plan = [samsung[0]].concat(engine, samsung.slice(1));
    else plan = plan.concat(samsung);
    return plan;
  }

  var Player = {
    /** Called with ('loading' | 'buffering' | 'playing' | 'error' | 'retry', info). */
    onState: function () {},
    current: null,
    retryTimer: null,
    attemptTimer: null,
    /** Last error name (shown small on the error screen to help diagnose). */
    lastError: '',

    /** options: {key: channel key (per-channel memory), uhd: 4K channel}. */
    play: function (url, altURL, options) {
      Player.stop();
      options = options || {};
      Player.current = { plan: buildPlan(url, altURL, options), step: 0, log: [], drops: 0,
        key: options.key || '', began: Date.now() };
      Player.rect = options.rect || null;
      Player.lastError = '';
      Player.open();
    },

    /** The try being made right now (for the loading screen). */
    attempt: function () {
      var c = Player.current;
      return c && c.plan[c.step];
    },

    open: function () {
      var current = Player.current;
      if (!current) return;
      var tryNow = current.plan[current.step];
      current.since = Date.now();
      current.format = tryNow.format;
      Player.onState('loading');
      clearTimeout(Player.attemptTimer);
      Player.attemptTimer = setTimeout(function () {
        if (Player.current === current && !current.playing) Player.fail('NO_PICTURE_' + Math.round(ATTEMPT_TIMEOUT / 1000) + 'S');
      }, ATTEMPT_TIMEOUT);
      if (tryNow.engine) {
        Player.openEngine(tryNow.url, tryNow.engine);
      } else if (hasAVPlay()) {
        Player.openAVPlay(tryNow.url, tryNow.agent.ua);
      } else {
        Player.openHTML5(tryNow.url);
      }
    },

    openEngine: function (url, mode) {
      Player.gen = (Player.gen || 0) + 1;
      var gen = Player.gen;
      function live() { return gen === Player.gen; }
      Player.engine = global.VeyloEngine.start(url, mode, {
        onPlaying: function () { if (live()) Player.started(); },
        onBuffering: function () { if (live()) Player.onState('buffering'); },
        onError: function (name) { if (live()) Player.fail(name); }
      }, Player.rect ? { rect: Player.rect } : null);
    },

    /** Moves the picture: a box on the page (live preview) or full screen (null) — without
     *  restarting the stream, so going from preview to full screen is instant. */
    setRect: function (rect) {
      Player.rect = rect || null;
      if (Player.engine && Player.engine.video) {
        var v = Player.engine.video;
        v.className = rect ? 'engine-video preview-video' : 'engine-video';
        v.style.left = rect ? rect.left + 'px' : '';
        v.style.top = rect ? rect.top + 'px' : '';
        v.style.width = rect ? rect.width + 'px' : '';
        v.style.height = rect ? rect.height + 'px' : '';
      } else if (hasAVPlay()) {
        try {
          var r = rect || { left: 0, top: 0, width: 1920, height: 1080 };
          global.webapis.avplay.setDisplayRect(Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height));
        } catch (e) { /* not open */ }
      }
    },

    started: function () {
      var current = Player.current;
      if (!current) return;
      clearTimeout(Player.attemptTimer);
      if (!current.playing) {
        current.playing = true;
        current.playingSince = Date.now();
        var tryNow = current.plan[current.step];
        remember({ agent: tryNow.agent.id, format: tryNow.format }, current.key);
        current.log.push({ format: tryNow.format, agent: tryNow.agent.label, result: 'OK', seconds: Math.round((Date.now() - current.since) / 1000) });
      }
      Player.onState('playing');
    },

    fail: function (reason) {
      if (reason) Player.lastError = String(reason);
      var current = Player.current;
      if (!current) return;
      clearTimeout(Player.attemptTimer);
      Player.stop(true);
      var tryNow = current.plan[current.step];

      // Was playing and dropped: reconnect with the same identity/format after a pause.
      if (current.playing) {
        current.playing = false;
        // A stream that ran fine for a minute starts its reconnect count afresh.
        if (Date.now() - (current.playingSince || 0) > 60000) current.drops = 0;
        if (current.drops < DROP_DELAYS.length) {
          var seconds = DROP_DELAYS[current.drops];
          current.drops += 1;
          Player.onState('retry', { attempt: current.drops, total: DROP_DELAYS.length, seconds: seconds, dropped: true });
          clearTimeout(Player.retryTimer);
          Player.retryTimer = setTimeout(function () {
            if (Player.current === current) Player.open();
          }, seconds * 1000);
          return;
        }
        Player.onState('error');
        return;
      }

      current.log.push({ format: tryNow.format, agent: tryNow.agent.label, result: Player.lastError,
        seconds: Math.round((Date.now() - current.since) / 1000) });
      if (current.step + 1 < current.plan.length) {
        current.step += 1;
        // A short pause so the provider has let go of the refused try.
        clearTimeout(Player.retryTimer);
        Player.retryTimer = setTimeout(function () {
          if (Player.current === current) Player.open();
        }, 800);
        return;
      }
      Player.onState('error');
    },

    openAVPlay: function (url, agent) {
      var av = global.webapis.avplay;
      // Callbacks from an older stream (fast zapping, retries) must not affect the new one.
      Player.gen = (Player.gen || 0) + 1;
      var gen = Player.gen;
      function live() { return gen === Player.gen; }
      try {
        av.open(url);
        av.setListener({
          onbufferingstart: function () {
            if (!live()) return;
            Player.onState(Player.current && Player.current.playing ? 'buffering' : 'loading');
          },
          onbufferingcomplete: function () { if (live()) Player.started(); },
          onstreamcompleted: function () { if (live()) Player.fail('STREAM_ENDED'); },
          onerror: function (type) { if (live()) Player.fail(type || 'PLAYER_ERROR'); },
          onevent: function () {}
        });
        // The identity for this try (see AGENTS); '' keeps the TV's own.
        if (agent) {
          try { av.setStreamingProperty('USER_AGENT', agent); } catch (e) {
            // Shown in the attempt log: if this fails, every identity is really the TV's own.
            if (Player.current) Player.current.uaError = (e && (e.name || e.message)) || 'failed';
          }
        }
        var r = Player.rect || { left: 0, top: 0, width: 1920, height: 1080 };
        av.setDisplayRect(Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height));
        try { av.setDisplayMethod('PLAYER_DISPLAY_MODE_LETTER_BOX'); } catch (e) { /* older TVs */ }
        av.prepareAsync(function () {
          if (!live()) return;
          try {
            av.play();
            Player.started();
          } catch (e) { Player.fail('PLAY_FAILED'); }
        }, function (error) { if (live()) Player.fail((error && (error.name || error.message)) || 'PREPARE_FAILED'); });
      } catch (e) {
        Player.fail((e && (e.name || e.message)) || 'OPEN_FAILED');
      }
    },

    openHTML5: function (url) {
      var video = document.getElementById('html5-video');
      if (!video) return Player.onState('error');
      Player.gen = (Player.gen || 0) + 1;
      var gen = Player.gen;
      function live() { return gen === Player.gen; }
      video.style.display = 'block';
      video.onplaying = function () { if (live()) Player.started(); };
      video.onwaiting = function () {
        if (live()) Player.onState(Player.current && Player.current.playing ? 'buffering' : 'loading');
      };
      video.onerror = function () { if (live()) Player.fail('MEDIA_ERROR'); };
      video.onended = function () { if (live()) Player.fail('STREAM_ENDED'); };
      video.src = url;
      var started = video.play();
      if (started && started.catch) started.catch(function () { /* autoplay or format */ });
    },

    togglePause: function () {
      if (Player.engine) {
        // Live pause: freeze the picture and disconnect; resume reconnects at the live point.
        if (!Player.engine.frozen) { Player.engine.freeze(); return true; }
        var c = Player.current;
        if (c) { Player.stop(true); c.playing = false; Player.open(); }
        return false;
      }
      if (hasAVPlay()) {
        var av = global.webapis.avplay;
        try {
          if (av.getState() === 'PLAYING') { av.pause(); return true; }
          av.play();
        } catch (e) { /* not ready */ }
        return false;
      }
      var video = document.getElementById('html5-video');
      if (!video) return false;
      if (video.paused) { video.play(); return false; }
      video.pause();
      return true;
    },

    /** `keepCurrent` = stopping only to try again (other format or busy retry). */
    stop: function (keepCurrent) {
      if (!keepCurrent) {
        clearTimeout(Player.retryTimer);
        clearTimeout(Player.attemptTimer);
      }
      Player.gen = (Player.gen || 0) + 1;
      if (Player.engine) {
        try { Player.engine.stop(); } catch (e) {}
        Player.engine = null;
      }
      if (hasAVPlay()) {
        try {
          var av = global.webapis.avplay;
          var state = av.getState();
          if (state !== 'NONE' && state !== 'IDLE') av.stop();
          av.close();
        } catch (e) { /* already closed */ }
      } else {
        var video = document.getElementById('html5-video');
        if (video) {
          video.onerror = null;
          video.pause();
          video.removeAttribute('src');
          video.load();
          video.style.display = 'none';
        }
      }
      if (!keepCurrent) Player.current = null;
    },

    /** Pause when the TV app goes to the background, resume when it comes back. */
    suspend: function () {
      if (hasAVPlay()) { try { global.webapis.avplay.suspend(); } catch (e) {} }
    },
    restore: function () {
      if (hasAVPlay()) { try { global.webapis.avplay.restore(); } catch (e) {} }
    }
  };

  Player.engineEnabled = engineEnabled;
  Player.setEngineEnabled = function (on) {
    try { global.localStorage.setItem(ENGINE_KEY, on ? 'on' : 'off'); } catch (e) {}
  };

  global.VeyloPlayer = Player;
})(window);

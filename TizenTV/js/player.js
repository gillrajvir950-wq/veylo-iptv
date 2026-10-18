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

  function remembered() {
    try { return JSON.parse(global.localStorage.getItem(MEMORY_KEY) || 'null'); } catch (e) { return null; }
  }
  function remember(value) {
    try { global.localStorage.setItem(MEMORY_KEY, JSON.stringify(value)); } catch (e) { /* storage blocked */ }
  }
  function agentByID(id) {
    for (var i = 0; i < AGENTS.length; i++) if (AGENTS[i].id === id) return AGENTS[i];
    return null;
  }
  function formatOf(url) { return /\.m3u8(\?|$)/i.test(url) ? 'HLS' : 'TS'; }

  /** Ordered tries: the identity that worked last time first, then every identity × format. */
  function buildPlan(url, altURL) {
    var urls = [url];
    if (altURL) urls.push(altURL);
    var memory = remembered();
    var agents = AGENTS.slice();
    var plan = [];
    if (memory) {
      var known = agentByID(memory.agent);
      if (known) {
        agents = [known].concat(AGENTS.filter(function (a) { return a !== known; }));
        // The format that worked first, with the remembered identity.
        if (memory.format === 'HLS' && altURL && formatOf(altURL) === 'HLS') urls = [altURL, url];
        if (memory.format === 'TS' && altURL && formatOf(altURL) === 'TS') urls = [altURL, url];
      }
    }
    agents.forEach(function (agent) {
      urls.forEach(function (u) { plan.push({ url: u, agent: agent, format: formatOf(u) }); });
    });
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

    play: function (url, altURL) {
      Player.stop();
      Player.current = { plan: buildPlan(url, altURL), step: 0, log: [], drops: 0 };
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
      if (hasAVPlay()) {
        Player.openAVPlay(tryNow.url, tryNow.agent.ua);
      } else {
        Player.openHTML5(tryNow.url);
      }
    },

    started: function () {
      var current = Player.current;
      if (!current) return;
      clearTimeout(Player.attemptTimer);
      if (!current.playing) {
        current.playing = true;
        var tryNow = current.plan[current.step];
        remember({ agent: tryNow.agent.id, format: tryNow.format });
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
        av.setDisplayRect(0, 0, 1920, 1080);
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

  global.VeyloPlayer = Player;
})(window);

/* Veylo TV — video playback.
 * On the Samsung TV this uses Samsung's AVPlay (webapis.avplay), which plays MPEG-TS and HLS.
 * In a normal browser (for testing) it falls back to an HTML5 <video>.
 *
 * Providers usually allow only one or two connections and keep counting a closed stream for
 * a while, so a refused connection is retried with growing pauses instead of failing at once. */
(function (global) {
  'use strict';

  function hasAVPlay() {
    return !!(global.webapis && global.webapis.avplay);
  }

  /** Seconds to wait before each "provider busy" retry (after TS and HLS were both tried once). */
  var BUSY_DELAYS = [4, 8, 12, 16];
  /** An attempt that hasn't started playing within this time counts as failed. */
  var ATTEMPT_TIMEOUT = 12000;

  var Player = {
    /** Called with ('loading' | 'playing' | 'error' | 'ended' | 'retry', info). */
    onState: function () {},
    current: null,
    retryTimer: null,
    attemptTimer: null,
    /** Last AVPlay error name (shown small on the error screen to help diagnose). */
    lastError: '',
    /** True once the alternate format (TS ↔ HLS) started faster this session; it is then tried first. */
    preferAlt: false,

    /** Plays `url`; on failure tries `altURL` (TS ↔ HLS), then retries while the provider is busy. */
    play: function (url, altURL) {
      Player.stop();
      var first = url, second = altURL || '';
      if (Player.preferAlt && second) { first = second; second = url; }
      Player.current = { first: first, second: second, step: 0, busy: 0 };
      Player.lastError = '';
      Player.open(first);
    },

    open: function (url) {
      Player.onState('loading');
      var current = Player.current;
      clearTimeout(Player.attemptTimer);
      Player.attemptTimer = setTimeout(function () {
        if (Player.current === current && !current.playing) Player.fail('TIMEOUT');
      }, ATTEMPT_TIMEOUT);
      if (hasAVPlay()) {
        Player.openAVPlay(url);
      } else {
        Player.openHTML5(url);
      }
    },

    started: function () {
      var current = Player.current;
      if (!current) return;
      clearTimeout(Player.attemptTimer);
      if (!current.playing) {
        current.playing = true;
        // The second format worked on its first try while the first failed: start with it next time.
        if (current.step === 1 && current.busy === 0 && current.second) Player.preferAlt = !Player.preferAlt;
      }
      Player.onState('playing');
    },

    /** step 0 = first format, step 1 = other format, then BUSY_DELAYS retries with the first format. */
    fail: function (reason) {
      if (reason) Player.lastError = String(reason);
      var current = Player.current;
      if (!current) return;
      clearTimeout(Player.attemptTimer);
      Player.stop(true);
      if (current.step === 0 && current.second) {
        current.step = 1;
        Player.open(current.second);
        return;
      }
      if (current.busy < BUSY_DELAYS.length) {
        var seconds = BUSY_DELAYS[current.busy];
        current.busy += 1;
        current.step = 2;
        Player.onState('retry', { attempt: current.busy, total: BUSY_DELAYS.length, seconds: seconds });
        clearTimeout(Player.retryTimer);
        Player.retryTimer = setTimeout(function () {
          if (Player.current !== current) return;
          // Alternate formats between busy retries.
          Player.open(current.busy % 2 === 1 || !current.second ? current.first : current.second);
        }, seconds * 1000);
        return;
      }
      Player.onState('error');
    },

    openAVPlay: function (url) {
      var av = global.webapis.avplay;
      // Callbacks from an older stream (fast zapping, retries) must not affect the new one.
      Player.gen = (Player.gen || 0) + 1;
      var gen = Player.gen;
      function live() { return gen === Player.gen; }
      try {
        av.open(url);
        av.setListener({
          onbufferingstart: function () { if (live()) Player.onState('loading'); },
          onbufferingcomplete: function () { if (live()) Player.started(); },
          onstreamcompleted: function () { if (live()) Player.onState('ended'); },
          onerror: function (type) { if (live()) Player.fail(type || 'PLAYER_ERROR'); },
          onevent: function () {}
        });
        // Providers that block the TV's browser engine get the same player identity as the API calls.
        var agent = global.VeyloAPI && global.VeyloAPI.state && global.VeyloAPI.state.userAgent;
        if (agent) {
          try { av.setStreamingProperty('USER_AGENT', agent); } catch (e) { /* not supported on this model */ }
        }
        // Start after a short buffer instead of the player's long default.
        try {
          av.setBufferingParam('PLAYER_BUFFER_FOR_PLAY', 'PLAYER_BUFFER_SIZE_IN_SECOND', 3);
          av.setBufferingParam('PLAYER_BUFFER_FOR_RESUME', 'PLAYER_BUFFER_SIZE_IN_SECOND', 5);
        } catch (e) { /* older firmware */ }
        try { av.setTimeoutForBuffering(10); } catch (e) { /* older firmware */ }
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
      video.onwaiting = function () { if (live()) Player.onState('loading'); };
      video.onerror = function () { if (live()) Player.fail('MEDIA_ERROR'); };
      video.onended = function () { if (live()) Player.onState('ended'); };
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

/* Veylo TV — video playback.
 * On the Samsung TV this uses Samsung's AVPlay (webapis.avplay), which plays MPEG-TS and HLS.
 * In a normal browser (for testing) it falls back to an HTML5 <video>. */
(function (global) {
  'use strict';

  function hasAVPlay() {
    return !!(global.webapis && global.webapis.avplay);
  }

  var Player = {
    /** Called with 'loading' | 'playing' | 'error' | 'ended'. */
    onState: function () {},
    current: null,
    triedAlt: false,

    /** Plays `url`; if it fails once, tries `altURL` (TS ↔ HLS). */
    play: function (url, altURL) {
      Player.stop();
      Player.current = { url: url, alt: altURL || '' };
      Player.triedAlt = false;
      Player.open(url);
    },

    open: function (url) {
      Player.onState('loading');
      if (hasAVPlay()) {
        Player.openAVPlay(url);
      } else {
        Player.openHTML5(url);
      }
    },

    retryAlternate: function () {
      var current = Player.current;
      if (current && current.alt && !Player.triedAlt) {
        Player.triedAlt = true;
        Player.stop(true);
        Player.open(current.alt);
        return true;
      }
      return false;
    },

    fail: function () {
      if (!Player.retryAlternate()) Player.onState('error');
    },

    openAVPlay: function (url) {
      var av = global.webapis.avplay;
      try {
        av.open(url);
        av.setListener({
          onbufferingstart: function () { Player.onState('loading'); },
          onbufferingcomplete: function () { Player.onState('playing'); },
          onstreamcompleted: function () { Player.onState('ended'); },
          onerror: function () { Player.fail(); },
          onevent: function () {}
        });
        av.setDisplayRect(0, 0, 1920, 1080);
        try { av.setDisplayMethod('PLAYER_DISPLAY_MODE_LETTER_BOX'); } catch (e) { /* older TVs */ }
        av.prepareAsync(function () {
          try {
            av.play();
            Player.onState('playing');
          } catch (e) { Player.fail(); }
        }, function () { Player.fail(); });
      } catch (e) {
        Player.fail();
      }
    },

    openHTML5: function (url) {
      var video = document.getElementById('html5-video');
      if (!video) return Player.onState('error');
      video.style.display = 'block';
      video.onplaying = function () { Player.onState('playing'); };
      video.onwaiting = function () { Player.onState('loading'); };
      video.onerror = function () { Player.fail(); };
      video.onended = function () { Player.onState('ended'); };
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

    /** `keepCurrent` = stopping only to try the alternate stream. */
    stop: function (keepCurrent) {
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

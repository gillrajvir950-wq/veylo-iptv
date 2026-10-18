/* Veylo TV — "Veylo engine": plays a live MPEG-TS stream the way the iPhone app (VLC) does.
 *
 * Samsung's own player (AVPlay) requests streams in its own way, and some providers stall or refuse
 * it while VLC on the iPhone starts instantly. Here the app fetches the stream itself — through the
 * web engine, or through Samsung's native downloader with VLC's identity (no browser origin) — turns
 * the MPEG-TS bytes into fragmented MP4 with mux.js and plays them in the page's <video> element
 * (Media Source Extensions). H.264/AAC streams are supported; anything else falls back to AVPlay.
 *
 * Written for Chromium 76 (Tizen 6): no optional chaining / nullish operator. */
(function (global) {
  'use strict';

  var VLC_AGENT = 'VLC/3.0.21 LibVLC/3.0.21';
  var PACKET = 188;
  /** How often received bytes are cut into fragments for the video element. */
  var FEED_INTERVAL = 700;
  /** No new bytes for this long while playing → the stream is treated as dropped. */
  var STALL_TIMEOUT = 15000;
  /** Native downloads write an ever-growing temp file; start a fresh one after this many bytes. */
  var NATIVE_FILE_LIMIT = 400 * 1024 * 1024;

  function supported() {
    return !!(global.MediaSource && global.muxjs && global.muxjs.mp4 && global.muxjs.mp4.Transmuxer && global.Uint8Array);
  }

  function hasNative() {
    return !!(global.tizen && global.tizen.download && global.tizen.DownloadRequest &&
      global.tizen.filesystem && global.tizen.filesystem.openFile);
  }

  function concat(a, b) {
    var out = new Uint8Array(a.byteLength + b.byteLength);
    out.set(a, 0);
    out.set(b, a.byteLength);
    return out;
  }

  function errorWith(name) {
    var e = new Error(name);
    e.name = name;
    return e;
  }

  // ---------- Byte sources ----------

  /** Streams the URL through the page's own network stack (fetch + ReadableStream). */
  function WebSource(url, onBytes, onError) {
    var self = this;
    this.stopped = false;
    this.controller = global.AbortController ? new global.AbortController() : null;
    var options = { cache: 'no-store', credentials: 'omit' };
    if (this.controller) options.signal = this.controller.signal;
    global.fetch(url, options).then(function (response) {
      if (self.stopped) return;
      if (!response.ok) throw errorWith('HTTP_' + response.status);
      if (!response.body || !response.body.getReader) throw errorWith('NO_STREAM_READER');
      var reader = response.body.getReader();
      self.reader = reader;
      function pump() {
        return reader.read().then(function (result) {
          if (self.stopped) return;
          if (result.done) { onError(errorWith('STREAM_ENDED')); return; }
          if (result.value && result.value.byteLength) onBytes(result.value);
          return pump();
        });
      }
      return pump();
    }).catch(function (error) {
      if (self.stopped) return;
      onError(error && error.name && error.name !== 'TypeError' ? error : errorWith('WEB_FETCH_FAILED'));
    });
  }
  WebSource.prototype.stop = function () {
    this.stopped = true;
    try { if (this.controller) this.controller.abort(); } catch (e) {}
    try { if (this.reader) this.reader.cancel(); } catch (e) {}
  };

  /** Samsung's native downloader (VLC identity, no browser origin) into a temp file that is read
   *  while it grows. */
  function NativeSource(url, agent, onBytes, onError) {
    this.url = url;
    this.agent = agent;
    this.onBytes = onBytes;
    this.onError = onError;
    this.stopped = false;
    this.begin();
  }
  NativeSource.prototype.begin = function () {
    var self = this;
    this.name = 'veylo-live-' + Date.now() + '-' + Math.floor(Math.random() * 1e6) + '.ts';
    this.path = 'wgt-private-tmp/' + this.name;
    this.position = 0;
    this.handle = null;
    this.started = Date.now();
    try {
      var request = new global.tizen.DownloadRequest(this.url, 'wgt-private-tmp', this.name, 'ALL', {
        'User-Agent': this.agent, 'Accept': '*/*', 'Icy-MetaData': '1', 'Connection': 'close'
      });
      this.id = global.tizen.download.start(request, {
        onprogress: function () {},
        onpaused: function () {},
        oncanceled: function () {},
        oncompleted: function () { if (!self.stopped) self.fail('STREAM_ENDED'); },
        onfailed: function (id, error) {
          if (!self.stopped) self.fail('NATIVE_' + ((error && (error.name || error.message)) || 'FAILED'));
        }
      });
    } catch (e) {
      this.fail('NATIVE_START_' + ((e && e.name) || 'FAILED'));
      return;
    }
    clearInterval(this.timer);
    this.timer = setInterval(function () { self.poll(); }, 300);
  };
  NativeSource.prototype.poll = function () {
    if (this.stopped) return;
    var fs = global.tizen.filesystem;
    try {
      if (!this.handle) this.handle = fs.openFile(this.path, 'r');
    } catch (e) {
      // The file appears with the first bytes; if it never does, the downloader isn't streaming.
      if (Date.now() - this.started > 12000) this.fail('NATIVE_NO_DATA');
      return;
    }
    try {
      var size = this.handle.seek(0, 'END');
      if (size > this.position) {
        this.handle.seek(this.position, 'BEGIN');
        var data = this.handle.readData(size - this.position);
        this.position = size;
        if (data && data.byteLength) this.onBytes(data instanceof Uint8Array ? data : new Uint8Array(data));
      } else if (!this.position && Date.now() - this.started > 12000) {
        this.fail('NATIVE_NO_DATA');
        return;
      }
      if (this.position > NATIVE_FILE_LIMIT) this.restart();
    } catch (e) {
      try { this.handle.close(); } catch (e2) {}
      this.handle = null;
    }
  };
  NativeSource.prototype.cleanup = function () {
    clearInterval(this.timer);
    try { if (this.id !== undefined) global.tizen.download.cancel(this.id); } catch (e) {}
    try { if (this.handle) this.handle.close(); } catch (e) {}
    this.handle = null;
    var path = this.path;
    setTimeout(function () {
      try { global.tizen.filesystem.deleteFile(path); } catch (e) { /* temp folder is cleaned anyway */ }
    }, 1500);
  };
  NativeSource.prototype.restart = function () {
    this.cleanup();
    this.begin();
  };
  NativeSource.prototype.fail = function (name) {
    if (this.stopped) return;
    this.stop();
    this.onError(errorWith(name));
  };
  NativeSource.prototype.stop = function () {
    if (this.stopped) return;
    this.stopped = true;
    this.cleanup();
  };

  // ---------- TS → fMP4 → <video> ----------

  /** Bytes up to the last start of a video PES (so no frame is cut in half when flushing). */
  function cutPoint(bytes, videoPID) {
    var last = -1;
    for (var i = 0; i + PACKET <= bytes.byteLength; i += PACKET) {
      if (bytes[i] !== 0x47) continue;
      var pusi = bytes[i + 1] & 0x40;
      var pid = ((bytes[i + 1] & 0x1f) << 8) | bytes[i + 2];
      if (pusi && (videoPID < 0 || pid === videoPID)) last = i;
    }
    return last;
  }

  /** The PID that carries most packets — the video in a normal TV stream. */
  function busiestPID(bytes) {
    var counts = {};
    var best = -1, bestCount = 0;
    for (var i = 0; i + PACKET <= bytes.byteLength; i += PACKET) {
      if (bytes[i] !== 0x47) continue;
      var pid = ((bytes[i + 1] & 0x1f) << 8) | bytes[i + 2];
      if (pid === 0 || pid === 0x1fff) continue;
      counts[pid] = (counts[pid] || 0) + 1;
      if (counts[pid] > bestCount) { bestCount = counts[pid]; best = pid; }
    }
    return best;
  }

  /** First offset where three sync bytes line up 188 apart. */
  function syncOffset(bytes) {
    for (var i = 0; i < Math.min(bytes.byteLength - PACKET * 2, PACKET * 4); i++) {
      if (bytes[i] === 0x47 && bytes[i + PACKET] === 0x47 && bytes[i + PACKET * 2] === 0x47) return i;
    }
    return -1;
  }

  function Session(video, url, mode, callbacks) {
    this.video = video;
    this.url = url;
    this.mode = mode;
    this.cb = callbacks;
    this.pending = new Uint8Array(0);
    this.synced = false;
    this.videoPID = -1;
    this.queue = [];
    this.sourceBuffer = null;
    this.playing = false;
    this.stopped = false;
    this.lastBytes = Date.now();
    this.start();
  }

  Session.prototype.start = function () {
    var self = this;
    var video = this.video;
    this.mediaSource = new global.MediaSource();
    this.objectURL = global.URL.createObjectURL(this.mediaSource);
    video.style.display = 'block';
    video.muted = false;
    video.src = this.objectURL;
    this.mediaSource.addEventListener('sourceopen', function () {
      if (self.stopped) return;
      self.transmuxer = new global.muxjs.mp4.Transmuxer({ remux: true });
      self.transmuxer.on('data', function (segment) { self.segment(segment); });
      self.open();
    });
    video.onplaying = function () {
      if (self.stopped) return;
      if (!self.playing) { self.playing = true; self.cb.onPlaying(); }
      else self.cb.onPlaying();
    };
    video.onwaiting = function () { if (!self.stopped && self.playing) self.cb.onBuffering(); };
    video.onerror = function () {
      var err = video.error;
      self.fail('VIDEO_ERROR_' + (err ? err.code : 0));
    };
  };

  Session.prototype.open = function () {
    var self = this;
    var onBytes = function (bytes) { self.bytes(bytes); };
    var onError = function (error) { self.fail((error && (error.name || error.message)) || 'SOURCE_FAILED'); };
    this.source = this.mode === 'native'
      ? new NativeSource(this.url, VLC_AGENT, onBytes, onError)
      : new WebSource(this.url, onBytes, onError);
    this.feedTimer = setInterval(function () { self.feed(); self.watch(); }, FEED_INTERVAL);
  };

  Session.prototype.bytes = function (chunk) {
    this.lastBytes = Date.now();
    this.pending = concat(this.pending, chunk);
    if (!this.synced) {
      var offset = syncOffset(this.pending);
      if (offset < 0) {
        if (this.pending.byteLength > 64 * 1024) this.fail('NOT_MPEG_TS');
        return;
      }
      this.pending = this.pending.subarray(offset);
      this.synced = true;
    }
  };

  Session.prototype.feed = function () {
    if (this.stopped || !this.synced || !this.transmuxer) return;
    if (this.pending.byteLength < PACKET * 50) return;
    if (this.videoPID < 0 && this.pending.byteLength > PACKET * 400) this.videoPID = busiestPID(this.pending);
    var cut = cutPoint(this.pending, this.videoPID);
    if (cut <= 0) {
      // Keep collecting until a frame boundary arrives (but never hold more than ~4 MB).
      if (this.pending.byteLength < 4 * 1024 * 1024) return;
      cut = this.pending.byteLength - (this.pending.byteLength % PACKET);
    }
    var ready = this.pending.subarray(0, cut);
    this.pending = this.pending.slice(cut);
    try {
      this.transmuxer.push(ready);
      this.transmuxer.flush();
    } catch (e) {
      this.fail('TRANSMUX_FAILED');
    }
  };

  Session.prototype.segment = function (segment) {
    if (this.stopped) return;
    if (!this.sourceBuffer) {
      var codecs = [];
      try {
        var tracks = global.muxjs.mp4.probe.tracks(segment.initSegment) || [];
        tracks.forEach(function (t) { if (t.codec) codecs.push(t.codec); });
      } catch (e) { /* use defaults below */ }
      var hasVideo = codecs.some(function (c) { return /^avc|^hvc|^hev/.test(c); });
      if (!hasVideo) {
        // mux.js only handles H.264 video; leave HEVC and audio-only streams to AVPlay.
        this.noVideoSegments = (this.noVideoSegments || 0) + 1;
        if (this.noVideoSegments > 6) this.fail('NO_H264_VIDEO');
        return;
      }
      var mime = 'video/mp4; codecs="' + codecs.join(',') + '"';
      if (global.MediaSource.isTypeSupported && !global.MediaSource.isTypeSupported(mime)) {
        mime = 'video/mp4; codecs="avc1.64001f' + (codecs.length > 1 ? ',mp4a.40.2' : '') + '"';
      }
      try {
        this.sourceBuffer = this.mediaSource.addSourceBuffer(mime);
      } catch (e) {
        this.fail('UNSUPPORTED_' + codecs.join('+'));
        return;
      }
      var self = this;
      this.sourceBuffer.addEventListener('updateend', function () { self.append(); });
      this.queue.push(concat(segment.initSegment, segment.data));
    } else {
      this.queue.push(segment.data);
    }
    this.append();
  };

  Session.prototype.append = function () {
    var sb = this.sourceBuffer;
    if (this.stopped || !sb || sb.updating) return;
    var video = this.video;
    // Drop what has already been watched to keep memory low.
    if (sb.buffered.length && video.currentTime - sb.buffered.start(0) > 40) {
      try { sb.remove(sb.buffered.start(0), video.currentTime - 20); return; } catch (e) {}
    }
    var next = this.queue.shift();
    if (!next) {
      this.startIfReady();
      return;
    }
    try {
      sb.appendBuffer(next);
    } catch (e) {
      if (e && e.name === 'QuotaExceededError') {
        this.queue.unshift(next);
        try { sb.remove(0, Math.max(0, video.currentTime - 5)); } catch (e2) {}
        return;
      }
      this.fail('APPEND_FAILED');
    }
  };

  Session.prototype.startIfReady = function () {
    var video = this.video;
    var sb = this.sourceBuffer;
    if (!sb || !sb.buffered.length) return;
    var start = sb.buffered.start(0), end = sb.buffered.end(sb.buffered.length - 1);
    if (!this.begun) {
      if (end - start < 1.5) return;   // ~1.5 s of picture before starting
      this.begun = true;
      try { video.currentTime = start + 0.1; } catch (e) {}
      var promise = video.play();
      if (promise && promise.catch) promise.catch(function () {});
      return;
    }
    // Stay close to live: if far behind, jump ahead.
    if (end - video.currentTime > 12) {
      try { video.currentTime = end - 3; } catch (e) {}
    }
  };

  Session.prototype.watch = function () {
    if (this.stopped) return;
    if (Date.now() - this.lastBytes > STALL_TIMEOUT) this.fail(this.playing ? 'STREAM_STALLED' : 'NO_DATA');
    // A gap in the buffer (lost fragment) would freeze playback: hop over it.
    var video = this.video;
    var sb = this.sourceBuffer;
    if (this.begun && sb && sb.buffered.length > 1 && video.readyState < 3) {
      for (var i = 0; i < sb.buffered.length; i++) {
        if (sb.buffered.start(i) > video.currentTime) {
          try { video.currentTime = sb.buffered.start(i) + 0.05; } catch (e) {}
          break;
        }
      }
    }
  };

  Session.prototype.fail = function (name) {
    if (this.stopped) return;
    this.stop();
    this.cb.onError(name);
  };

  Session.prototype.stop = function () {
    if (this.stopped) return;
    this.stopped = true;
    clearInterval(this.feedTimer);
    if (this.source) this.source.stop();
    var video = this.video;
    video.onplaying = null;
    video.onwaiting = null;
    video.onerror = null;
    try { video.pause(); } catch (e) {}
    try { video.removeAttribute('src'); video.load(); } catch (e) {}
    try { global.URL.revokeObjectURL(this.objectURL); } catch (e) {}
    video.style.display = 'none';
  };

  global.VeyloEngine = {
    supported: supported,
    hasNative: hasNative,
    /** mode: 'web' | 'native'. callbacks: onPlaying, onBuffering, onError(name). */
    start: function (url, mode, callbacks) {
      var video = document.getElementById('html5-video');
      if (!video || !supported()) {
        setTimeout(function () { callbacks.onError('ENGINE_UNAVAILABLE'); }, 0);
        return null;
      }
      return new Session(video, url, mode, callbacks);
    }
  };
})(window);

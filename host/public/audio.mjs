// Physical audio resources are keyed by the Bend operation ticket. No task or
// draft policy, account credentials, or final-history writes live in this adapter.
export class AudioRuntime {
  constructor({ emit, request, createTask, field, browserId, limits, loginTarget,
    openWindow = (...args) => globalThis.open(...args), mediaDevices = globalThis.navigator?.mediaDevices,
    MediaRecorder = globalThis.MediaRecorder, RTCPeerConnection = globalThis.RTCPeerConnection,
    Audio = globalThis.Audio, EventSource = globalThis.EventSource, fetch = globalThis.fetch.bind(globalThis) }) {
    Object.assign(this, { emit, request, createTask, field, browserId, limits, loginTarget, openWindow, mediaDevices, MediaRecorder,
      RTCPeerConnection, Audio, EventSource, fetch });
    this.resources = new Map();
    this.disposed = false;
  }
  url(path) {
    return `${path}${path.includes('?') ? '&' : '?'}browser_id=${encodeURIComponent(this.browserId)}`;
  }
  current(entry) { return !this.disposed && this.resources.get(entry.ticket) === entry && !entry.controller.signal.aborted; }
  observe(type, values = {}) { if (!this.disposed) this.emit(type, values); }
  async capabilities() {
    try {
      const body = await this.request(this.url('/api/audio/capabilities'));
      this.observe('Capabilities', { connections: body.connections });
      if (body.connections.length === 0) this.observe('CapabilitiesFailed', {
        reason: 'Use Sign in for voice to authorize ChatGPT dictation and voice.',
      });
    } catch (error) {
      // DEFENSE: The authenticated capabilities request may fail after account removal or a network disconnect.
      this.observe('CapabilitiesFailed', { reason: error.message });
    }
  }
  closeLogin() {
    const pending = this.loginController;
    pending?.abort();
    this.loginController = null;
    // DEFENSE: Detaching opener prevents closing the cross-origin authorization page; only our pending blank window remains closeable.
    if (pending) this.loginWindow?.close();
    this.loginWindow = null;
  }
  accountChanged(error) {
    this.closeLogin();
    // DEFENSE: A rejected OAuth callback reports its error here; a capabilities refresh would clear that failure notice.
    if (error) this.observe('CapabilitiesFailed', { reason: error });
    else this.observe('Refresh');
  }
  focus() {
    if (!this.loginWindow) return;
    if (this.loginWindow.closed) this.loginWindow = null;
    this.observe('Refresh');
  }
  async login() {
    if (this.loginWindow && !this.loginWindow.closed) { this.loginWindow.focus(); return; }
    const popup = this.openWindow('about:blank', '_blank');
    // DEFENSE: A browser's popup policy can reject the window opened by the explicit sign-in gesture.
    if (!popup) { this.observe('CapabilitiesFailed', { reason: 'Allow the sign-in popup and choose Sign in for voice again.' }); return; }
    popup.opener = null;
    this.loginWindow = popup;
    const controller = this.loginController = new AbortController();
    try {
      const body = await this.request('/api/audio/login', { method: 'POST',
        headers: { 'content-type': 'application/json' }, signal: controller.signal,
        body: JSON.stringify({ browser_id: this.browserId }) });
      // DEFENSE: The user can close the popup, or a trusted completion can release it, before the login URL arrives.
      if (controller.signal.aborted || popup.closed) return;
      popup.location.replace(this.loginTarget(body.url));
      this.loginController = null;
    } catch (error) {
      // DEFENSE: Starting official authorization or validating its returned URL can fail; retain the draft and expose that error.
      if (controller.signal.aborted) return;
      this.closeLogin();
      this.observe('CapabilitiesFailed', { reason: error.message });
    }
  }
  entry(ticket) {
    const entry = { ticket, controller: new AbortController(), chunks: [], bytes: 0, inputMuted: false, outputMuted: false };
    this.resources.set(ticket, entry);
    return entry;
  }
  fail(entry, error) {
    if (!this.current(entry)) return;
    this.observe('Failed', { ticket: entry.ticket, reason: error.message ?? String(error) });
    this.release(entry.ticket);
  }
  microphone() {
    // DEFENSE: Browsers omit mediaDevices when a remote Selvedge page is served over an insecure HTTP origin.
    if (!this.mediaDevices?.getUserMedia) throw new Error('Microphone access requires HTTPS or localhost');
    return this.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true } });
  }
  async record(effect) {
    const entry = this.entry(effect.ticket);
    try {
      const field = this.field(effect.owner);
      // DEFENSE: Navigation can remove the originating composer before the recording effect begins.
      if (!field) throw new Error('The recording editor is no longer open');
      const start = BigInt(Array.from(field.value.slice(0, field.selectionStart ?? field.value.length)).length);
      const end = BigInt(Array.from(field.value.slice(0, field.selectionEnd ?? field.value.length)).length);
      entry.stream = await this.microphone();
      if (!this.current(entry)) { this.stopTracks(entry); return; }
      entry.recorder = new this.MediaRecorder(entry.stream);
      entry.stopped = new Promise((resolve, reject) => {
        entry.recorder.ondataavailable = event => {
          if (!this.current(entry) || !event.data.size) return;
          entry.bytes += event.data.size;
          // DEFENSE: Long recordings can exceed the host's accepted upload size while buffered in the browser.
          if (entry.bytes > this.limits.asr_max_bytes) { this.fail(entry, new Error(`Recording exceeds ${this.limits.asr_max_bytes} bytes`)); return; }
          entry.chunks.push(event.data);
        };
        entry.recorder.onstop = () => resolve();
        entry.recorder.onerror = event => reject(event.error ?? new Error('Microphone recording failed'));
      });
      // The stop promise can reject before the user chooses Finish.
      entry.stopped.catch(error => this.fail(entry, error));
      entry.recorder.start(1000);
      this.observe('Captured', { ticket: entry.ticket, start, end });
    } catch (error) {
      // DEFENSE: Microphone permission, a missing device, or unsupported recording can reject an explicit recording request.
      this.fail(entry, error);
    }
  }
  async transcribe(effect) {
    const entry = this.resources.get(effect.ticket);
    if (!entry || !this.current(entry)) return;
    try {
      if (entry.recorder.state !== 'inactive') entry.recorder.stop();
      await entry.stopped;
      this.stopTracks(entry);
      if (!this.current(entry)) return;
      const mime = entry.recorder.mimeType || entry.chunks[0]?.type;
      // DEFENSE: An empty recording or a recorder without an actual media type cannot be sent as a valid audio file.
      if (!entry.bytes || !mime) throw new Error('The recording contains no audio');
      const audio = new Blob(entry.chunks, { type: mime });
      entry.chunks = [];
      const body = await this.request(this.url(`/api/audio/transcribe?connection=${encodeURIComponent(effect.connection)}`), {
        method: 'POST', headers: { 'content-type': mime }, body: audio,
        signal: AbortSignal.any([entry.controller.signal, AbortSignal.timeout(this.limits.request_timeout_ms)]),
      });
      if (!this.current(entry)) return;
      this.resources.delete(entry.ticket);
      this.observe('Transcribed', { ticket: entry.ticket, text: body.text });
    } catch (error) {
      // DEFENSE: Uploads can be rejected, lose the network connection, or be cancelled by a later Bend decision.
      if (error.name !== 'AbortError') this.fail(entry, error);
    }
  }
  async create(effect) {
    const entry = this.entry(effect.ticket);
    try {
      const task = await this.createTask(effect.command, entry.controller.signal);
      if (!this.current(entry)) return;
      this.resources.delete(entry.ticket);
      this.observe('TaskCreated', { ticket: effect.ticket, task: BigInt(task) });
    } catch (error) {
      // DEFENSE: Task creation uses the ordinary command boundary and can reject the selected model or workspace.
      if (error.name !== 'AbortError') this.fail(entry, error);
    }
  }
  async connect(effect) {
    const entry = this.entry(effect.ticket);
    entry.timer = setTimeout(() => this.fail(entry, new Error('Voice connection timed out')), this.limits.connect_timeout_ms);
    try {
      entry.stream = await this.microphone();
      if (!this.current(entry)) { this.stopTracks(entry); return; }
      for (const track of entry.stream.getAudioTracks()) track.enabled = false;
      entry.peer = new this.RTCPeerConnection();
      entry.output = new this.Audio();
      entry.output.autoplay = true;
      entry.output.playsInline = true;
      entry.peer.ontrack = event => {
        if (!this.current(entry)) return;
        entry.output.srcObject = event.streams[0] ?? new MediaStream([event.track]);
        entry.output.play().catch(error => this.fail(entry, error));
      };
      entry.peer.onconnectionstatechange = () => {
        if (!this.current(entry)) return;
        if (entry.peer.connectionState === 'failed' || entry.peer.connectionState === 'closed') this.fail(entry, new Error('Voice media connection ended'));
        else this.ready(entry);
      };
      for (const track of entry.stream.getTracks()) entry.peer.addTrack(track, entry.stream);
      entry.channel = entry.peer.createDataChannel('oai-events');
      entry.channel.onopen = () => this.ready(entry);
      entry.channel.onmessage = event => {
        if (!this.current(entry)) return;
        let message;
        try { message = JSON.parse(event.data); }
        catch (error) {
          // DEFENSE: A malformed upstream data-channel event cannot participate in the session readiness protocol.
          this.fail(entry, error); return;
        }
        if (['session.started', 'session.created', 'session.updated'].includes(message.type)) {
          entry.sessionReady = true;
          this.ready(entry);
        } else if (message.type === 'error') this.fail(entry, new Error(message.error?.message ?? message.message ?? 'Voice service error'));
      };
      entry.channel.onerror = () => this.fail(entry, new Error('Voice data channel failed'));
      entry.channel.onclose = () => this.fail(entry, new Error('Voice data channel ended'));
      await entry.peer.setLocalDescription(await entry.peer.createOffer());
      await this.iceGathered(entry);
      if (!this.current(entry)) return;
      const body = await this.request(this.url('/api/audio/sessions'), { method: 'POST',
        headers: { 'content-type': 'application/json' }, signal: entry.controller.signal,
        body: JSON.stringify({ connection: effect.connection, task_id: Number(effect.task),
          browser_id: this.browserId, sdp: entry.peer.localDescription.sdp }),
      });
      entry.session = body.id;
      if (!this.current(entry)) { this.stopSession(entry); return; }
      await entry.peer.setRemoteDescription({ type: 'answer', sdp: body.sdp });
      if (!this.current(entry)) return;
      entry.events = new this.EventSource(this.url(`/api/audio/sessions/${encodeURIComponent(body.id)}/events`), { withCredentials: true });
      entry.events.onmessage = event => {
        if (!this.current(entry)) return;
        let message;
        try { message = JSON.parse(event.data); }
        catch (error) {
          // DEFENSE: Invalid JSON on the host event stream cannot be interpreted as a voice observation.
          this.fail(entry, error); return;
        }
        if (message.type === 'ready') { entry.controlReady = true; this.ready(entry); }
        else if (message.type === 'account_changed') this.accountChanged(message.error);
        else if (message.type === 'error') this.fail(entry, new Error(message.message ?? 'Voice control connection failed'));
        else if (message.type === 'stopped') {
          this.observe('Ended', { ticket: entry.ticket, reason: message.reason ?? '' });
          this.release(entry.ticket);
        } else if (message.type === 'transcript') {
          entry.live ??= new Map();
          const key = message.role;
          if (message.final) {
            // A final may follow deltas from the next utterance; the host supplies the remaining partial snapshot.
            if (message.remaining) entry.live.set(key, message.remaining);
            else entry.live.delete(key);
          } else entry.live.set(key, (entry.live.get(key) ?? '') + message.text);
          this.observe('LiveText', { ticket: entry.ticket, text: [...entry.live.values()].join('\n') });
        }
      };
      entry.events.onerror = () => this.fail(entry, new Error('Voice control connection ended'));
      this.ready(entry);
    } catch (error) {
      // DEFENSE: Microphone permission, SDP negotiation, the local endpoint or upstream authentication can fail during startup.
      if (error.name !== 'AbortError') this.fail(entry, error);
    }
  }
  ready(entry) {
    if (!this.current(entry) || entry.ready || !entry.controlReady || !entry.sessionReady ||
      entry.peer.connectionState !== 'connected' || entry.channel.readyState !== 'open') return;
    entry.ready = true;
    clearTimeout(entry.timer);
    entry.durationTimer = setTimeout(() => {
      if (!this.current(entry)) return;
      this.observe('Ended', { ticket: entry.ticket, reason: 'Voice session duration limit reached' });
      this.release(entry.ticket);
    }, this.limits.session_max_ms);
    for (const track of entry.stream.getAudioTracks()) track.enabled = !entry.inputMuted;
    this.observe('VoiceReady', { ticket: entry.ticket });
  }
  iceGathered(entry) {
    if (entry.peer.iceGatheringState === 'complete') return Promise.resolve();
    return new Promise((resolve, reject) => {
      const changed = () => {
        if (entry.peer.iceGatheringState === 'complete') { cleanup(); resolve(); }
      };
      const aborted = () => { cleanup(); reject(new DOMException('Voice cancelled', 'AbortError')); };
      const cleanup = () => {
        entry.peer.removeEventListener('icegatheringstatechange', changed);
        entry.controller.signal.removeEventListener('abort', aborted);
      };
      entry.peer.addEventListener('icegatheringstatechange', changed);
      entry.controller.signal.addEventListener('abort', aborted, { once: true });
    });
  }
  muteInput(effect) {
    const entry = this.resources.get(effect.ticket);
    if (!entry || !this.current(entry)) return;
    entry.inputMuted = effect.muted;
    for (const track of entry.stream?.getAudioTracks() ?? []) track.enabled = entry.ready && !effect.muted;
  }
  muteOutput(effect) {
    const entry = this.resources.get(effect.ticket);
    if (!entry || !this.current(entry)) return;
    entry.outputMuted = effect.muted;
    if (entry.output) entry.output.muted = effect.muted;
  }
  stopTracks(entry) { for (const track of entry.stream?.getTracks() ?? []) track.stop(); }
  stopSession(entry, keepalive = false) {
    if (!entry.session) return;
    const id = entry.session;
    entry.session = null;
    // DEFENSE: Hang-up and page release can race with a network disconnect; local media is already released even when the stop request fails.
    void this.fetch(this.url(`/api/audio/sessions/${encodeURIComponent(id)}/stop`), {
      method: 'POST', credentials: 'same-origin', keepalive,
    }).catch(() => {});
  }
  release(ticket, keepalive = false) {
    const entry = this.resources.get(ticket);
    if (!entry) return;
    this.resources.delete(ticket);
    entry.controller.abort();
    clearTimeout(entry.timer);
    clearTimeout(entry.durationTimer);
    entry.events?.close();
    if (entry.recorder?.state === 'recording') entry.recorder.stop();
    this.stopTracks(entry);
    entry.channel?.close();
    entry.peer?.close();
    if (entry.output) { entry.output.pause(); entry.output.srcObject = null; }
    entry.chunks = [];
    this.stopSession(entry, keepalive);
  }
  dispose() {
    this.disposed = true;
    this.closeLogin();
    for (const ticket of [...this.resources.keys()]) this.release(ticket, true);
  }
  async execute(tag, effect) {
    switch (tag) {
      case 'BeginAudioLogin': return this.login();
      case 'LoadCapabilities': return this.capabilities();
      case 'Record': return this.record(effect);
      case 'Transcribe': return this.transcribe(effect);
      case 'CreateTask': return this.create(effect);
      case 'ConnectVoice': return this.connect(effect);
      case 'SetInputMute': return this.muteInput(effect);
      case 'SetOutputMute': return this.muteOutput(effect);
      case 'Release': return this.release(effect.ticket);
    }
  }
}

const statusInterval = 1_500;

// The browser session owns the dialog and its ticket. This adapter retains the
// corresponding popup or polling resources and reports host observations.
export class ChatGPTLogin {
  constructor({ request, emit, loginTarget, selectCode }) {
    Object.assign(this, { request, emit, loginTarget, selectCode });
  }

  send(body, options = {}) {
    return this.request('/api/audio/login', {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body), ...options,
    });
  }

  active(entry) { return this.entry === entry; }

  async start(ticket, method) {
    const entry = { ticket, controller: new AbortController() };
    this.entry = entry;
    try {
      if (method === 'browser') {
        const popup = window.open('about:blank', '_blank');
        // DEFENSE: Browser popup policy can block even the explicit sign-in gesture.
        if (!popup) throw new Error('Allow the sign-in popup and try again.');
        popup.opener = null;
        entry.popup = popup;
      }
      if (this.cancellation) await this.cancellation;
      if (!this.active(entry)) return;
      // Read the start reply even if dismissed in the meantime, so we can
      // cancel the attempt as soon as the host returns its identifier.
      entry.starting = this.send(method === 'browser' ? {} : { method });
      const body = await entry.starting;
      if (!this.active(entry)) return;
      if (typeof body?.attempt_id === 'string' && body.attempt_id) entry.id = body.attempt_id;
      if (method === 'browser') {
        const popup = entry.popup;
        // DEFENSE: The sign-in tab may have been closed before its URL arrived.
        if (popup.closed) throw new Error('The sign-in tab was closed.');
        popup.location.replace(this.loginTarget(method, body.url));
        entry.navigated = true;
        this.emit({ type: 'audio_login_browser_opened', ticket });
        if (entry.id) this.scheduleStatus(entry);
        return;
      }

      // DEFENSE: The login endpoint may return an incomplete challenge.
      if (!entry.id)
        throw new Error('Selvedge did not return a device sign-in attempt.');
      const url = this.loginTarget(method, body.verification_url);
      const expires = new Date(body.expires_at);
      // DEFENSE: An incomplete or malformed challenge cannot be shown as usable.
      if (typeof body.user_code !== 'string' || !body.user_code || typeof body.expires_at !== 'string' || !Number.isFinite(expires.getTime()))
        throw new Error('Selvedge returned an invalid device code.');
      this.emit({ type: 'audio_login_code_received', ticket, url, code: body.user_code, expires: expires.toLocaleString() });
      this.scheduleStatus(entry);
    } catch (error) {
      // DEFENSE: A failed start or rejected verification URL must not leave a live code behind.
      if (this.active(entry)) await this.fail(entry, error);
    }
  }

  scheduleStatus(entry) {
    if (this.active(entry)) entry.timer = setTimeout(() => this.readStatus(entry), statusInterval);
  }

  async readStatus(entry) {
    try {
      const body = await this.send({ action: 'status', attempt_id: entry.id }, { signal: entry.controller.signal });
      if (!this.active(entry)) return;
      switch (body?.status) {
        case 'pending': this.scheduleStatus(entry); return;
        case 'signed_in':
        case 'cancelled':
        case 'expired': this.finish(entry, body.status); return;
        case 'failed': this.finish(entry, 'failed', body.error || 'ChatGPT sign-in failed.'); return;
        // DEFENSE: A malformed reply cannot advance the sign-in dialog.
        default: throw new Error('Selvedge returned an unknown sign-in status.');
      }
    } catch (error) {
      // DEFENSE: The service can restart or become unreachable while the dialog is waiting.
      if (this.active(entry)) await this.fail(entry, error);
    }
  }

  async fail(entry, error) {
    if (entry.id && error.status !== 404) {
      const outcome = await this.cancelAttempt(entry);
      if (outcome?.status === 'signed_in') { this.finish(entry, 'signed_in'); return; }
    }
    this.finish(entry, 'failed', error.message);
  }

  finish(entry, status, error) {
    if (!this.active(entry)) return;
    this.detach(entry);
    this.emit({ type: 'audio_login_finished', ticket: entry.ticket, status, ...(error ? { error } : {}) });
  }

  detach(entry) {
    this.entry = undefined;
    clearTimeout(entry.timer);
    entry.controller.abort();
    // DEFENSE: The blank popup is still ours; after navigation it belongs to ChatGPT.
    if (entry.popup && !entry.navigated) entry.popup.close();
  }

  cancelAttempt(entry) {
    return entry.cancelling ??= (async () => {
      try {
        const id = entry.id ?? (await entry.starting)?.attempt_id;
        if (typeof id === 'string' && id)
          return await this.send({ action: 'cancel', attempt_id: id }, { keepalive: true });
      } catch {
        // DEFENSE: Page teardown, a service restart, or a lost connection can
        // prevent delivery. The host still bounds the lifetime of the attempt.
      }
    })();
  }

  release(ticket) {
    const entry = this.entry;
    if (!entry || ticket !== entry.ticket) return;
    this.detach(entry);
    if (entry.starting) {
      const cancellation = this.cancellation = this.cancelAttempt(entry);
      void cancellation.then(() => { if (this.cancellation === cancellation) this.cancellation = undefined; });
    }
  }

  dispose() {
    if (this.entry) this.release(this.entry.ticket);
  }

  focus() {
    if (this.entry?.navigated && !this.entry.id) this.emit({ type: 'audio_refresh' });
  }

  async copy(ticket, key, code) {
    const entry = this.entry;
    if (!entry || entry.ticket !== ticket) return;
    let copied = false;
    try {
      // DEFENSE: Remote HTTP pages may not have the Clipboard API, and browsers
      // may deny writeText even in a secure context.
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(code);
        copied = true;
      }
    } catch {}
    if (!this.active(entry)) return;
    if (!copied) this.selectCode(key);
    this.emit({ type: 'audio_login_copy_finished', ticket, copied });
  }
}

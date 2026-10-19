// SSE delimiters may span network reads, including the CR/LF pair itself.
// A bounded incremental decoder is shared by the browser and protocol probes.
export class EventFrames {
  constructor(consume, limit = 4 * 1024 * 1024) {
    this.consume = consume;
    this.limit = limit;
    this.pending = '';
  }
  write(chunk) {
    this.pending += chunk;
    let separator;
    while ((separator = /\r?\n\r?\n/.exec(this.pending))) {
      // DEFENSE: A network SSE frame can exceed the 4 MiB retained-input limit before its delimiter arrives.
      if (separator.index > this.limit) throw new RangeError('Event frame is too large');
      const frame = this.pending.slice(0, separator.index);
      this.pending = this.pending.slice(separator.index + separator[0].length);
      const data = frame.split(/\r?\n/).filter(line => line.startsWith('data:'))
        .map(line => line.slice(5).replace(/^ /, '')).join('\n');
      if (data) this.consume(JSON.parse(data));
    }
    // DEFENSE: An SSE peer may keep sending data without a delimiter; cap the retained unfinished frame.
    if (this.pending.length > this.limit) throw new RangeError('Event frame is too large');
  }
}

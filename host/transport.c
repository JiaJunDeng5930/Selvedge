// Native-only effect for a dedicated kernel process. Blocking stdin is deliberate:
// this process has no other IO work; the host performs concurrent external effects.
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

static int selvedge_read_exact(unsigned char *data, size_t size) {
  size_t offset = 0;
  while (offset < size) {
    ssize_t got = read(STDIN_FILENO, data + offset, size - offset);
    if (got == 0) return offset == 0 ? 0 : -EPROTO;
    if (got < 0) {
      if (errno == EINTR) continue;
      return -errno;
    }
    offset += (size_t)got;
  }
  return 1;
}

static uint32_t selvedge_be32(const unsigned char *p) {
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
         ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static int selvedge_utf8(const unsigned char *p, size_t n) {
  size_t i = 0;
  while (i < n) {
    unsigned int c = p[i++];
    if (c < 0x80) continue;
    unsigned int value, count, minimum;
    if (c >= 0xc2 && c <= 0xdf) { value = c & 31; count = 1; minimum = 0x80; }
    else if (c >= 0xe0 && c <= 0xef) { value = c & 15; count = 2; minimum = 0x800; }
    else if (c >= 0xf0 && c <= 0xf4) { value = c & 7; count = 3; minimum = 0x10000; }
    else return 0;
    if (count > n - i) return 0;
    while (count--) {
      unsigned int next = p[i++];
      if ((next & 0xc0) != 0x80) return 0;
      value = (value << 6) | (next & 63);
    }
    if (value < minimum || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) return 0;
  }
  return 1;
}

Term host_receive_run(Env e, Term *f, IoWork *work) {
  (void)work;
  // Bend normally flushes when its event loop parks. This synchronous read
  // bypasses that point, so publish the preceding response before blocking.
  io_sync();
  unsigned char header[4];
  int status = selvedge_read_exact(header, sizeof(header));
  if (status == 0) return io_done(e, term_pak(CID_NONE, 0));
  if (status < 0) return io_fail(e, (uint32_t)-status, "incomplete frame header");
  uint32_t size = selvedge_be32(header);
  if (size == 0 || size > (uint32_t)f[0]) return io_fail(e, EMSGSIZE, "input frame exceeds the declared bound");
  unsigned char *data = malloc(size);
  if (!data) return io_fail(e, ENOMEM, NULL);
  status = selvedge_read_exact(data, size);
  if (status <= 0) { free(data); return io_fail(e, status < 0 ? (uint32_t)-status : EPROTO, "incomplete frame body"); }

  size_t count = 0, offset = 0;
  while (offset < size) {
    if (size - offset < 4) { free(data); return io_fail(e, EPROTO, "incomplete token length"); }
    uint32_t length = selvedge_be32(data + offset);
    offset += 4;
    if (length == 0 || length > size - offset || !selvedge_utf8(data + offset, length)) {
      free(data); return io_fail(e, EPROTO, "invalid UTF-8 token");
    }
    offset += length;
    count++;
  }
  size_t *positions = malloc(count * sizeof(size_t));
  if (!positions) { free(data); return io_fail(e, ENOMEM, NULL); }
  for (size_t i = 0, pos = 0; i < count; i++) {
    positions[i] = pos;
    pos += 4 + selvedge_be32(data + pos);
  }
  Term tokens = term_pak(CID_NIL, 0);
  while (count > 0) {
    size_t pos = positions[--count];
    uint32_t length = selvedge_be32(data + pos);
    tokens = io_node(e, CID_CON, io_str(e, (const char *)data + pos + 4, length), tokens);
  }
  free(positions);
  free(data);
  return io_done(e, io_box(e, CID_SOME, tokens));
}

static void __attribute__((constructor)) host_receive_use(void) {
  io_eff(CID_HOST_RECEIVE, host_receive_run, 0);
}

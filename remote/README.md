# Remote wire protocol

[protocol.mjs](protocol.mjs) owns the versioned JSON envelopes, frame bounds and
endpoint URL rules shared by the host connector and the Cloudflare relay. It has
no Node, Cloudflare or native-kernel dependency. Validators return the original
value or throw `RemoteProtocolError`; parsing and encoding apply the same UTF-8
bound. Remote business authorization and durable request receipts belong to the
native remote feature, not this transport module.

Production relay origins use HTTPS on TCP 443. Explicit test mode permits HTTP
on a loopback address. Credentials are carried in Authorization headers, except
for short-lived, single-use WebSocket tickets.

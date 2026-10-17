# Remote wire protocol

[protocol.mjs](protocol.mjs) owns the versioned JSON envelopes, frame bounds and
endpoint URL rules shared by the host connector and the Cloudflare relay. It has
no Node, Cloudflare or native-kernel dependency. Validators return the original
value or throw `RemoteProtocolError`; parsing and encoding apply the same UTF-8
bound. Remote business authorization and durable request receipts belong to the
native remote feature, not this transport module.

`connection_id` and RPC `id` correlate one live transport session. A command's
separate `request_id` passes unchanged to the service's native receipt boundary.
The connector owns socket lifetime and discards stale deliveries; it does not
retry commands or maintain another receipt store.

Production relay origins use HTTPS on TCP 443. Explicit test mode permits HTTP
on a loopback address. Credentials are carried in Authorization headers, except
for short-lived, single-use WebSocket tickets.

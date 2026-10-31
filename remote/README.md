# Remote wire protocol

[RemoteProtocol.v](../theories/Host/RemoteProtocol.v) owns the versioned JSON
envelope schema shared by the host connector and the Cloudflare relay.
[protocol.mjs](protocol.mjs) interprets UTF-8 transport bounds and endpoint URL
rules and invokes the generated schema. Run `bun run build` before bundling the
relay so both peers include the same generated host model. Validators return values constructed by the shared declaration or throw
`RemoteProtocolError`; parsing and encoding apply the same UTF-8 bound. The
constructor canonicalizes envelope integers while opaque commands, results and
events retain their number tokens. Remote business authorization and durable request receipts belong to the
native remote feature, not this transport module.

`connection_id` and RPC `id` correlate one live transport session. A command's
separate `request_id` passes unchanged to the service's native receipt boundary.
The extracted [RemoteControl.v](../theories/Host/RemoteControl.v) transitions
own generation, grant, pairing, queue and ticket decisions. The connector
interprets socket lifetime and discards stale deliveries; it does not
retry commands or maintain another receipt store.

Production relay origins use HTTPS on TCP 443. Explicit test mode permits HTTP
on a loopback address. Credentials are carried in Authorization headers, except
for short-lived, single-use WebSocket tickets.

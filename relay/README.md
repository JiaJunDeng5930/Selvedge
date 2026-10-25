# Cloudflare remote relay

This independent Workers package relays one Selvedge environment through a
Durable Object selected by its installation UUID. Both the host and a future
controller connect outbound over WSS on TCP 443. There is no phone UI here.
The shared wire definitions are in [../remote](../remote/README.md).

The relay stores a SHA-256 host credential digest and its current forwarding
grants. The native host journal remains the authority for grants and commands.
Pairing codes, pending requests and connection tickets are transient and bounded;
the relay never queues commands for an offline host. Hibernating sockets retain
their roles, host generation, connection IDs and grant epochs in attachments.
At most eight unspent tickets share a host's 2 KiB attachment; further issuance
returns HTTP 429 until a ticket is consumed or expires.

Install and check from the repository root, without a Cloudflare account:

```bash
bun install --frozen-lockfile
bun run check
bun run test
```

The default suite includes one focused [Durable Object hibernation regression](../tests/relay.test.mjs).
Its [runtime fixture](test/runtime.mjs) runs the production Worker and deployment
bindings in local workerd through Miniflare, including real WebSocket upgrades,
socket attachments and stored grants. It checks forwarding and an unspent ticket
after eviction. Bun workspace installation supplies the pinned runtime tools;
Node.js 22 or later is also required. Loopback HTTP is only used by this fixture.

Deploy with an authenticated Cloudflare account:

```bash
bun install --frozen-lockfile
bun run build
cd relay
bun x --no-install wrangler secret put RELAY_ENROLLMENT_TOKEN
bun run deploy
```

Use a random enrollment secret, for example `openssl rand -base64 32`. Retain
it only while registering hosts. The host credential is separate; an enrollment
credential cannot replace an existing host identity. `wrangler.jsonc` supplies a
Workers-provided address, so neither a VPS nor a purchased domain is required.
The deployed Worker accepts HTTPS/WSS; TLS terminates at Cloudflare, so Cloudflare
is part of the trust boundary and can see relayed payloads. Account plan quotas,
availability, billing and a live deployment must be verified in the target
Cloudflare account; local checks do not establish those properties.

The enrollment secret is never a Worker variable or a committed file. No task
payloads or bearer credentials are logged. A lost host credential requires a new
installation identity; this package does not provide unauthenticated recovery.

# local-client

<!-- selvedge-package-readme
package: selvedge-local-client
freshness_commit: f86607e521e640e17d56a038e67d8dffa64fbdda
-->

This crate owns the process-local client handle for talking to an existing Selvedge localhost server.

Use it to validate localhost endpoint configuration, connect through a caller-provided `LocalTransport`, run ready probes, submit local protocol commands, open one attach stream, and close the underlying transport.

`LocalEndpoint` is structured as loopback TCP by construction: `TcpIpv4 { port }` means `127.0.0.1:<port>`, and `TcpIpv6 { port }` means `[::1]:<port>`. Port `0` is invalid.

An active attach stream has one client-owned frame reader. `close()` and request failures close the active stream, drop the inner transport stream, and wake a pending reader so its next poll completes.

This crate does not start the server, call systemd, select an IPC transport, inspect command payload schemas, cache snapshots, or access router/events/client-sync mailboxes directly.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([LocalClient operation])
  ValidateEndpoint[Validate loopback endpoint]
  Connect[Connect transport]
  ReadyProbe[Send ready probe]
  Submit[Submit command envelope]
  Attach[Open attach stream]
  ActiveAttach[Active frame reader]
  Close[Close transport and active stream]
  Success[Return operation result]
  ConfigError[Return endpoint validation error]
  TransportError[Return transport error]
  ProtocolError[Return protocol error]

  Start -->|client is constructed| ValidateEndpoint
  ValidateEndpoint -->|endpoint is 127.0.0.1 or ::1 with nonzero port| Connect
  ValidateEndpoint -->|port is zero or endpoint shape is invalid| ConfigError
  Connect -->|transport connect succeeds| Success
  Connect -->|transport connect fails| TransportError
  Start -->|ready is called| ReadyProbe
  ReadyProbe -->|transport returns valid ready response| Success
  ReadyProbe -->|transport fails or response is malformed| TransportError
  Start -->|submit is called| Submit
  Submit -->|transport returns accepted command response| Success
  Submit -->|server rejects command with protocol reason| ProtocolError
  Submit -->|transport fails or response is malformed| TransportError
  Start -->|attach is called and no active attach exists| Attach
  Attach -->|server accepts attach request| ActiveAttach
  Attach -->|server rejects attach request| ProtocolError
  Attach -->|transport fails or attach response is malformed| TransportError
  ActiveAttach -->|caller polls next frame and transport yields frame| ActiveAttach
  ActiveAttach -->|reader reaches EOF, request failure occurs, or close is called| Close
  Close -->|transport close completes| Success
```

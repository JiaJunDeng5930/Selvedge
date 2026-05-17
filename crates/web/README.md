# web

<!-- selvedge-package-readme
package: selvedge-web
freshness_commit: f2a0e6aa7f63b0fb8b575fefc5026e0535a7e64f
-->

This crate defines the localhost HTTP ingress boundary used by `selvedge-server`.

Use it to pass HTTP bind settings, bridge requests, bridge futures, attach frame streams, runtime state, start errors, bridge errors, and the web control handle across package boundaries.

`spawn_web_surface` binds the configured loopback address and keeps that listener owned by the web task. `WebControl` exposes the request handling core used by local HTTP routes: `ready` forwards readiness probes, `submit_command` validates and forwards command requests, and `attach` validates and wraps bridge frame streams.

`WebBridge` is implemented by `selvedge-server`. The web package forwards through that bridge and never touches router, events, database, or systemd state.

Stopping the web control moves the runtime to closing, stops accepting new control operations, closes wrapped attach streams, releases the listener, and resolves the join handle with `WebExitStatus::Stopped`.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([spawn_web_surface])
  Bind[Bind configured loopback listener]
  Serving[Accept HTTP requests]
  Ready[Forward ready probe to bridge]
  Submit[Validate and forward command]
  Attach[Validate and forward attach]
  Stream[Wrap attach frame stream]
  Closing[Stop accepting operations]
  Stopped[Resolve WebExitStatus Stopped]
  StartError[Return bind or runtime start error]
  BridgeError[Return bridge error response]
  RequestError[Return malformed request or protocol rejection]

  Start -->|caller provides bind settings and bridge| Bind
  Bind -->|listener binds to configured loopback address| Serving
  Bind -->|bind fails or address is invalid| StartError
  Serving -->|ready route is requested| Ready
  Serving -->|command route is requested| Submit
  Serving -->|attach route is requested| Attach
  Serving -->|stop is requested| Closing
  Ready -->|bridge ready succeeds| Serving
  Ready -->|bridge ready fails| BridgeError
  Submit -->|request JSON and protocol fields validate| Serving
  Submit -->|request JSON is malformed or protocol fields fail validation| RequestError
  Submit -->|bridge command submit fails| BridgeError
  Attach -->|request JSON and subscriptions validate| Stream
  Attach -->|request JSON is malformed or attach is rejected| RequestError
  Attach -->|bridge attach fails| BridgeError
  Stream -->|bridge frame stream yields frames| Stream
  Stream -->|frame stream ends or control stops| Serving
  Closing -->|active streams close and listener is released| Stopped
```

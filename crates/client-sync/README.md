# client-sync

This crate defines the client hydration synchronization boundary used by the server and router attach path.

Use it to pass hydration starts, cancellation, shutdown signals, snapshot builder requests, snapshot builder results, client-sync errors, and the client-sync task handle across package boundaries.

This crate currently provides the stable public interface and lifecycle handle needed by `selvedge-server`. Hydration ordering, current-request replacement, failure notice delivery, and late-result handling are implemented when the full client-sync package is advanced in the package sequence.

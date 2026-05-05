# web

This crate defines the browser-facing web surface boundary used by `selvedge-server`.

Use it to pass web bind settings, bridge requests, bridge futures, attach frame streams, runtime state, start errors, bridge errors, and the web control handle across package boundaries.

This crate currently provides the stable public interface and lifecycle handle needed by `selvedge-server`. HTTP route handling, page serving, attach stream forwarding, browser session shutdown, and localhost listener ownership are implemented when the full web package is advanced in the package sequence.

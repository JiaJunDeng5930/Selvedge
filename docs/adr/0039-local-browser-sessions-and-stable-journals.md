# ADR 0039: local browser sessions and stable journals

## Context

Opening the local interface required an instance token in the URL or a credential
entered in the browser. A fresh tab or restarted service could therefore present
a connection barrier even though the user had opened the intended loopback
server. Browser JavaScript also retained and forwarded a secret that the browser
could manage directly.

Journal compatibility was tied to source and compiler fingerprints. Those values
identify a build, but ordinary UI, source or compiler updates need not change the
meaning of previously committed decisions. Treating every build change as a data
incompatibility forced users to abandon recoverable history or create another
service home.

## Decision

Opening the local server URL establishes an automatic HttpOnly browser session.
This lets the browser attach the local credential without exposing it to product
JavaScript or asking the user to transfer it. Existing local request admission
remains necessary: an automatically established session does not grant arbitrary
origins or hosts access. CLI discovery retains its Bearer credential, and plugin
connections retain independent credentials because their clients and grants have
different lifetimes and purposes from a browser session.

Journal compatibility follows the persisted protocol rather than build
provenance. Format 3 no longer records a source fingerprint or compiler version
as a compatibility requirement. Build identities remain useful for compilation
and diagnostic evidence, without deciding whether stored work can be restored.

The supported format 2 conversion validates the old journal using its own stored
provenance and checks every committed decision against the current kernel before
changing the database. Comparing complete decisions preserves replies, ordered
effects and durability as well as reconstructed state. Integrity alone would
not detect a validly stored history whose meaning has changed; agreement on state
alone could overlook changes to promised results or external actions.

Conversion is atomic and retains the original input and decision bytes. A failed
validation must leave the original journal available for investigation, while a
successful conversion must not leave a partially rewritten history. Replaying
for validation never publishes historical effects. Unknown formats and actual
decision incompatibilities remain errors instead of being hidden by conversion.

## Limits

This decision permits the specific format 2 conversion; it does not establish a
general migration framework or accept unknown historical schemas. Ordinary build
changes can preserve compatibility, but changes to committed semantics still
require replay agreement. HTTP, cookie handling, SQLite transactions and compiler
execution remain external boundaries covered by integration checks, not by the
pure Bend proofs alone.

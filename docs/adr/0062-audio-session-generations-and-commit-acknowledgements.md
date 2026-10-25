# ADR 0062: Audio session generations and commit acknowledgements

Status: Accepted

Voice observations can arrive after a browser has disconnected, while a socket is
closing, or while the journal is committing a transcript. Treating socket presence
as ownership conflates these independent lifetimes. Keeping transcript tails and
pending delegations in JavaScript also lets shutdown bypass the domain rules.

We use the extracted audio stream and session transitions for these decisions.
The stream records turns, unresolved delegation references and partial transcripts;
closing consumes its tails once. The service session records browser ownership,
a generation, pending journal receipts and committed delegation identities. Each
transition installs its resulting state before its primitive effects run. A physical
callback carries the generation observed when its connection was created.

A completed journal operation is an explicit observation. Transcript publication
and accepted-work context require its successful acknowledgement. A failed journal
operation retires the voice session without retrying or claiming acceptance; its
commit outcome belongs to journal recovery. Stopping a voice call still permits
its final partial transcript to commit before the physical stream reports closure.

The activation controller owns the observed 404 retry window and socket-attempt
identity. A rejected upgrade cannot make its subsequent close callback terminate
a replacement attempt. Retry timers and new sockets are primitive effects.

Sockets, promises, timers, HTTP and journal execution remain host effects. Domain
proofs constrain the extracted transitions; they do not establish provider behavior
or physical IO delivery guarantees.

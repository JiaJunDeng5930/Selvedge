# 0069: Construct correlated feature requests

Status: accepted.

Title, card, context-maintenance and connection requests used to allocate an
identity, install their receiver and emit their external effect independently.
A matching effect coordinate alone did not establish that its receiver existed;
in particular, replacing a card beyond its positional registry left no receiver.

Extend `TicketedRequest.Scoped` with a finite family of feature requests and
maintenance requests. The interpreter consumes each frozen domain input once,
allocates from the declared identity space, installs its pending receiver and
emits the corresponding effect together. Task tickets and connection operation
identities retain their separate counters through the shared allocator. Owners
retain their business admission and reply projection; transport fitting remains
before request issuance so a rejected oversized request consumes no identity.

The interpreter refuses card keys beyond the append position and connection
requests whose job is already settled. These cases cannot emit an external
request. Receiver correspondence is proved against actual domain registry
lookups, and production entry theorems connect the owner functions to this
interpreter. The frame theorem keeps task execution, projects, environment and
sequence unchanged while feature requests are installed.

This avoids accepting an arbitrary state-transforming callback or separately
supplied pending state and effect. It also leaves reply budgets and physical IO
at their existing external assurance boundaries.

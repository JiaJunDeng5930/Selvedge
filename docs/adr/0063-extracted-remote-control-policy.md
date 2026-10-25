# 0063: Extracted remote transport policy

Date: 2026-10-25
Status: Accepted

## Context

The kernel accepted controller identities that the relay rejected, and a
lossless JSON parser exposed different numeric representations to handwritten
wire checks. Independently maintained transport rules could therefore turn a
successful local grant into an endlessly rejected host connection. Socket
replacement and asynchronous hashing also allow observations to arrive after
the connection or authorization that produced them has changed.

## Decision

The host and relay use the same extracted Gallina frame predicates and remote
control transitions. Controller identities, command receipt request identities,
and grant epochs have distinct domain types. Only declared envelope integer
fields are materialized as exact bounded JavaScript integers; opaque command,
result and event JSON keeps its numeric tokens.

Socket handles, cryptographic hashing, wall-clock observations, atomic
WebSocket attachment updates, and durable storage remain host primitives.
Transitions install their new state before the corresponding send or socket
acceptance. Ticket consumption is published before authorization. After a
hashing await, the relay reads the current attachment again rather than
publishing a snapshot captured before the await. This follows Cloudflare's
[Durable Object concurrency guidance](https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/):
storage input gates do not serialize arbitrary external awaits.

The relay bundles the generated host model from the repository build. It does
not keep a copied wire validator or another durable command receipt database.
The native journal remains the command idempotency authority. Relay attachment
state supports the current format only; an earlier in-flight ticket is not
converted into authority under a new runtime.

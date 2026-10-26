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

Connection recovery also belongs to the model. Separate constructors for a
probe, negotiation, online transport, scheduled retry and rejected identity
prevent a ready flag from coexisting with an unfinished probe. HTTP status,
clock readings and random samples are observations; they do not choose whether
to reconnect. The checked action interpreter installs the next state before
executing a primitive, including socket retirement. Authorization uses four
successive checking states because a counter in a JavaScript loop left both
the retry budget and the sequence comparison outside the extracted contract.
A capture action requires the checked sequence to equal the current committed
sequence in that same observation.

Session ledgers use closed states as well: a connector cannot hold connections
before negotiation, and a relay cannot hold tickets before its first grant
snapshot. Pending jobs determine connector queue counts and bytes, so an
independent counter cannot drift after revocation or a delayed completion.
Owner pairing has one optional pending request rather than a list whose
cardinality is maintained by convention. The wire records encode these states;
they do not supply an additional state machine beside the typed step.

Enrollment credentials have their own shared accepted language. Reusing a
host-token header limit made credentials accepted by local provisioning fail
at the relay. HTTP adapters therefore pass the original header, route, and
decoded body to the model rather than interpreting credential length or
format themselves. Similarly, bounded wire integers use mathematical value,
while domain naturals retain their separate canonical-token contract. These
choices prevent host representation details from silently narrowing the
domain accepted by another boundary.

The connector session also owns subscription and notice cutoffs. Its notice
sequence survives transport replacement; each connection carries either no
subscription or the last captured sequence. A subscription captures the current
sequence in the same synchronous action that exposes its snapshot. Queued
notices retain their sequence, and delivery requires both a still-present queue
entry and a sequence beyond the connection's current cutoff. Unsubscribe,
re-subscribe, revocation and delayed queue completion therefore share one
transition authority. The physical connector retains socket handles and Promise
ordering; `interpretConnectorCapture` and `interpretConnectorDelivery` interpret
the generated action union without choosing cursor policy in JavaScript.

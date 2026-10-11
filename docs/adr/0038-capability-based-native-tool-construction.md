# Capability-based native tool construction

Status: accepted

Native harness tools were identified by a closed list of tool names. Adding a
second tool over an existing task operation consequently required another
interpreter case, although its command semantics were already proved.

Use a capability grammar whose arguments describe constants, caller identity
and named input bindings. The same declaration determines the schema and frozen
source program. This keeps ordinary tool definitions separate from additions to
the semantic vocabulary. Reject malformed declarations before producing a
certified descriptor; a correspondence proof alone does not establish that an
input schema can be used.

Represent schema bounds with the existing fixed-width U32 operations. Rendering
and checking the full task-identity range through Peano naturals makes concrete
catalog admission expensive to normalize; the representation must keep the same
numeric limits without forcing billions of successor constructors.

Categories remain predicates, with inclusion proved by implication and
intersection referring to the same entity. Their organization need not follow
the syntax tree. Reuse complete operation laws and existing admission premises;
do not create another wrapper merely to rename an already proved family or split
every Boolean clause. Current ownership and authorization remain contextual
properties, and external process execution retains its host boundary.

Checker-only tests are removed because accepting or rejecting a Bend source,
proof or certificate repeats the production checker's verdict rather than
observing an independent domain behavior. Production constructions and their
proofs retain the universal requirements and mandatory check gate. Actual
runtime values, JavaScript translator source-data boundaries, native round trips
with frozen clients and external integration remain test responsibilities.

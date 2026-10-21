# 0063: Preserve source-specific tool argument contracts

Date: 2026-10-21
Status: Accepted

## Context

A public command, a native model tool, an extension and an MCP server do not
promise the same argument language. Public commands use nullable defaults and
can carry rich content. Direct task tools have narrower model-facing signatures:
for example, a fork advertises the configured child limit, and an optional Bash
mode can be absent but cannot be null. Flattening these distinctions into a
shared JSON field list lost useful schemas and deferred malformed model calls
until after authorization hooks.

Extensions deliberately support a finite decidable schema fragment. MCP servers
advertise their own JSON Schema dialect and validate their own arguments. Using
the extension fragment for both sources rejected valid MCP number and reference
schemas before the server could participate.

## Decision

Represent tool sources as a sum whose native case carries its argument signature
and whose external cases carry their original schema. Derive the public tool
schema and source metadata from that value; do not store an independent native
schema or accept a native source through the external-tool DTO decoder.

Use the existing field declarations as the starting point for native signatures,
with controlled views for genuine differences in invocation contracts. Model
presence and nullability separately. The same signature produces the advertised
schema and performs argument admission. Reuse the existing schema interpreter
for nested structural descriptions, and domain-owned field declarations for
settings, images and graph data. Ordinary interpretation is sufficient here;
a second schema implementation or generator would increase maintenance cost.

Initial model-item admission checks the frozen contract before recording a call
or requesting a hook. Rewritten arguments are checked again against that same
contract and current capability before dispatch. MCP admission checks the object
argument envelope; the MCP server owns validation against its full schema.

## Consequences and limits

A legal field shape does not establish task availability, permission bounds,
image membership or successful external execution. Those remain actual domain
and IO admission rules. Kernel-checked structural and dispatch properties are
stated separately from extraction, host execution and server assumptions.

Correcting these decisions changes replay behavior, so reconstruction uses the
single unreleased journal format 3. Earlier decision streams are not silently
reinterpreted through a compatibility bridge.

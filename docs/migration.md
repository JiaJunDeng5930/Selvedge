# Migration behavior changes

The reference product is commit `acfbe86`, including cloud task environments added
after the original `242dba9` migration snapshot. Task execution, image inputs,
history search, persistent Work interfaces, remote control and browser
interactions remain migration responsibilities. A checked module does not
establish that its complete public workflow has passed acceptance.

The replacement has one journal format, `selvedge-rocq-journal-2`. It rejects
older formats. Keep an existing home separate when starting the replacement;
there is no old-journal conversion or mixed-runtime mode.

These deliberate changes correct ambiguities or defects at the old boundaries:

- Managed-resource identity is retained in frozen task settings. Independent child
  tasks can inherit a cloud environment without a fork lineage. Execution uses
  that identity rather than choosing a cloud resource from a matching path.
- The current journal rejects earlier Rocq journal formats. Journal rows replay
  inputs and compare decisions; the backend and resource-binding fields change
  those decisions, so an older journal cannot preserve the new replay contract.

- Raw HTTP command admission and provider function arguments use the extracted
  domain parser and reject duplicate object members. Stdio JSON-RPC retains its
  existing parsed-object protocol boundary; this is not a claim that every
  transport rejects duplicate members before parsing.
- Retry calculations compare exact decimal delays with their limits before
  rounding admitted waits upward to integral milliseconds. Fractional
  nonnegative `Retry-After` delays remain supported without retrying early. HTTP dates accept the IMF-fixdate,
  RFC 850 and asctime forms required by RFC 9110; unrelated extensions accepted
  by JavaScript `Date.parse` are excluded.
- Portable compaction replaces an existing `max_output_tokens` member with its
  planned reserve. It does not append a duplicate member whose interpretation
  depends on a downstream parser.
- Backend credential environment-variable references must be strings. Boolean
  values are rejected rather than coerced into environment-variable names.
- Derived profile keys reserve `/~auto` for adaptive profiles and
  `/~reviewer/<16hex>` for reviewers of manually configured profiles. Accepted
  provider model slugs cannot contain `~`, so a legitimate model ending in
  `-auto` can coexist with another model's adaptive variant.
- ChatGPT retries compare admitted argument fields independently of JSON object
  member order. Reordering the same fields does not create a different request.
- Late, unknown or completed ChatGPT job results remain rejected and now leave
  the journal sequence and unrelated task scheduling unchanged.
- Selecting a Project inherits its managed-worktree default. Choosing an
  environment for a single new Task does not modify the Project's shared default;
  edit that default explicitly in Project settings.
- Browser layout uses native CSS geometry, including fractional dimensions,
  instead of the old saturated integer pixel allocator. Narrow navigation keeps
  commands reachable through scrolling. Charts reject mixed numeric/categorical
  axes instead of silently combining their coordinate interpretations.
- Account identity components reject NUL, which otherwise makes distinct tuples
  share the same NUL-delimited digest input. Existing ordinary identities retain
  their digest and namespace. A present malformed credential record is an error,
  rather than permission to replace it as though it were missing. Invalid UTF-8
  in a disposable model cache follows the existing malformed-cache behavior.

The migration preserves complete native tool replies, result hooks and raw
execution receipts through rewrites and denials. Final dispatch uses the current
side-conversation parent view and honors revocations from the complete committed
decision. Self-archive retains execution evidence and interrupts result processing,
because an archived Task cannot acquire new callback rights.

JSON numeric lexemes and domain integers remain exact across the JavaScript
boundary. Text is UTF-8; native string length means byte length where Gallina
strings are used. This representation change does not permit truncating numbers
to JavaScript's safe-integer range or changing Unicode text.

See [ADR 0054](adr/0054-rocq-semantic-source-and-extracted-runtime.md) for the
reasons behind the semantic source and compilation boundaries, and
[the proof boundary](proofs.md) for what the checked results establish.

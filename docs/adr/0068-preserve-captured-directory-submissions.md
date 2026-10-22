# 0068: Preserve captured directory submissions

Date: 2026-10-22
Status: Accepted

## Context

Directory observation happens asynchronously before a command can be assessed by
its worker. A draft edit or navigation during that observation does not retract
the submission the user already requested. Treating a directory preview as a busy
submission also prevents the user from requesting this next preparation step.

A current draft's worker assessment cannot authorize a captured older revision:
the new editor can replace that assessment, while the older command still needs
its own real verdict against the current authoritative world.

## Decision

Reuse the preparation resource to retain the captured draft until its directory
observation and worker admission complete. A preview can become a submission
without replacing its matching observation ticket. Give captured worker requests
an owner derived from that ticket and the command identity, independently of the
current editor's assessments. Consume the captured request when it is refused or
issued; command completion uses the existing submission settlement.

Retain the original navigation and layer generations and the requested Project
preference update with the captured submission. Only completion of the current
draft revision may clear that draft or perform its foreground navigation. New
workspace previews and navigation do not cancel already captured submissions.

Canonicalize selected workspace paths in browser preparation, but leave root
guidance to the service's existing filesystem observation boundary. Browser
observations must not become service-authoritative command input; assessment and
execution both observe that guidance before reaching the worker.

Keep actual execution behind the worker's command boundary. Completing a Project
preference update continues its captured command rather than consulting the
current editor's workspace observation a second time.

## Assurance

The checked propositions constrain the production callback, captured command
continuation and version settlement. Browser acceptance additionally exercises
real delayed directory observation, service assessment, command execution and
navigation. The proofs do not establish successful physical IO.

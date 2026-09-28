# 0021: Independent evaluator connections and native reasoning checkpoints

The reference is Astra-Ares at
`b2011446d88202329dcdc5163500ca818aba9dbb`:
<https://github.com/miuuyy/Astra-Ares>. Its bounded evaluator context and
generation-counted effort leases are integrated into Selvedge's existing native
transition, not its patched Codex CLI or socket bridge. The upstream transport
mechanism is documented at
<https://developers.openai.com/api/docs/guides/reasoning>.

Evaluator connection data, frozen endpoint policy and account-discovery presets
are separate. A preset cannot enable Jev on ordinary profiles discovered through
the same account connection. Discovery materializes ordinary profile data and
respects an explicit auto-profile override. Secrets remain host environment
values, never native policy or journal fields.

The lease is derived from the task's existing ordered history. This avoids a
second mutable cache that must be synchronized with input, tool settlement,
forks, compaction and replay. Existing list/sequence operations and the project's
checked command, protocol, scheduler and trace refinement remain authoritative;
the change introduces no new general algebra or foreign theorem bridge.
The local proof cost is the domain-specific routing, authorization, settlement
and projection correspondence. The former unconditional model-dispatch equation
is replaced by independent reasoning-start refinement, including the fixed path.

Jev completion is an input carrying a ticket and observed history revision.
The host interprets a committed evaluator effect. The native protocol determines
whether the answer is still applicable; cancellation, stale observations and
permission to launch a generation are not decided in JavaScript.

`configuration_update` freezes the request baseline and appends effort changes.
`request_effort` supports endpoints without that item without pretending to retain
the same cache prefix. A compacted prefix and a new user/tool-error observation
must be evaluated in their new context. Approval judgments remain ordinary,
independent model requests.

Pure proofs do not establish evaluator quality, token estimates, real model
availability, cache savings or HTTP behavior. Component tests cover the three
Jev wire formats, bounded Unicode previews, timeout/cancellation and provider
identity. Native/host tests cover actual request encoding, account discovery,
SQLite-before-dispatch ordering and restart. Type-correct semantic mutations
exercise the production proof root, including archived and stale callbacks.

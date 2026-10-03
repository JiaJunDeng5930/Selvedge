# 0023: Component-local state, vocabulary and proofs

## Context

Adding the board in PR 45 changed unrelated task, reasoning and proof files
because they destructured the complete `World` record. The public command,
completion and effect types also exposed each feature constructor to global
consumers. Correct complete-decision proofs did not prevent this source coupling.

The supported change is adding an independent capability or replacing a component
implementation while keeping its public contract. A contract includes behavior,
observations, resource assumptions and permitted effects. Changes to shared task
semantics, resource ownership or scheduling can require corresponding interaction
changes; existing imports do not by themselves make those changes necessary.

## Decision

Task-domain values and shared task/project resources live in `bendlib/domain.bend`.
The closed core import boundary in `components.json` excludes application and
feature assembly. Core stateful operations quantify over an unknown remainder
type; their effect type also has an unknown feature-payload parameter.
`bendlib/component.bend` supplies product state and complete decisions containing
state, reply and ordered effects. `MODEL.bend` chooses concrete state and effect
instances. `FEATURES.bend` owns feature state and effect composition.

The global vocabulary has stable feature categories. `feature-resolution`,
`feature-protocol`, `feature-codec` and `feature-state` own the corresponding
contributions. Feature-specific resolved operations are interpreted
by `feature-execution`, specified by `feature-spec`, and connected by
`feature-laws`. Task creation is an explicit interaction premise: the assembler
supplies the independent specification, implementation and their complete-decision
proof. It never uses a production callback as its own expected behavior.

The current semantic interface is in [../../UI.bend](../../UI.bend) and
[../../core/interface.bend](../../core/interface.bend); feature command encoding
is in [../../bendlib/feature-codec.bend](../../bendlib/feature-codec.bend).
A cursor that survives only in memory but resets on the next input cannot
support an extensible UI.

Local task and reasoning proofs quantify over arbitrary surrounding types.
The application reuses these values in its existing input-wide proof.
`CONCEPTS.Harness.locality` additionally requires actual update and preservation
evidence for task storage, reasoning dispatch and board storage.
Write laws constrain the requested value as well as the untouched remainder.
Board-specific laws leave future components free to update their own state.

`feature-state` assembles validity, evolution, recovery, pending resource tickets,
reference checks and effect authority. Their existing board/task meaning remains
in force. Extending the resource protocol still requires the new component's
actual obligations; placing values in separate records does not establish
effect commutation, fairness or external exactly-once behavior.

## Source enforcement and evidence

`scripts/check-components.mjs` reads current sources, including unstaged files.
It checks core imports, declared dependencies of stable application modules,
private feature patterns in both cases and destructuring bindings, production
proof coverage and declared foreign boundaries. Imports use explicit aliases;
unknown import syntax and missing sources fail closed. The board view's existing
nested command pattern is an explicitly owned exception, not a blanket exception
for every board module. Normal checks and builds execute the gate before cache
reuse; a regression supplies a matching cache fingerprint and requires rejection.
The checker does not infer higher-order semantic dependencies or replace semantic
review of these declared boundaries.

`tests-bend/locality.test.mjs` freezes old source bytes in isolated copies. It
extends both state and cursor representations, then adds a separate component
through eleven feature assembly modules. The latter has five new component files
covering state/contract, execution, assembly, local proof and rendering, plus
commands, a query, completion, effect intent and a UI event. It checks the original
root proof, builds the unchanged `MAIN.bend`, and uses the ordinary host `Kernel`
transport. New cursor state survives serialization, refresh and board navigation;
the new view renders alongside the existing application. The old task/board
implementation, global model/dispatcher/UI/codecs and their proofs remain
byte-identical. Those eleven assembly edits count as maintenance, not free work.

A separate replacement changes task storage by an extensionally equal list
reconstruction that requires the imported `app_nil_r` theorem. Only the component
implementation and its proof provider change; the contract and every client stay
frozen. This exposed and removed a protocol proof that had expanded the concrete
task list update instead of using the storage operation. An alias-only replacement
would not detect that dependency.

Two negative checks distinguish the guarantees. A behavior-preserving dependency
on the global model passes semantic proof but fails the structural gate. A
type-correct missing write or damaged remainder fails the production proof.
Existing semantic mutation suites retain their fault models and follow the
relocated definitions. Native probes cover compiler and encoding/assembly risks;
host and end-to-end suites continue to cover physical effects and persistence.

## Consequences

The initial migration changes many source references once. Future independent
features extend their own modules and the relevant feature assembly; old core
implementations and their parameterized proofs remain unchanged. Assembly changes,
new adapters and generators count as maintenance rather than being hidden from
the change budget.

This structure guarantees neither constant whole-build time nor constant human
reading time. Structural configuration and semantic contracts remain reviewable
assumptions. A new external effect still needs its host interpreter and external
boundary evidence. The counter extension fixture validates an emitted intention
and its encoding, not a hypothetical external service.

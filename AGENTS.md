# AGENTS.md

This file is for coding agents working in this repository.

## Start Here

- Read [README.md](./README.md) first for the repository-level workflow.
- Before you call or modify a module, read that module's `README.md` first.
- If the relevant `README.md` already answers your question, do not open the module internals first.

## Executable Requirements

- Start at CONCEPTS.Harness, COMMANDS, and MODEL. Task values and policy primitives belong to bendlib/domain; FEATURES assembles independent feature state and vocabulary. Read INVARIANTS and LAWS before changing behavior; PROGRAM realizes the resolved operations and executes the bounded transition.
- Public command preconditions belong in COMMANDS.resolve; completion correlation and accepted-call resolution belong in bendlib/protocol. A change must retain complete-decision, invocation and input-wide committed refinement, not merely state safety. Keep rejection distinct from an already accepted tool's error result.
- Choose meaningful existing theory representations before introducing domain abstractions. Use the quoted list, iterator, relation and association-map definitions/theorems directly; keep only domain correspondence and necessary premises local. Do not rebuild a parallel general algebra hierarchy, hand-reprove imported results, or edit generated certificates. Account for bridge cost separately from removed application proof maintenance.
- Requirements belong in executable definitions and propositions. Do not maintain duplicate lifecycle tables or state-machine diagrams in documentation.
- PROOF must discharge the production laws. Never replace a proof with an axiom, a hole, or unchecked recursion, or weaken a requirement solely to pass a check.
- The host interprets committed effects. Keep task policy in Bend and verify host ordering through integration tests.
- Internal semantics belong to proofs; compiler and external component boundaries belong to focused tests; cross-boundary behavior belongs to end-to-end tests. Remove finite semantic replay tests only after checking their actual proof coverage. Keep independent proof/certificate mutation tests. The evidence map is tests-bend/README.md.
- Record architecture reasons in an ADR and exploration-specific findings in `docs/bend2-exploration.md`.
- Keep the core import closure declared in `components.json` independent of the assembled MODEL and concrete features. Add feature cases in their owning `feature-*`/component modules; global consumers process stable outer categories. Boundary configuration changes require the same review as contract changes.
- Bind component refinement, intended writes and unrelated-state preservation to actual production functions. Scope preservation to the owning component's operations. Run `bun run test:locality` after changing component interfaces or assembly; freeze unrelated implementation and proof files in extension fixtures rather than copying and repairing them.
- Keep shared surface types independent of feature views. Feature cursor encoding, validation and decoding belong to the same assembly boundary as navigation. Exercise real native round trips in extension fixtures, and contract-preserving replacements that require propositional equality with all clients frozen.

## Git Hooks

- `pre-commit` runs `bun scripts/check.mjs` to check actual component boundaries, the pinned compiler, reproducible imported certificates, Bend proof obligations, the native entry point and host/script syntax. `scripts/build.mjs` checks the same source boundaries before using a cached binary.
- `pre-commit` runs `bun scripts/agents-index.mjs check` to check the tracked-file index.
- `pre-push` runs `bun run test` for native kernel and host integration tests.
- `just hooks` runs both configured stages. CI runs the same proof, syntax, integration, and index checks on macOS and Linux.

## Persistent Data Formats

- Persisted data has one current format. Do not add migrations, fallback parsers, dual reads or writes, version bridges, or compatibility shims for obsolete formats unless the user explicitly requests compatibility.
- When a persisted format changes, remove the superseded schema, fixtures, adapters, and tests. Existing data in any other format must fail current-format validation instead of being converted.

## Branch Protection

- `main` is a protected branch.
- Do not commit work directly on `main`.
- Do not use `main` as the active branch for task work unless the user explicitly asks for a change on `main`.

## Branch Workflow

- Create or switch branches in the repository root.
- Keep each branch focused on one task so review and cleanup remain straightforward.

## Working Notes

- Unless the user explicitly asks otherwise, place temporary task documents (such as specs, plans, and research notes) under `.workpad/`.
- `.workpad/` is git-ignored on purpose and should be used for task artifacts that should not be committed.

## Code Marker Comments

- Allowed tags: `TODO`, `FIXME`, `HACK`, `NOTE`, `XXX`.
- Format: `<comment marker> <TAG>(<optional issue>): <specific action or reason>`.
- Marker comments must explain the intent, decision, risk, or follow-up behind the code. Do not use marker comments to restate facts already visible from the code.
- `TODO` means known follow-up work while current code is acceptable.
- `FIXME` means a known defect that needs repair.
- `HACK` means a temporary workaround that should be replaced by normal design.
- `NOTE` means important context that affects code understanding.
- `XXX` means high-risk code that needs reviewer attention.

## Project Index Workflow

- Stage added, renamed, and deleted paths before updating the index.
- Update with `bun run index` or `just agents-index`, then stage AGENTS.md.
- Check with `bun run index:check` or `just agents-index-check`.
- The generator uses Git-tracked staged paths only. Ignored and untracked files are excluded.

## Project Index

<!-- BEGIN AGENTS_MD_PROJECT_INDEX -->
```text
[Project Index]|root:.
|source:git-tracked-files-only
|excluded:{git-ignored,git-untracked}
|.:{.codex/,.editorconfig,.gitattributes,.github/,.gitignore,.pre-commit-config.yaml,AGENTS.md,APPROVALS.bend,BOARD.bend,BROWSER.bend,COMMANDS.bend,CONCEPTS.bend,CONTRIBUTING.md,FEATURES.bend,HOOKS.bend,INVARIANTS.bend,Justfile,KERNEL.bend,LAWS.bend,MAIN.bend,MODEL.bend,PROGRAM.bend,PROJECTS.bend,PROOF.bend,README.md,REASONING.bend,UI.bend,WORKSPACE.bend,bend-checksums.txt,bend-version,bendlib/,bun.lock,components.json,core/,docs/,examples/,host/,package.json,scripts/,tests-bend/,theory/,webui/}
|.codex:{environments/}
|.codex/environments:{environment.toml}
|.github:{workflows/}
|.github/workflows:{ci.yml}
|bendlib:{README.md,approval-architecture.bend,architecture.bend,association-map.bend,board-architecture.bend,board-codec.bend,board-filter.bend,board-resolution.bend,board-scheduling-spec.bend,board-scheduling.bend,board-spec.bend,board-state.bend,board.bend,command-codec.bend,commit.bend,component.bend,conversation-spec.bend,conversation.bend,domain.bend,effects.bend,equality.bend,execution.bend,feature-architecture.bend,feature-codec.bend,feature-execution.bend,feature-frame.bend,feature-laws.bend,feature-operations.bend,feature-protocol.bend,feature-resolution.bend,feature-spec.bend,feature-state.bend,frontend.bend,interface.bend,json.bend,locality.bend,notifications.bend,operations.bend,presentation.bend,proofs/,protocol.bend,reachability.bend,reasoning-architecture.bend,reasoning-context.bend,reasoning-laws.bend,reasoning-spec.bend,reasoning.bend,relations.bend,results.bend,schema.bend,stdlib.bend,task-laws.bend,tasks.bend,theory.bend,traces.bend,transcript.bend,wire-shape.bend,wire.bend,workspace-architecture.bend}
|bendlib/proofs:{README.md,algebra.bend,approvals.bend,board.bend,commit.bend,conversation.bend,equality.bend,execution.bend,frontend.bend,json.bend,observations.bend,operations.bend,plugins.bend,protocol.bend,reachability.bend,reasoning.bend,results.bend,safety.bend,tasks.bend,traces.bend,ui.bend,workspaces.bend}
|core:{SYSTEM.bend,board-capability-laws.bend,board-presentation-laws.bend,boundary-laws.bend,client-services.bend,code-block.bend,composition-laws.bend,composition.bend,contract.bend,conversation-presentation-laws.bend,directory-entry-laws.bend,execution-context-laws.bend,field-options.bend,form-fields.bend,interface.bend,laws.bend,live-output.bend,page-region-laws.bend,project-interaction-laws.bend,session-laws.bend,submission-feedback-laws.bend,submission-laws.bend,surface-laws.bend,ui-world.bend,user-context.bend,user-conversation.bend,user-experience-laws.bend,user-experience.bend,user-input.bend}
|docs:{adaptive-reasoning.md,adr/,bend2-exploration.md,chatgpt-web.md,plugins.md,task-board.md}
|docs/adr:{0001-task-owned-tool-contracts.md,0002-open-tool-call-recovery.md,0003-persisted-task-lifecycle.md,0004-semantic-ownership-at-runtime-boundaries.md,0005-single-source-configuration-and-transport.md,0006-executable-bend-task-model.md,0007-admit-certified-bend-transitions.md,0008-core-coding-effects-and-context-checkpoints.md,0009-command-meaning-and-imported-theory.md,0010-interaction-refinement-and-context-recovery.md,0011-independent-execution-semantics.md,0012-theory-indexed-whole-program-composition.md,0013-independent-operation-rights.md,0014-native-presentation-model.md,0015-native-extension-protocol.md,0016-relational-theory-reuse.md,0017-chatgpt-account-contract.md,0018-web-workspace-rendering.md,0019-task-workspaces-and-approval.md,0020-desktop-presentation-adapter.md,0021-adaptive-reasoning.md,0022-native-task-board.md,0023-component-locality.md,0024-chatgpt-web-backend.md,0025-native-conversation-and-desktop-source.md,0026-browser-executed-bend-ui.md,0027-bun-runtime.md,0028-populated-page-regions.md,0029-board-observations-and-presentation.md,0030-project-and-execution-context.md,0031-semantic-surfaces.md,0032-content-enclosure-allocation.md,0033-frame-interaction-ownership.md,0034-canonical-observations-and-visual-properties.md,0035-single-prepared-scene.md}
|examples:{plugins/}
|examples/plugins:{audit.mjs}
|host:{README.md,approvals.mjs,auth.mjs,board-files.mjs,board-text.mjs,chatgpt-contract.mjs,chatgpt-models.mjs,chatgpt-web-store.mjs,chatgpt-web.mjs,cli.mjs,codec.mjs,config.mjs,directories.mjs,files.mjs,jev.mjs,journal.mjs,kernel-worker.mjs,kernel.mjs,mcp.mjs,model-request.mjs,network.mjs,plugins.mjs,process.mjs,project.mjs,providers.mjs,public/,reasoning-config.mjs,sandbox.mjs,server.mjs,service.mjs,stdio-rpc.mjs,transport.c}
|host/public:{README.md,app.mjs,bend-value.mjs,bootstrap.mjs,events.mjs,index.html,markdown-worker.mjs,markdown.mjs,renderer.mjs,style.css,vendor/}
|host/public/vendor:{README.md,desktop-scroll.mjs,desktop-source.json,desktop-tokens.css,desktop-ui.mjs,desktop.css,highlight.LICENSE,highlight.mjs,katex.LICENSE,katex.mjs,manifest.json,streaming-markdown.LICENSE,streaming-markdown.mjs}
|scripts:{ExportMaps.v,ExportRelations.v,ExportStdlib.v,QuoteCertificate.v,agents-index.mjs,benchmark.mjs,bootstrap.sh,build.mjs,check-components.mjs,check-web-vendor.mjs,check.mjs,compile-javascript.mjs,desktop/,import-desktop.mjs,import-maps.mjs,import-relations.mjs,import-stdlib.mjs,install-bend.sh,setup-worktree.sh,theory-index.mjs,toolchain.mjs,verify-proof.mjs}
|scripts/desktop:{README.md,entry.mjs.in,scroll.mjs.in}
|tests-bend:{README.md,after-hooks.test.mjs,approval-decoding.test.mjs,approvals.test.mjs,architecture.test.mjs,association-map.test.mjs,async-service.test.mjs,auth.test.mjs,board-files.test.mjs,board-proof.test.mjs,board-service.test.mjs,board-text.test.mjs,chatgpt-compaction.test.mjs,chatgpt-models.test.mjs,chatgpt-web.test.mjs,chatgpt.test.mjs,coding.test.mjs,context-recovery.test.mjs,fixtures/,journal.test.mjs,kernel-boundaries.test.mjs,locality-support.mjs,locality.test.mjs,plugin-support.mjs,plugins.test.mjs,process.test.mjs,project-context.test.mjs,proof-gate.test.mjs,providers.test.mjs,pure-proof.test.mjs,reasoning-boundaries.test.mjs,reasoning-proof.test.mjs,reasoning.test.mjs,relations.test.mjs,sandbox.test.mjs,service-recovery.test.mjs,service.test.mjs,stdlib.test.mjs,support.mjs,whole-program-proof.test.mjs,workspaces.test.mjs}
|tests-bend/fixtures:{approved-tool.mjs,catalog.mjs,chatgpt-web.mjs,chatgpt.mjs,committed-tool.mjs,locality-extension.mjs,mcp.mjs,plugin.mjs}
|theory:{EXTLIB-LICENSE,LICENSE,README.md,relation-certificates.json,rocq-maps.json,stdlib-certificates.json}
|webui:{MODEL.bend,PROOF.bend,appearance-laws.bend,appearance.bend,board-spatial-laws.bend,browser-laws.bend,browser.bend,card-destination-laws.bend,context-control-laws.bend,control-content-laws.bend,control-laws.bend,controls.bend,design.bend,dialog-spatial-laws.bend,directory-entry-laws.bend,dismissal-laws.bend,dock-laws.bend,document.bend,editor-layout.bend,editor.bend,enclosure-laws.bend,enclosure-render-laws.bend,enclosure.bend,execution-presentation-laws.bend,fact-content-laws.bend,focus-retention-laws.bend,focus.bend,form-input-laws.bend,frame-relation-laws.bend,interaction.bend,laws.bend,layout-laws.bend,layout.bend,page-region-laws.bend,persistent-trigger-laws.bend,platform.bend,presentation-laws.bend,presentation-order-laws.bend,presentation-order.bend,project-presentation-laws.bend,reading.bend,render-contract.bend,render-laws.bend,rendered.bend,renderer-laws.bend,renderer.bend,request-laws.bend,request.bend,shell-spatial-laws.bend,submission-feedback-laws.bend,surface-laws.bend,surface-render-laws.bend,surfaces.bend,visibility.bend}
```
<!-- END AGENTS_MD_PROJECT_INDEX -->

# AGENTS.md

This file is for coding agents working in this repository.

## Start Here

- Read [README.md](./README.md) first for the repository-level workflow.
- Before you call or modify a module, read that module's `README.md` first.
- If the relevant `README.md` already answers your question, do not open the module internals first.

## Executable Requirements

- Start at the root MODEL.bend for the operational abstraction and PROOF.bend for its production instance. Keep its state carriers abstract when reasoning across layers; bind universal properties to the operations clients actually call. For execution details, read harness/COMMANDS.bend and harness/MODEL.bend. Task values and policy primitives belong to harness/DOMAIN.bend; harness/features/MODEL.bend assembles independent feature state and vocabulary. Read harness/INVARIANTS.bend and harness/LAWS.bend before changing behavior; harness/PROGRAM.bend realizes the resolved operations and executes the bounded transition.
- Public command preconditions belong in harness/COMMANDS.bend's resolve; completion correlation and accepted-call resolution belong in harness/protocol/PROGRAM.bend. A change must retain complete-decision, invocation and input-wide committed refinement, not merely state safety. Keep rejection distinct from an already accepted tool's error result.
- Keep Bend models in concept directories at most two levels below the repository root. Read each concept's README and model/contract entries before its helpers. Place proofs beside their concepts as PROOF.bend or *-proof.bend; the global PROOF.bend assembles production evidence.
- Choose meaningful existing theory representations before introducing domain abstractions. Use the quoted list, iterator, relation and association-map definitions/theorems directly; keep only domain correspondence and necessary premises local. Do not rebuild a parallel general algebra hierarchy, hand-reprove imported results, or edit generated certificates. Account for bridge cost separately from removed application proof maintenance.
- Requirements belong in executable definitions and propositions. Do not maintain duplicate lifecycle tables or state-machine diagrams in documentation.
- PROOF must discharge the production laws. Never replace a proof with an axiom, a hole, or unchecked recursion, or weaken a requirement solely to pass a check.
- The host interprets committed effects. Keep task policy in Bend and verify host ordering through integration tests.
- Internal semantics belong to proofs; compiler and external component boundaries belong to focused tests; cross-boundary behavior belongs to end-to-end tests. Remove finite semantic replay tests only after checking their actual proof coverage. Do not add tests whose only criterion is Bend accepting or rejecting source code, proofs or certificates. Keep the production proof gate and actual compiler execution, external component and end-to-end checks. The evidence map is tests-bend/README.md.
- Express decision reasons that are program requirements as Bend entities, executable specifications or public rules bound to actual production computations. Do not maintain another account in documentation of requirements already expressed there. ADRs are optional; record exploration-specific findings in `docs/bend2-exploration.md`.
- Keep the core import closure declared in `components.json` independent of the assembled harness/MODEL.bend and concrete features. Add feature cases in their owning `features/<concept>` modules or `harness/features` assembly; global consumers process stable outer categories. Boundary configuration changes require the same review as contract changes.
- Bind component refinement, intended writes and unrelated-state preservation to actual production functions. Scope preservation to the owning component's operations. Run `bun run test:locality` after changing component interfaces or assembly; freeze unrelated implementation and proof files in extension fixtures rather than copying and repairing them.
- Keep shared surface types independent of feature views. Feature cursor encoding, validation and decoding belong to the same assembly boundary as navigation. Exercise real native round trips in extension fixtures, with clients frozen. Contract-preserving replacement equality belongs to production proofs, not checker-only fixtures.

## Git Hooks

- `pre-commit` runs `bun scripts/check.mjs` to check actual component boundaries, the pinned compiler, reproducible imported certificates, Bend proof obligations, the native entry point and host/script syntax. `scripts/build.mjs` checks the same source boundaries before using a cached binary.
- `pre-commit` runs `bun scripts/agents-index.mjs check` to check the tracked-file index.
- `pre-push` runs `bun run test` for native kernel and host integration tests.
- `just hooks` runs both configured stages.

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
|.:{.codex/,.editorconfig,.gitattributes,.gitignore,.pre-commit-config.yaml,AGENTS.md,BROWSER.bend,CONCEPTS.bend,CONTRIBUTING.md,HOST.bend,Justfile,KERNEL.bend,MAIN.bend,MODEL.bend,PROOF.bend,README.md,bend-checksums.txt,bend-version,bendlib/,browser/,bun.lock,components.json,docs/,examples/,features/,harness/,host/,interaction/,package.json,plugins/,scripts/,tests-bend/,theory/}
|.codex:{environments/}
|.codex/environments:{environment.toml}
|bendlib:{README.md,algebra-proof.bend,association-map.bend,categories.bend,component.bend,effects.bend,equality-proof.bend,equality.bend,json-proof.bend,json.bend,logic-proof.bend,relations.bend,stdlib.bend,theory.bend}
|browser:{CONTRACT.bend,MODEL.bend,PROOF.bend,README.md,appearance/,controls/,document/,editor/,focus/,layout/,model-proof.bend,model-rules.bend,reading/,runtime/}
|browser/appearance:{CONTRACT.bend,DESIGN.bend,FONT.bend,ICONS.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,TYPOGRAPHY.bend}
|browser/controls:{BUTTONS.bend,CONTRACT.bend,CONTROLS.bend,GEOMETRY.bend,MODEL.bend,NAVIGATION.bend,PROGRAM.bend,PROOF.bend,README.md,SHELL.bend,SIDEBAR.bend,SURFACES.bend,authored-primitives.bend,authored-proof.bend,button-proof.bend,navigation-proof.bend}
|browser/document:{CONTRACT.bend,FRAME.bend,MODEL.bend,PROOF.bend,README.md,RENDERED.bend,SOURCE.bend,SPEC.bend,content-proof.bend,presentation-order.bend,presentation-proof.bend,render-contract.bend,render-proof.bend,source-contract.bend,source-proof.bend}
|browser/editor:{CONTRACT.bend,MODEL.bend,PROOF.bend,README.md}
|browser/focus:{CONTRACT.bend,MODEL.bend,PROOF.bend,README.md}
|browser/layout:{ACTIVITY.bend,ADAPTATION.bend,CONTENT.bend,CONTRACT.bend,GEOMETRY.bend,HIERARCHY.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,RENDERER.bend,SOURCE.bend,SPACE.bend,activity-contract.bend,activity-proof.bend,adaptation-proof.bend,allocation-contract.bend,allocation-proof.bend,enclosure.bend,geometry-contract.bend,geometry-proof.bend,measurement-contract.bend,natural-size.bend,physical-content-measurement.bend,physical-native.bend,physical-plan.bend,physical-probe.bend,physical-space.bend,render-contract.bend,render-proof.bend,sizing-proof.bend}
|browser/reading:{CONTRACT.bend,MODEL.bend,PROOF.bend,README.md}
|browser/runtime:{CONTRACT.bend,MODEL.bend,PLATFORM.bend,PROOF.bend,README.md,SEMANTICS.bend,frontend-utility.bend,native-fields.bend,platform-proof.bend,request.bend,utility-proof.bend}
|docs:{adaptive-reasoning.md,adr/,bend2-exploration.md,chatgpt-web.md,plugins.md,proofs.md,task-board.md}
|docs/adr:{0024-project-scoped-chatgpt-plugin.md,0025-native-compiler-performance.md,0026-ci-validation-scope.md,0027-official-chatgpt-sign-in.md,0028-model-representation-boundaries.md,0029-shallow-concept-directories.md,0030-concept-local-proof-providers.md,0031-public-vocabulary-and-proof-boundaries.md,0032-operational-model-abstraction.md,0033-button-category-inclusion.md,0034-open-category-construction.md,0035-context-bound-construction.md,0036-host-semantic-constructions.md,0037-production-instance-construction.md,0038-capability-based-native-tool-construction.md,0039-local-browser-sessions-and-stable-journals.md,0040-append-only-model-history.md,0040-executable-ui-relationships.md,0041-context-compaction.md,0041-operational-user-experience-relations.md,0042-observable-properties-and-action-causes.md,0043-information-needs-and-progressive-disclosure.md,0044-adaptive-presentation-and-navigation-relationships.md,0045-whole-sidebar-construction.md,0046-observation-backed-activity-construction.md,0047-shared-activity-construction-and-measured-scale.md,0048-role-preserving-summary-and-visual-alignment.md,0049-activity-scoped-information-and-settings.md,0050-constructed-task-graphs.md}
|examples:{plugins/}
|examples/plugins:{audit.mjs}
|features:{README.md,board/,chatgpt/,compaction/,task_graph/}
|features/board:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SPEC.bend,STATE.bend,filter.bend,resolution.bend,scheduling-spec.bend,scheduling.bend}
|features/chatgpt:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SPEC.bend,STATE.bend,view.bend}
|features/compaction:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SPEC.bend,STATE.bend}
|features/task_graph:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SPEC.bend,construction-proof.bend,registry-proof.bend}
|harness:{COMMANDS.bend,CONTRACT.bend,DOMAIN.bend,INVARIANTS.bend,LAWS.bend,LOCALITY.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,approval/,compaction/,context/,conversation/,execution/,features/,history/,protocol/,reasoning/,tasks/,tools/,transport/,workspace/}
|harness/approval:{CONTRACT.bend,HOOKS.bend,MODEL.bend,PROOF.bend,README.md}
|harness/compaction:{CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md}
|harness/context:{MODEL.bend,PROGRAM.bend,PROOF.bend,README.md}
|harness/conversation:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md}
|harness/execution:{OPERATIONS.bend,PROGRAM.bend,PROOF.bend,README.md,notifications.bend}
|harness/features:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROOF.bend,README.md,SPEC.bend,STATE.bend,execution.bend,graph-execution.bend,graph-proof.bend,graph-spec.bend,graph-state.bend,laws.bend,operations.bend,protocol.bend,resolution.bend}
|harness/history:{MODEL.bend,PROGRAM.bend,PROOF.bend,README.md}
|harness/protocol:{COMMIT.bend,PROGRAM.bend,PROOF.bend,README.md,RESULTS.bend,commit-proof.bend}
|harness/reasoning:{CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SPEC.bend,context.bend,view-proof.bend,view.bend}
|harness/tasks:{CONTRACT.bend,PROGRAM.bend,PROOF.bend,README.md}
|harness/tools:{MODEL.bend,README.md,SYNTAX.bend}
|harness/transport:{CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,command-codec.bend,command-contract.bend,model-json.bend,presentation.bend,schema.bend,wire-shape.bend,wire.bend}
|harness/workspace:{CONTRACT.bend,PROJECTS.bend,PROOF.bend,README.md,WORKSPACE.bend}
|host:{README.md,adapters/,approvals.mjs,board-files.mjs,board-text.mjs,chatgpt-account.mjs,chatgpt-contract.mjs,chatgpt-models.mjs,chatgpt-plugin.mjs,chatgpt-web-store.mjs,chatgpt-web.mjs,cli.mjs,codec.mjs,compaction.mjs,config.mjs,directories.mjs,files.mjs,jev.mjs,journal.mjs,kernel-worker.mjs,kernel.mjs,mcp.mjs,model-request.mjs,network.mjs,opaque-credentials.mjs,plugins.mjs,process.mjs,project.mjs,providers.mjs,public/,reasoning-config.mjs,sandbox.mjs,server.mjs,service.mjs,stdio-rpc.mjs,transport.c}
|host/adapters:{ACCOUNTS.bend,BACKENDS.bend,BROWSER.bend,COMPACTION.bend,CONFIGURATION.bend,EFFECTS.bend,EVALUATOR.bend,HTTP.bend,MODEL.bend,PLUGINS.bend,PROGRAM.bend,PROOF.bend,README.md,RPC.bend,WEB.bend,accounts-proof.bend,backends-proof.bend,browser-proof.bend,compaction-proof.bend,configuration-proof.bend,effects-proof.bend,evaluator-proof.bend,http-proof.bend,plugins-proof.bend,rpc-proof.bend,web-proof.bend}
|host/public:{README.md,app.mjs,bend-value.mjs,bootstrap.mjs,events.mjs,index.html,json-tokens.mjs,markdown-worker.mjs,markdown.mjs,model-boundary.mjs,physical-markdown.css,physical-measurement.mjs,renderer.mjs,style.css,text-measurement.mjs,vendor/}
|host/public/vendor:{README.md,desktop-source.json,desktop-tokens.css,highlight.LICENSE,highlight.mjs,katex.LICENSE,katex.mjs,manifest.json,streaming-markdown.LICENSE,streaming-markdown.mjs}
|interaction:{CONTRACT.bend,IDENTITY.bend,INPUT.bend,MODEL.bend,PROOF.bend,README.md,STATE.bend,TYPES.bend,conversation/,experience/,identity-laws.bend,presentation/,services/,session/,submission/}
|interaction/conversation:{CODE.bend,CONTRACT.bend,MODEL.bend,OUTPUT.bend,PROOF.bend,README.md}
|interaction/experience:{ACTIVITY.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md}
|interaction/presentation:{COMPOSITION.bend,CONTRACT.bend,INFORMATION.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SURFACE.bend,VIEW.bend,interaction-proof.bend,scene-proof.bend,surface-proof.bend}
|interaction/services:{CONTEXT.bend,CONTRACT.bend,MODEL.bend,PROOF.bend,README.md}
|interaction/session:{CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md}
|interaction/submission:{CONTRACT.bend,FIELDS.bend,MODEL.bend,PROOF.bend,README.md,field-options.bend}
|plugins:{selvedge-chatgpt/}
|plugins/selvedge-chatgpt:{MODEL.bend,README.md,bin/,mcp.json,package-lock.json,package.json,plugin.json,scripts/,skills/,src/}
|plugins/selvedge-chatgpt/bin:{server.mjs,setup.mjs,tunnel.mjs}
|plugins/selvedge-chatgpt/scripts:{build-model.mjs}
|plugins/selvedge-chatgpt/skills:{local-projects/}
|plugins/selvedge-chatgpt/skills/local-projects:{SKILL.md}
|plugins/selvedge-chatgpt/src:{client.mjs,server.mjs}
|scripts:{ExportMaps.v,ExportRelations.v,ExportStdlib.v,QuoteCertificate.v,agents-index.mjs,benchmark.mjs,bootstrap.sh,build.mjs,check-components.mjs,check-web-vendor.mjs,check.mjs,compile-javascript.mjs,import-desktop.mjs,import-maps.mjs,import-relations.mjs,import-stdlib.mjs,install-bend.sh,setup-worktree.sh,test.mjs,theory-index.mjs,toolchain.mjs,ui-verification.mjs,verify-proof.mjs}
|tests-bend:{README.md,after-hooks.test.mjs,approval-decoding.test.mjs,approvals.test.mjs,association-map.test.mjs,async-service.test.mjs,auth.test.mjs,automatic-compaction.test.mjs,board-files.test.mjs,board-service.test.mjs,board-text.test.mjs,categories.test.mjs,chatgpt-compaction.test.mjs,chatgpt-models.test.mjs,chatgpt-plugin-package.test.mjs,chatgpt-plugin-sandbox.test.mjs,chatgpt-plugin-support.mjs,chatgpt-plugin.test.mjs,chatgpt-web.test.mjs,chatgpt.test.mjs,coding.test.mjs,context-recovery.test.mjs,control-categories.test.mjs,fixtures/,journal.test.mjs,kernel-boundaries.test.mjs,locality-support.mjs,locality.test.mjs,model-abstraction.test.mjs,plugin-support.mjs,plugins.test.mjs,process-identity.mjs,process.test.mjs,project-context.test.mjs,providers.test.mjs,reasoning-boundaries.test.mjs,reasoning.test.mjs,relations.test.mjs,sandbox.test.mjs,service-recovery.test.mjs,service.test.mjs,stdlib.test.mjs,support.mjs,task-execution.test.mjs,task-graph-service.test.mjs,task-graph.test.mjs,ui-verification.test.mjs,workspaces.test.mjs}
|tests-bend/fixtures:{approved-tool.mjs,catalog.mjs,chatgpt-web.mjs,chatgpt.mjs,committed-tool.mjs,compaction.mjs,locality-extension.mjs,mcp.mjs,plugin.mjs,task-graph.mjs}
|theory:{EXTLIB-LICENSE,LICENSE,README.md,relation-certificates.json,rocq-maps.json,stdlib-certificates.json}
```
<!-- END AGENTS_MD_PROJECT_INDEX -->

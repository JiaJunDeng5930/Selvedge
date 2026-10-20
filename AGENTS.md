# AGENTS.md

This file is for coding agents working in this repository.

## 最高原则：直接围绕工程需求与目标

- 工程目标是本仓库一切工作的最终依据。需求、规格、仓库约定、技能流程、历史方案和工作记录均须据此判断和调整，不得成为脱离目标的独立要求。
- 写入工程的所有内容，包括文字、代码、规格、证明、测试、脚本和配置，都必须直接围绕工程目标所要求的性质及解决这些性质所需的问题展开。
- 已有工程产物可以作为参考或工具，但不得仅凭其存在、既有结构或既有行为引入新要求。调整工程时，已有产物默认删除或调整；只有经验或证据表明其仍服务于工程目标时才保留。
- 规格必须直接表达需求。实现必须满足规格；证明必须建立实现对规格的保证；测试必须直接检验所负责的工程行为或边界。不得把历史实现、当前实现自身、证明便利性、测试通过或流程完成当作正确性的依据。
- 修改实现前，先确认工程规格仍准确表达工程目标；规格偏离目标时一并修正。不得仅为保持旧算法而保留旧实现、建立新旧实现等价要求，或把旧实现的具体选择追加为程序义务。
- 审查首先判断内容是否直接服务于工程目标，再判断其内部是否正确。不能说明直接需求依据的内容，应删除或改正，不得通过追加假设、适配、证明、测试或审查流程使其自我成立。
- 不得为了简化实现或通过验证而削弱真实需求。进度以工程目标的实际完成情况衡量，不以新增定义、证明、检查或审查轮次的数量衡量。
- 测试是否新增或保留，必须结合真实使用场景、故障经验、具体改动风险、已有保障和运行维护成本判断；“这是需求”或“想保证某个性质”本身不构成增测理由。删除收益不足的测试，不得把人为测试门槛反过来当作工程目标。

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
- For each property, prefer construction in the domain language, then types, then proofs, then focused tests, and finally end-to-end tests. Check those earlier mechanisms before retaining a test; do not test a property already guaranteed there. A possible bug or an external boundary alone does not justify a test: require a convincing, concrete likelihood of real failure relative to its maintenance cost; default to deleting it otherwise. Merge related physical checks and their setup. Keep the complete production proof gate. The remaining test responsibilities are in tests-bend/README.md.
- Express decision reasons that are program requirements as Bend entities, executable specifications or public rules bound to actual production computations. Do not maintain another account in documentation of requirements already expressed there. ADRs are optional; record exploration-specific findings in `docs/bend2-exploration.md`.
- Keep the transitive import closure of the core roots in `components.json` independent of the assembled harness/MODEL.bend, harness/features and concrete features. New helpers need no dependency inventory when they preserve that independence. Add feature cases in their owning `features/<concept>` modules or `harness/features` assembly; global consumers process stable outer categories. Review boundary changes against those responsibilities.
- Bind component refinement, intended writes and unrelated-state preservation to actual production functions. Scope preservation to the owning component's operations. Check changed component interfaces and assembly through the production proof and source-ownership gates; do not maintain hypothetical extensions that repeatedly compile copies of the application.
- Keep shared surface types independent of feature views. Feature cursor encoding, validation and decoding belong to the same assembly boundary as navigation. Replacement implementations must satisfy the required observations and updates through production proofs; equality with an old implementation is not an independent obligation.

## Git Hooks

- `pre-commit` runs `bun scripts/check.mjs` to check actual component boundaries, the pinned compiler, reproducible imported certificates, Bend proof obligations, generated JavaScript libraries, the native entry point and host/script syntax. `scripts/build.mjs` checks the same source boundaries before using cached build artifacts.
- `pre-commit` runs `bun scripts/agents-index.mjs check` to check the tracked-file index.
- `pre-push` runs `bun run test` for the focused physical regression suite after the production build.
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

- Allowed tags: `TODO`, `FIXME`, `HACK`, `NOTE`, `XXX`, `DEFENSE`.
- Format: `<comment marker> <TAG>(<optional issue>): <specific action or reason>`.
- Marker comments must explain the intent, decision, risk, or follow-up behind the code. Do not use marker comments to restate facts already visible from the code.
- `TODO` means known follow-up work while current code is acceptable.
- `FIXME` means a known defect that needs repair.
- `HACK` means a temporary workaround that should be replaced by normal design.
- `NOTE` means important context that affects code understanding.
- `XXX` means high-risk code that needs reviewer attention.

## 防御性代码约束

- 任何防御性代码都必须对应开发或实际运行中遇到过的问题、当前系统真实外部输入或调用路径能够触发的场景，或明确功能契约、协议规范、安全要求规定必须处理的场景；并且该场景必须带来实际工程问题。凭经验判断，默认不添加。不得仅凭未来异常推测添加，也不得虚构内部状态或违反现有契约构造触发情景。
- 每个防御性分支必须用以 `DEFENSE` 开头的注释说明具体触发条件。不得使用“以防万一”“增强健壮性”等笼统理由；无法说明触发情景的代码应删除。
- 防御性代码阻碍功能开发、修改或正常执行时，优先审查必要性。场景已不可能发生或已不属于当前系统职责时直接删除，不得为保留它增加额外实现。拿不准时默认删除。
- 不得为未经证实的异常添加默认值、静默忽略、自动重试、通用异常捕获或兼容分支。错误处理必须具有明确触发条件及预期行为。

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
|.:{.codex/,.editorconfig,.gitattributes,.gitignore,.pre-commit-config.yaml,AGENTS.md,BROWSER.bend,CONCEPTS.bend,CONTRIBUTING.md,HOST.bend,Justfile,KERNEL.bend,MAIN.bend,MODEL.bend,PROOF.bend,README.md,bend-checksums.txt,bend-version,bendlib/,browser/,bun.lock,components.json,docs/,examples/,features/,harness/,host/,interaction/,package.json,plugins/,relay/,remote/,scripts/,tests-bend/,theory/}
|.codex:{environments/}
|.codex/environments:{environment.toml}
|bendlib:{README.md,algebra-proof.bend,association-map.bend,categories.bend,component.bend,effects.bend,equality-proof.bend,equality.bend,json-proof.bend,json.bend,logic-proof.bend,relations.bend,stdlib.bend,string-equality.bend,theory.bend}
|browser:{CONTRACT.bend,MODEL.bend,PROOF.bend,README.md,appearance/,controls/,document/,editor/,focus/,layout/,model-proof.bend,model-rules.bend,reading/,runtime/}
|browser/appearance:{CONTRACT.bend,DESIGN.bend,FONT.bend,ICONS.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,TYPOGRAPHY.bend}
|browser/controls:{BUTTONS.bend,CONTRACT.bend,CONTROLS.bend,GEOMETRY.bend,MODEL.bend,NAVIGATION.bend,PROGRAM.bend,PROOF.bend,README.md,SHELL.bend,SIDEBAR.bend,SURFACES.bend,authored-primitives.bend,authored-proof.bend,button-proof.bend,chart.bend,interactive-markdown.bend,navigation-proof.bend}
|browser/document:{CONTRACT.bend,FRAME.bend,MODEL.bend,PROOF.bend,README.md,RENDERED.bend,SOURCE.bend,SPEC.bend,content-proof.bend,diagnostic-proof.bend,presentation-order.bend,presentation-proof.bend,render-contract.bend,render-proof.bend,source-contract.bend,source-proof.bend}
|browser/editor:{CONTRACT.bend,MODEL.bend,PROOF.bend,README.md,skill-mention.bend,skill-view.bend}
|browser/focus:{CONTRACT.bend,MODEL.bend,PROOF.bend,README.md}
|browser/layout:{ACTIVITY.bend,ADAPTATION.bend,CONTENT.bend,CONTRACT.bend,GEOMETRY.bend,HIERARCHY.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,RENDERER.bend,SOURCE.bend,SPACE.bend,activity-contract.bend,activity-proof.bend,adaptation-proof.bend,allocation-contract.bend,allocation-proof.bend,enclosure.bend,field-dimensions.bend,geometry-contract.bend,geometry-proof.bend,measurement-contract.bend,measurement-proof.bend,measurement-requirements.bend,natural-size.bend,physical-content-measurement.bend,physical-native.bend,physical-plan.bend,physical-probe.bend,physical-space.bend,render-contract.bend,render-proof.bend,sizing-proof.bend}
|browser/reading:{CONTRACT.bend,MODEL.bend,PROOF.bend,README.md}
|browser/runtime:{CONTRACT.bend,MODEL.bend,PLATFORM.bend,PROOF.bend,README.md,SEMANTICS.bend,frontend-utility.bend,native-fields.bend,platform-proof.bend,request.bend,utility-proof.bend}
|docs:{adaptive-reasoning.md,adr/,bend2-exploration.md,chatgpt-web.md,plugins.md,proofs.md,remote-control.md,task-board.md}
|docs/adr:{0024-project-scoped-chatgpt-plugin.md,0025-native-compiler-performance.md,0026-ci-validation-scope.md,0027-official-chatgpt-sign-in.md,0028-model-representation-boundaries.md,0029-shallow-concept-directories.md,0030-concept-local-proof-providers.md,0031-public-vocabulary-and-proof-boundaries.md,0032-operational-model-abstraction.md,0033-button-category-inclusion.md,0034-open-category-construction.md,0035-context-bound-construction.md,0036-host-semantic-constructions.md,0037-production-instance-construction.md,0038-capability-based-native-tool-construction.md,0039-local-browser-sessions-and-stable-journals.md,0040-append-only-model-history.md,0040-executable-ui-relationships.md,0041-context-compaction.md,0041-context-deltas.md,0041-operational-user-experience-relations.md,0042-context-definition-construction.md,0042-observable-properties-and-action-causes.md,0043-information-needs-and-progressive-disclosure.md,0044-adaptive-presentation-and-navigation-relationships.md,0045-whole-sidebar-construction.md,0046-observation-backed-activity-construction.md,0047-shared-activity-construction-and-measured-scale.md,0048-role-preserving-summary-and-visual-alignment.md,0049-activity-scoped-information-and-settings.md,0050-constructed-task-graphs.md,0051-tracked-context-and-input-selection.md,0052-chatgpt-audio-and-task-execution.md,0052-image-model-input.md,0053-deferred-tool-definitions.md,0053-work-shared-ui.md,0054-cloud-task-workspaces.md,0055-native-catalog-construction.md}
|examples:{plugins/}
|examples/plugins:{audit.mjs}
|features:{README.md,board/,chatgpt/,compaction/,remote/,task_graph/,titles/,work/,worktree/}
|features/board:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SPEC.bend,STATE.bend,filter.bend,resolution.bend,scheduling-spec.bend,scheduling.bend}
|features/chatgpt:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SPEC.bend,STATE.bend,view.bend}
|features/compaction:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SPEC.bend,STATE.bend}
|features/remote:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SPEC.bend}
|features/task_graph:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SPEC.bend,construction-proof.bend,registry-proof.bend}
|features/titles:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SPEC.bend,STATE.bend}
|features/work:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SPEC.bend,ui-patch.bend}
|features/worktree:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROOF.bend,README.md}
|harness:{COMMANDS.bend,CONTRACT.bend,DOMAIN.bend,INVARIANTS.bend,LAWS.bend,LOCALITY.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,approval/,compaction/,context/,conversation/,execution/,features/,history/,initial-catalog-proof.bend,protocol/,reasoning/,search/,tasks/,tools/,transport/,workspace/}
|harness/approval:{CONTRACT.bend,HOOKS.bend,MODEL.bend,PROOF.bend,README.md}
|harness/compaction:{CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md}
|harness/context:{CONTRACT.bend,KINDS.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,constructor-proof.bend,instruction.bend,interactive-markdown.bend,patch-proof.bend,project-guidance.bend,selection-proof.bend,selection.bend,skill-information.bend,task-lifecycle.bend}
|harness/conversation:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,TITLE.bend,origin-contract.bend,origin-proof.bend,speech-contract.bend,speech-proof.bend,speech.bend}
|harness/execution:{OPERATIONS.bend,PROGRAM.bend,PROOF.bend,README.md,notifications.bend}
|harness/features:{CODEC.bend,CONTRACT.bend,MODEL.bend,PROOF.bend,README.md,SPEC.bend,STATE.bend,execution.bend,graph-execution.bend,graph-proof.bend,graph-spec.bend,graph-state.bend,idle.bend,laws.bend,operations.bend,protocol.bend,remote-proof.bend,remote.bend,resolution.bend,work-proof.bend,work-state.bend,worktree-execution.bend,worktree-proof.bend,worktree-sharing-proof.bend,worktree-spec.bend,worktree-state.bend,worktree-storage-proof.bend}
|harness/history:{MODEL.bend,PROGRAM.bend,PROOF.bend,README.md}
|harness/protocol:{COMMIT.bend,PROGRAM.bend,PROOF.bend,README.md,RESULTS.bend,commit-proof.bend}
|harness/reasoning:{CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SPEC.bend,context.bend,view-proof.bend,view.bend}
|harness/search:{MODEL.bend,PROGRAM.bend,PROOF.bend,README.md}
|harness/tasks:{CONTRACT.bend,PROGRAM.bend,PROOF.bend,README.md,side-context-contract.bend,side-context-proof.bend,side-context.bend,side-contract.bend,side-conversation.bend,side-proof.bend}
|harness/tools:{MODEL.bend,README.md,SYNTAX.bend,discovery-proof.bend,discovery.bend}
|harness/transport:{CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,command-codec.bend,command-contract.bend,model-json.bend,presentation.bend,schema.bend,wire-shape.bend,wire.bend}
|harness/workspace:{CONTRACT.bend,PROJECTS.bend,PROOF.bend,README.md,WORKSPACE.bend}
|host:{README.md,adapters/,approvals.mjs,board-files.mjs,chatgpt-account.mjs,chatgpt-audio.mjs,chatgpt-contract.mjs,chatgpt-models.mjs,chatgpt-plugin.mjs,chatgpt-web-store.mjs,chatgpt-web.mjs,cli.mjs,cloud-environments.mjs,codec.mjs,compaction.mjs,config.mjs,context-discovery.mjs,context-patches.mjs,context-sources.mjs,directories.mjs,files.mjs,jev.mjs,journal.mjs,kernel-worker.mjs,kernel.mjs,mcp.mjs,model-request.mjs,network.mjs,opaque-credentials.mjs,plugins.mjs,process.mjs,project.mjs,providers.mjs,public/,reasoning-config.mjs,remote-connector.mjs,remote-control.mjs,sandbox.mjs,server.mjs,service.mjs,stdio-rpc.mjs,task-text.mjs,task-workspaces.mjs,tencent-cvm.mjs,transport.c,worktrees.mjs}
|host/adapters:{ACCOUNTS.bend,AUDIO.bend,BACKENDS.bend,BROWSER.bend,COMPACTION.bend,CONFIGURATION.bend,EFFECTS.bend,EVALUATOR.bend,HTTP.bend,MODEL.bend,PLUGINS.bend,PROGRAM.bend,PROOF.bend,README.md,RPC.bend,WEB.bend,accounts-proof.bend,audio-proof.bend,backends-proof.bend,browser-proof.bend,compaction-proof.bend,configuration-proof.bend,effects-proof.bend,evaluator-proof.bend,http-proof.bend,plugins-proof.bend,rpc-proof.bend,web-proof.bend}
|host/public:{README.md,app.mjs,appearance.mjs,audio.mjs,bend-value.mjs,bootstrap.mjs,connection.mjs,events.mjs,index.html,interactive-storage.mjs,json-tokens.mjs,keyboard.mjs,layout-reveal.mjs,markdown-fences.mjs,markdown-worker.mjs,markdown.mjs,model-boundary.mjs,physical-markdown.css,physical-measurement.mjs,presentation-motion.mjs,renderer.mjs,style.css,text-measurement.mjs,vendor/}
|host/public/vendor:{README.md,desktop-source.json,desktop-tokens.css,highlight.LICENSE,highlight.mjs,katex.LICENSE,katex.mjs,manifest.json,streaming-markdown.LICENSE,streaming-markdown.mjs}
|interaction:{CONTRACT.bend,IDENTITY.bend,INPUT.bend,MODEL.bend,PROOF.bend,README.md,STATE.bend,TYPES.bend,conversation/,experience/,identity-laws.bend,interactive_markdown/,presentation/,search/,services/,session/,speech/,submission/}
|interaction/conversation:{CODE.bend,CONTRACT.bend,MODEL.bend,OUTPUT.bend,PROOF.bend,README.md}
|interaction/experience:{ACTIVITY.bend,CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md}
|interaction/interactive_markdown:{CODEC.bend,CONTRACT.bend,DECIMAL.bend,DESIGN.md,DOCUMENTS.bend,EXPAND.bend,EXPRESSION.bend,MODEL.bend,PARSER.bend,PROOF.bend,README.md,REGISTRY.bend,SCENE.bend,SCHEMA.bend,SOURCES.bend,STATE.bend,SYNTAX.bend,TYPES.bend,VIEW_SCHEMA.bend,documents-contract.bend,documents-proof.bend,expression-proof.bend,scene-proof.bend,snapshot-contract.bend,snapshot-proof.bend}
|interaction/presentation:{COMPOSITION.bend,CONTRACT.bend,INFORMATION.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,SURFACE.bend,VIEW.bend,interaction-proof.bend,scene-proof.bend,surface-proof.bend}
|interaction/search:{CONTRACT.bend,MODEL.bend,PROOF.bend,README.md}
|interaction/services:{CONTEXT.bend,CONTRACT.bend,MODEL.bend,PROOF.bend,README.md,connection-contract.bend,connection-proof.bend}
|interaction/session:{CONTRACT.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md}
|interaction/speech:{CONTRACT.bend,MODEL.bend,PROOF.bend,README.md}
|interaction/submission:{CONTRACT.bend,FIELDS.bend,MODEL.bend,PROOF.bend,README.md,field-options.bend}
|plugins:{selvedge-chatgpt/}
|plugins/selvedge-chatgpt:{MODEL.bend,README.md,bin/,mcp.json,package-lock.json,package.json,plugin.json,scripts/,skills/,src/}
|plugins/selvedge-chatgpt/bin:{server.mjs,setup.mjs,tunnel.mjs}
|plugins/selvedge-chatgpt/scripts:{build-model.mjs}
|plugins/selvedge-chatgpt/skills:{local-projects/}
|plugins/selvedge-chatgpt/skills/local-projects:{SKILL.md}
|plugins/selvedge-chatgpt/src:{client.mjs,server.mjs}
|relay:{.gitignore,README.md,package.json,src/,test/,wrangler.jsonc}
|relay/src:{worker.mjs}
|relay/test:{runtime.mjs}
|remote:{README.md,protocol.mjs}
|scripts:{ExportMaps.v,ExportRelations.v,ExportStdlib.v,QuoteCertificate.v,agents-index.mjs,benchmark.mjs,bootstrap.sh,build.mjs,check-components.mjs,check-web-vendor.mjs,check.mjs,compile-javascript.mjs,compiler-source.mjs,import-desktop.mjs,import-maps.mjs,import-relations.mjs,import-stdlib.mjs,install-bend.sh,optimize-javascript.mjs,setup-worktree.sh,test-history-search-browser.py,test-images-browser.py,test-interactive-markdown-browser.py,test-process.mjs,test.mjs,theory-index.mjs,toolchain.mjs,ui-verification.mjs,validate.mjs,verify-proof.mjs}
|tests-bend:{README.md,approvals.test.mjs,auth.test.mjs,board-files.test.mjs,browser-boundaries.test.mjs,chatgpt-plugin-package.test.mjs,chatgpt-plugin.test.mjs,chatgpt-web.test.mjs,cloud-workspaces.test.mjs,compiler-support.mjs,context-discovery.test.mjs,fixtures/,history-search.test.mjs,images-service.test.mjs,interactive-markdown-fences.test.mjs,interactive-markdown-service.test.mjs,interactive-markdown-storage.test.mjs,javascript-cache.test.mjs,javascript-intrinsics.test.mjs,javascript-purity.test.mjs,journal.test.mjs,kernel-boundaries.test.mjs,locality.test.mjs,plugins.test.mjs,process.test.mjs,providers.test.mjs,relay.test.mjs,remote-connector.test.mjs,remote-control.test.mjs,sandbox.test.mjs,service.test.mjs,support.mjs,test-process.test.mjs,tool-discovery.test.mjs,ui-verification.test.mjs,work-ui-service.test.mjs,works-service.test.mjs,worktrees.test.mjs}
|tests-bend/fixtures:{approved-tool.mjs,chatgpt.mjs,cloud-tools.mjs,discovery-tools.mjs,image-data.mjs,images.mjs,interactive-markdown.mjs}
|theory:{EXTLIB-LICENSE,LICENSE,README.md,relation-certificates.json,rocq-maps.json,stdlib-certificates.json}
```
<!-- END AGENTS_MD_PROJECT_INDEX -->

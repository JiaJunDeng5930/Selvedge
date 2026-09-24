# AGENTS.md

This file is for coding agents working in this repository.

## Start Here

- Read [README.md](./README.md) first for the repository-level workflow.
- Before you call or modify a module, read that module's `README.md` first.
- If the relevant `README.md` already answers your question, do not open the module internals first.

## Executable Requirements

- Read MODEL, INVARIANTS, and LAWS before changing task behavior; PROGRAM executes the modeled transition.
- Requirements belong in executable definitions and propositions. Do not maintain duplicate lifecycle tables or state-machine diagrams in documentation.
- PROOF must discharge the production laws. Never replace a proof with an axiom, a hole, or unchecked recursion, or weaken a requirement solely to pass a check.
- The host interprets committed effects. Keep task policy in Bend and verify host ordering through integration tests.
- Record architecture reasons in an ADR and exploration-specific findings in `docs/bend2-exploration.md`.

## Git Hooks

- `pre-commit` runs `node scripts/check.mjs` to check the pinned compiler, Bend proof obligations, and host/script syntax.
- `pre-commit` runs `node scripts/agents-index.mjs check` to check the tracked-file index.
- `pre-push` runs `npm test` for native kernel and host integration tests.
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
- Update with `npm run index` or `just agents-index`, then stage AGENTS.md.
- Check with `npm run index:check` or `just agents-index-check`.
- The generator uses Git-tracked staged paths only. Ignored and untracked files are excluded.

## Project Index

<!-- BEGIN AGENTS_MD_PROJECT_INDEX -->
```text
[Project Index]|root:.
|source:git-tracked-files-only
|excluded:{git-ignored,git-untracked}
|.:{.codex/,.editorconfig,.github/,.gitignore,.pre-commit-config.yaml,AGENTS.md,CONTRIBUTING.md,INVARIANTS.bend,Justfile,LAWS.bend,MAIN.bend,MODEL.bend,PROGRAM.bend,PROOF.bend,README.md,bend-checksums.txt,bend-version,bendlib/,docs/,host/,package.json,scripts/,tests-bend/}
|.codex:{environments/}
|.codex/environments:{environment.toml}
|.github:{workflows/}
|.github/workflows:{ci.yml}
|bendlib:{README.md,equality.bend,json.bend,presentation.bend,schema.bend,tasks.bend,theory.bend,wire.bend}
|docs:{adr/,bend2-exploration.md}
|docs/adr:{0001-task-owned-tool-contracts.md,0002-open-tool-call-recovery.md,0003-persisted-task-lifecycle.md,0004-semantic-ownership-at-runtime-boundaries.md,0005-single-source-configuration-and-transport.md,0006-executable-bend-task-model.md,0007-admit-certified-bend-transitions.md}
|host:{README.md,auth.mjs,cli.mjs,codec.mjs,config.mjs,files.mjs,journal.mjs,kernel.mjs,mcp.mjs,network.mjs,process.mjs,providers.mjs,public/,server.mjs,service.mjs,transport.c}
|host/public:{app.mjs,index.html,style.css}
|scripts:{agents-index.mjs,benchmark.mjs,bootstrap.sh,build.mjs,check.mjs,install-bend.sh,setup-worktree.sh,toolchain.mjs}
|tests-bend:{auth.test.mjs,fixtures/,journal.test.mjs,kernel.test.mjs,process.test.mjs,proof-gate.test.mjs,service-recovery.test.mjs,service.test.mjs,support.mjs}
|tests-bend/fixtures:{catalog.mjs,committed-tool.mjs,mcp.mjs}
```
<!-- END AGENTS_MD_PROJECT_INDEX -->

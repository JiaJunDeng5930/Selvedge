# xtask

<!-- selvedge-package-readme
package: xtask
freshness_commit: f2a0e6aa7f63b0fb8b575fefc5026e0535a7e64f
-->

`xtask` contains repository-local automation that should stay out of production crates.

## Requirement Commands

- `cargo xtask req scan` prints parsed requirement comments, their bindings, and diagnostics.
- `cargo xtask req fmt-agents` regenerates only the AGENTS.md requirement index block from source comments.
- `cargo xtask req check --staged` validates the staged Git snapshot for pre-commit.
- `cargo xtask req check --all` validates the full tracked checkout for CI.
- `cargo xtask req check --base <git-ref>` validates changed Rust hunks against a base ref for CI.
- `cargo xtask readme check-mermaid` renders every package README Mermaid fence.
- `cargo xtask readme check-freshness` checks package README freshness metadata against package-directory changes since the recorded commit, excluding the README file itself.

The requirement registry is in memory for one command invocation. AGENTS.md is the only generated tracked artifact.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([cargo xtask command])
  Parse[Parse command arguments]
  AgentsIndex[Run agents-index update or check]
  Req[Run requirement scan, fmt-agents, or check]
  Readme[Run README Mermaid or freshness check]
  Success[Exit code 0]
  Usage[Exit code 2 with usage]
  Failure[Exit code 1 with diagnostics]

  Start -->|process starts| Parse
  Parse -->|args match agents-index update or check| AgentsIndex
  Parse -->|args match req scan, fmt-agents, or check mode| Req
  Parse -->|args match readme check-mermaid or check-freshness| Readme
  Parse -->|args match no known command shape| Usage
  AgentsIndex -->|index update succeeds or check is fresh| Success
  AgentsIndex -->|filesystem, git, warning collection, or stale check fails| Failure
  Req -->|requirement scan has no diagnostics, fmt succeeds, or check is fresh| Success
  Req -->|diagnostics exist, AGENTS index is stale, git fails, or filesystem fails| Failure
  Readme -->|all package Mermaid diagrams render or all README freshness metadata covers package changes| Success
  Readme -->|metadata is missing, a commit is invalid, a package changed after metadata commit, or Mermaid rendering fails| Failure
```

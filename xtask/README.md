# xtask

<!-- selvedge-package-readme
package: xtask
freshness_commit: 592f95539c225023a2f2d66f8096a3f85ac304ee
-->

`xtask` contains repository-local automation that should stay out of production crates.

## Commands

- `cargo xtask agents-index update` regenerates the AGENTS.md project index.
- `cargo xtask agents-index check` checks that the AGENTS.md project index is current.
- `cargo xtask readme check-mermaid` renders every package README Mermaid fence.
- `cargo xtask readme check-freshness` checks package README freshness metadata against package-directory changes since the recorded commit, excluding the README file itself.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([cargo xtask command])
  Parse[Parse command arguments]
  AgentsIndex[Run agents-index update or check]
  Readme[Run README Mermaid or freshness check]
  Success[Exit code 0]
  Usage[Exit code 2 with usage]
  Failure[Exit code 1 with diagnostics]

  Start -->|process starts| Parse
  Parse -->|args match agents-index update or check| AgentsIndex
  Parse -->|args match readme check-mermaid or check-freshness| Readme
  Parse -->|args match no known command shape| Usage
  AgentsIndex -->|index update succeeds or check is fresh| Success
  AgentsIndex -->|filesystem, git, warning collection, or stale check fails| Failure
  Readme -->|all package Mermaid diagrams render or all README freshness metadata covers package changes| Success
  Readme -->|metadata is missing, a commit is invalid, a package changed after metadata commit, or Mermaid rendering fails| Failure
```

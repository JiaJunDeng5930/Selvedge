# xtask

<!-- selvedge-package-readme
package: xtask
freshness_fingerprint: 056e25277c6b2bc7431754d7d3859715c21eafa3
-->

`xtask` contains repository-local automation that should stay out of production crates.

## Commands

- `cargo xtask agents-index update` regenerates the AGENTS.md project index.
- `cargo xtask agents-index check` checks that the AGENTS.md project index is current.
- `cargo xtask readme check-mermaid` renders every package README Mermaid fence.
- `cargo xtask readme update-freshness` records a history-independent fingerprint of each package's tracked paths and staged blob ids, excluding its README.
- `cargo xtask readme check-freshness` compares each recorded fingerprint with the current Git index.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([cargo xtask command])
  Parse[Parse command arguments]
  AgentsIndex[Run agents-index update or check]
  Readme[Run README Mermaid check or freshness update/check]
  Success[Exit code 0]
  Usage[Exit code 2 with usage]
  Failure[Exit code 1 with diagnostics]

  Start -->|process starts| Parse
  Parse -->|args match agents-index update or check| AgentsIndex
  Parse -->|args match readme update-freshness, check-mermaid, or check-freshness| Readme
  Parse -->|args match no known command shape| Usage
  AgentsIndex -->|index update succeeds or check is fresh| Success
  AgentsIndex -->|filesystem, git, warning collection, or stale check fails| Failure
  Readme -->|update writes fingerprints, diagrams render, or recorded fingerprints match| Success
  Readme -->|metadata, Git index inspection, file writing, fingerprint comparison, or Mermaid rendering fails| Failure
```

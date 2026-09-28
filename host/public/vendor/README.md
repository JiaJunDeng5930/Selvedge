# Pinned browser dependencies

The Markdown dependencies below are unmodified package files, renamed for local ES-module serving. They
are included in the repository so the web client needs neither a CDN nor a
runtime package installation. `manifest.json` records package versions, npm
tarball integrity, original paths and SHA-256 hashes of the shipped files.
`node scripts/check-web-vendor.mjs` checks the latter, not the semantics of the
dependencies. The adjacent license files are part of each dependency.
Git preserves their original bytes, including upstream line endings and whitespace;
only these copied sources/licenses are excluded from project whitespace checks.

| Package | Version | Use |
| --- | --- | --- |
| `streaming-markdown` | 0.2.15 | Incremental token parser; Selvedge supplies its own safe DOM sink |
| `@highlightjs/cdn-assets` | 11.12.0 | Known-language highlighting in the formatter worker |
| `katex` | 0.18.9 | MathML generation in the formatter worker; no fonts or HTML layout dependency |

Sources: https://github.com/thetarnav/streaming-markdown,
https://github.com/highlightjs/cdn-release, https://github.com/KaTeX/KaTeX.

To reproduce the copies, install these exact versions into an ignored temporary
directory with `npm install --ignore-scripts --save-exact`, verify the lockfile's
tarball integrity against this manifest, then copy each listed `source` path from
its package to its `file` path here. No minifier, bundler, patch or source transform
is applied. Recompute the file hashes and compare them before replacing anything.
Dependency upgrades require a new manifest and the browser/security regressions.

Of these Markdown dependencies, only the streaming parser loads with the page.
Formatting libraries are lazy imports in a worker. Math uses native MathML.

## Installed Codex Desktop source

`desktop-source.json` separately records `openai-codex-electron` 26.917.71314.
These files are not npm package copies. `desktop-ui.mjs` is the actual styled
menu implementation and its React/ReactDOM dependencies, bundled from verified
installed sources. It retains the upstream legal notices present in those
bundles. This record does not assert an additional redistribution license for
the desktop application.

`desktop-scroll.mjs` contains unchanged source callback bodies and helpers in a
small DOM-lifetime adapter. `desktop.css` scopes the original stylesheet to
transplanted components and excludes every font face. `desktop-tokens.css`
contains selected original theme rules, without global element/Markdown rules.
No font files or complete application bundle are included.

`scripts/import-desktop.mjs` reproduces the four artifacts byte-for-byte using
the pinned archive members and esbuild version. Source ranges, transformations,
input/output hashes and instructions are in the source manifest and
`scripts/desktop/README.md`. The normal vendor check validates both manifests;
it requires neither an installed desktop application nor network access.

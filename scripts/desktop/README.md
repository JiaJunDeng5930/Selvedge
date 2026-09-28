# Installed desktop source import

`../import-desktop.mjs` reproduces the browser files recorded in
`../../host/public/vendor/desktop-source.json`. It accepts the installed
`openai-codex-electron` archive, not a launcher with a similar name. The input
member hashes, package version and output hashes must all match.

`entry.mjs.in` selects the actual styled menu components, React and ReactDOM
from the desktop bundle. Two private ReactDOM factory bindings are exported;
their implementations are unchanged. The pinned bundler removes unrelated
application code. The finished browser module must have no external imports.

`scroll.mjs.in` supplies the DOM/ref lifetime for the original scroll callbacks.
The importer replaces source markers with exact, hash-checked source slices.
It does not rewrite their conditionals, calculations, event handling or timing.
The native cursor owns explicit history paging, so automatic history retrieval
and unsupported response spacers are not supplied to this adapter.

The scoped stylesheet contains the original rules with font faces removed;
root and host selectors are rebound to the component's scope. Theme tokens are
selected original rules, not a second hand-maintained palette. Neither global
Markdown element rules nor fonts are installed. The existing incremental
Markdown renderer and its dependencies are independent of this import.

Ordinary checks verify committed output hashes without accessing an installed
application. To reproduce into a temporary directory:

```sh
node scripts/import-desktop.mjs \
  --asar /Applications/ChatGPT.app/Contents/Resources/app.asar \
  --esbuild /path/to/esbuild-0.25.10 \
  --out .workpad/reproduced-desktop
```

The importer fails on a different source version instead of silently accepting
changed offsets or fetching a newer package. Source ranges use UTF-16 string
offsets in decoded JavaScript/CSS, not byte offsets in the ASAR archive.

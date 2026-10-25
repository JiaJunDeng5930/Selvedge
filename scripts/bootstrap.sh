#!/usr/bin/env bash
set -euo pipefail
# Standard Rocq extraction and MetaRocq Template are separate pinned dependencies.
command -v bun >/dev/null
# DEFENSE: Reject unsupported Bun before installing any dependencies.
bun -e 'const pins = await Bun.file("toolchain.json").json(); if (!Bun.semver.satisfies(Bun.version, `>=${pins.bun}`)) throw new Error(`Bun ${pins.bun} or later is required by toolchain.json`);'
command -v opam >/dev/null
opam install --yes dune.3.23.1 ocaml-base-compiler.4.14.2 rocq-core.9.2.0 rocq-stdlib.9.2.0 rocq-metarocq-template.1.5.1+9.2 js_of_ocaml.6.4.1 zarith.1.14
bun install --frozen-lockfile
mkdir -p .build/deps
if [ ! -d .build/deps/zarith_stubs_js ]; then
  opam source zarith_stubs_js.v0.16.1 --dir=.build/deps/zarith_stubs_js
fi

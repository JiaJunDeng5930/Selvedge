# Record update dependency

Upstream: <https://github.com/tchajed/coq-record-update>

Pinned commit: `1dd231db87451479043a3812dbdbd9658657ff7c`.

License: MIT, retained verbatim in `LICENSE`.

Only imports beginning `From RecordUpdate Require` are changed to
`From Selvedge.ThirdParty.RecordUpdate Require` so the project's ordinary
Rocq dependency graph checks this dependency. The four source files otherwise
retain the upstream implementation. Rocq 9.2 checks all four modules, despite
the upstream opam package's narrower published Stdlib constraint.

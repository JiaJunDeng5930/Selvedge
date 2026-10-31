# Requirements and design reasons

These Gallina sources explain the current user and engineering goals, select the
existing contracts that express them, and prove any missing connection to the
operation the product executes. Read the relevant requirement before changing a
public contract. The domain definitions, computations and their proofs remain
under `theories/`; their meaning is referenced here rather than reimplemented.

Keep a reason next to the contract it explains. Use an existing theorem directly
when it already states the requirement. Add a proposition or derivation when the
goal requires a relationship that is not yet expressed. Requirements and
implementation choices depend on current goals and observations; old designs
and historical alternatives do not create additional requirements.

For an extension, first use the existing controlled constructors and composition
operations. Their quantified contracts supply the shared properties. Prove only
the additional behavior required by the extension. `Engineering.v` covers local
declaration extension without a list of all possible owners.

## Checking and dependency direction

The normal build discovers every `.v` file in this directory and checks its
assumptions. A focused check uses the existing module option:

```sh
bun scripts/build.mjs --module Requirements.Engineering
```

`requirements/` has the logical root `SelvedgeRequirements`. Its compilation can
import `Selvedge` and other requirements. Production modules and extraction only
receive the `Selvedge` load path, so they cannot depend on this directory.
Changing a requirement therefore does not invalidate an unchanged runtime
module. No requirement registry or per-module build list needs updating when a
new source is added.

Physical behavior is checked at the public boundary where it occurs. Permanent
tests exercise complete public operations and express user or engineering
requirements. Properties already guaranteed by construction or proof are not
repeated in tests. Temporary experiments belong in `.workpad/`.

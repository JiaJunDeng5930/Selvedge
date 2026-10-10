# Documents

Builds rendered document content from semantic sources and defines its presentation requirements.

Start with [MODEL.bend](MODEL.bend), [SOURCE.bend](SOURCE.bend) and
[CONTRACT.bend](CONTRACT.bend). Follow [source-contract.bend](source-contract.bend)
for source validity, [render-contract.bend](render-contract.bend) for rendered
observations. `CONTRACT.bend` owns content presentation and composes these
boundaries. Source-policy validation belongs to `SOURCE.bend`, so production
clients do not import a law-bearing contract merely to validate source values.

The corresponding evidence is organized in [source-proof.bend](source-proof.bend),
[render-proof.bend](render-proof.bend) and [content-proof.bend](content-proof.bend).
[PROOF.bend](PROOF.bend) retains document dialog and realization evidence;
[presentation-proof.bend](presentation-proof.bend) remains an independent provider
for cross-concept clients. The repository [PROOF.bend](../../PROOF.bend) imports all
production providers. Read observations and intended updates before private
representations; contracts define the obligations rather than this reading guide.

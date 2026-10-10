# Semantic presentation

Produces semantic page content and binds presentation composition and capabilities to the application.

Start with [MODEL.bend](MODEL.bend) for scene vocabulary and [SURFACE.bend](SURFACE.bend)
for nodes, gestures and surface vocabulary. [VIEW.bend](VIEW.bend) generates scenes;
[PROGRAM.bend](PROGRAM.bend) realizes surfaces and their interaction. These public
vocabularies remain independent of the computations that consume them.

[CONTRACT.bend](CONTRACT.bend) groups the presentation obligations by complete
responsibility. [scene-proof.bend](scene-proof.bend) provides semantic scene and
capability evidence; [interaction-proof.bend](interaction-proof.bend) provides
surface composition and interaction evidence. [PROOF.bend](PROOF.bend) retains
the whole-interface evidence needed by its clients. The repository
[PROOF.bend](../../PROOF.bend) imports all production providers.

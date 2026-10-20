# Conversation search

Start with `MODEL.bend`, `CONTRACT.bend` and `PROOF.bend`.

`MODEL.bend` owns the transient search form and its bounded submitted result.
`submit` calls the same harness query used by agents. Rendering reads the cached
result, so stream publication and layout measurement never repeat history scans.
Project and Work filters intersect; changing either filter or the keyword clears
the previous result. A hit retains the original task and history message index.

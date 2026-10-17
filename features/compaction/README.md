# Automatic context compaction

Owns the independent measurement lease, background compaction operation and idle
maintenance watermark. Task execution phases remain owned by the task component.

Start with `MODEL.bend`, `SPEC.bend`, `PROGRAM.bend`, `CONTRACT.bend` and
`PROOF.bend`. Complete source history remains in the task. A compaction operation
captures a source prefix; a generated result is adopted after measuring the
complete replacement and the current suffix for the selected target. A supplied
summary is recorded locally; the next model request retains its normal budget
check.

The host reports clocks and request measurements and executes committed calls.
The Bend transition chooses thresholds, waiting, retries and adoption. A model
call identity is consumed once; a later chunk receives a new identity.

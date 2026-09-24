# Bend support library

`json.bend` handles the generic, lossless JSON value boundary. Numbers keep their
source lexemes. The host sends postfix tokens; only this module constructs JSON
values from those tokens. Rendering is explicitly bounded and fails on exhaustion.

`theory.bend` contains reusable list and transition-system results. Domain code
uses the same list operations and replay function that these results describe.

Neither module performs effects or contains task-specific policy.

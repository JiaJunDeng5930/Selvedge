# ADR 0057: Exact retry delays at the IO boundary

Status: Accepted

## Context

Provider requests and the reasoning evaluator interpret the same HTTP Retry-After header. Keeping separate JavaScript and Gallina interpretations duplicated decimal parsing, calendar rules and waiting limits. The JavaScript evaluator also passed exact fractional JSON values to native timers, which accept ordinary integral millisecond counts rather than the exact-number representation.

Retry-After is a minimum wait. Truncating a fractional delay can retry too early, while rounding before checking the configured cap can hide a value above that cap.

## Decision

Both policies use the shared Gallina RetryAfter parser and exact decimal delay representation. Backend and evaluator retain their distinct attempt, floor and cap policies. They compare exact delays with those limits before projecting an admitted delay to the least integral millisecond that is at least the requested wait.

The physical host supplies the raw header and current time, then executes the extracted retry plan. It does not independently interpret dates, decimal delays or retry limits. General timer theorems establish the minimum-wait, least-integer and integral-cap properties; public Api theorems connect those properties to the emitted plans.

## Consequences

This intentionally corrects early fractional retries and native timer failures for exact fractional numbers. HTTP clocks, upstream header values, timer scheduling and the extraction toolchain remain external trust obligations; a checked delay plan does not prove that a physical timer fires at its requested instant.

The obsolete two-digit HTTP-date form retains the previous fixed 1950–2049 interpretation. Its receipt-dependent fifty-year window is a documented known limitation. Contemporary four-digit HTTP dates use the shared calendar interpretation.

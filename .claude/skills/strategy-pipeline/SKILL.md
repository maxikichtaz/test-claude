---
name: strategy-pipeline
description: Run the full pipeline for a trading idea - spec, Python backtest, review, EA implementation, MT5 validation by the user. Use when the user brings a new ICT transcript/idea or a filter to test on an EA.
---
# Strategy pipeline

Pipeline (each step is a subagent; stop at every gate marked HUMAN):

1. **strategy-analyst** -> rule spec section in `ICT_NOTES.md`.
   HUMAN: the user confirms the ambiguities' interpretations (skip if none are core rules).
2. **backtester** -> `tools/backtest_<name>.py` + results in `ICT_NOTES.md`.
   If the CSV is missing: ask the user for it and stop.
3. **risk-reviewer** on the backtest.
   - STOP -> log "not pursued" + reason in `ICT_NOTES.md`, end.
   - FIX  -> back to backtester (max 2 rounds, then ask the user).
   - GO   -> next step.
   HUMAN: the user decides whether it is worth an EA (or a new EA version).
4. **mql5-developer** -> EA change, version bump.
5. **risk-reviewer** on the EA diff (parity + safety). FIX -> back to step 4 (max 2 rounds).
6. HUMAN: the user runs the MT5 Strategy Tester and pastes the report.
   **risk-reviewer** compares with Python; the result is logged in `ICT_NOTES.md`.
7. Commit (`EA vX.YY: ...`) and push only when the user asks.

Hand-offs are files, not chat: the spec and results live in `ICT_NOTES.md`, the code in
`tools/` and `*.mq5`. Each subagent prompt must name the section/file it works from.

The human always decides: interpretation of core rules, going from backtest to EA,
and anything touching a live account.

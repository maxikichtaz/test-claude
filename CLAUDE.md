# test-claude: ICT strategies -> Python backtest -> MT5 Expert Advisors

## Files
- `ICT_NOTES.md`: rules taken from ICT transcripts + every backtest/MT5 result (the project log).
- `tools/backtest_*.py`: Python backtests on MT5 M5 CSV exports (`time,open,high,low,close,...,spread`).
  The CSV (e.g. `NAS100_M5.csv`) is NOT in the repo: the user exports it from MT5.
- `*.mq5`: Expert Advisors. `#property version` is bumped on every behaviour change.

## Conventions (all agents)
- Broker server time = New York + 7h. Always state times as "NY" or "server".
- Backtests are conservative: if SL and TP are hit in the same M5 bar, the SL is hit first.
  Spread comes from the CSV. No lookahead: only data closed before the decision bar.
- Results are always reported in R with: trades, win %, PF, total R, R without the 3 best
  trades, max drawdown, max losing streak, and a split by year (or in/out of sample).
- A filter or parameter is kept only if it helps in BOTH halves of the data and the result is not
  fragile to a small change of its value. Otherwise: "not added" + the reason, in ICT_NOTES.md.
- The Python model and the EA must implement the same rules. A version is validated when the
  MT5 Strategy Tester result (run by the user) matches the Python model within a few trades.
- Inputs default to the validated settings; new features default to OFF.
- Commit messages: `EA vX.YY: <change>` for EA changes.
- Claude never runs MT5 and never trades a live account: the user runs the Strategy Tester and
  decides what goes live.

# ICT notes (from transcripts provided by the user)

## OTE series 2020 - episode 1 (Optimal Trade Entry, New York session)
- Mark previous day high (PDH) and low (PDL) on the daily chart.
- PDH taken -> look for a BUY OTE. PDL taken -> look for a SELL OTE. Trade WITH the break.
- Time window: 08:30 - 11:00 New York only (8:30 news, 11:00 London close). Nothing outside.
- Chart: M5.
- Range (buy): short-term low -> short-term high of the leg that broke PDH. Mirror for sells.
- Entry: limit at 62% retracement (OTE zone 62% - 79%, sweet spot 70.5%), prefer a round
  institutional level nearby (00 / 20 / 50 / 80).
- Stop: beyond the range extreme (below the low for a buy).
- TP1: -0.5 extension (only if >= 15 pips in forex) -> stop to range midpoint.
- TP2: -1.0 extension, rounded down to the nearest 10-pip level -> stop to entry + 2-3 pips.
- Final: -2.0 extension; take a partial at 100 pips if it comes first. Trail stop under a
  structure low, not too tight.
- No minimum risk/reward. Discipline: if the setup is not in the window, no trade.

## Backtest on NAS100 M5 (May 2025 - Sep 2026), see tools/backtest_ote.py
- Server time = New York + 7h for this broker.
- OTE 62%, all days: 92 trades, 36% win, PF 1.16, +9.5R, ~0R without the 3 best trades.
- 70.5% and 79% entries: negative. Wednesday only: ~flat.
- Reclaim EA (WednesdayPDHPDL) with NY 07:00-10:00 killzone: 41 trades, PF 2.29, +35R, but
  ~0R without its 3 best trades (tools/backtest_killzones.py).

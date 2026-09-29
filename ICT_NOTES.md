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

## ICT reviews: Opening Range Gap, First Presented FVG, Judas swing (2 videos)
- Opening Range Gap (ORG): previous RTH close (16:14/16:15 NY) vs 09:30 NY open. Gap up =
  premium (expect shorts back into it), gap down = discount (longs). Midpoint = "consequent
  encroachment" (CE), said to be reached ~70% of the time by 10:00 NY.
- New York midnight open: best shorts above it (if bearish), best longs below it, until 11:00.
- Judas swing 09:30-10:00: false run against the bias through liquidity (London high/low,
  previous NY session high/low), then market structure shift + displacement FVG -> entry.
  Stop above the CE of the higher FVG when there are two ("two rule").
- First Presented FVG (FPFVG): first FVG after 09:30. FPFVG with displacement (its run takes a
  high/low) matters more. Reflection FVG: first opposite FVG after the FPFVG. Extend them into
  the following days; watch bodies vs their CE.
- Post-holiday days: small size, low-hanging-fruit targets.

## Backtest on NAS100 CFD M5 (tools/backtest_org_judas.py)
- ORG CE reached: 53% by 10:00 NY, 66% by 11:00, 75% by 16:00 (348 days).
- Judas swing + FVG entry toward the gap CE: all variants negative (best: with MSS filter,
  74 trades, PF 0.81, -6R). Stop at FVG edge: very negative. 09:30 market entry toward CE: negative.
- Caveat: CFD trades overnight so the "gap" is synthetic; ICT uses NQ/ES futures RTH on M1.

## WednesdayPDHPDL v1.03 (reclaim + NY killzone 07:00-10:00 NY) - filters tested
- "Fresh reclaim" filter (entry only right after the sweep): WORSE (+27.6R vs +35R), not added.
- Min SL distance = 0.15 x previous day range: removes unrealistic tiny stops, less outlier-driven.
  - Wednesday: 38 trades, PF 1.77, +18.5R, maxDD 4.9% (2025 flat, 2026 +17R)
  - Tue-Thu:  104 trades, PF 1.60, +40.1R, +22R without top 3, maxDD 12.2%, both years positive
  - Mon-Fri:  164 trades, PF 1.42, +43.6R, maxDD 19.8%, 22-loss streak in 2026

## MT5 results reported by the user
- v1.03 Wednesday, Jan-Sep 2026 (99% quality): 15 trades, 40% win, PF 2.38, +13.4%, DD 4.9%
  -> matches the Python model (16 trades, PF 2.92, DD 4.9%).
- v1.03 Wednesday, long history (~5 years, 45% history quality): 123 trades, 29% win, PF 1.16,
  +14.8%, DD 20.3%, 11-loss streak. Trades closed on Wednesday lose; closed on Thursday win.
  -> edge much weaker over the long history.

## v1.04: flat before the weekend (Friday 17:00 server, configurable)
- Python (May 2025 - Sep 2026): no effect on Wednesday only; Tue-Thu +40.1R -> +31.6R (Thursday
  trades cut short).
- v1.04 Wednesday, ~Apr 2025 - Sep 2026 (100% quality): 43 trades, 39.5% win, PF 1.69, +19.8%,
  DD 5.3% -> matches the Python model again (38 trades, PF 1.77, +19.2%).

## v1.05: max SL distance filter (MaxSLFraction, default 0.30 x previous day range)
- Feature study (2025 vs 2026 split): trades with SL between 0.15 and 0.25 x range have PF ~2.4-2.8
  in both years; SL > 0.25 x range is flat or losing. Deep sweeps (> 0.5 x range) lose.
- Trend filters (previous day direction, SMA20) and entry hour: no stable effect, not added.
- Results (min 0.15, max SL x, Friday close 17h):
  - Wednesday max 0.30: 23 trades, PF 2.38, +20.7R, DD 3.9% (but max 0.20 -> PF 0.88: fragile)
  - Tue-Thu  max 0.30: 60 trades, PF 1.92, +37.8R, DD 9.4%, 2025 PF 1.62 / 2026 PF 2.22
  - Tue-Thu  max 0.25: 53 trades, PF 2.12, +39.8R, DD 8.5%, 2025 PF 1.80 / 2026 PF 2.47
- MT5 Z-score = runs test on win/loss sequence (dependence between trades), not profitability.
  Near 0 = trades independent, which is what we want; do not optimise it.

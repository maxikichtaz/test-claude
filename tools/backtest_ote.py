# Backtest of the ICT OTE New York model (ICT OTE series, episode 1) on MT5 M5 CSV data.
#
# Rules:
#   - Bias: first of PDH / PDL taken since New York midnight -> BUY above PDH, SELL below PDL
#   - Range (buy): lowest low since NY midnight up to the highest high (mirror for sell)
#   - Limit entry at the EntryFib retracement of the range, only 08:30-11:00 New York
#   - SL beyond the range extreme; TPs at -0.5 / -1.0 / -2.0 extensions, 1/3 each
#   - After TP1 the stop moves to the range midpoint, after TP2 to entry (never loosened)
#   - Optional flat at 16:00 New York
# Server time = New York + 7h (checked: cash open at 16:30 server). Spread from the CSV.
# Conservative: if SL and TP are both inside the same M5 bar, the SL is assumed first.
#
# Usage: python3 tools/backtest_ote.py NAS100_M5.csv
import csv, datetime as D, sys, collections

F = sys.argv[1] if len(sys.argv) > 1 else "NAS100_M5.csv"
PT = 0.01
NY_OFFSET = 7            # server hour = NY hour + 7
WIN_START = (8, 30)      # New York
WIN_END = (11, 0)
EOD = (16, 0)

bars = []
for r in csv.DictReader(open(F)):
    t = D.datetime.strptime(r['time'], "%Y.%m.%d %H:%M")
    bars.append((t, float(r['open']), float(r['high']), float(r['low']),
                 float(r['close']), int(r['spread']) * PT))

# Server daily high / low (same as iHigh/iLow on D1 in MT5)
days = collections.OrderedDict()
for b in bars:
    d = b[0].date()
    if d not in days:
        days[d] = [b[2], b[3]]
    else:
        days[d][0] = max(days[d][0], b[2]); days[d][1] = min(days[d][1], b[3])
dlist = list(days)
prev = {dlist[i]: days[dlist[i - 1]] for i in range(1, len(dlist))}


def srv(d, hm):
    return D.datetime.combine(d, D.time(0)) + D.timedelta(hours=hm[0] + NY_OFFSET, minutes=hm[1])


def run(entry_fib=0.62, wednesday_only=False, eod=True, start=None, end=None):
    trades = []
    i = 0
    n = len(bars)
    for d in dlist:
        if d not in prev or d.weekday() > 4: continue
        if wednesday_only and d.weekday() != 2: continue
        if start and d < start or end and d > end: continue
        pdh, pdl = prev[d]
        ny0, ws, we, ee = srv(d, (0, 0)), srv(d, WIN_START), srv(d, WIN_END), srv(d, EOD)
        while i < n and bars[i][0] < ny0: i += 1
        j = i
        side = None; hi = lo = None; ext_lo = ext_hi = None
        valid = True; filled = None
        # ---- build setup and look for fill ----
        while j < n and bars[j][0] < we:
            t, o, h, l, c, sp = bars[j]
            if side is None:
                hi = h if hi is None else max(hi, h)
                lo = l if lo is None else min(lo, l)
                if hi > pdh:
                    side = 'B'; rh = hi; rl = lo   # low before/at the high
                elif lo < pdl:
                    side = 'S'; rh = hi; rl = lo
                j += 1; continue
            if not valid: break
            rng = rh - rl
            if t >= ws and rng > 0:
                if side == 'B':
                    entry = rh - entry_fib * rng
                    if l + sp <= entry:                      # ask touched the limit
                        filled = (j, min(entry, o + sp), rl, rh); break
                else:
                    entry = rl + entry_fib * rng
                    if h >= entry:
                        filled = (j, max(entry, o), rl, rh); break
            # update / invalidate the range (after the fill check)
            if side == 'B':
                if h > rh: rh = h
                if l < rl: valid = False
            else:
                if l < rl: rl = l
                if h > rh: valid = False
            j += 1
        if not filled: continue
        k, entry, rl, rh = filled
        rng = rh - rl
        if side == 'B':
            sl = rl; tps = [rh + 0.5 * rng, rh + 1.0 * rng, rh + 2.0 * rng]
        else:
            sl = rh; tps = [rl - 0.5 * rng, rl - 1.0 * rng, rl - 2.0 * rng]
        risk = abs(entry - sl)
        mid = (rh + rl) / 2
        left = 3; R = 0.0; tp_i = 0; exit_t = None
        for m in range(k, n):
            t, o, h, l, c, sp = bars[m]
            if eod and t >= ee:
                px = o if side == 'B' else o + sp
                R += left * ((px - entry) if side == 'B' else (entry - px)) / risk / 3
                left = 0; exit_t = t; break
            # stop first (conservative)
            if side == 'B' and l <= sl or side == 'S' and h + sp >= sl:
                R += left * ((sl - entry) if side == 'B' else (entry - sl)) / risk / 3
                left = 0; exit_t = t; break
            if m == k: continue                      # no TP on the fill bar
            while tp_i < 3 and (side == 'B' and h >= tps[tp_i] or side == 'S' and l + sp <= tps[tp_i]):
                R += abs(tps[tp_i] - entry) / risk / 3
                left -= 1; tp_i += 1
                new_sl = mid if tp_i == 1 else entry
                sl = max(sl, new_sl) if side == 'B' else min(sl, new_sl)
            if left == 0: exit_t = t; break
        if left: continue                            # data ended
        trades.append(dict(t=bars[k][0], side=side, R=R, risk=risk, tps=tp_i, exit=exit_t, wd=d.weekday()))
        i = m
    return trades


def stats(name, tr):
    if not tr: print(f"{name:34s} no trades"); return
    bal = 10000; peak = bal; mdd = 0; st = 0; mst = 0
    for x in tr:
        bal += bal * 0.01 * x['R']; peak = max(peak, bal); mdd = max(mdd, (peak - bal) / peak)
        st = st + 1 if x['R'] < 0 else 0; mst = max(mst, st)
    w = [x for x in tr if x['R'] > 0]
    gp = sum(x['R'] for x in w); gl = -sum(x['R'] for x in tr if x['R'] < 0)
    Rs = sorted((x['R'] for x in tr), reverse=True)
    L = [x for x in tr if x['side'] == 'B']; S = [x for x in tr if x['side'] == 'S']
    wr = lambda a: f"{sum(1 for x in a if x['R'] > 0)}/{len(a)}"
    print(f"{name:34s} n={len(tr):3d} win={len(w)/len(tr)*100:5.1f}% PF={gp/gl if gl else 99:5.2f} "
          f"sumR={sum(Rs):+6.1f} noTop3={sum(Rs[3:]):+6.1f} net={(bal/10000-1)*100:+6.1f}% "
          f"maxDD={mdd*100:5.1f}% lossStreak={mst} longs={wr(L)} shorts={wr(S)}")


if __name__ == '__main__':
    periods = {'FULL': (None, None),
               '2025 (May-Dec)': (None, D.date(2025, 12, 31)),
               '2026 (Jan-Sep)': (D.date(2026, 1, 1), None)}
    for p, (a, b) in periods.items():
        print("==", p)
        for fib in (0.62, 0.705, 0.79):
            stats(f"all days fib={fib}", run(fib, False, True, a, b))
        stats("wednesday only fib=0.62", run(0.62, True, True, a, b))
        stats("all days fib=0.62 no EOD close", run(0.62, False, False, a, b))

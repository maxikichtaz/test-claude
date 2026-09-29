# Backtest of the ICT "NY AM Judas swing + Opening Range Gap" model on MT5 M5 CSV data.
#
# Rules (from ICT reviews: Opening Range Gap, New York midnight open, Judas swing, FVG):
#   - Opening Range Gap (ORG): previous day close at 16:15 NY vs 09:30 NY open.
#     Gap up (premium)  -> bearish bias, look for shorts back into the gap.
#     Gap down (discount) -> bullish bias, look for longs back into the gap.
#   - Judas swing (09:30 onward): price runs AGAINST the bias, above the New York
#     midnight open (premium) and through a liquidity pool (pre-market / London high).
#   - Then a displacement leaves a fair value gap (FVG) in the bias direction.
#   - Entry: limit at the FVG edge, stop beyond the Judas extreme (or the FVG far edge).
#   - Target: gap consequent encroachment (50%) or full gap fill.
#   - Entries only until 11:00 NY, flat at 16:00 NY.
# Server time = New York + 7h. Spread from the CSV. SL first if SL and TP in one M5 bar.
#
# Usage: python3 tools/backtest_org_judas.py NAS100_M5.csv
import csv, datetime as D, sys, collections

F = sys.argv[1] if len(sys.argv) > 1 else "NAS100_M5.csv"
PT = 0.01
NY = 7

bars = []
for r in csv.DictReader(open(F)):
    t = D.datetime.strptime(r['time'], "%Y.%m.%d %H:%M")
    bars.append((t, float(r['open']), float(r['high']), float(r['low']),
                 float(r['close']), int(r['spread']) * PT))
idx = {b[0]: i for i, b in enumerate(bars)}
dates = sorted({b[0].date() for b in bars})


def at(d, h, m):                       # server datetime for NY time h:m on server date d
    return D.datetime.combine(d, D.time(0)) + D.timedelta(hours=h + NY, minutes=m)


def hl(t0, t1):
    hi = lo = None
    i = idx.get(t0)
    if i is None: return None, None
    while i < len(bars) and bars[i][0] < t1:
        hi = bars[i][2] if hi is None else max(hi, bars[i][2])
        lo = bars[i][3] if lo is None else min(lo, bars[i][3])
        i += 1
    return hi, lo


def run(liq='pre', stop='judas', target='ce', min_gap=0.0, need_mss=False, start=None, end=None):
    trades = []
    prev_d = None
    for d in dates:
        if d.weekday() > 4: continue
        pd_ = prev_d; prev_d = d
        if pd_ is None: continue
        if start and d < start or end and d > end: continue
        i_close = idx.get(at(pd_, 16, 10))          # bar closing at 16:15 NY
        i_open = idx.get(at(d, 9, 30))
        i_mid = idx.get(at(d, 0, 0))
        if i_close is None or i_open is None or i_mid is None: continue
        prev_close = bars[i_close][4]
        o930 = bars[i_open][1]
        midnight = bars[i_mid][1]
        gap = o930 - prev_close
        if abs(gap) < min_gap * o930 or gap == 0: continue
        bias = -1 if gap > 0 else 1                   # trade back into the gap
        tgt = (o930 + prev_close) / 2 if target == 'ce' else prev_close
        if liq == 'pre':
            lh, ll = hl(at(d, 7, 0), at(d, 9, 30))
        elif liq == 'lon':
            lh, ll = hl(at(d, 2, 0), at(d, 5, 0))
        else:
            lh, ll = (o930, o930)
        if lh is None: continue
        t_end, t_eod = at(d, 11, 0), at(d, 16, 0)

        # ---- find Judas swing + FVG + fill ----
        ext = None; ext_i = None; fvg = None; fill = None
        i = i_open
        while i < len(bars) and bars[i][0] < t_end:
            t, o, h, l, c, sp = bars[i]
            # pending FVG limit fill
            if fvg:
                entry, far, sl0 = fvg
                if bias == -1 and h >= entry:
                    fill = (i, max(entry, o), sl0); break
                if bias == 1 and l + sp <= entry:
                    fill = (i, min(entry, o + sp), sl0); break
            # track the Judas extreme (a new extreme cancels the FVG)
            if bias == -1 and (ext is None or h > ext):
                ext, ext_i, fvg = h, i, None
            if bias == 1 and (ext is None or l < ext):
                ext, ext_i, fvg = l, i, None
            swept = (ext > lh and ext > midnight) if bias == -1 else (ext < ll and ext < midnight)
            if swept and i - ext_i >= 1 and i >= 2:
                b0, b1, b2 = bars[i - 2], bars[i - 1], bars[i]
                if bias == -1 and b0[3] > b2[2] and b1[4] < b1[1]:          # bearish FVG
                    mss_ok = not need_mss or b2[3] < min(x[3] for x in bars[max(i_open, ext_i - 3):ext_i + 1])
                    entry = b2[2]
                    if mss_ok and entry > tgt:
                        sl0 = ext if stop == 'judas' else b0[3]
                        fvg = (entry, b0[3], sl0)
                if bias == 1 and b0[2] < b2[3] and b1[4] > b1[1]:           # bullish FVG
                    mss_ok = not need_mss or b2[2] > max(x[2] for x in bars[max(i_open, ext_i - 3):ext_i + 1])
                    entry = b2[3]
                    if mss_ok and entry < tgt:
                        sl0 = ext if stop == 'judas' else b0[2]
                        fvg = (entry, b0[2], sl0)
            i += 1
        if not fill: continue
        k, entry, sl = fill
        risk = abs(entry - sl)
        if risk <= 0: continue
        R = None
        for m in range(k, len(bars)):
            t, o, h, l, c, sp = bars[m]
            if t >= t_eod:
                px = o if bias == 1 else o + sp
                R = (px - entry) / risk * bias; break
            if bias == -1 and h + sp >= sl or bias == 1 and l <= sl:
                R = -1.0; break
            if m > k and (bias == -1 and l + sp <= tgt or bias == 1 and h >= tgt):
                R = abs(tgt - entry) / risk; break
        if R is None: continue
        trades.append(dict(t=bars[k][0], side='B' if bias == 1 else 'S', R=R, rr=abs(tgt - entry) / risk))
    return trades


def stats(name, tr):
    if not tr: print(f"{name:40s} no trades"); return
    bal = 10000; peak = bal; mdd = 0; st = 0; mst = 0
    for x in tr:
        bal += bal * 0.01 * x['R']; peak = max(peak, bal); mdd = max(mdd, (peak - bal) / peak)
        st = st + 1 if x['R'] < 0 else 0; mst = max(mst, st)
    w = [x for x in tr if x['R'] > 0]
    gp = sum(x['R'] for x in w); gl = -sum(x['R'] for x in tr if x['R'] < 0)
    Rs = sorted((x['R'] for x in tr), reverse=True)
    L = [x for x in tr if x['side'] == 'B']; S = [x for x in tr if x['side'] == 'S']
    wr = lambda a: f"{sum(1 for x in a if x['R'] > 0)}/{len(a)}"
    print(f"{name:40s} n={len(tr):3d} win={len(w)/len(tr)*100:5.1f}% PF={gp/gl if gl else 99:5.2f} "
          f"sumR={sum(Rs):+6.1f} noTop3={sum(Rs[3:]):+6.1f} net={(bal/10000-1)*100:+6.1f}% "
          f"maxDD={mdd*100:5.1f}% streak={mst} L={wr(L)} S={wr(S)}")


if __name__ == '__main__':
    periods = {'FULL': (None, None), '2025': (None, D.date(2025, 12, 31)), '2026': (D.date(2026, 1, 1), None)}
    for p, (a, b) in periods.items():
        print("==", p)
        for liq in ('pre', 'lon', 'none'):
            for stop in ('judas', 'fvg'):
                stats(f"liq={liq} stop={stop} tgt=ce", run(liq, stop, 'ce', 0, False, a, b))
        stats("liq=pre stop=judas tgt=full", run('pre', 'judas', 'full', 0, False, a, b))
        stats("liq=pre stop=judas tgt=ce MSS", run('pre', 'judas', 'ce', 0, True, a, b))
        stats("liq=pre stop=judas tgt=ce gap>0.3%", run('pre', 'judas', 'ce', 0.003, False, a, b))

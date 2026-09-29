# Backtest of WednesdayPDHPDL logic on NAS100 M5 data (server time = NY+7)
import csv, datetime as D, sys, collections
F=sys.argv[1] if len(sys.argv)>1 else "NAS100_M5.csv"
PT=0.01
bars=[]
for r in csv.DictReader(open(F)):
    t=D.datetime.strptime(r['time'],"%Y.%m.%d %H:%M")
    bars.append((t,float(r['open']),float(r['high']),float(r['low']),float(r['close']),int(r['spread'])*PT))

# daily high/low per server date
days=collections.OrderedDict()
for b in bars:
    d=b[0].date()
    if d not in days: days[d]=[b[2],b[3]]
    else: days[d][0]=max(days[d][0],b[2]); days[d][1]=min(days[d][1],b[3])
dlist=list(days)
prev={dlist[i]:days[dlist[i-1]] for i in range(1,len(dlist))}

# M15 bars built from M5
m15=collections.OrderedDict()
for b in bars:
    t=b[0].replace(minute=b[0].minute//15*15)
    if t not in m15: m15[t]=[b[1],b[2],b[3],b[4]]
    else:
        m=m15[t]; m[1]=max(m[1],b[2]); m[2]=min(m[2],b[3]); m[3]=b[4]
m15_times=list(m15)

KZ={
 'none':   None,
 'london': [(9*60,12*60)],                 # 02:00-05:00 NY
 'nyam':   [(14*60,17*60)],                # 07:00-10:00 NY
 'lon+ny': [(9*60,12*60),(14*60,17*60)],
 'lon+ny+pm':[(9*60,12*60),(14*60,17*60),(20*60+30,23*60)],  # + NY PM 13:30-16:00 NY
}

def in_kz(t,zones):
    if zones is None: return True
    m=t.hour*60+t.minute
    return any(a<=m<b for a,b in zones)

bar_idx={b[0]:i for i,b in enumerate(bars)}

def run(zones, start=None, end=None, sweep_only_kz=False, fresh_n=None, min_sl_frac=0.0, weekdays=(2,), fri_close=None):
    # fri_close: server hour on Friday at which open trades are closed (None = hold over weekend)
    # fresh_n: reclaim must come within N M15 bars of the last bar beyond the level (0 = same bar)
    # min_sl_frac: minimum SL distance as a fraction of the previous day range
    trades=[]; state={}; open_until=None
    for t in m15_times:
        close_time=t+D.timedelta(minutes=15)   # signal evaluated at candle close
        d=t.date()
        if start and d<start or end and d>end: continue
        if t.weekday() not in weekdays or d not in prev: continue
        if state.get('day')!=d:
            pdh,pdl=prev[d]
            state=dict(day=d,pdh=pdh,pdl=pdl,sh=pdh,sl=pdl,first=None,done=False,nH=999,nL=999)
        o,h,l,c=m15[t]
        s=state
        s['nH']+=1; s['nL']+=1
        if h>s['pdh']:
            s['sh']=max(s['sh'],h); s['first']=s['first'] or 'H'; s['nH']=0
        if l<s['pdl']:
            s['sl']=min(s['sl'],l); s['first']=s['first'] or 'L'; s['nL']=0
        if s['done'] or (open_until and close_time<open_until): continue
        if close_time.date()!=d: continue
        if not in_kz(t,zones): continue
        side=None
        if s['first']=='H' and c<s['pdh']: side='S'; sl=s['sh']; tp=s['pdl']
        elif s['first']=='L' and c>s['pdl']: side='B'; sl=s['sl']; tp=s['pdh']
        if not side: continue
        if fresh_n is not None and (s['nH'] if side=='S' else s['nL'])>fresh_n: continue
        i=bar_idx.get(close_time)
        if i is None: continue
        spr=bars[i][5]
        entry=bars[i][1]+(spr if side=='B' else 0)   # buy at ask, sell at bid
        if side=='B' and (sl>=entry or tp<=entry): s['done']=True; continue
        if side=='S' and (sl<=entry or tp>=entry): s['done']=True; continue
        risk=abs(entry-sl)
        if risk < min_sl_frac*(s['pdh']-s['pdl']): continue
        rr=abs(tp-entry)/risk
        # walk forward on M5
        res=None
        for j in range(i,len(bars)):
            bt,bo,bh,bl,bc,sp=bars[j]
            if side=='B':
                hit_sl=bl<=sl; hit_tp=bh>=tp
            else:
                hit_sl=bh+sp>=sl; hit_tp=bl+sp<=tp
            if fri_close is not None and bt.weekday()==4 and bt.hour>=fri_close or bt.weekday()>4:
                px=bo if side=='B' else bo+sp
                res=(px-entry)/risk if side=='B' else (entry-px)/risk; exit_t=bt; break
            if hit_sl: res=-1.0; exit_t=bt; break      # conservative: SL first if both
            if hit_tp: res=rr; exit_t=bt; break
        if res is None: break
        s['done']=True; open_until=exit_t
        trades.append(dict(t=close_time,side=side,R=res,rr=rr,exit=exit_t,risk=risk))
    return trades

def stats(name,tr):
    if not tr: print(f"{name:12s} no trades"); return
    bal=10000; peak=bal; mdd=0; streak=0; maxstreak=0
    for x in tr:
        bal+=bal*0.01*x['R']; peak=max(peak,bal); mdd=max(mdd,(peak-bal)/peak)
        streak=streak+1 if x['R']<0 else 0; maxstreak=max(maxstreak,streak)
    w=[x for x in tr if x['R']>0]; gp=sum(x['R'] for x in w); gl=-sum(x['R'] for x in tr if x['R']<0)
    L=[x for x in tr if x['side']=='B']; S=[x for x in tr if x['side']=='S']
    wr=lambda a: f"{sum(1 for x in a if x['R']>0)}/{len(a)}"
    print(f"{name:12s} n={len(tr):3d} win={len(w)/len(tr)*100:5.1f}% PF={gp/gl if gl else 99:5.2f} "
          f"sumR={sum(x['R'] for x in tr):+6.1f} net={(bal/10000-1)*100:+6.1f}% maxDD={mdd*100:5.1f}% "
          f"maxLossStreak={maxstreak} longs={wr(L)} shorts={wr(S)} avgRR={sum(x['rr'] for x in tr)/len(tr):.1f}")

if __name__=='__main__':
    for per,(a,b) in {'FULL 2025-05..2026-09':(None,None),
                      'JAN-SEP 2026':(D.date(2026,1,1),D.date(2026,9,30)),
                      '2025 (mai-dec)':(None,D.date(2025,12,31))}.items():
        print("==",per)
        for k,z in KZ.items(): stats(k,run(z,a,b))

//+------------------------------------------------------------------+
//|                                              WednesdayPDHPDL.mq5 |
//|  Wednesday only - PDH / PDL reclaim                              |
//|  - Sweep of PDH then M15 close back below PDH -> SELL, TP = PDL  |
//|  - Sweep of PDL then M15 close back above PDL -> BUY,  TP = PDH  |
//|  - The level taken first during the day sets the direction       |
//|  - SL = sweep extreme, risk = % of balance                       |
//|  - Max 1 trade per day, entries only in the NY killzone          |
//|  - Min SL distance filter (fraction of previous day range)       |
//|  - Flat before the weekend (Friday cutoff, server time)          |
//+------------------------------------------------------------------+
#property copyright "test-claude"
#property version   "1.04"

#include <Trade\Trade.mqh>

//--- inputs
input double          RiskPercent = 1.0;         // Risk per trade (% of balance)
input ENUM_TIMEFRAMES SignalTF    = PERIOD_M15;  // Signal candle timeframe
input long            MagicNumber = 20260926;    // Magic number
input int             Slippage    = 20;          // Max slippage (points)
input double          MinSLFraction = 0.15;      // Min SL distance, fraction of previous day range (0 = off)

//--- trading days (backtest NAS100: Tue-Thu more robust than Wednesday only)
input bool            TradeMonday    = false;
input bool            TradeTuesday   = false;
input bool            TradeWednesday = true;
input bool            TradeThursday  = false;
input bool            TradeFriday    = false;

//--- no position over the weekend (avoid weekend swap / gap)
input bool            CloseBeforeWeekend = true; // Close open trades on Friday
input int             FridayCloseHour    = 17;   // Friday close hour (server time)
input int             FridayCloseMinute  = 0;    // Friday close minute (server time)

//--- ICT killzones (broker SERVER time, hours). Default = broker GMT+2/+3 (NY + 7h)
input bool            UseKillzones = true;       // Only enter inside killzones
input bool            UseLondonKZ  = false;      // London KZ (02:00-05:00 New York)
input int             LondonStart  = 9;          // London KZ start hour (server)
input int             LondonEnd    = 12;         // London KZ end hour (server)
input bool            UseNewYorkKZ = true;       // New York AM KZ (07:00-10:00 New York)
input int             NewYorkStart = 14;         // New York KZ start hour (server)
input int             NewYorkEnd   = 17;         // New York KZ end hour (server)

//--- which level was swept first today
enum ENUM_FIRST_SWEEP
{
   SWEEP_NONE = 0,
   SWEEP_HIGH = 1,
   SWEEP_LOW  = 2
};

//--- globals
CTrade           g_trade;
datetime         g_lastBarTime = 0;
datetime         g_currentDay  = 0;
double           g_pdh         = 0.0;
double           g_pdl         = 0.0;
double           g_sweepHigh   = 0.0;
double           g_sweepLow    = 0.0;
ENUM_FIRST_SWEEP g_firstSweep  = SWEEP_NONE;
bool             g_tradedToday = false;

//+------------------------------------------------------------------+
//| Lot size so that the SL loses RiskPercent % of the balance       |
//+------------------------------------------------------------------+
double CalcLots(double slDistance)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickSize <= 0.0 || tickValue <= 0.0 || lotStep <= 0.0 || slDistance <= 0.0)
      return(0.0);

   double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   double lossPerLot = (slDistance / tickSize) * tickValue;
   double lots       = MathFloor((riskMoney / lossPerLot) / lotStep) * lotStep;

   if(lots < minLot)
      return(0.0);                 // risk too small for broker minimum lot
   if(lots > maxLot)
      lots = maxLot;

   return(NormalizeDouble(lots, 2));
}

//+------------------------------------------------------------------+
//| Is this weekday enabled?                                         |
//+------------------------------------------------------------------+
bool IsTradingDay(int dayOfWeek)
{
   switch(dayOfWeek)
   {
      case 1: return(TradeMonday);
      case 2: return(TradeTuesday);
      case 3: return(TradeWednesday);
      case 4: return(TradeThursday);
      case 5: return(TradeFriday);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Is the signal candle (open time) inside an enabled killzone?     |
//+------------------------------------------------------------------+
bool InKillzone(datetime t)
{
   if(!UseKillzones)
      return(true);
   MqlDateTime k;
   TimeToStruct(t, k);
   if(UseLondonKZ && k.hour >= LondonStart && k.hour < LondonEnd)
      return(true);
   if(UseNewYorkKZ && k.hour >= NewYorkStart && k.hour < NewYorkEnd)
      return(true);
   return(false);
}

//+------------------------------------------------------------------+
//| Is there already a position from this EA on this symbol?         |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Send a market order with SL / TP                                 |
//+------------------------------------------------------------------+
void OpenTrade(bool isBuy, double entry, double sl, double tp)
{
   // SL and TP must be on the correct side of the entry price
   if(isBuy && (sl >= entry || tp <= entry))
   {
      g_tradedToday = true;
      return;
   }
   if(!isBuy && (sl <= entry || tp >= entry))
   {
      g_tradedToday = true;
      return;
   }

   // Too tight stops are not realistic: require a minimum SL distance
   if(MathAbs(entry - sl) < MinSLFraction * (g_pdh - g_pdl))
      return;

   // Broker minimum stop distance
   double minDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(MathAbs(entry - sl) < minDist || MathAbs(tp - entry) < minDist)
      return;

   double lots = CalcLots(MathAbs(entry - sl));
   if(lots <= 0.0)
      return;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   bool ok = false;
   if(isBuy)
      ok = g_trade.Buy(lots, _Symbol, 0.0, sl, tp, "PDL reclaim");
   else
      ok = g_trade.Sell(lots, _Symbol, 0.0, sl, tp, "PDH reclaim");

   if(ok)
      g_tradedToday = true;
   else
      Print("Order error: ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_trade.SetExpertMagicNumber((ulong)MagicNumber);
   g_trade.SetDeviationInPoints((ulong)Slippage);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Close this EA's positions that must not stay over the weekend    |
//+------------------------------------------------------------------+
bool WeekendCloseCheck()
{
   if(!CloseBeforeWeekend)
      return(false);

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int  nowMin     = now.hour * 60 + now.min;
   int  cutoffMin  = FridayCloseHour * 60 + FridayCloseMinute;
   bool afterCutoff = (now.day_of_week == 5 && nowMin >= cutoffMin) ||
                      now.day_of_week == 6 || now.day_of_week == 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      // Also catch positions that crossed a weekend (e.g. market closed on Friday)
      MqlDateTime op;
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      TimeToStruct(openTime, op);
      bool crossedWeekend = (now.day_of_week < op.day_of_week) ||
                            (TimeCurrent() - openTime >= 7 * 86400);

      if(afterCutoff || crossedWeekend)
      {
         if(!g_trade.PositionClose(ticket))
            Print("Weekend close error: ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
      }
   }
   return(afterCutoff);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // 0. No position over the weekend, and no new entry after the Friday cutoff
   if(WeekendCloseCheck())
      return;

   // 1. Work only once per new signal candle
   datetime barTime = iTime(_Symbol, SignalTF, 0);
   if(barTime == 0 || barTime == g_lastBarTime)
      return;
   g_lastBarTime = barTime;

   // 2. Enabled trading days only (broker server time)
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(!IsTradingDay(dt.day_of_week))
   {
      g_currentDay = 0;
      return;
   }

   // 3. New day: read PDH / PDL and reset state
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
   if(dayStart != g_currentDay)
   {
      g_currentDay  = dayStart;
      g_pdh         = iHigh(_Symbol, PERIOD_D1, 1);
      g_pdl         = iLow(_Symbol, PERIOD_D1, 1);
      g_sweepHigh   = g_pdh;
      g_sweepLow    = g_pdl;
      g_firstSweep  = SWEEP_NONE;
      g_tradedToday = false;
   }
   if(g_pdh <= 0.0 || g_pdl <= 0.0)
      return;

   // The closed candle must belong to today
   if(iTime(_Symbol, SignalTF, 1) < g_currentDay)
      return;

   double barHigh  = iHigh(_Symbol, SignalTF, 1);
   double barLow   = iLow(_Symbol, SignalTF, 1);
   double barClose = iClose(_Symbol, SignalTF, 1);

   // 4. Track sweeps
   if(barHigh > g_pdh)
   {
      g_sweepHigh = MathMax(g_sweepHigh, barHigh);
      if(g_firstSweep == SWEEP_NONE)
         g_firstSweep = SWEEP_HIGH;
   }
   if(barLow < g_pdl)
   {
      g_sweepLow = MathMin(g_sweepLow, barLow);
      if(g_firstSweep == SWEEP_NONE)
         g_firstSweep = SWEEP_LOW;
   }

   if(g_tradedToday || HasOpenPosition())
      return;

   // Entries only inside the killzones (sweeps are tracked all day)
   if(!InKillzone(iTime(_Symbol, SignalTF, 1)))
      return;

   // 5. Reclaim signal on candle close
   if(g_firstSweep == SWEEP_HIGH && barClose < g_pdh)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      OpenTrade(false, bid, g_sweepHigh, g_pdl);
   }
   else if(g_firstSweep == SWEEP_LOW && barClose > g_pdl)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      OpenTrade(true, ask, g_sweepLow, g_pdh);
   }
}
//+------------------------------------------------------------------+

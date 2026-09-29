//+------------------------------------------------------------------+
//|                                                   ICT_OTE_NY.mq5 |
//|  ICT Optimal Trade Entry - New York session (OTE series, ep. 1)  |
//|  - Bias: first of PDH / PDL taken since NY midnight              |
//|      PDH taken -> BUY setup, PDL taken -> SELL setup             |
//|  - Range (buy): lowest low since NY midnight -> highest high     |
//|  - Limit entry at EntryFib retracement, 08:30-11:00 New York     |
//|  - SL beyond the range extreme, risk = % of balance              |
//|  - TP1 -0.5 / TP2 -1.0 / TP3 -2.0 extensions, 1/3 each           |
//|  - After TP1 SL -> range midpoint, after TP2 SL -> entry         |
//|  - Optional flat at 16:00 New York                               |
//+------------------------------------------------------------------+
#property copyright "test-claude"
#property version   "1.00"

#include <Trade\Trade.mqh>

//--- inputs
input double RiskPercent    = 1.0;    // Risk per trade (% of balance)
input double EntryFib       = 0.62;   // Entry retracement (0.62 / 0.705 / 0.79)
input bool   WednesdayOnly  = false;  // Trade Wednesday only
input int    ServerMinusNY  = 7;      // Server time minus New York time (hours)
input int    WindowStartMin = 510;    // Window start, NY minutes after midnight (510 = 08:30)
input int    WindowEndMin   = 660;    // Window end, NY minutes after midnight (660 = 11:00)
input bool   CloseEndOfDay  = true;   // Close everything at end of NY day
input int    EndOfDayMin    = 960;    // End of day, NY minutes after midnight (960 = 16:00)
input long   MagicNumber    = 20260929;
input int    Slippage       = 20;     // Max slippage (points)

//--- globals
CTrade   g_trade;
datetime g_day        = 0;      // server date of the current NY day
bool     g_done       = false;  // a trade was taken (or the day is over)
int      g_side       = 0;      // +1 buy, -1 sell, 0 none
double   g_rangeHigh  = 0.0;
double   g_rangeLow   = 0.0;
bool     g_valid      = false;
double   g_entry      = 0.0;    // levels frozen at fill time
double   g_fillHigh   = 0.0;
double   g_fillLow    = 0.0;
double   g_initVolume = 0.0;
int      g_stage      = 0;      // number of TPs already taken
datetime g_lastBar    = 0;

//+------------------------------------------------------------------+
double NormalizeVolume(double lots)
{
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0)
      return(0.0);
   lots = MathFloor(lots / step) * step;
   if(lots < minLot)
      return(0.0);
   if(lots > maxLot)
      lots = maxLot;
   return(NormalizeDouble(lots, 2));
}

//+------------------------------------------------------------------+
//| Lot size so that the SL loses RiskPercent % of the balance       |
//+------------------------------------------------------------------+
double CalcLots(double slDistance)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || slDistance <= 0.0)
      return(0.0);
   double riskMoney  = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   double lossPerLot = (slDistance / tickSize) * tickValue;
   return(NormalizeVolume(riskMoney / lossPerLot));
}

//+------------------------------------------------------------------+
ulong FindPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return(ticket);
   }
   return(0);
}

//+------------------------------------------------------------------+
ulong FindPendingOrder()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == MagicNumber)
         return(ticket);
   }
   return(0);
}

//+------------------------------------------------------------------+
void DeletePending()
{
   ulong ticket = FindPendingOrder();
   if(ticket > 0)
      g_trade.OrderDelete(ticket);
}

//+------------------------------------------------------------------+
//| New York minutes after midnight for a server time                |
//+------------------------------------------------------------------+
int NYMinutes(datetime serverTime)
{
   MqlDateTime k;
   TimeToStruct(serverTime - ServerMinusNY * 3600, k);
   return(k.hour * 60 + k.min);
}

//+------------------------------------------------------------------+
//| Rebuild bias and OTE range from closed M5 bars since NY midnight |
//+------------------------------------------------------------------+
void BuildSetup(datetime nyMidnight)
{
   double pdh = iHigh(_Symbol, PERIOD_D1, 1);
   double pdl = iLow(_Symbol, PERIOD_D1, 1);
   g_side = 0;
   g_valid = false;
   if(pdh <= 0.0 || pdl <= 0.0)
      return;

   MqlRates rates[];
   int count = CopyRates(_Symbol, PERIOD_M5, nyMidnight, TimeCurrent(), rates);
   if(count < 2)
      return;

   double hi = 0.0, lo = 0.0;
   bool valid = true;
   for(int i = 0; i < count - 1; i++)          // last bar is still forming
   {
      double h = rates[i].high;
      double l = rates[i].low;
      if(g_side == 0)
      {
         hi = (i == 0) ? h : MathMax(hi, h);
         lo = (i == 0) ? l : MathMin(lo, l);
         if(hi > pdh)      { g_side = 1;  g_rangeHigh = hi; g_rangeLow = lo; }
         else if(lo < pdl) { g_side = -1; g_rangeHigh = hi; g_rangeLow = lo; }
         continue;
      }
      if(g_side == 1)
      {
         if(h > g_rangeHigh) g_rangeHigh = h;
         if(l < g_rangeLow)  valid = false;
      }
      else
      {
         if(l < g_rangeLow)  g_rangeLow = l;
         if(h > g_rangeHigh) valid = false;
      }
   }
   g_valid = (g_side != 0 && valid && g_rangeHigh > g_rangeLow);
}

//+------------------------------------------------------------------+
//| Place or refresh the OTE limit order                             |
//+------------------------------------------------------------------+
void PlaceOrUpdateOrder()
{
   double range = g_rangeHigh - g_rangeLow;
   double entry, sl;
   if(g_side == 1) { entry = g_rangeHigh - EntryFib * range; sl = g_rangeLow; }
   else            { entry = g_rangeLow + EntryFib * range;  sl = g_rangeHigh; }
   entry = NormalizeDouble(entry, _Digits);
   sl    = NormalizeDouble(sl, _Digits);

   ulong pending = FindPendingOrder();
   if(pending > 0)
   {
      if(MathAbs(OrderGetDouble(ORDER_PRICE_OPEN) - entry) < _Point &&
         MathAbs(OrderGetDouble(ORDER_SL) - sl) < _Point)
         return;                                // unchanged
      g_trade.OrderDelete(pending);
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool ok = false;

   if(g_side == 1)
   {
      if(ask <= sl)
         return;
      double px = MathMin(entry, ask);
      double lots = CalcLots(px - sl);
      if(lots <= 0.0)
         return;
      if(ask <= entry)                          // already inside the OTE
         ok = g_trade.Buy(lots, _Symbol, 0.0, sl, 0.0, "OTE buy");
      else
         ok = g_trade.BuyLimit(lots, entry, _Symbol, sl, 0.0, ORDER_TIME_GTC, 0, "OTE buy");
   }
   else
   {
      if(bid >= sl)
         return;
      double px = MathMax(entry, bid);
      double lots = CalcLots(sl - px);
      if(lots <= 0.0)
         return;
      if(bid >= entry)
         ok = g_trade.Sell(lots, _Symbol, 0.0, sl, 0.0, "OTE sell");
      else
         ok = g_trade.SellLimit(lots, entry, _Symbol, sl, 0.0, ORDER_TIME_GTC, 0, "OTE sell");
   }
   if(!ok)
      Print("Order error: ", g_trade.ResultRetcode(), " ", g_trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Partial exits at -0.5 / -1.0 / -2.0 and stop management          |
//+------------------------------------------------------------------+
void ManagePosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return;

   // First time we see the position: freeze the levels
   if(g_initVolume <= 0.0)
   {
      g_initVolume = PositionGetDouble(POSITION_VOLUME);
      g_entry      = PositionGetDouble(POSITION_PRICE_OPEN);
      g_fillHigh   = g_rangeHigh;
      g_fillLow    = g_rangeLow;
      g_stage      = 0;
   }

   double range = g_fillHigh - g_fillLow;
   double ext[3] = {0.5, 1.0, 2.0};
   bool   isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   double price  = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   while(g_stage < 3)
   {
      double tp = isBuy ? g_fillHigh + ext[g_stage] * range : g_fillLow - ext[g_stage] * range;
      if((isBuy && price < tp) || (!isBuy && price > tp))
         break;

      double volume = PositionGetDouble(POSITION_VOLUME);
      double part   = NormalizeVolume(g_initVolume / 3.0);
      if(g_stage == 2 || part <= 0.0 || part >= volume)
      {
         g_trade.PositionClose(ticket);
         g_stage = 3;
         return;
      }
      if(!g_trade.PositionClosePartial(ticket, part))
         return;
      g_stage++;

      // Move the stop (never loosen it)
      double newSl = (g_stage == 1) ? (g_fillHigh + g_fillLow) / 2.0 : g_entry;
      if(!PositionSelectByTicket(ticket))
         return;
      double curSl = PositionGetDouble(POSITION_SL);
      if((isBuy && newSl > curSl) || (!isBuy && (curSl == 0.0 || newSl < curSl)))
         g_trade.PositionModify(ticket, NormalizeDouble(newSl, _Digits), 0.0);
   }
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
void OnTick()
{
   datetime now = TimeCurrent();

   // Only work between NY midnight and the end of the server day
   MqlDateTime s;
   TimeToStruct(now, s);
   if(s.hour < ServerMinusNY)
      return;

   datetime serverDay  = iTime(_Symbol, PERIOD_D1, 0);
   datetime nyMidnight = serverDay + ServerMinusNY * 3600;
   int      nyMin      = NYMinutes(now);

   // New day: reset state
   if(serverDay != g_day)
   {
      g_day        = serverDay;
      g_done       = (s.day_of_week == 0 || s.day_of_week == 6 ||
                      (WednesdayOnly && s.day_of_week != 3));
      g_side       = 0;
      g_valid      = false;
      g_initVolume = 0.0;
      g_stage      = 0;
   }

   ulong position = FindPosition();

   // End of NY day: flat
   if(CloseEndOfDay && nyMin >= EndOfDayMin)
   {
      DeletePending();
      if(position > 0)
         g_trade.PositionClose(position);
      g_done = true;
      return;
   }

   if(position > 0)
   {
      g_done = true;                            // one trade per day
      ManagePosition(position);
      return;
   }
   g_initVolume = 0.0;

   // After the window: remove the unfilled order
   if(nyMin >= WindowEndMin)
   {
      DeletePending();
      g_done = true;
      return;
   }
   if(g_done)
   {
      DeletePending();
      return;
   }

   // Rebuild setup on each new M5 bar
   datetime bar = iTime(_Symbol, PERIOD_M5, 0);
   if(bar != g_lastBar)
   {
      g_lastBar = bar;
      BuildSetup(nyMidnight);
      if(!g_valid)
      {
         DeletePending();
         return;
      }
      if(nyMin >= WindowStartMin)
         PlaceOrUpdateOrder();
   }
}
//+------------------------------------------------------------------+

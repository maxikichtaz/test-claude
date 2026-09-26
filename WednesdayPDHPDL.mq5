//+------------------------------------------------------------------+
//|                                              WednesdayPDHPDL.mq5 |
//|  Mercredi uniquement - Reclaim du PDH / PDL                      |
//|  - Sweep du PDH puis clôture M15 sous le PDH -> SELL, TP = PDL   |
//|  - Sweep du PDL puis clôture M15 au-dessus du PDL -> BUY, TP=PDH |
//|  - Le niveau pris en premier dans la journée définit le sens     |
//|  - SL = extrême du sweep, risque = % du solde                    |
//|  - 1 trade maximum par mercredi                                  |
//+------------------------------------------------------------------+
#property copyright "test-claude"
#property version   "1.00"

#include <Trade\Trade.mqh>

input double          RiskPercent = 1.0;         // Risque par trade (% du solde)
input ENUM_TIMEFRAMES SignalTF    = PERIOD_M15;  // Timeframe de la bougie de signal
input ulong           Magic       = 20260926;    // Magic number
input int             Slippage    = 20;          // Slippage max (points)

enum FirstLevel { NOT_TAKEN, HIGH_FIRST, LOW_FIRST };

CTrade     trade;
datetime   lastBarTime  = 0;
datetime   currentDay   = 0;
double     pdh = 0, pdl = 0;
double     sweepHigh = 0, sweepLow = 0;
FirstLevel firstTaken  = NOT_TAKEN;
bool       tradedToday = false;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(Magic);
   trade.SetDeviationInPoints(Slippage);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Traiter uniquement à l'ouverture d'une nouvelle bougie de signal
   datetime barTime = iTime(_Symbol, SignalTF, 0);
   if(barTime == 0 || barTime == lastBarTime) return;
   lastBarTime = barTime;

   // 2. Mercredi uniquement (heure serveur du broker)
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week != 3) { currentDay = 0; return; }

   // 3. Nouveau jour : récupérer PDH / PDL et réinitialiser l'état
   datetime dayStart = iTime(_Symbol, PERIOD_D1, 0);
   if(dayStart != currentDay)
   {
      currentDay  = dayStart;
      pdh         = iHigh(_Symbol, PERIOD_D1, 1);
      pdl         = iLow(_Symbol, PERIOD_D1, 1);
      sweepHigh   = pdh;
      sweepLow    = pdl;
      firstTaken  = NOT_TAKEN;
      tradedToday = false;
   }
   if(pdh <= 0 || pdl <= 0) return;

   // La bougie clôturée doit appartenir à la journée en cours
   if(iTime(_Symbol, SignalTF, 1) < currentDay) return;

   double high  = iHigh(_Symbol, SignalTF, 1);
   double low   = iLow(_Symbol, SignalTF, 1);
   double close = iClose(_Symbol, SignalTF, 1);

   // 4. Suivi des sweeps
   if(high > pdh)
   {
      sweepHigh = MathMax(sweepHigh, high);
      if(firstTaken == NOT_TAKEN) firstTaken = HIGH_FIRST;
   }
   if(low < pdl)
   {
      sweepLow = MathMin(sweepLow, low);
      if(firstTaken == NOT_TAKEN) firstTaken = LOW_FIRST;
   }

   if(tradedToday || HasOpenPosition()) return;

   // 5. Signal de reclaim à la clôture de la bougie
   if(firstTaken == HIGH_FIRST && close < pdh)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      OpenTrade(ORDER_TYPE_SELL, entry, sweepHigh, pdl);
   }
   else if(firstTaken == LOW_FIRST && close > pdl)
   {
      double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      OpenTrade(ORDER_TYPE_BUY, entry, sweepLow, pdh);
   }
}

//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, double entry, double sl, double tp)
{
   bool isBuy = (type == ORDER_TYPE_BUY);

   // SL / TP doivent être du bon côté du prix d'entrée
   if(isBuy  && (sl >= entry || tp <= entry)) { tradedToday = true; return; }
   if(!isBuy && (sl <= entry || tp >= entry)) { tradedToday = true; return; }

   // Distance minimale imposée par le broker
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(MathAbs(entry - sl) < minDist || MathAbs(tp - entry) < minDist) return;

   double lots = CalcLots(MathAbs(entry - sl));
   if(lots <= 0) return;

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   bool ok = isBuy ? trade.Buy(lots, _Symbol, 0, sl, tp, "PDL reclaim")
                   : trade.Sell(lots, _Symbol, 0, sl, tp, "PDH reclaim");
   if(ok) tradedToday = true;
   else   Print("Erreur ordre: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
// Taille de position pour risquer RiskPercent % du solde
double CalcLots(double slDistance)
{
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(tickSize <= 0 || tickValue <= 0 || step <= 0 || slDistance <= 0) return 0;

   double riskMoney   = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;
   double lossPerLot  = slDistance / tickSize * tickValue;
   double lots        = MathFloor(riskMoney / lossPerLot / step) * step;

   if(lots < minLot) return 0;   // risque trop faible pour le lot minimum
   return MathMin(lots, maxLot);
}

//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == (long)Magic)
         return true;
   }
   return false;
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                           SidewaysOnlyBox.mq5    |
//|                                     Copyright 2026, Senior Dev   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Senior Dev"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- input parameters
input ENUM_TIMEFRAMES InpTimeFrame = PERIOD_M15;   // chart timeframe for MA
input int    FastMA = 10;                         // fast EMA period
input int    SlowMA = 20;                         // slow EMA period
input double FixedLot = 0.02;                     // lot size
input int    StopLossPoints = 200;                // SL in points
input int    TakeProfitPoints = 200;              // TP in points

//--- global objects
CTrade trade;                                      // trade helper
datetime lastEntryTime = 0;                        // to avoid duplicate orders on same bar
#define SIDE_MAGIC 9876543

int OnInit()
{
   trade.SetExpertMagicNumber(SIDE_MAGIC);
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   //--- obtain EMA handles each tick (simple for this EA)
   int fastHandle = iMA(_Symbol, InpTimeFrame, FastMA, 0, MODE_EMA, PRICE_CLOSE);
   int slowHandle = iMA(_Symbol, InpTimeFrame, SlowMA, 0, MODE_EMA, PRICE_CLOSE);

   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   //--- copy last two values of each MA
   if(CopyBuffer(fastHandle, 0, 0, 2, fast) < 2 ||
      CopyBuffer(slowHandle, 0, 0, 2, slow) < 2) return;

   //--- draw MA overlay (trend objects) on the chart
   ObjectDelete(0, "FastMA");
   ObjectDelete(0, "SlowMA");
   datetime t0 = iTime(_Symbol, InpTimeFrame, 0);
   datetime t1 = iTime(_Symbol, InpTimeFrame, 1);
   ObjectCreate(0, "FastMA", OBJ_TREND, 0, t1, fast[1], t0, fast[0]);
   ObjectSetInteger(0, "FastMA", OBJPROP_COLOR, clrDeepSkyBlue);
   ObjectSetInteger(0, "FastMA", OBJPROP_WIDTH, 2);
   ObjectCreate(0, "SlowMA", OBJ_TREND, 0, t1, slow[1], t0, slow[0]);
   ObjectSetInteger(0, "SlowMA", OBJPROP_COLOR, clrOrangeRed);
   ObjectSetInteger(0, "SlowMA", OBJPROP_WIDTH, 2);
   ChartRedraw();

   //--- avoid sending another order on the same completed bar
   datetime currentBarTime = iTime(_Symbol, InpTimeFrame, 0);
   if(lastEntryTime == currentBarTime) return;

   //--- MA crossover trading logic
   if(!PositionSelect(_Symbol))
   {
      // bullish crossover: fast crosses above slow
      if(fast[0] > slow[0] && fast[1] <= slow[1])
      {
         double sl = SymbolInfoDouble(_Symbol, SYMBOL_BID) - StopLossPoints * _Point;
         double tp = SymbolInfoDouble(_Symbol, SYMBOL_BID) + TakeProfitPoints * _Point;
         if(trade.Buy(FixedLot, _Symbol, 0, sl, tp, "MA Cross Buy"))
            lastEntryTime = currentBarTime;
      }
      // bearish crossover: fast crosses below slow
      else if(fast[0] < slow[0] && fast[1] >= slow[1])
      {
         double sl = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + StopLossPoints * _Point;
         double tp = SymbolInfoDouble(_Symbol, SYMBOL_ASK) - TakeProfitPoints * _Point;
         if(trade.Sell(FixedLot, _Symbol, 0, sl, tp, "MA Cross Sell"))
            lastEntryTime = currentBarTime;
      }
   }
}

void OnDeinit(const int reason)
{
   // clean up chart objects created by this EA
   ObjectDelete(0, "FastMA");
   ObjectDelete(0, "SlowMA");
}

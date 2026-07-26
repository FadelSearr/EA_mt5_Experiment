//+------------------------------------------------------------------+
//|                                           TrendFollowerSwing.mq5 |
//|                                     Copyright 2026, Senior Dev   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Senior Dev"
#property version   "2.01"
#property strict

#include <Trade\Trade.mqh>

input double MaximumRisk        = 0.02;    // Maximum Risk in percentage
input int    MovingPeriod       = 20;      // Signal MA period
input int    TrendPeriod        = 200;     // Trend Filter EMA period
//---
int    fastMaHandle, slowMaHandle, adxHandle;
CTrade trade;

#define MA_MAGIC 1234501

int OnInit(void)
{
   trade.SetExpertMagicNumber(MA_MAGIC);
   fastMaHandle = iMA(_Symbol, PERIOD_M5, 20, 0, MODE_EMA, PRICE_CLOSE);
   slowMaHandle = iMA(_Symbol, PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE);
   adxHandle    = iADX(_Symbol, PERIOD_M5, 14);
   return(INIT_SUCCEEDED);
}

void OnTick(void)
{
   // Strategy: EMA Crossover + ADX Filter (M5)
   double fastMa[], slowMa[], adx[];
   CopyBuffer(fastMaHandle, 0, 0, 2, fastMa);
   CopyBuffer(slowMaHandle, 0, 0, 2, slowMa);
   CopyBuffer(adxHandle, 0, 0, 1, adx);
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   if(!PositionSelect(_Symbol) && adx[0] > 25) { // ADX > 25 = Trend Strong
      // Buy: Crossover Up
      if(fastMa[1] < slowMa[1] && fastMa[0] > slowMa[0]) {
         trade.Buy(0.01, _Symbol, ask, ask - 300*_Point, ask + 450*_Point, "M5 Trend Buy");
      }
      // Sell: Crossover Down
      else if(fastMa[1] > slowMa[1] && fastMa[0] < slowMa[0]) {
         trade.Sell(0.01, _Symbol, bid, bid + 300*_Point, bid - 450*_Point, "M5 Trend Sell");
      }
   }
}

void OnDeinit(const int reason) 
{ 
   IndicatorRelease(fastMaHandle); 
   IndicatorRelease(slowMaHandle);
   IndicatorRelease(adxHandle);
}

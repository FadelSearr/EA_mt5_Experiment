//+------------------------------------------------------------------+
//|                                           TrendFollowerSwing.mq5 |
//|                                     Copyright 2026, Senior Dev   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Senior Dev"
#property version   "3.10"
#property strict

#include <Trade\Trade.mqh>

input int    MaPeriod         = 20;   // Periode MA & BB
input int    AdxPeriod        = 14;   // Periode ADX
input double AdxThreshold     = 25.0; // Batas ADX (Trending vs Sideways)
input double FixedLot         = 0.02; // Lot Transaksi
//---
int    maHandle, adxHandle, bbHandle;
CTrade trade;

#define MA_MAGIC 1234501

int OnInit(void)
{
   trade.SetExpertMagicNumber(MA_MAGIC);
   maHandle  = iMA(_Symbol, PERIOD_M5, MaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   adxHandle = iADX(_Symbol, PERIOD_M5, AdxPeriod);
   bbHandle  = iBands(_Symbol, PERIOD_M5, MaPeriod, 0, 2.0, PRICE_CLOSE);
   return(INIT_SUCCEEDED);
}

void OnTick(void)
{
   double ma[], adx[], bbUpper[], bbLower[], ratesClose[];
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(ratesClose, true);
   
   if(CopyBuffer(maHandle, 0, 0, 2, ma) < 2 || CopyBuffer(adxHandle, 0, 0, 2, adx) < 2 || 
      CopyBuffer(bbHandle, 1, 0, 2, bbUpper) < 2 || CopyBuffer(bbHandle, 2, 0, 2, bbLower) < 2 || 
      CopyClose(_Symbol, PERIOD_M5, 0, 2, ratesClose) < 2) return;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   static datetime lastCandleTime = 0;
   datetime currentCandleTime = iTime(_Symbol, PERIOD_M5, 0);
   if(currentCandleTime == lastCandleTime) return;

   bool isTrending = (adx[0] >= AdxThreshold);
   bool hasPos = PositionSelect(_Symbol);

   // Mode 1: Trending (Momentum Following)
   if(isTrending) {
       if(!hasPos) {
           if(ratesClose[0] > ma[0] && ratesClose[1] <= ma[1]) trade.Buy(FixedLot, _Symbol, ask, 0, 0, "Trend Buy");
           if(ratesClose[0] < ma[0] && ratesClose[1] >= ma[1]) trade.Sell(FixedLot, _Symbol, bid, 0, 0, "Trend Sell");
       }
   }
   // Mode 2: Sideways (Mean Reversion / Bounce Trading)
   else {
       if(!hasPos) {
           if(ratesClose[0] < bbLower[0]) trade.Buy(FixedLot, _Symbol, ask, 0, 0, "Sideways Buy (Bounce)");
           if(ratesClose[0] > bbUpper[0]) trade.Sell(FixedLot, _Symbol, bid, 0, 0, "Sideways Sell (Bounce)");
       }
       // Exit Mean Reversion di MA Tengah
       else {
           long posType = PositionGetInteger(POSITION_TYPE);
           if(posType == POSITION_TYPE_BUY && ratesClose[0] >= ma[0]) trade.PositionClose(_Symbol);
           if(posType == POSITION_TYPE_SELL && ratesClose[0] <= ma[0]) trade.PositionClose(_Symbol);
       }
   }
   
   lastCandleTime = currentCandleTime;
}

void OnDeinit(const int reason) 
{ 
   IndicatorRelease(maHandle); 
   IndicatorRelease(adxHandle);
   IndicatorRelease(bbHandle);
}

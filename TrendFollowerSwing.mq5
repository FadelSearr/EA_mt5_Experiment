//+------------------------------------------------------------------+
//|                                           TrendFollowerSwing.mq5 |
//|                                     Copyright 2026, Senior Dev   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Senior Dev"
#property version   "3.07"
#property strict

#include <Trade\Trade.mqh>

input int    MaPeriod            = 20;   // EMA Periode (Default 20)
input int    AdxPeriod           = 14;   // Periode ADX untuk filter tren
input double AdxThreshold        = 22.0; // Batas ADX (Di bawah ini = Sideways/Konsolidasi)
input double MaSlopeThreshold    = 0.15; // Minimum Kemiringan MA (0.15x ATR / 2 Bar) untuk saring sideways datar
input double FixedLot            = 0.02; // Lot Transaksi
input int    StopLossPoints      = 500;  // Fixed Stop Loss dalam Poin (Default 250 poin / 25 pips)
input double BufferAtrMultiplier = 0.2;  // Buffer Penembusan MA (0.2x ATR)
//---
int    maHandle, atrHandle, adxHandle;
CTrade trade;

#define MA_MAGIC 1234501

int OnInit(void)
{
   trade.SetExpertMagicNumber(MA_MAGIC);
   maHandle  = iMA(_Symbol, PERIOD_M5, MaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_M5, 14);
   adxHandle = iADX(_Symbol, PERIOD_M5, AdxPeriod);
   return(INIT_SUCCEEDED);
}

void OnTick(void)
{
   double ma[], atr[], adx[], ratesClose[];
   ArraySetAsSeries(ma, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(ratesClose, true);
   
   if(CopyBuffer(maHandle, 0, 0, 4, ma) < 4 || CopyBuffer(atrHandle, 0, 0, 2, atr) < 2 || CopyBuffer(adxHandle, 0, 0, 2, adx) < 2 || CopyClose(_Symbol, PERIOD_M5, 0, 3, ratesClose) < 3) return;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   static datetime lastCandleTime = 0;
   datetime currentCandleTime = iTime(_Symbol, PERIOD_M5, 0);
   if(currentCandleTime == lastCandleTime) return;

   // Hitung kemiringan MA 20 (Slope) selama 2 candle terakhir dinormalisasi dengan ATR
   double maSlope = (ma[1] - ma[3]) / atr[1];

   // Filter Konsolidasi Parah: Jika MA mendatar (slope di bawah threshold) ATAU ADX < 22, blokir semua entry & reversal
   if(MathAbs(maSlope) <= MaSlopeThreshold || adx[1] < AdxThreshold) {
       lastCandleTime = currentCandleTime;
       return;
   }

   // Hitung zona buffer untuk menyaring noise
   double buyThreshold  = ma[1] + atr[1] * BufferAtrMultiplier;
   double sellThreshold = ma[1] - atr[1] * BufferAtrMultiplier;

   // 1. Cek jika ada posisi aktif running (Reversal / Recovery saat candle menembus zona buffer & MA miring tegas)
   if(PositionSelect(_Symbol)) {
       long posType = PositionGetInteger(POSITION_TYPE);
       if(posType == POSITION_TYPE_BUY && ratesClose[1] < sellThreshold && maSlope < -MaSlopeThreshold) {
           trade.PositionClose(_Symbol);
           trade.Sell(FixedLot, _Symbol, bid, bid + StopLossPoints * _Point, 0, "Price Cut Down");
           string name = "PriceCutDown_" + TimeToString(TimeCurrent());
           ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), bid);
           ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 234);
           ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
       }
       else if(posType == POSITION_TYPE_SELL && ratesClose[1] > buyThreshold && maSlope > MaSlopeThreshold) {
           trade.PositionClose(_Symbol);
           trade.Buy(FixedLot, _Symbol, ask, ask - StopLossPoints * _Point, 0, "Price Cut Up");
           string name = "PriceCutUp_" + TimeToString(TimeCurrent());
           ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), ask);
           ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 233);
           ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);
       }
   }
   // 2. Jika posisi kosong, entry saat candle menembus tegas zona buffer & MA miring tegas
   else {
       if(ratesClose[1] > buyThreshold && maSlope > MaSlopeThreshold) {
           string name = "EntryBuy_" + TimeToString(TimeCurrent());
           ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), ask);
           ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 233);
           ObjectSetInteger(0, name, OBJPROP_COLOR, clrBlue);
           trade.Buy(FixedLot, _Symbol, ask, ask - StopLossPoints * _Point, 0, "Entry Buy");
       } 
       else if(ratesClose[1] < sellThreshold && maSlope < -MaSlopeThreshold) {
           string name = "EntrySell_" + TimeToString(TimeCurrent());
           ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), bid);
           ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 234);
           ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
           trade.Sell(FixedLot, _Symbol, bid, bid + StopLossPoints * _Point, 0, "Entry Sell");
       }
   }
   
   lastCandleTime = currentCandleTime;
}

void OnDeinit(const int reason) 
{ 
   IndicatorRelease(maHandle); 
   IndicatorRelease(atrHandle);
   IndicatorRelease(adxHandle);
}

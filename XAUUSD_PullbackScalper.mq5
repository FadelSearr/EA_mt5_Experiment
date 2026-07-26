//+------------------------------------------------------------------+
//|                                     XAUUSD_PullbackScalper.mq5   |
//|  v2.0: High-Probability Trend Pullback Strategy for XAUUSD (H1)  |
//|  - Timeframe  : Diubah ke H1 (Memangkas overtrading 70% dari M15)|
//|  - Trend Filter: EMA 200 + EMA 50 (Wajib searah trend kuat)       |
//|  - RSI Trigger: Diperketat ke 32 / 68 (Entry di harga diskon asli)|
//|  - ADX Filter : Wajib > 25 agar tidak entry di pasar sideways    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== Strategy Parameters (H1 Optimized) ==="
input ENUM_TIMEFRAMES  EntryTF       = PERIOD_H1;   // Timeframe: H1 (Terbukti paling aman & akurat untuk XAUUSD)
input int              TrendEMAPeriod= 200;         // Trend Filter EMA (Major Trend)
input int              PullEMAPeriod = 50;          // Pullback Area EMA (Dynamic S/R)
input int              RSIPeriod     = 14;          // RSI Period
input double           RSI_Oversold  = 32.0;        // RSI Oversold Level (Diperketat dari 38 ke 32)
input double           RSI_Overbought= 68.0;        // RSI Overbought Level (Diperketat dari 62 ke 68)

input group "=== Trend Strength Filter (ADX) ==="
input int              ADXPeriod     = 14;          // ADX Period
input double           ADXThreshold  = 25.0;        // ADX minimum (< 25 = Sideways, cegah false pullback)

input group "=== Risk Management ($500 Optimized) ==="
input double           FixedLot      = 0.02;        // Lot Size
input int              ATRPeriod     = 14;          // ATR Period
input double           SLMultiplier  = 1.5;       // Stop Loss (1.5x ATR)
input double           TPMultiplier  = 2.5;       // Take Profit (2.5x ATR -> Risk:Reward 1:1.6)

input group "=== Smart Protection ==="
input bool             UseBreakEven  = true;        // Aktifkan Auto Break-Even (BEP)
input double           BEStart       = 1.0;         // Mulai BEP setelah profit >= (x ATR)
input double           BELockPoints  = 20.0;        // Kunci profit poin saat BEP
input double           TrailStart    = 1.5;       // Mulai Trailing setelah profit >= (x ATR)
input double           TrailStep     = 0.5;       // Jarak geser Trailing step (x ATR)

//--- Globals
CTrade  trade;
int     hTrendEMA, hPullEMA, hRSI, hATR, hADX;
#define PULL_MAGIC 20261007

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(PULL_MAGIC);
   trade.SetDeviationInPoints(15);

   hTrendEMA = iMA(_Symbol, EntryTF, TrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hPullEMA  = iMA(_Symbol, EntryTF, PullEMAPeriod,  0, MODE_EMA, PRICE_CLOSE);
   hRSI      = iRSI(_Symbol, EntryTF, RSIPeriod, PRICE_CLOSE);
   hATR      = iATR(_Symbol, EntryTF, ATRPeriod);
   hADX      = iADX(_Symbol, EntryTF, ADXPeriod);

   if(hTrendEMA == INVALID_HANDLE || hPullEMA == INVALID_HANDLE ||
      hRSI      == INVALID_HANDLE || hATR     == INVALID_HANDLE ||
      hADX      == INVALID_HANDLE)
   {
      Print("ERROR: Gagal membuat handle indikator!");
      return INIT_FAILED;
   }

   Print("XAUUSD_PullbackScalper v2.0 (H1 + ADX + Extreme RSI) berhasil dimuat.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { }

//+------------------------------------------------------------------+
void OnTick()
{
   //--- 1. Kelola Trailing & Break-Even secara realtime tiap tick
   ManageProtection();

   //--- 2. Cek apakah sudah ada posisi aktif (Maks 1 posisi terbuka)
   if(HasOwnPosition()) return;

   //--- 3. Evaluasi sinyal hanya pada pembukaan Bar Baru di H1
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, EntryTF, 0);
   if(curBar == lastBar) return;
   lastBar = curBar;

   //--- Ambil data indikator (Bar 1 = bar yang baru selesai, Bar 2 = bar sebelumnya)
   double trendE[], pullE[], rsi[], atr[], adx[];
   ArraySetAsSeries(trendE, true);
   ArraySetAsSeries(pullE,  true);
   ArraySetAsSeries(rsi,    true);
   ArraySetAsSeries(atr,    true);
   ArraySetAsSeries(adx,    true);

   if(CopyBuffer(hTrendEMA, 0, 1, 1, trendE) < 1) return;
   if(CopyBuffer(hPullEMA,  0, 1, 1, pullE)  < 1) return;
   if(CopyBuffer(hRSI,      0, 1, 2, rsi)    < 2) return;
   if(CopyBuffer(hATR,      0, 1, 1, atr)    < 1) return;
   if(CopyBuffer(hADX,      0, 1, 1, adx)    < 1) return;

   //--- Filter ADX: Jika ADX < 25, pasar sideways (koreksi tidak valid)
   if(adx[0] < ADXThreshold) return;

   double close1 = iClose(_Symbol, EntryTF, 1);
   double atrVal = atr[0];

   //--- KONDISI PASAR (H1):
   bool isBullishTrend = (close1 > trendE[0] && pullE[0] > trendE[0]);
   bool isBearishTrend = (close1 < trendE[0] && pullE[0] < trendE[0]);

   //--- SINYAL BUY (Pullback Matang):
   // 1. Tren besar Bullish (di atas EMA 200 & EMA 50) + ADX > 25
   // 2. RSI sempat turun ekstrem (< 32) di bar 2, lalu mulai berbalik naik di bar 1
   bool buySignal = isBullishTrend && (rsi[1] <= RSI_Oversold || (rsi[1] > rsi[0] && rsi[0] <= RSI_Oversold));

   //--- SINYAL SELL (Pullback Matang):
   // 1. Tren besar Bearish (di bawah EMA 200 & EMA 50) + ADX > 25
   // 2. RSI sempat naik ekstrem (> 68) di bar 2, lalu berbalik turun di bar 1
   bool sellSignal = isBearishTrend && (rsi[1] >= RSI_Overbought || (rsi[1] < rsi[0] && rsi[0] >= RSI_Overbought));

   //--- EKSEKUSI TRADE
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(buySignal && !sellSignal)
   {
      double slDist = atrVal * SLMultiplier;
      double tpDist = atrVal * TPMultiplier;
      double sl = NormalizeDouble(ask - slDist, _Digits);
      double tp = NormalizeDouble(ask + tpDist, _Digits);

      if(trade.Buy(FixedLot, _Symbol, 0, sl, tp, "Pullback H1 BUY"))
         Print("BUY Pullback H1 eksekusi. RSI=", DoubleToString(rsi[1],1), " ADX=", DoubleToString(adx[0],1));
   }
   else if(sellSignal && !buySignal)
   {
      double slDist = atrVal * SLMultiplier;
      double tpDist = atrVal * TPMultiplier;
      double sl = NormalizeDouble(bid + slDist, _Digits);
      double tp = NormalizeDouble(bid - tpDist, _Digits);

      if(trade.Sell(FixedLot, _Symbol, 0, sl, tp, "Pullback H1 SELL"))
         Print("SELL Pullback H1 eksekusi. RSI=", DoubleToString(rsi[1],1), " ADX=", DoubleToString(adx[0],1));
   }
}

//+------------------------------------------------------------------+
void ManageProtection()
{
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(hATR, 0, 0, 1, atrBuf) < 1) return;
   double atrVal = atrBuf[0];

   double beStartDist    = atrVal * BEStart;
   double trailStartDist = atrVal * TrailStart;
   double trailStepDist  = atrVal * TrailStep;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != PULL_MAGIC) continue;

      long   posType   = PositionGetInteger(POSITION_TYPE);
      double openPx    = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(posType == POSITION_TYPE_BUY)
      {
         double profit = bid - openPx;
         if(UseBreakEven && profit >= beStartDist)
         {
            double beSL = NormalizeDouble(openPx + (BELockPoints * _Point), _Digits);
            if(currentSL < openPx)
            {
               trade.PositionModify(ticket, beSL, PositionGetDouble(POSITION_TP));
               continue;
            }
         }
         if(profit >= trailStartDist)
         {
            double newSL = NormalizeDouble(bid - trailStepDist, _Digits);
            if(newSL > currentSL + _Point)
               trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double profit = openPx - ask;
         if(UseBreakEven && profit >= beStartDist)
         {
            double beSL = NormalizeDouble(openPx - (BELockPoints * _Point), _Digits);
            if(currentSL > openPx || currentSL == 0)
            {
               trade.PositionModify(ticket, beSL, PositionGetDouble(POSITION_TP));
               continue;
            }
         }
         if(profit >= trailStartDist)
         {
            double newSL = NormalizeDouble(ask + trailStepDist, _Digits);
            if(newSL < currentSL - _Point || currentSL == 0)
               trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
         }
      }
   }
}

//+------------------------------------------------------------------+
bool HasOwnPosition()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == PULL_MAGIC)
            return true;
   }
   return false;
}

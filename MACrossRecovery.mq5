//+------------------------------------------------------------------+
//|                                              MACrossTrendMTF.mq5 |
//|  v6: Profit Booster — MA Crossover + MTF + Smart BEP + Trailing  |
//|  - Smart Break-Even (BEP): Amankan posisi ke $0 saat profit 1 ATR|
//|  - Trailing Stop: Aktif setelah profit 2 ATR, step 1 ATR         |
//|  - Lot default dinaikkan ke 0.02 (masih sangat aman untuk $500)  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "6.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== MA Settings ==="
input int              FastPeriod    = 9;           // Fast EMA Period
input int              SlowPeriod    = 21;          // Slow EMA Period
input ENUM_MA_METHOD   MAMethod      = MODE_EMA;    // MA Method

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES  EntryTF       = PERIOD_H1;   // Entry TF: H1
input ENUM_TIMEFRAMES  TrendTF       = PERIOD_H4;   // Trend TF: H4

input group "=== Trend Filter (ADX) ==="
input int              ADXPeriod     = 14;          // ADX Period
input double           ADXThreshold  = 28.0;        // ADX minimum (< ini = sideways, skip)

input group "=== Risk Management ==="
input double           FixedLot      = 0.02;        // Fixed Lot Size (Dioptimalkan ke 0.02)
input int              ATRPeriod     = 14;          // ATR Period
input double           SLMultiplier  = 1.5;       // Stop Loss jarak awal (1.5x ATR)

input group "=== Smart BEP & Trailing Stop ==="
input bool             UseBreakEven  = true;        // Aktifkan Auto Break-Even (BEP)
input double           BEStart       = 1.0;         // Mulai BEP setelah profit >= (x ATR)
input double           BELockPoints  = 20.0;        // Kunci profit tipis saat BEP (dalam poin)
input double           TrailStart    = 2.0;       // Mulai Trailing setelah profit >= (x ATR)
input double           TrailStep     = 1.0;       // Jarak geser Trailing step (x ATR)

//--- Globals
CTrade  trade;
int     hFastEntry, hSlowEntry;
int     hFastTrend, hSlowTrend;
int     hADX, hATR;
bool    prevFastAbove = false;
bool    initialized   = false;

#define MAC_MAGIC 20261006

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MAC_MAGIC);
   trade.SetDeviationInPoints(10);

   hFastEntry = iMA(_Symbol, EntryTF, FastPeriod, 0, MAMethod, PRICE_CLOSE);
   hSlowEntry = iMA(_Symbol, EntryTF, SlowPeriod, 0, MAMethod, PRICE_CLOSE);
   hFastTrend = iMA(_Symbol, TrendTF, FastPeriod, 0, MAMethod, PRICE_CLOSE);
   hSlowTrend = iMA(_Symbol, TrendTF, SlowPeriod, 0, MAMethod, PRICE_CLOSE);
   hADX       = iADX(_Symbol, EntryTF, ADXPeriod);
   hATR       = iATR(_Symbol, EntryTF, ATRPeriod);

   if(hFastEntry == INVALID_HANDLE || hSlowEntry == INVALID_HANDLE ||
      hFastTrend == INVALID_HANDLE || hSlowTrend == INVALID_HANDLE ||
      hADX       == INVALID_HANDLE || hATR       == INVALID_HANDLE)
   {
      Print("ERROR: Gagal buat indicator handle");
      return INIT_FAILED;
   }

   Print("MACrossTrendMTF v6 (Profit Booster). EntryTF=", EnumToString(EntryTF),
         " TrendTF=", EnumToString(TrendTF), " Lot=", FixedLot);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { }

//+------------------------------------------------------------------+
void OnTick()
{
   //--- 1. Kelola Break-Even (BEP) dan Trailing Stop setiap tick
   ManageProtection();

   //--- 2. Jika SUDAH ADA posisi aktif dari EA ini, tidak entry lagi
   if(HasOwnPosition()) return;

   //--- 3. Cek sinyal crossover hanya pada bar baru
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, EntryTF, 0);
   if(curBar == lastBar) return;
   lastBar = curBar;

   double fastE[], slowE[], adx[], atr[];
   ArraySetAsSeries(fastE, true);
   ArraySetAsSeries(slowE, true);
   ArraySetAsSeries(adx,   true);
   ArraySetAsSeries(atr,   true);

   if(CopyBuffer(hFastEntry, 0, 1, 2, fastE) < 2) return;
   if(CopyBuffer(hSlowEntry, 0, 1, 2, slowE) < 2) return;
   if(CopyBuffer(hADX,       0, 1, 2, adx)   < 2) return;
   if(CopyBuffer(hATR,       0, 1, 1, atr)   < 1) return;

   double fastT[], slowT[];
   ArraySetAsSeries(fastT, true);
   ArraySetAsSeries(slowT, true);
   if(CopyBuffer(hFastTrend, 0, 0, 1, fastT) < 1) return;
   if(CopyBuffer(hSlowTrend, 0, 0, 1, slowT) < 1) return;

   bool trendBull = (fastT[0] > slowT[0]);
   bool trendBear = (fastT[0] < slowT[0]);

   if(!initialized)
   {
      prevFastAbove = (fastE[1] > slowE[1]);
      initialized   = true;
      return;
   }

   bool currFastAbove = (fastE[0] > slowE[0]);
   bool crossUp       = (!prevFastAbove && currFastAbove);
   bool crossDown     = (prevFastAbove  && !currFastAbove);
   prevFastAbove      = currFastAbove;

   if(!crossUp && !crossDown) return;

   //--- ADX Filter
   if(adx[0] < ADXThreshold) return;

   //--- MTF Filter
   if(crossUp   && !trendBull) return;
   if(crossDown && !trendBear) return;

   //--- Stop Loss Awal
   double atrVal = atr[0];
   double slDist = atrVal * SLMultiplier;
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slBuy  = NormalizeDouble(ask - slDist, _Digits);
   double slSell = NormalizeDouble(bid + slDist, _Digits);

   if(crossUp)
   {
      if(trade.Buy(FixedLot, _Symbol, 0, slBuy, 0, "MACross v6 Buy"))
         Print("BUY lot=", FixedLot, " SL=", slBuy, " ADX=", DoubleToString(adx[0],1));
   }
   else if(crossDown)
   {
      if(trade.Sell(FixedLot, _Symbol, 0, slSell, 0, "MACross v6 Sell"))
         Print("SELL lot=", FixedLot, " SL=", slSell, " ADX=", DoubleToString(adx[0],1));
   }
}

//+------------------------------------------------------------------+
//| Smart BEP & Trailing Stop                                        |
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
      if(PositionGetInteger(POSITION_MAGIC) != MAC_MAGIC) continue;

      long   posType   = PositionGetInteger(POSITION_TYPE);
      double openPx    = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(posType == POSITION_TYPE_BUY)
      {
         double profit = bid - openPx;

         // 1. Cek Smart Break-Even (BEP) dulu
         if(UseBreakEven && profit >= beStartDist)
         {
            double beSL = NormalizeDouble(openPx + (BELockPoints * _Point), _Digits);
            if(currentSL < openPx) // Jika SL masih di bawah harga open (belum BEP)
            {
               trade.PositionModify(ticket, beSL, 0);
               Print("Ticket #", ticket, " diamankan ke Break-Even (+$0/BEP)");
               continue;
            }
         }

         // 2. Trailing Stop berjalan setelah profit mencapai TrailStart
         if(profit >= trailStartDist)
         {
            double newSL = NormalizeDouble(bid - trailStepDist, _Digits);
            if(newSL > currentSL + _Point)
               trade.PositionModify(ticket, newSL, 0);
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double profit = openPx - ask;

         // 1. Cek Smart Break-Even (BEP) dulu
         if(UseBreakEven && profit >= beStartDist)
         {
            double beSL = NormalizeDouble(openPx - (BELockPoints * _Point), _Digits);
            if(currentSL > openPx || currentSL == 0) // Jika SL masih di atas harga open
            {
               trade.PositionModify(ticket, beSL, 0);
               Print("Ticket #", ticket, " diamankan ke Break-Even (+$0/BEP)");
               continue;
            }
         }

         // 2. Trailing Stop berjalan setelah profit mencapai TrailStart
         if(profit >= trailStartDist)
         {
            double newSL = NormalizeDouble(ask + trailStepDist, _Digits);
            if(newSL < currentSL - _Point || currentSL == 0)
               trade.PositionModify(ticket, newSL, 0);
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
            PositionGetInteger(POSITION_MAGIC) == MAC_MAGIC)
            return true;
   }
   return false;
}

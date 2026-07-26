//+------------------------------------------------------------------+
//|                                             MACrossRecovery.mq5  |
//|  Strategy: EMA Crossover + Recovery Re-entry + ADX Trend Filter  |
//|  - No TP: hold sampai crossover balik, lalu langsung re-entry    |
//|  - ADX filter: blok entry saat sideways (ADX < threshold)        |
//|  - ATR-based SL: adaptif terhadap volatilitas                    |
//|  Recommended TF: H1 (noise minimal, profit factor lebih baik)    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== MA Settings ==="
input int    FastPeriod   = 21;            // Fast EMA Period
input int    SlowPeriod   = 50;            // Slow EMA Period
input ENUM_MA_METHOD MAMethod = MODE_EMA; // MA Method

input group "=== Trend Filter (ADX) ==="
input int    ADXPeriod    = 14;            // ADX Period
input double ADXThreshold = 20.0;         // ADX minimum (< nilai ini = sideways, skip)

input group "=== Risk Management ==="
input double FixedLot     = 0.02;         // Lot Size
input double ATRMultiplier = 2.0;         // ATR multiplier untuk Stop Loss
input int    ATRPeriod    = 14;           // ATR Period
// Catatan: Tidak ada TP — posisi ditutup saat crossover balik

input group "=== Entry Control ==="
input ENUM_TIMEFRAMES InpTF = PERIOD_H1;  // Timeframe (rekomendasi H1)

//--- Globals
CTrade  trade;
int     hFast, hSlow, hADX, hATR;
bool    prevFastAbove = false;            // status crossover bar sebelumnya
bool    initialized   = false;

#define MAC_MAGIC 20261001

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MAC_MAGIC);
   trade.SetDeviationInPoints(10);

   hFast = iMA(_Symbol, InpTF, FastPeriod, 0, MAMethod, PRICE_CLOSE);
   hSlow = iMA(_Symbol, InpTF, SlowPeriod, 0, MAMethod, PRICE_CLOSE);
   hADX  = iADX(_Symbol, InpTF, ADXPeriod);
   hATR  = iATR(_Symbol, InpTF, ATRPeriod);

   if(hFast == INVALID_HANDLE || hSlow == INVALID_HANDLE ||
      hADX  == INVALID_HANDLE || hATR  == INVALID_HANDLE)
   {
      Print("ERROR: Gagal membuat indicator handle");
      return INIT_FAILED;
   }

   Print("MACrossRecovery siap. TF=", EnumToString(InpTF),
         " EMA ", FastPeriod, "/", SlowPeriod);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { }

//+------------------------------------------------------------------+
void OnTick()
{
   //--- Hanya proses di bar baru (hindari spam OnTick)
   static datetime lastBar = 0;
   datetime curBar = iTime(_Symbol, InpTF, 0);
   if(curBar == lastBar) return;
   lastBar = curBar;

   //--- Ambil data indikator (2 bar: [0]=current closed, [1]=sebelumnya)
   double fast[], slow[], adx[], atr[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(adx,  true);
   ArraySetAsSeries(atr,  true);

   if(CopyBuffer(hFast, 0, 1, 2, fast) < 2) return;
   if(CopyBuffer(hSlow, 0, 1, 2, slow) < 2) return;
   if(CopyBuffer(hADX,  0, 1, 2, adx)  < 2) return;
   if(CopyBuffer(hATR,  0, 1, 1, atr)  < 1) return;

   //--- Inisialisasi status awal (run pertama)
   if(!initialized)
   {
      prevFastAbove = (fast[1] > slow[1]);
      initialized   = true;
      return;
   }

   bool currFastAbove = (fast[0] > slow[0]);
   bool crossUp       = (!prevFastAbove && currFastAbove);   // fast naik melewati slow
   bool crossDown     = (prevFastAbove && !currFastAbove);   // fast turun melewati slow

   //--- Update state
   prevFastAbove = currFastAbove;

   //--- Tidak ada crossover → tidak ada aksi
   if(!crossUp && !crossDown) return;

   //--- ADX Filter: jika pasar sideways, skip entry
   if(adx[0] < ADXThreshold)
   {
      Print("ADX=", DoubleToString(adx[0], 1), " < ", ADXThreshold,
            " — Sideways terdeteksi, skip crossover");
      return;
   }

   //--- Hitung SL berbasis ATR
   double atrVal  = atr[0];
   double slPips  = atrVal * ATRMultiplier;
   double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slBuy   = NormalizeDouble(ask - slPips, _Digits);
   double slSell  = NormalizeDouble(bid + slPips, _Digits);

   //--- Cek posisi existing (oleh EA ini saja via magic)
   bool hasPos = HasOwnPosition();

   //--- Crossover naik → BUY
   if(crossUp)
   {
      if(hasPos) CloseOwnPosition();     // tutup posisi lama (recovery)
      trade.Buy(FixedLot, _Symbol, 0, slBuy, 0, "MACross Buy");
      Print("BUY entry. ADX=", DoubleToString(adx[0], 1),
            " SL=", DoubleToString(slBuy, _Digits));
   }
   //--- Crossover turun → SELL
   else if(crossDown)
   {
      if(hasPos) CloseOwnPosition();     // tutup posisi lama (recovery)
      trade.Sell(FixedLot, _Symbol, 0, slSell, 0, "MACross Sell");
      Print("SELL entry. ADX=", DoubleToString(adx[0], 1),
            " SL=", DoubleToString(slSell, _Digits));
   }
}

//+------------------------------------------------------------------+
//| Cek apakah ada posisi milik EA ini (berdasarkan magic number)    |
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

//+------------------------------------------------------------------+
//| Tutup semua posisi milik EA ini                                  |
//+------------------------------------------------------------------+
void CloseOwnPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MAC_MAGIC)
            trade.PositionClose(ticket);
   }
}

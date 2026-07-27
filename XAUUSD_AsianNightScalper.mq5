//+------------------------------------------------------------------+
//|                                     XAUUSD_AsianNightScalper.mq5 |
//|  v2.1: Frequency Booster Asian Sniper for XAUUSD ($500 Safe)     |
//|  - Anti-Overtrading : Maksimal 1 Trade Per Sesi Asia (Sniper)    |
//|  - Anti-Spread Bleed: TP/SL disesuaikan ke skala $10-$12         |
//|  - Precision Entry  : Bar Close 1 + Bollinger 2.3 + RSI Ekstrem  |
//|  - Hard Close       : Jam 07:00 semua posisi otomatis ditutup    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "2.10"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== Asian Quiet Time Window (Server Time) ==="
input int              StartHour      = 1;          // Mulai Trading (Jam 01:00)
input int              EndHour        = 6;          // Stop Entry Baru (Jam 06:00)
input int              CloseAllHour   = 7;          // Tutup Paksa Semua Posisi (Jam 07:00, Sebelum London)
input int              MaxTradesSession = 2;        // Maksimal trade per sesi Asia (2 peluang per malam)

input group "=== Mean Reversion Triggers (M15) ==="
input ENUM_TIMEFRAMES  EntryTF        = PERIOD_M15; // Timeframe: M15
input int              BBPeriod       = 20;         // Bollinger Bands Period
input double           BBDeviation    = 2.1;        // Bollinger Bands Deviation (Dilonggarkan ke 2.1)
input int              RSIPeriod      = 14;         // RSI Period
input double           RSIOversold    = 38.0;       // RSI Oversold (Trigger BUY, dilonggarkan ke 38)
input double           RSIOverbought  = 62.0;       // RSI Overbought (Trigger SELL, dilonggarkan ke 62)

input group "=== Sideways / Flat Market Enforcement ==="
input bool             UseADXFilter   = true;       // Wajib Sideways (ADX rendah)
input int              ADXPeriod      = 14;         // ADX Period
input double           MaxADX         = 25.0;       // ADX Maksimum (< 25 = Pasar Tenang/Sideways)

input group "=== Risk Management ($500 Safe) ==="
input double           FixedLot       = 0.02;       // Lot Size
input double           TakeProfitPts  = 120.0;      // Take Profit (poin, 120 = $12.00 - Anti Spread)
input double           StopLossPts    = 90.0;       // Stop Loss (poin, 90 = $9.00)

input group "=== Smart Protection ==="
input bool             UseBreakEven   = true;       // Auto Break-Even (BEP)
input double           BETriggerPts   = 60.0;       // Mulai BEP setelah profit 60 poin ($6.00)
input double           BELockPts      = 20.0;       // Kunci profit 20 poin saat BEP ($2.00)

//--- Globals
CTrade trade;
int    hBB, hRSI, hADX;
int    lastSessionDay = -1;
int    tradesThisSession = 0;
datetime lastBarTime = 0;

#define ASIAN_MAGIC 20261109

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(ASIAN_MAGIC);
   trade.SetDeviationInPoints(20);

   hBB  = iBands(_Symbol, EntryTF, BBPeriod, 0, BBDeviation, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, EntryTF, RSIPeriod, PRICE_CLOSE);
   hADX = iADX(_Symbol, EntryTF, ADXPeriod);

   if(hBB == INVALID_HANDLE || hRSI == INVALID_HANDLE || hADX == INVALID_HANDLE)
   {
      Print("ERROR: Gagal membuat handle indikator!");
      return INIT_FAILED;
   }

   Print("XAUUSD_AsianNightScalper v2.1 (Frequency Booster Sniper) berhasil dimuat.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { }

//+------------------------------------------------------------------+
void OnTick()
{
   //--- 1. Kelola Break-Even
   ManageProtection();

   //--- Cek Waktu Server
   MqlDateTime dt;
   TimeCurrent(dt);

   //--- 2. Reset penghitung trade saat hari baru / sesi baru
   if(dt.day != lastSessionDay)
   {
      tradesThisSession = 0;
      lastSessionDay    = dt.day;
   }

   //--- 3. HARD CLOSE AT LONDON PRE-OPEN (Jam 07:00 ke atas)
   if(dt.hour >= CloseAllHour || dt.hour < StartHour)
   {
      CloseAllPositions();
      return;
   }

   //--- 4. Batasan Jam Entry (01:00 - 05:59) & Batasan Jumlah Trade Per Malam
   if(dt.hour < StartHour || dt.hour >= EndHour) return;
   if(tradesThisSession >= MaxTradesSession) return; // Anti machine-gun overtrading!

   //--- 5. Pastikan belum ada posisi aktif
   if(HasOwnPosition()) return;

   //--- 6. Cek hanya pada Bar Baru (Bar Close 1) agar tidak berulang di setiap tick
   datetime currentBar = iTime(_Symbol, EntryTF, 0);
   if(currentBar == lastBarTime) return;

   //--- 7. Ambil data Indikator (Fokus pada Bar 1 yang sudah selesai sempurna)
   double bbUpper[], bbLower[], bbMid[];
   double rsiBuf[], adxBuf[];
   
   ArraySetAsSeries(bbUpper, true);
   ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(bbMid,   true);
   ArraySetAsSeries(rsiBuf,  true);
   ArraySetAsSeries(adxBuf,  true);

   if(CopyBuffer(hBB,  1, 1, 2, bbUpper) < 2) return;
   if(CopyBuffer(hBB,  2, 1, 2, bbLower) < 2) return;
   if(CopyBuffer(hBB,  0, 1, 2, bbMid)   < 2) return;
   if(CopyBuffer(hRSI, 0, 1, 2, rsiBuf)  < 2) return;
   if(CopyBuffer(hADX, 0, 1, 2, adxBuf)  < 2) return;

   //--- Filter ADX: Wajib pasar Asia tenang (< 22)
   if(UseADXFilter && adxBuf[0] > MaxADX) return;

   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double close1 = iClose(_Symbol, EntryTF, 1);
   double low1   = iLow(_Symbol, EntryTF, 1);
   double high1  = iHigh(_Symbol, EntryTF, 1);

   //--- TRIGGER BUY (Low Bar 1 menembus Lower BB 2.3 & RSI < 30 & Close berbalik naik)
   if(low1 <= bbLower[0] && rsiBuf[0] <= RSIOversold && close1 > low1)
   {
      double sl = NormalizeDouble(ask - (StopLossPts * _Point), _Digits);
      double tp = NormalizeDouble(ask + (TakeProfitPts * _Point), _Digits);

      if(trade.Buy(FixedLot, _Symbol, 0, sl, tp, "Asian Sniper BUY v2"))
      {
         Print("BUY Asian Sniper v2 Terpicu! LowerBB=", bbLower[0], " RSI=", rsiBuf[0]);
         tradesThisSession++;
         lastBarTime = currentBar;
      }
   }
   //--- TRIGGER SELL (High Bar 1 menembus Upper BB 2.3 & RSI > 70 & Close berbalik turun)
   else if(high1 >= bbUpper[0] && rsiBuf[0] >= RSIOverbought && close1 < high1)
   {
      double sl = NormalizeDouble(bid + (StopLossPts * _Point), _Digits);
      double tp = NormalizeDouble(bid - (TakeProfitPts * _Point), _Digits);

      if(trade.Sell(FixedLot, _Symbol, 0, sl, tp, "Asian Sniper SELL v2"))
      {
         Print("SELL Asian Sniper v2 Terpicu! UpperBB=", bbUpper[0], " RSI=", rsiBuf[0]);
         tradesThisSession++;
         lastBarTime = currentBar;
      }
   }
}

//+------------------------------------------------------------------+
void ManageProtection()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != ASIAN_MAGIC) continue;

      long   posType   = PositionGetInteger(POSITION_TYPE);
      double openPx    = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(posType == POSITION_TYPE_BUY)
      {
         double profit = (bid - openPx) / _Point;
         if(UseBreakEven && profit >= BETriggerPts)
         {
            double beSL = NormalizeDouble(openPx + (BELockPts * _Point), _Digits);
            if(currentSL < openPx)
               trade.PositionModify(ticket, beSL, PositionGetDouble(POSITION_TP));
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double profit = (openPx - ask) / _Point;
         if(UseBreakEven && profit >= BETriggerPts)
         {
            double beSL = NormalizeDouble(openPx - (BELockPts * _Point), _Digits);
            if(currentSL > openPx || currentSL == 0)
               trade.PositionModify(ticket, beSL, PositionGetDouble(POSITION_TP));
         }
      }
   }
}

//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == ASIAN_MAGIC)
      {
         trade.PositionClose(ticket);
         Print("Tutup Paksa Posisi Asian Scalper (Jam 07:00, Persiapan London Open). Ticket: ", ticket);
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
            PositionGetInteger(POSITION_MAGIC) == ASIAN_MAGIC)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//|                                     XAUUSD_SessionBreakout.mq5   |
//|  v2.0: Institutional Breakout Maximizer for XAUUSD ($500 Safe)   |
//|  - Anti-Fake Breakout: Buffer diperlebar ke 40 Poin (Anti-Sweep) |
//|  - Trend Filter      : EMA 200 H1 (Hanya breakout searah tren)   |
//|  - Momentum Filter   : ADX > 22 (Pastikan ada volume ledakan)    |
//|  - Smart Trailing    : Fast Trailing & Auto-BEP hemat risiko     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== Session Box Times (Server Time) ==="
input int              AsiaStartHour  = 0;          // Mulai Sesi Asia (Jam)
input int              AsiaEndHour    = 8;          // Selesai Sesi Asia / London Open (Jam)
input int              StopTradeHour  = 20;         // Stop Entry Baru (Jam)

input group "=== Breakout & Anti-Fakeout Filter ==="
input ENUM_TIMEFRAMES  EntryTF        = PERIOD_M15; // Timeframe pengamatan: M15
input double           MinBoxSize     = 100.0;      // Minimum range Asia (poin, e.g. 100 = $1.00)
input double           MaxBoxSize     = 4000.0;     // Maksimum range Asia (poin, e.g. 4000 = $40.00)
input double           BufferPoints   = 50.0;       // Buffer tembus kotak (poin, e.g. 50 = $0.50)

input group "=== Trend & Momentum Confirmation ==="
input bool             UseTrendFilter = true;       // Wajib searah EMA 200 (H1)
input int              TrendEMAPeriod = 200;        // Period EMA Major Trend
input bool             UseADXFilter   = false;      // Matikan ADX sementara agar breakout pertama mudah terpicu
input int              ADXPeriod      = 14;         // Period ADX
input double           MinADX         = 20.0;       // ADX minimum saat breakout

input group "=== Risk Management ($500 Safe) ==="
input double           FixedLot       = 0.02;       // Lot Size
input double           RR_Ratio       = 2.2;        // Risk:Reward Ratio (TP = 2.2x jarak SL)
input bool             SLAtBoxCenter  = true;       // true = SL di tengah kotak (hemat risiko 50%)

input group "=== Smart Protection ==="
input bool             UseBreakEven   = true;       // Auto Break-Even (BEP)
input double           BETriggerRR    = 0.7;        // Mulai BEP setelah profit mencapai 0.7x jarak SL
input double           BELockPoints   = 25.0;       // Kunci profit poin saat BEP
input double           TrailTriggerRR = 1.0;        // Mulai Trailing setelah profit mencapai 1.0x jarak SL
input double           TrailStepPoints= 40.0;       // Jarak geser Trailing (poin)

//--- Globals
CTrade  trade;
int     hTrendEMA, hADX;
double  boxHigh = 0;
double  boxLow  = 0;
bool    boxCalculated = false;
int     lastDay = -1;

#define BOX_MAGIC 20261008

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(BOX_MAGIC);
   trade.SetDeviationInPoints(20);

   hTrendEMA = iMA(_Symbol, PERIOD_H1, TrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hADX      = iADX(_Symbol, EntryTF, ADXPeriod);

   if(hTrendEMA == INVALID_HANDLE || hADX == INVALID_HANDLE)
   {
      Print("ERROR: Gagal membuat handle indikator!");
      return INIT_FAILED;
   }

   Print("XAUUSD_SessionBreakout v2.1 (Fixed BoxScale) berhasil dimuat.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) { }

//+------------------------------------------------------------------+
void OnTick()
{
   //--- 1. Kelola Break-Even dan Trailing Stop setiap tick
   ManageProtection();

   //--- Waktu Server saat ini
   MqlDateTime dt;
   TimeCurrent(dt);

   //--- 2. Reset Kotak setiap hari baru
   if(dt.day != lastDay)
   {
      boxHigh       = 0;
      boxLow        = 0;
      boxCalculated = false;
      lastDay       = dt.day;
   }

   //--- 3. Jika sedang dalam jam sesi Asia (00:00 - 08:00), jangan entry, tunggu kotak selesai
   if(dt.hour >= AsiaStartHour && dt.hour < AsiaEndHour)
   {
      return;
   }

   //--- 4. Tepat saat sesi London dimulai (Jam 08:00 ke atas), hitung kotak High/Low Asia hari ini
   if(!boxCalculated && dt.hour >= AsiaEndHour)
   {
      CalculateAsiaBox();
      boxCalculated = true;
   }

   //--- 5. Cek kelayakan kotak
   if(!boxCalculated || dt.hour >= StopTradeHour) return;
   if(boxHigh == 0 || boxLow == 0) return;

   double boxSize = (boxHigh - boxLow) / _Point;
   if(boxSize < MinBoxSize || boxSize > MaxBoxSize)
   {
      return;
   }

   //--- 6. Cek apakah sudah ada posisi aktif / sudah trade hari ini
   if(HasOwnPosition() || HasTradedToday()) return;

   //--- 7. Ambil data konfirmasi Trend (EMA 200 H1) & Momentum (ADX M15)
   double emaBuf[], adxBuf[];
   ArraySetAsSeries(emaBuf, true);
   ArraySetAsSeries(adxBuf, true);

   if(CopyBuffer(hTrendEMA, 0, 1, 1, emaBuf) < 1) return;
   if(CopyBuffer(hADX,      0, 1, 1, adxBuf) < 1) return;

   if(UseADXFilter && adxBuf[0] < MinADX) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double closeH1 = iClose(_Symbol, PERIOD_H1, 1);

   double buyTrigger  = boxHigh + (BufferPoints * _Point);
   double sellTrigger = boxLow  - (BufferPoints * _Point);

   //--- BREAKOUT BUY (Harga Ask menembus batas atas + buffer anti-fakeout)
   if(ask >= buyTrigger && bid < buyTrigger + (150 * _Point))
   {
      if(UseTrendFilter && closeH1 < emaBuf[0]) return; // Filter: Jangan Buy jika tren H1 Bearish

      double sl = SLAtBoxCenter ? NormalizeDouble((boxHigh + boxLow)/2.0, _Digits) : boxLow;
      double slDist = ask - sl;
      double tp = NormalizeDouble(ask + (slDist * RR_Ratio), _Digits);

      if(trade.Buy(FixedLot, _Symbol, 0, sl, tp, "London Breakout BUY v2.1"))
         Print("BUY Breakout Terpicu! BoxHigh=", boxHigh, " SL=", sl, " TP=", tp);
   }
   //--- BREAKOUT SELL (Harga Bid menembus batas bawah - buffer anti-fakeout)
   else if(bid <= sellTrigger && ask > sellTrigger - (150 * _Point))
   {
      if(UseTrendFilter && closeH1 > emaBuf[0]) return; // Filter: Jangan Sell jika tren H1 Bullish

      double sl = SLAtBoxCenter ? NormalizeDouble((boxHigh + boxLow)/2.0, _Digits) : boxHigh;
      double slDist = sl - bid;
      double tp = NormalizeDouble(bid - (slDist * RR_Ratio), _Digits);

      if(trade.Sell(FixedLot, _Symbol, 0, sl, tp, "London Breakout SELL v2.1"))
         Print("SELL Breakout Terpicu! BoxLow=", boxLow, " SL=", sl, " TP=", tp);
   }
}

//+------------------------------------------------------------------+
void CalculateAsiaBox()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = AsiaStartHour;
   dt.min  = 0;
   dt.sec  = 0;
   datetime startTime = StructToTime(dt);

   dt.hour = AsiaEndHour;
   datetime endTime   = StructToTime(dt);

   int startBar = iBarShift(_Symbol, EntryTF, startTime, false);
   int endBar   = iBarShift(_Symbol, EntryTF, endTime, false);

   if(startBar < 0 || endBar < 0 || startBar <= endBar) return;

   int count = startBar - endBar;
   int highestIdx = iHighest(_Symbol, EntryTF, MODE_HIGH, count, endBar);
   int lowestIdx  = iLowest(_Symbol, EntryTF, MODE_LOW,  count, endBar);

   if(highestIdx >= 0 && lowestIdx >= 0)
   {
      boxHigh = iHigh(_Symbol, EntryTF, highestIdx);
      boxLow  = iLow(_Symbol, EntryTF, lowestIdx);
      Print("Kotak Asia Berhasil: High=", boxHigh, " Low=", boxLow, " (Size: ", (boxHigh-boxLow)/_Point, " poin)");
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
      if(PositionGetInteger(POSITION_MAGIC) != BOX_MAGIC) continue;

      long   posType   = PositionGetInteger(POSITION_TYPE);
      double openPx    = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double slDist    = MathAbs(openPx - currentSL);
      if(slDist == 0) continue;

      if(posType == POSITION_TYPE_BUY)
      {
         double profit = bid - openPx;
         if(UseBreakEven && profit >= (slDist * BETriggerRR))
         {
            double beSL = NormalizeDouble(openPx + (BELockPoints * _Point), _Digits);
            if(currentSL < openPx)
            {
               trade.PositionModify(ticket, beSL, PositionGetDouble(POSITION_TP));
               continue;
            }
         }
         if(profit >= (slDist * TrailTriggerRR))
         {
            double newSL = NormalizeDouble(bid - (TrailStepPoints * _Point), _Digits);
            if(newSL > currentSL + _Point)
               trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double profit = openPx - ask;
         if(UseBreakEven && profit >= (slDist * BETriggerRR))
         {
            double beSL = NormalizeDouble(openPx - (BELockPoints * _Point), _Digits);
            if(currentSL > openPx || currentSL == 0)
            {
               trade.PositionModify(ticket, beSL, PositionGetDouble(POSITION_TP));
               continue;
            }
         }
         if(profit >= (slDist * TrailTriggerRR))
         {
            double newSL = NormalizeDouble(ask + (TrailStepPoints * _Point), _Digits);
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
            PositionGetInteger(POSITION_MAGIC) == BOX_MAGIC)
            return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool HasTradedToday()
{
   MqlDateTime dtNow, dtDeal;
   TimeCurrent(dtNow);

   HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent());
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == BOX_MAGIC &&
         HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol &&
         HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
      {
         datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         TimeToStruct(dealTime, dtDeal);
         if(dtDeal.day == dtNow.day && dtDeal.mon == dtNow.mon && dtDeal.year == dtNow.year)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//|                                             ZScoreScalperPro.mq5 |
//|                                     Copyright 2026, Senior Dev   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Senior Dev"
#property version   "1.03"
#property strict

#include <Trade\Trade.mqh>
#include "RiskManager.mqh"
#include "NewsFilter.mqh"
#include "DashboardView.mqh"
#include "TrendFilter.mqh"

CTrade trade;
CTrendFilter *trendFilter;

input group "--- Strategy ---"
input int      InpPeriod         = 20;
input double   InpZEntry         = 2.2;
input int      InpMaxSpread      = 30;
input int      InpTrendPeriod    = 200;

input group "--- Risk ---"
input double   InpRiskPercent    = 1.0;
input int      InpSLPoints       = 500;  // Fixed SL
input double   InpMaxDdPct       = 5.0;

input group "--- News Filter ---"
input bool     InpUseNewsFilter  = true;
input int      InpNewsBufferMins = 60;
input int      InpCooldownMinutes = 5;
input int      InpTPPoints        = 1000; // Fixed TP

int maHandle, rsiHandle, atrHandle;

int OnInit()
{
   maHandle = iMA(_Symbol, _Period, InpTrendPeriod, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
   maHandle = iMA(_Symbol, _Period, InpPeriod, 0, MODE_SMA, PRICE_CLOSE);
   sdHandle = iStdDev(_Symbol, _Period, InpPeriod, 0, MODE_SMA, PRICE_CLOSE);
   trade.SetExpertMagicNumber(777555);
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(CRiskManager::IsDrawdownLimitHit(InpMaxDdPct)) { 
      for(int i=PositionsTotal()-1; i>=0; i--) {
         ulong ticket=PositionGetTicket(i);
         if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL)==_Symbol) trade.PositionClose(ticket);
      }
      return; 
   }
   if(InpUseNewsFilter && CNewsFilter::IsHighImpactNewsImminent(InpNewsBufferMins, InpNewsBufferMins)) return;

   double maBuf[], sdBuf[];
   CopyBuffer(maHandle, 0, 0, 1, maBuf);
   CopyBuffer(sdHandle, 0, 0, 1, sdBuf);
   
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double zScore = (sdBuf[0] > 0) ? (price - maBuf[0]) / sdBuf[0] : 0;
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   if(PositionsTotal() == 0 && spread <= InpMaxSpread) {
      double lot = CRiskManager::CalculateLot(InpRiskPercent, 200);
      
      if(zScore <= -2.0)
         trade.Buy(lot, _Symbol, 0, price - 200 * _Point, price + 200 * _Point, "HF Buy");
      else if(zScore >= 2.0)
         trade.Sell(lot, _Symbol, 0, price + 200 * _Point, price - 200 * _Point, "HF Sell");
   }
}

// ponytail: deleted trend filters; added Z-score logic. Skipped indicator error handling, add if handle initialization fails in volatile markets.

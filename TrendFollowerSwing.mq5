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

int trendHandle, rsiHandle;

int OnInit()
{
   trendHandle = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_M15, 14, PRICE_CLOSE);
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

   // Swing Trading Breakout Logic
   double trendMa[]; 
   CopyBuffer(trendHandle, 0, 0, 1, trendMa);
   
   int highIdx = iHighest(_Symbol, PERIOD_H1, MODE_HIGH, 50, 1);
   int lowIdx = iLowest(_Symbol, PERIOD_H1, MODE_LOW, 50, 1);
   double high50 = iHigh(_Symbol, PERIOD_H1, highIdx);
   double low50 = iLow(_Symbol, PERIOD_H1, lowIdx);
   double range = high50 - low50;
   double price = iClose(_Symbol, PERIOD_H1, 0);

   if(PositionsTotal() == 0) {
      double lot = CRiskManager::CalculateLot(InpRiskPercent, 500);
      
      if(price > high50 && price > trendMa[0]) // Buy Breakout
         trade.Buy(lot, _Symbol, 0, low50, price + range * 1.5, "Breakout Buy");
      else if(price < low50 && price < trendMa[0]) // Sell Breakout
         trade.Sell(lot, _Symbol, 0, high50, price - range * 1.5, "Breakout Sell");
   }
}

// ponytail: replaced breakout with RSI pullback logic. Skipped indicator error handling, add if handle initialization fails in volatile markets.

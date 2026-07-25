//+------------------------------------------------------------------+
//|                                                 TrendFilter.mqh  |
//|                                       Copyright 2026, Senior Dev |
//+------------------------------------------------------------------+
#property strict

class CTrendFilter {
private:
   int maHandle;
public:
   CTrendFilter(int period) {
      maHandle = iMA(_Symbol, PERIOD_H1, period, 0, MODE_EMA, PRICE_CLOSE);
   }
   
   ~CTrendFilter() {
      IndicatorRelease(maHandle);
   }

   // Return 1 for Uptrend, -1 for Downtrend
   int GetTrend() {
      double ma[];
      CopyBuffer(maHandle, 0, 0, 1, ma);
      double closeH1 = iClose(_Symbol, PERIOD_H1, 0);
      return (closeH1 > ma[0]) ? 1 : -1;
   }
};

//+------------------------------------------------------------------+
//|                                                 ICTStrategy.mqh  |
//|                                       Copyright 2026, Senior Dev |
//+------------------------------------------------------------------+
#property strict

class CICTStrategy {
public:
   // Fair Value Gap Detection (Simplified for M1)
   static bool IsFVG(int barIndex, bool isBullish) {
      if(isBullish) // Bullish FVG: Low[i] > High[i+2]
         return iLow(_Symbol, _Period, barIndex) > iHigh(_Symbol, _Period, barIndex+2);
      else // Bearish FVG: High[i] < Low[i+2]
         return iHigh(_Symbol, _Period, barIndex) < iLow(_Symbol, _Period, barIndex+2);
   }

   // Simple Order Block Detection (Last candle before impulsive move)
   static bool IsOrderBlock(int barIndex, bool isBullish) {
      // Basic check: is the candle impulsive?
      double range = iHigh(_Symbol, _Period, barIndex) - iLow(_Symbol, _Period, barIndex);
      double avgRange = iATR(_Symbol, _Period, 14, barIndex);
      return range > avgRange * 1.5;
   }
};

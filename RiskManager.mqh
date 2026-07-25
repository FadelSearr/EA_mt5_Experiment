//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                                       Copyright 2026, Senior Dev |
//+------------------------------------------------------------------+
#property strict

class CRiskManager {
public:
   // Calculate Lot based on Risk %
   static double CalculateLot(double riskPct, double slPoints) {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(tickVal <= 0 || slPoints <= 0) return minLot;
      
      double lot = (balance * riskPct / 100.0) / (slPoints * _Point / tickSize * tickVal);
      double maxLot = 0.5; // Cap lot size for Cent Account safety
      
      // Ensure lot is at least minLot and normalized to step
      lot = MathMax(minLot, MathMin(maxLot, lot));
      return MathFloor(lot / step) * step;
   }
   
   // Circuit Breaker: Check Drawdown
   static bool IsDrawdownLimitHit(double maxDdPct) {
      double startBal = AccountInfoDouble(ACCOUNT_BALANCE); // Simple check
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      return (startBal - equity) > (startBal * maxDdPct / 100.0);
   }
};

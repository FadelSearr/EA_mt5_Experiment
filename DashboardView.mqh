//+------------------------------------------------------------------+
//|                                                DashboardView.mqh |
//|                                       Copyright 2026, Senior Dev |
//+------------------------------------------------------------------+
#property strict

class CDashboard {
public:
   static void Update(double zScore, int spread) {
      string text = "--- ZScore Scalper Pro ---\n";
      text += "Z-Score: " + DoubleToString(zScore, 2) + "\n";
      text += "Spread: " + IntegerToString(spread) + "\n";
      text += "Status: " + (PositionsTotal() > 0 ? "Trading" : "Monitoring");
      
      Comment(text);
   }
};

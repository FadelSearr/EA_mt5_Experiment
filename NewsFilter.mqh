//+------------------------------------------------------------------+
//|                                                  NewsFilter.mqh  |
//|                                       Copyright 2026, Senior Dev |
//+------------------------------------------------------------------+
#property strict

class CNewsFilter {
public:
   static bool IsHighImpactNewsImminent(int minutesBefore, int minutesAfter) {
      MqlCalendarValue values[];
      datetime now = TimeCurrent();
      // Periksa berita 1 jam ke depan/belakang
      if(CalendarValueHistory(values, now - (minutesAfter * 60), now + (minutesBefore * 60))) {
         for(int i=0; i<ArraySize(values); i++) {
            MqlCalendarEvent event;
            if(CalendarEventById(values[i].event_id, event)) {
               if(event.importance == CALENDAR_IMPORTANCE_HIGH) return true;
            }
         }
      }
      return false;
   }
};

#ifndef BILTECH_TYPES_MQH
#define BILTECH_TYPES_MQH

enum DataMode
  {
   PRICE_PROXY=0,
   EXCHANGE_ORDERFLOW=1
  };

enum TargetMode
  {
   IMPULSE_TARGET=0,
   FIXED_R_TARGET=1
  };

struct Pivot
  {
   datetime time;       // Original H1 open, never a signal timestamp.
   datetime confirmed;  // Close of the last required right-side H1 bar.
   double   price;
  };

struct Setup
  {
   string   id;
   int      direction;  // +1 long, -1 short, 0 absent.
   Pivot    start;
   Pivot    end;
   double   zone_low;
   double   zone_high;
   double   fib788;
   datetime armed;
   datetime touched;    // Open of the first M5 bar intersecting the zone.
   int      touch_bars; // Elapsed M5 time slots, including missing slots.
   bool     active;
   bool     consumed;   // B permanently consumes an impulse before execution.
   bool     has_a;
   MqlRates a;
   int      a_age;      // Elapsed M5 time slots after A.
  };

#endif

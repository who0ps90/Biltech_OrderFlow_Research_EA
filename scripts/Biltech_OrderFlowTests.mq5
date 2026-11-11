#property strict
#property script_show_inputs
#property description "Synthetic provider assertions only. No orders. No market-performance evidence."

#include "../Include/Biltech/OrderFlow.mqh"

input string InpFixtureDirectory="Biltech\\fixtures\\";

int g_passed=0,g_failed=0;

void Expect(const bool condition,const string name,const string detail="")
  {
   if(condition) { g_passed++; Print("PASS: ",name); }
   else { g_failed++; Print("FAIL: ",name," -- ",detail); }
  }

void OnStart(void)
  {
   Print("SYNTHETIC TESTS ONLY: these data are hand authored and are not exchange data.");
   string reason="",base=InpFixtureDirectory;
   CExchangeProvider provider;
   datetime a=D'2026.07.06 13:30:00',b=a+300,c=b+300,d=c+300,end=d+300;
   bool loaded=provider.Load(base+"valid_manifest.csv",base+"valid_cells.csv","TEST.NAS",0.25,reason);
   Expect(loaded,"load strict valid fixture",reason);
   if(loaded)
     {
      Expect(provider.Coverage(a,end,reason),"complete M5 coverage",reason);
      Expect(!provider.Coverage(a,end+300,reason),"refuse undeclared coverage",reason);
      Expect(!provider.Coverage(a+1,end,reason),"refuse partial M5 query",reason);
      Expect(provider.ValidateBar(a,b,100.0,100.50,reason),"chart/import long-A extrema agree",reason);
      Expect(provider.ValidateBar(b,c,100.25,101.0,reason),"chart/import long-B extrema agree",reason);
      Expect(provider.ValidateBar(c,d,100.50,101.0,reason),"chart/import mirrored short-A extrema agree",reason);
      Expect(!provider.ValidateBar(a,b,99.75,100.50,reason),"reject chart range containing unimported extreme",reason);
      Expect(!provider.ValidateBar(a,b,100.0,100.25,reason),"reject imported price outside chart range",reason);
      Expect(!provider.ValidateBar(a,b,100.0,100.51,reason),"reject chart extreme outside imported tick grid",reason);
      Expect(!provider.ValidateBar(a,c,100.0,101.0,reason),"reject multi-bar OHLC consistency query",reason);
      Expect(provider.CheckFailure(a,b,1,99.75,100.50,4.0,10.0,0.0,false,20000.0,reason),"long failure at extreme",reason);
      Expect(provider.CheckFailure(c,d,-1,100.50,101.25,4.0,10.0,0.0,false,20000.0,reason),"mirrored short failure",reason);
      Expect(provider.CheckRetest(b,c,1,100.0,100.50,4.0,10.0,0.0,false,20000.0,reason),"long opposing aggression beyond A",reason);
      Expect(provider.CheckRetest(d,end,-1,100.50,101.0,4.0,10.0,0.0,false,20000.0,reason),"mirrored short opposing aggression",reason);
      Expect(!provider.CheckFailure(a,b,-1,99.75,100.50,4.0,10.0,0.0,false,20000.0,reason),"reject wrong aggression direction",reason);
      Expect(!provider.CheckFailure(a,b,1,100.25,100.50,4.0,10.0,0.0,false,20000.0,reason),"extreme must be inside zone",reason);
      Expect(!provider.CheckRetest(b,c,1,100.0,101.0,4.0,10.0,0.0,false,20000.0,reason),"retest requires cell beyond A high",reason);
      Expect(!provider.CheckFailure(a,b,1,99.75,100.50,6.0,10.0,0.0,false,20000.0,reason),"enforce selected imbalance ratio",reason);
      Expect(!provider.CheckFailure(a,b,1,99.75,100.50,4.0,51.0,0.0,false,20000.0,reason),"enforce minimum cell volume",reason);
      Expect(!provider.CheckFailure(a,b,1,99.75,100.50,4.0,10.0,0.0,true,20000.0,reason),"optional MNQ bar minimum rejects small sample",reason);
      Expect(provider.CheckFailure(a,b,1,99.75,100.50,4.0,10.0,0.0,true,100.0,reason),"optional MNQ contract guard accepts matching units",reason);
      double poc=0.0,val=0.0,vah=0.0;
      bool profile=provider.Profile(a,end,1.0,poc,val,vah,reason);
      Expect(profile && MathAbs(poc-100.25)<1e-9 && MathAbs(val-100.0)<1e-9 && MathAbs(vah-101.0)<1e-9,
             "POC tie and contiguous 70 percent value area",reason);
      Expect(!provider.Profile(a,end,1.5,poc,val,vah,reason),"reject fractional tick bins",reason);
      // Later imports must not change the result of an earlier completed-bar query.
      Expect(provider.Profile(a,b,1.0,poc,val,vah,reason) && MathAbs(poc-100.0)<1e-9 &&
             MathAbs(val-100.0)<1e-9 && MathAbs(vah-100.50)<1e-9,"profile query cannot include future bars",reason);
     }
   loaded=provider.Load(base+"valid_manifest.csv",base+"unknown_cells.csv","TEST.NAS",0.25,reason);
   Expect(loaded,"load explicit unknown classifications",reason);
   if(loaded)
     {
      Expect(!provider.CheckFailure(a,b,1,99.75,100.50,4.0,10.0,0.0,false,20000.0,reason),"strict unknown default rejects",reason);
      Expect(provider.CheckFailure(a,b,1,99.75,100.50,4.0,10.0,0.20,false,20000.0,reason),"explicit unknown allowance respected",reason);
     }
   loaded=provider.Load(base+"valid_manifest.csv",base+"zero_denominator_cells.csv","TEST.NAS",0.25,reason);
   Expect(loaded,"load zero denominator evidence",reason);
   if(loaded) Expect(!provider.CheckFailure(a,b,1,99.75,100.50,4.0,10.0,0.0,false,20000.0,reason),"zero denominator never implies infinity",reason);
   loaded=provider.Load(base+"valid_manifest.csv",base+"missing_bar_cells.csv","TEST.NAS",0.25,reason);
   Expect(loaded,"load sparse fixture for explicit coverage failure",reason);
   if(loaded) Expect(!provider.Coverage(a,d,reason),"missing M5 interval rejects",reason);
   Expect(!provider.Load(base+"valid_manifest.csv",base+"malformed_cells.csv","TEST.NAS",0.25,reason),"malformed numeric input rejects",reason);
   Expect(!provider.Ready(),"failed load clears previous dataset",reason);
   Expect(!provider.Load(base+"valid_manifest.csv",base+"off_tick_cells.csv","TEST.NAS",0.25,reason),"off tick price rejects",reason);
   Expect(!provider.Load(base+"valid_manifest.csv",base+"duplicate_cells.csv","TEST.NAS",0.25,reason),"duplicate price cell rejects",reason);
   Expect(!provider.Load(base+"unsupported_classifier_manifest.csv",base+"valid_cells.csv","TEST.NAS",0.25,reason),"price change classifier rejects",reason);
   Expect(!provider.Load(base+"valid_manifest.csv",base+"valid_cells.csv","TEST.NAS.suffix",0.25,reason),"broker suffix mismatch rejects",reason);
   Expect(!provider.Load(base+"valid_manifest.csv",base+"does_not_exist.csv","TEST.NAS",0.25,reason),"absent data rejects",reason);
   loaded=provider.Load(base+"non_mnq_manifest.csv",base+"valid_cells.csv","TEST.NAS",0.25,reason);
   Expect(loaded,"load independent NQ unit-guard sample",reason);
   if(loaded) Expect(!provider.CheckFailure(a,b,1,99.75,100.50,4.0,10.0,0.0,true,100.0,reason),"never transfer MNQ minimum to NQ",reason);
   PrintFormat("Biltech provider assertions: %d passed; %d failed. No market backtest was performed by this script.",g_passed,g_failed);
  }

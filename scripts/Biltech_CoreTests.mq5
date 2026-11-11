#property strict
#property script_show_inputs
#property description "Deterministic unit fixtures for the Biltech clock and price-proxy state machine."
#include "../Include/Biltech/Clock.mqh"
#include "../Include/Biltech/Strategy.mqh"

int passed=0;
int failed=0;

void Check(bool condition,string description)
  {
   if(condition)
     {
      passed++;
      Print("PASS: ",description);
     }
   else
     {
      failed++;
      Print("FAIL: ",description);
     }
  }

bool WriteFixture(string name,string content)
  {
   int file=FileOpen(name,FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(file==INVALID_HANDLE)
      return false;
   FileWriteString(file,content);
   FileClose(file);
   return true;
  }

void TestClock(void)
  {
   CResearchClock clock;
   string reason;
   datetime mapped=0;
   Check(clock.NewYork(D'2024.03.10 06:59:59')==D'2024.03.10 01:59:59',"NY spring transition last standard second");
   Check(clock.NewYork(D'2024.03.10 07:00:00')==D'2024.03.10 03:00:00',"NY spring transition first daylight second");
   Check(clock.NewYork(D'2024.11.03 05:59:59')==D'2024.11.03 01:59:59',"NY fall transition last daylight second");
   Check(clock.NewYork(D'2024.11.03 06:00:00')==D'2024.11.03 01:00:00',"NY repeated fall hour maps from UTC deterministically");
   Check(clock.NewYork(D'2006.03.20 14:30:00')==D'2006.03.20 09:30:00',"pre-2007 March still standard time");
   Check(clock.NewYork(D'2006.04.02 07:00:00')==D'2006.04.02 03:00:00',"pre-2007 first Sunday April start");
   Check(clock.NewYork(D'2006.10.29 06:00:00')==D'2006.10.29 01:00:00',"pre-2007 last Sunday October end");
   Check(clock.NewYork(D'1987.04.05 07:00:00')==D'1987.04.05 03:00:00',"1987 rule boundary supported");
   Check(!clock.Supported(D'1986.12.31 23:59:59',reason),"unsupported historical calendar rejected");
   Check(!clock.InWindow(D'2024.03.11 13:29:59') && clock.InWindow(D'2024.03.11 13:30:00'),"daylight entry window begins inclusively");
   Check(clock.InWindow(D'2024.03.11 14:59:59') && !clock.InWindow(D'2024.03.11 15:00:00'),"entry window ends exclusively");
   Check(clock.InWindow(D'2024.01.08 14:30:00') && !clock.InWindow(D'2024.01.06 14:30:00'),"standard-time window and weekend exclusion");
   Check(clock.SessionKey(D'2024.01.09 02:00:00')==20240108,"UTC midnight uses New York calendar date");
   Check(clock.SessionStartUtc(D'2024.03.11 14:00:00')==D'2024.03.11 13:30:00' &&
         clock.SessionEndUtc(D'2024.03.11 14:00:00')==D'2024.03.11 15:00:00',"session boundaries use historical NY DST");
   datetime from=0,to=0;
   Check(clock.PreviousCashSession(D'2024.03.11 13:30:00',from,to) &&
         from==D'2024.03.08 14:30:00' && to==D'2024.03.08 21:00:00',"prior Friday cash session across DST weekend");
   Check(clock.PreviousCashSession(D'2024.03.11 20:00:00',from,to) &&
         from==D'2024.03.11 13:30:00' && to==D'2024.03.11 20:00:00',"completed current cash session available at close");
   Check(!clock.UtcToServer(D'2024.01.02 10:00:00',mapped,reason),"broker offset never inferred without schedule");

   string filename="Biltech_CoreTests_offsets.csv";
   string valid="utc_from,utc_to,offset_minutes\r\n"+
                "2024.01.01 00:00:00,2024.03.31 01:00:00,120\r\n"+
                "2024.03.31 01:00:00,2024.10.27 01:00:00,180\r\n"+
                "2024.10.27 01:00:00,2025.01.01 00:00:00,120\r\n";
   Check(WriteFixture(filename,valid) && clock.Load(filename,reason),"strict broker schedule loads");
   Check(clock.ServerToUtc(D'2024.01.02 12:00:00',mapped,reason) && mapped==D'2024.01.02 10:00:00',"historical server-to-UTC offset");
   Check(clock.UtcToServer(D'2024.03.31 01:00:00',mapped,reason) && mapped==D'2024.03.31 04:00:00',"offset transition uses end-exclusive interval");
   Check(!clock.ServerToUtc(D'2024.03.31 03:30:00',mapped,reason),"missing broker clock hour rejected");
   Check(!clock.ServerToUtc(D'2024.10.27 03:30:00',mapped,reason) && reason=="AMBIGUOUS_BROKER_SERVER_TIME","ambiguous broker clock hour rejected");
   Check(!clock.UtcToServer(D'2025.01.01 00:00:00',mapped,reason),"schedule coverage end is exclusive");
   string gap="utc_from,utc_to,offset_minutes\r\n"+
              "2024.01.01 00:00:00,2024.06.01 00:00:00,120\r\n"+
              "2024.06.02 00:00:00,2025.01.01 00:00:00,120\r\n";
   Check(WriteFixture(filename,gap) && !clock.Load(filename,reason),"schedule gap rejected at load");
   string overlap="utc_from,utc_to,offset_minutes\r\n"+
                  "2024.01.01 00:00:00,2024.06.02 00:00:00,120\r\n"+
                  "2024.06.01 00:00:00,2025.01.01 00:00:00,120\r\n";
   Check(WriteFixture(filename,overlap) && !clock.Load(filename,reason),"schedule overlap rejected at load");
   string malformed="utc_from,utc_to,offset_minutes\r\n"+
                    "2024.02.30 00:00:00,2025.01.01 00:00:00,120junk\r\n";
   Check(WriteFixture(filename,malformed) && !clock.Load(filename,reason),"malformed calendar or offset rejected");
   FileDelete(filename);
  }

void MakeBar(MqlRates &bar,datetime time,double open,double high,double low,double close)
  {
   ZeroMemory(bar);
   bar.time=time;
   bar.open=open;
   bar.high=high;
   bar.low=low;
   bar.close=close;
  }

void FixtureH1(MqlRates &bars[],bool mirror=false)
  {
   double highs[8]={110,120,114,125,118,130,122,127};
   double lows[8]={100,108,102,106,104,110,108,113};
   ArrayResize(bars,8);
   for(int i=0;i<8;i++)
     {
      double mid=(highs[i]+lows[i])/2.0;
      MakeBar(bars[i],(datetime)((long)D'2024.01.02 00:00:00'+i*3600),mid,highs[i],lows[i],mid);
      if(mirror)
        {
         bars[i].open=300.0-mid;
         bars[i].close=300.0-mid;
         bars[i].high=300.0-lows[i];
         bars[i].low=300.0-highs[i];
        }
     }
  }

void FixtureArm(CResearchStrategy &strategy,const MqlRates &h1[],Setup &setup,int expiry=12)
  {
   strategy.Configure(1,expiry,3);
   ZeroMemory(setup);
   MqlRates bar;
   MakeBar(bar,D'2024.01.02 07:55:00',120,121,119,120);
   string event;
   strategy.Evaluate(h1,bar,D'2024.01.02 08:00:00',setup,event);
  }

void TestStrategy(void)
  {
   MqlRates h1[];
   FixtureH1(h1);
   CResearchStrategy strategy;
   Setup setup;
   ZeroMemory(setup);
   strategy.Configure(1,12,3);
   MqlRates bar;
   string event;
   MakeBar(bar,D'2024.01.02 05:55:00',120,121,119,120);
   strategy.Evaluate(h1,bar,D'2024.01.02 06:00:00',setup,event);
   Check(setup.active && setup.end.time==D'2024.01.02 03:00:00' &&
         setup.end.confirmed==D'2024.01.02 05:00:00',"future H1 right-side bars cannot confirm latest pivot early");
   strategy.Reset();
   ZeroMemory(setup);
   MakeBar(bar,D'2024.01.02 06:55:00',120,121,119,120);
   strategy.Evaluate(h1,bar,D'2024.01.02 07:00:00',setup,event);
   Check(setup.active && setup.end.time==D'2024.01.02 05:00:00' && setup.end.confirmed==D'2024.01.02 07:00:00',"pivot becomes eligible exactly at right-bar close");
   Check(setup.start.time==D'2024.01.02 04:00:00',"impulse pairs latest eligible high with latest chronologically earlier low");

   FixtureArm(strategy,h1,setup);
   Check(setup.active && setup.direction==1 && !setup.has_a,"newly armed setup excludes just-closed M5 bar");
   Check(MathAbs(setup.zone_low-106.964)<0.000001 && MathAbs(setup.zone_high-111.67)<0.000001,"frozen long retracement boundaries");
   MakeBar(bar,D'2024.01.02 08:00:00',109,112,108,111);
   Check(!strategy.Evaluate(h1,bar,D'2024.01.02 08:05:00',setup,event) && setup.has_a,"long A intersects zone and closes upward");
   MakeBar(bar,D'2024.01.02 08:05:00',110,114,109,113);
   Check(strategy.Evaluate(h1,bar,D'2024.01.02 08:10:00',setup,event) && setup.consumed && !setup.active,"long B confirms and permanently consumes setup");
   string id=setup.id;
   Check(!strategy.Evaluate(h1,bar,D'2024.01.02 08:10:00',setup,event) && event=="DUPLICATE_OR_OUT_OF_ORDER_M5_BAR","duplicate decision does not produce another signal");
   MakeBar(bar,D'2024.01.02 08:10:00',110,114,109,113);
   Check(!strategy.Evaluate(h1,bar,D'2024.01.02 08:15:00',setup,event) && !setup.active && setup.id==id && event=="IMPULSE_ALREADY_RETIRED","rejected execution cannot rearm consumed impulse");

   CResearchStrategy restored;
   restored.Configure(1,12,3);
   string state=strategy.RetiredState();
   Check(restored.Restore(state,D'2024.01.02 08:10:00'),"strategy retirement and last-bar state restores");
   Check(!restored.Evaluate(h1,bar,D'2024.01.02 08:15:00',setup,event) && event=="DUPLICATE_OR_OUT_OF_ORDER_M5_BAR","restart rejects already processed bar");
   MakeBar(bar,D'2024.01.02 08:15:00',110,114,109,113);
   Check(!restored.Evaluate(h1,bar,D'2024.01.02 08:20:00',setup,event) && event=="IMPULSE_ALREADY_RETIRED","restart retains consumed impulse lock");
   Check(!restored.Restore("1_bad_123",D'2024.01.02 08:10:00'),"malformed restored strategy state rejected");

   FixtureArm(strategy,h1,setup);
   MqlRates later_h1[];
   ArrayCopy(later_h1,h1);
   ArrayResize(later_h1,11);
   MakeBar(later_h1[8],D'2024.01.02 08:00:00',126,136,116,126);
   MakeBar(later_h1[9],D'2024.01.02 09:00:00',120,129,112,120);
   MakeBar(later_h1[10],D'2024.01.02 10:00:00',124,133,115,124);
   MakeBar(bar,D'2024.01.02 10:55:00',120,121,119,120);
   strategy.Evaluate(later_h1,bar,D'2024.01.02 11:00:00',setup,event);
   Check(setup.active && setup.end.time==D'2024.01.02 05:00:00' &&
         setup.start.time==D'2024.01.02 04:00:00',"newer pivots never replace active frozen anchors");

   MqlRates short_h1[];
   FixtureH1(short_h1,true);
   FixtureArm(strategy,short_h1,setup);
   Check(setup.active && setup.direction==-1 && MathAbs(setup.zone_high-(300.0-106.964))<0.000001,"short anchors and zone exactly mirror long");
   MakeBar(bar,D'2024.01.02 08:00:00',191,192,188,189);
   strategy.Evaluate(short_h1,bar,D'2024.01.02 08:05:00',setup,event);
   MakeBar(bar,D'2024.01.02 08:05:00',190,191,186,187);
   Check(strategy.Evaluate(short_h1,bar,D'2024.01.02 08:10:00',setup,event),"short A/B confirmation exactly mirrors long");

   FixtureArm(strategy,h1,setup);
   MakeBar(bar,D'2024.01.02 08:00:00',109,112,108,111);
   strategy.Evaluate(h1,bar,D'2024.01.02 08:05:00',setup,event);
   MakeBar(bar,D'2024.01.02 08:05:00',109,111.5,108.5,111);
   strategy.Evaluate(h1,bar,D'2024.01.02 08:10:00',setup,event);
   Check(setup.a.time==D'2024.01.02 08:00:00',"earliest A remains selected despite later candidates");
   MakeBar(bar,D'2024.01.02 08:20:00',110,114,109,113);
   Check(!strategy.Evaluate(h1,bar,D'2024.01.02 08:25:00',setup,event) && setup.a.time!=D'2024.01.02 08:00:00',"missing M5 slots consume B confirmation window");

   FixtureArm(strategy,h1,setup);
   MakeBar(bar,D'2024.01.02 08:00:00',111,112,108,109);
   strategy.Evaluate(h1,bar,D'2024.01.02 08:05:00',setup,event);
   Check(setup.touched==D'2024.01.02 08:00:00' && !setup.has_a,"first zone touch starts expiry even without directional A");
   MakeBar(bar,D'2024.01.02 09:00:00',110,114,109,113);
   Check(!strategy.Evaluate(h1,bar,D'2024.01.02 09:05:00',setup,event) && !setup.active && event=="EXPIRED_AFTER_FIRST_TOUCH","expiry counts elapsed slots across missing bars");

   FixtureArm(strategy,h1,setup,2);
   MakeBar(bar,D'2024.01.02 08:00:00',109,112,108,111);
   strategy.Evaluate(h1,bar,D'2024.01.02 08:05:00',setup,event);
   MakeBar(bar,D'2024.01.02 08:10:00',110,114,109,113);
   Check(!strategy.Evaluate(h1,bar,D'2024.01.02 08:15:00',setup,event) && event=="EXPIRED_AFTER_FIRST_TOUCH","expiry takes precedence over otherwise valid B");

   FixtureArm(strategy,h1,setup);
   // Deliberately seeded contradictory evidence verifies ordering independently
   // of geometry (an organic valid A makes close-beyond-886 and B incompatible).
   MakeBar(setup.a,D'2024.01.02 08:00:00',104.5,105,104,104.8);
   setup.has_a=true;
   MakeBar(bar,D'2024.01.02 08:05:00',105.5,106.5,105,106);
   Check(!strategy.Evaluate(h1,bar,D'2024.01.02 08:10:00',setup,event) && event=="INVALID_CLOSE_BEYOND_886" && !setup.consumed,"88.6 invalidation takes precedence over seeded B evidence");
   MakeBar(bar,D'2024.01.02 08:10:00',110,114,109,113);
   Check(!strategy.Evaluate(h1,bar,D'2024.01.02 08:15:00',setup,event) && event=="IMPULSE_ALREADY_RETIRED","invalidated impulse cannot rearm");

   FixtureArm(strategy,h1,setup);
   MakeBar(bar,D'2024.01.02 08:00:00',109,112,108,111);
   strategy.Evaluate(h1,bar,D'2024.01.02 08:05:00',setup,event);
   MakeBar(bar,D'2024.01.02 08:05:00',110,114,109,113);
   Check(!strategy.Evaluate(short_h1,bar,D'2024.01.02 08:10:00',setup,event) && event=="INVALID_BIAS_CHANGED","changed bias invalidates before otherwise valid B");

   MqlRates atr_bars[];
   ArrayResize(atr_bars,3);
   MakeBar(atr_bars[0],D'2024.01.02 08:00:00',100,102,98,100);
   MakeBar(atr_bars[1],D'2024.01.02 08:05:00',106,108,105,107);
   MakeBar(atr_bars[2],D'2024.01.02 08:10:00',106,109,104,105);
   Check(MathAbs(strategy.ATR(atr_bars,2)-6.5)<0.000001,"ATR mean true range includes gap from previous close");
   Check(strategy.ATR(atr_bars,14)==0.0,"ATR rejects insufficient history");
  }

void OnStart(void)
  {
   TestClock();
   TestStrategy();
   PrintFormat("BILTECH_CORE_TESTS: passed=%d failed=%d",passed,failed);
   if(failed>0)
      Alert("Biltech core fixtures failed. See Experts log.");
  }

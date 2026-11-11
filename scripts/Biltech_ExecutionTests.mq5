#property strict
#property script_show_inputs
#property description "Offline journal safety fixtures. No orders or positions are created."
#include "../Include/Biltech/State.mqh"
#include "../Include/Biltech/Strategy.mqh"

int state_passed=0,state_failed=0;

void StateCheck(bool condition,string description)
  {
   if(condition) { state_passed++; Print("PASS: ",description); }
   else { state_failed++; Print("FAIL: ",description); }
  }

void SeedJournal(ResearchState &state)
  {
   ZeroMemory(state);
   state.config="native-journal-fixture-v1";
   state.symbol="FIXTURE_SYMBOL";
   state.session=20240102;
   state.baseline=10000.0;
   state.blocked=true;
   state.uncertain=true;
   state.last_bar=D'2024.01.02 08:05:00';
   state.last_closed_deal=123456789;
   state.setup.id="1_1704168000_1704171600";
   state.setup.direction=1;
   state.setup.start.time=D'2024.01.02 04:00:00';
   state.setup.start.confirmed=D'2024.01.02 06:00:00';
   state.setup.start.price=104;
   state.setup.end.time=D'2024.01.02 05:00:00';
   state.setup.end.confirmed=D'2024.01.02 07:00:00';
   state.setup.end.price=130;
   state.setup.zone_low=106.964;
   state.setup.zone_high=111.67;
   state.setup.fib788=109.512;
   state.setup.armed=D'2024.01.02 08:00:00';
   state.setup.touched=D'2024.01.02 08:00:00';
   state.setup.touch_bars=1;
   state.setup.active=false;
   state.setup.consumed=true;
   state.setup.has_a=true;
   state.setup.a.time=D'2024.01.02 08:00:00';
   state.setup.a.open=109;
   state.setup.a.high=112;
   state.setup.a.low=108;
   state.setup.a.close=111;
   state.setup.a_age=1;
   state.retired=state.setup.id;
   state.plan.direction=1;
   state.plan.requested=113;
   state.plan.stop=107.5;
   state.plan.target=130;
   state.plan.volume=0.03;
   state.plan.spread=0.25;
   state.plan.rr=1.75;
   state.plan.risk_cash=25;
   state.plan.risk_per_lot=833.333333333;
   state.plan.order=987654321;
   state.trade_setup=state.setup;
   state.trade_setup.id="1_1704153600_1704157200";
   state.trade_b.time=D'2024.01.02 08:05:00';
   state.trade_b.open=110;
   state.trade_b.high=114;
   state.trade_b.low=109;
   state.trade_b.close=113;
   state.trade_position=345678901;
   state.last_entry_deal=456789012;
   state.trade_risk=24.875;
   state.trade_risk_valid=true;
   state.trade_closed_logged=true;
   state.trade_config="original-submitted-config";
   state.trade_run="original-submitted-run";
   state.close_uncertain=true;
   state.close_position=345678901;
   state.close_order=678901234;
   state.risk_deals=";456789012;";
   state.trade_filled_volume=0.03;
  }

void TestJournal(void)
  {
   string filename="Biltech_ExecutionTests_state.bin";
   FileDelete(filename);
   CResearchStateStore writer,reader,contender;
   ResearchState expected,loaded,other;
   SeedJournal(expected);
   bool fresh=false;
   string reason;
   StateCheck(writer.Open(filename,false,loaded,fresh,reason) && fresh,"new journal opens with fresh state");
   StateCheck(writer.Save(expected),"consumed impulse and uncertain submission are flushed before execution");
   bool second_fresh=false;
   StateCheck(!contender.Open(filename,false,other,second_fresh,reason),"second writer cannot acquire exclusive journal lock");
   contender.Close();
   writer.Close();

   StateCheck(reader.Open(filename,false,loaded,fresh,reason) && !fresh,"committed journal reopens without resetting");
   StateCheck(loaded.config==expected.config && loaded.symbol==expected.symbol &&
              loaded.session==expected.session && loaded.baseline==expected.baseline,"configuration and session equity baseline round trip");
   StateCheck(loaded.blocked && loaded.uncertain && loaded.setup.consumed && !loaded.setup.active,
              "restart retains risk, unresolved submission and consumed setup locks");
   StateCheck(loaded.retired==expected.retired && loaded.last_bar==expected.last_bar &&
              loaded.last_closed_deal==expected.last_closed_deal,"impulse retirement, completed bar and closed deal cursor round trip");
   StateCheck(loaded.setup.start.time==expected.setup.start.time && loaded.setup.end.confirmed==expected.setup.end.confirmed &&
              loaded.setup.zone_low==expected.setup.zone_low && loaded.setup.a.high==expected.setup.a.high &&
              loaded.setup.has_a && loaded.setup.a_age==1,"frozen pivot anchors, zone and A evidence round trip");
   StateCheck(loaded.plan.order==expected.plan.order && loaded.plan.risk_cash==expected.plan.risk_cash &&
              loaded.plan.volume==expected.plan.volume && loaded.plan.stop==expected.plan.stop,"submitted execution evidence round trip");
   StateCheck(loaded.trade_setup.id==expected.trade_setup.id && loaded.trade_setup.id!=loaded.setup.id &&
              loaded.trade_position==expected.trade_position && loaded.last_entry_deal==expected.last_entry_deal &&
              loaded.trade_risk==expected.trade_risk && loaded.trade_risk_valid &&
              loaded.trade_filled_volume==expected.trade_filled_volume && loaded.risk_deals==expected.risk_deals,
              "trade-specific setup and original account-currency risk remain independent of current setup");
   StateCheck(loaded.trade_b.time==expected.trade_b.time && loaded.trade_b.high==expected.trade_b.high &&
              loaded.trade_b.low==expected.trade_b.low && loaded.trade_b.close==expected.trade_b.close,
              "trade-specific B confirmation evidence round trips with its trade");
   StateCheck(loaded.trade_closed_logged && loaded.trade_config==expected.trade_config && loaded.trade_run==expected.trade_run,
              "closed-trade cursor and original configuration/run survive later configuration changes");
   StateCheck(loaded.close_uncertain && loaded.close_position==expected.close_position && loaded.close_order==expected.close_order,
              "uncertain forced-close request remains locked across restart");
   CResearchStrategy strategy;
   strategy.Configure(1,12,3);
   StateCheck(strategy.Restore(loaded.retired,loaded.last_bar) && strategy.RetiredState()==expected.retired,
              "restored journal supplies permanent strategy retirement state");
   reader.Close();

   // Empty strings must not shift the subsequent binary fields.
   expected.retired="";
   expected.setup.id="";
   StateCheck(writer.Open(filename,false,loaded,fresh,reason) && writer.Save(expected),"journal supports empty string fields");
   writer.Close();
   StateCheck(reader.Open(filename,false,loaded,fresh,reason) && loaded.retired=="" && loaded.setup.id=="" &&
              loaded.plan.order==expected.plan.order && loaded.uncertain,"empty fields do not erase following safety or plan fields");
   reader.Close();

   // Reproduce interruption after the durable dirty marker but before commit.
   int file=FileOpen(filename,FILE_READ|FILE_WRITE|FILE_BIN|FILE_ANSI);
   bool dirty_written=(file!=INVALID_HANDLE);
   if(dirty_written)
     {
      FileSeek(file,0,SEEK_SET);
      FileWriteInteger(file,0,INT_VALUE);
      FileFlush(file);
      FileClose(file);
     }
   StateCheck(dirty_written && !reader.Open(filename,false,loaded,fresh,reason),"interrupted dirty journal refuses initialization");
   reader.Close();

   // Restore a committed file then retain only its header and a partial body.
   StateCheck(writer.Open(filename,true,loaded,fresh,reason) && writer.Save(expected),"explicit fixture reset can create another committed test journal");
   writer.Close();
   file=FileOpen(filename,FILE_READ|FILE_BIN|FILE_ANSI);
   int header=0;
   if(file!=INVALID_HANDLE) { header=FileReadInteger(file,INT_VALUE); FileClose(file); }
   file=FileOpen(filename,FILE_WRITE|FILE_BIN|FILE_ANSI);
   bool truncated_written=(file!=INVALID_HANDLE && header!=0);
   if(file!=INVALID_HANDLE)
     {
      FileWriteInteger(file,header,INT_VALUE);
      FileWriteInteger(file,20,INT_VALUE);
      FileWriteString(file,"short");
      FileFlush(file);
      FileClose(file);
     }
   StateCheck(truncated_written && !reader.Open(filename,false,loaded,fresh,reason),"truncated journal refuses initialization");
   reader.Close();
   FileDelete(filename);
  }

void OnStart(void)
  {
   TestJournal();
   PrintFormat("BILTECH_EXECUTION_TESTS: passed=%d failed=%d",state_passed,state_failed);
   if(state_failed>0) Alert("Biltech journal safety fixtures failed. See Experts log.");
  }

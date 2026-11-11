#ifndef BILTECH_STATE_MQH
#define BILTECH_STATE_MQH
#include "Types.mqh"
#include "Execution.mqh"

struct ResearchState
  {
   string config,symbol,retired;
   int session;
   double baseline;
   bool blocked,uncertain;
   datetime last_bar;
   ulong last_closed_deal;
   Setup setup;
   Setup trade_setup;
   MqlRates trade_b;
   TradePlan plan;
   ulong trade_position,last_entry_deal;
   double trade_risk;
   bool trade_risk_valid,trade_closed_logged;
   string trade_config,trade_run;
   bool close_uncertain;
   ulong close_position,close_order;
   string risk_deals;
   double trade_filled_volume;
  };

// An exclusive handle prevents two charts using this account/magic namespace.
// A torn journal refuses initialization rather than silently resetting limits.
class CResearchStateStore
  {
private:
   int m_file;
   bool m_bad;
   void S(string value) { FileWriteInteger(m_file,StringLen(value),INT_VALUE); FileWriteString(m_file,value); }
   string R(void)
     {
      int n=FileReadInteger(m_file,INT_VALUE);
      if(n<0 || n>2000000 || FileIsEnding(m_file)) { m_bad=true; return ""; }
      return FileReadString(m_file,n);
     }
   void D(double value) { FileWriteDouble(m_file,value); }
   double F(void) { return FileReadDouble(m_file); }
   void T(datetime value) { FileWriteLong(m_file,(long)value); }
   datetime U(void) { return (datetime)FileReadLong(m_file); }
   void SavePivot(const Pivot &p) { T(p.time); T(p.confirmed); D(p.price); }
   void LoadPivot(Pivot &p) { p.time=U(); p.confirmed=U(); p.price=F(); }
   void SaveSetup(const Setup &s)
     {
      S(s.id); FileWriteInteger(m_file,s.direction,INT_VALUE);
      SavePivot(s.start); SavePivot(s.end); D(s.zone_low); D(s.zone_high); D(s.fib788);
      T(s.armed); T(s.touched); FileWriteInteger(m_file,s.touch_bars,INT_VALUE);
      FileWriteInteger(m_file,(int)s.active,INT_VALUE); FileWriteInteger(m_file,(int)s.consumed,INT_VALUE);
      FileWriteInteger(m_file,(int)s.has_a,INT_VALUE); T(s.a.time); D(s.a.open); D(s.a.high); D(s.a.low); D(s.a.close);
      FileWriteInteger(m_file,s.a_age,INT_VALUE);
     }
   void LoadSetup(Setup &s)
     {
      s.id=R(); s.direction=FileReadInteger(m_file,INT_VALUE); LoadPivot(s.start); LoadPivot(s.end);
      s.zone_low=F(); s.zone_high=F(); s.fib788=F(); s.armed=U(); s.touched=U(); s.touch_bars=FileReadInteger(m_file,INT_VALUE);
      s.active=FileReadInteger(m_file,INT_VALUE)!=0; s.consumed=FileReadInteger(m_file,INT_VALUE)!=0;
      s.has_a=FileReadInteger(m_file,INT_VALUE)!=0; s.a.time=U(); s.a.open=F(); s.a.high=F(); s.a.low=F(); s.a.close=F();
      s.a_age=FileReadInteger(m_file,INT_VALUE);
     }
public:
   CResearchStateStore(void) { m_file=INVALID_HANDLE; m_bad=false; }
   bool Open(string filename,bool reset,ResearchState &state,bool &fresh,string &reason)
     {
      m_file=FileOpen(filename,FILE_READ|FILE_WRITE|FILE_BIN|FILE_ANSI);
      if(m_file==INVALID_HANDLE)
        { reason=StringFormat("STATE_OPEN_OR_EXCLUSIVE_LOCK_FAILED:%d",GetLastError()); return false; }
      fresh=reset || FileSize(m_file)==0;
      if(fresh) { ZeroMemory(state); reason=""; return true; }
      FileSeek(m_file,0,SEEK_SET);
      m_bad=false;
      if(FileReadInteger(m_file,INT_VALUE)!=5102507) { reason="STATE_VERSION_OR_UNCOMMITTED_HEADER_INVALID"; return false; }
      state.config=R(); state.symbol=R(); state.retired=R();
      state.session=FileReadInteger(m_file,INT_VALUE); state.baseline=F();
      state.blocked=FileReadInteger(m_file,INT_VALUE)!=0; state.uncertain=FileReadInteger(m_file,INT_VALUE)!=0;
      state.last_bar=U(); state.last_closed_deal=(ulong)FileReadLong(m_file);
      LoadSetup(state.setup); LoadSetup(state.trade_setup);
      state.trade_b.time=U(); state.trade_b.open=F(); state.trade_b.high=F(); state.trade_b.low=F(); state.trade_b.close=F();
      state.plan.direction=FileReadInteger(m_file,INT_VALUE); state.plan.requested=F(); state.plan.stop=F();
      state.plan.target=F(); state.plan.volume=F(); state.plan.spread=F(); state.plan.rr=F(); state.plan.risk_cash=F();
      state.plan.risk_per_lot=F(); state.plan.order=(ulong)FileReadLong(m_file);
      state.trade_position=(ulong)FileReadLong(m_file); state.last_entry_deal=(ulong)FileReadLong(m_file);
      state.trade_risk=F(); state.trade_risk_valid=FileReadInteger(m_file,INT_VALUE)!=0;
      state.trade_closed_logged=FileReadInteger(m_file,INT_VALUE)!=0;
      state.trade_config=R(); state.trade_run=R(); state.close_uncertain=FileReadInteger(m_file,INT_VALUE)!=0;
      state.close_position=(ulong)FileReadLong(m_file); state.close_order=(ulong)FileReadLong(m_file);
      state.risk_deals=R(); state.trade_filled_volume=F();
      if(FileReadInteger(m_file,INT_VALUE)!=2505107 || m_bad || !MathIsValidNumber(state.baseline) || state.baseline<0 ||
         !MathIsValidNumber(state.trade_risk) || state.trade_risk<0)
        { reason="STATE_TRUNCATED_OR_CORRUPT_REFUSE_RESET"; return false; }
      reason="";
      return true;
     }

   bool Save(const ResearchState &state)
     {
      if(m_file==INVALID_HANDLE) return false;
      ResetLastError();
      FileSeek(m_file,0,SEEK_SET);
      // Durable dirty marker first. A crash cannot retain an old committed
      // header around a partially overwritten body, even at equal file sizes.
      FileWriteInteger(m_file,0,INT_VALUE); FileFlush(m_file);
      if(GetLastError()!=0) return false;
      S(state.config); S(state.symbol); S(state.retired);
      FileWriteInteger(m_file,state.session,INT_VALUE); D(state.baseline);
      FileWriteInteger(m_file,(int)state.blocked,INT_VALUE); FileWriteInteger(m_file,(int)state.uncertain,INT_VALUE);
      T(state.last_bar); FileWriteLong(m_file,(long)state.last_closed_deal);
      SaveSetup(state.setup); SaveSetup(state.trade_setup);
      T(state.trade_b.time); D(state.trade_b.open); D(state.trade_b.high); D(state.trade_b.low); D(state.trade_b.close);
      FileWriteInteger(m_file,state.plan.direction,INT_VALUE); D(state.plan.requested); D(state.plan.stop);
      D(state.plan.target); D(state.plan.volume); D(state.plan.spread); D(state.plan.rr); D(state.plan.risk_cash);
      D(state.plan.risk_per_lot); FileWriteLong(m_file,(long)state.plan.order);
      FileWriteLong(m_file,(long)state.trade_position); FileWriteLong(m_file,(long)state.last_entry_deal);
      D(state.trade_risk); FileWriteInteger(m_file,(int)state.trade_risk_valid,INT_VALUE);
      FileWriteInteger(m_file,(int)state.trade_closed_logged,INT_VALUE);
      S(state.trade_config); S(state.trade_run); FileWriteInteger(m_file,(int)state.close_uncertain,INT_VALUE);
      FileWriteLong(m_file,(long)state.close_position); FileWriteLong(m_file,(long)state.close_order);
      S(state.risk_deals); D(state.trade_filled_volume);
      FileWriteInteger(m_file,2505107,INT_VALUE);
      FileFlush(m_file);
      if(GetLastError()!=0) return false;
      FileSeek(m_file,0,SEEK_SET); FileWriteInteger(m_file,5102507,INT_VALUE); FileFlush(m_file);
      return GetLastError()==0;
     }
   void Close(void) { if(m_file!=INVALID_HANDLE) FileClose(m_file); m_file=INVALID_HANDLE; }
  };
#endif

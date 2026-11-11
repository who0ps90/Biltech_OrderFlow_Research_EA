#ifndef BILTECH_AUDIT_MQH
#define BILTECH_AUDIT_MQH
#include "Types.mqh"
#include "Execution.mqh"

string AuditTime(datetime value) { return value>0?TimeToString(value,TIME_DATE|TIME_SECONDS):""; }
string AuditNumber(double value,int digits=8) { return MathIsValidNumber(value)?DoubleToString(value,digits):""; }
string AuditQuote(string value)
  {
   StringReplace(value,"\"","\"\"");
   return "\""+value+"\"";
  }

struct AuditRecord
  {
   string event,reason,mode,symbol,config,run;
   datetime utc,server,ny,bar_time;
   int bias;
   Setup setup;
   MqlRates b;
   bool profile;
   datetime profile_from,profile_to;
   double poc,val,vah;
   TradePlan plan;
   ulong deal,position;
   double executed,executed_volume,commission,swap,fee,net,realized_r,slippage;
   bool has_execution,has_net,has_r,has_slippage;
   string exit_reason;
   double baseline,equity;
   int entries,losses;
  };

class CResearchAudit
  {
private:
   int m_file;
   bool m_enabled;
   string m_name;

public:
   CResearchAudit(void) { m_file=INVALID_HANDLE; m_enabled=false; }
   bool Open(string filename,bool enabled,string &reason)
     {
      m_enabled=enabled;
      m_name=filename;
      if(!enabled) return true;
      m_file=FileOpen(filename,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_SHARE_READ,0,CP_UTF8);
      if(m_file==INVALID_HANDLE) { reason=StringFormat("AUDIT_OPEN_FAILED:%d",GetLastError()); return false; }
      if(FileSize(m_file)==0)
         FileWriteString(m_file,"event,reason,mode,symbol,config_id,run_id,utc,server_time,new_york_time,decision_bar_server,bias,setup_id,direction,armed_utc,anchor_start_utc,anchor_start_confirmed_utc,anchor_start_price,anchor_end_utc,anchor_end_confirmed_utc,anchor_end_price,zone_low,zone_high,fib788,first_touch_utc,a_utc,a_open,a_high,a_low,a_close,a_age,profile_from_utc,profile_to_utc,poc,val,vah,requested_price,requested_volume,initial_stop,target,spread_price,estimated_net_rr,estimated_risk_cash,order_ticket,deal_ticket,position_id,executed_price,executed_volume,commission,swap,fee,observed_slippage_ticks,exit_reason,net_result,realized_r,session_baseline_equity,current_equity,session_entries,consecutive_losses,b_utc,b_open,b_high,b_low,b_close\r\n");
      FileSeek(m_file,0,SEEK_END);
      FileFlush(m_file);
      reason="";
      return true;
     }
   string Filename(void) { return m_name; }
   void Close(void) { if(m_file!=INVALID_HANDLE) FileClose(m_file); m_file=INVALID_HANDLE; }

   bool Write(const AuditRecord &r)
     {
      if(!m_enabled) return true;
      if(m_file==INVALID_HANDLE) return false;
      string cells[];
      ArrayResize(cells,63);
      cells[0]=r.event; cells[1]=r.reason; cells[2]=r.mode; cells[3]=r.symbol; cells[4]=r.config; cells[5]=r.run;
      cells[6]=AuditTime(r.utc); cells[7]=AuditTime(r.server); cells[8]=AuditTime(r.ny); cells[9]=AuditTime(r.bar_time);
      cells[10]=IntegerToString(r.bias); cells[11]=r.setup.id; cells[12]=IntegerToString(r.setup.direction);
      cells[13]=AuditTime(r.setup.armed); cells[14]=AuditTime(r.setup.start.time); cells[15]=AuditTime(r.setup.start.confirmed);
      cells[16]=AuditNumber(r.setup.start.price); cells[17]=AuditTime(r.setup.end.time); cells[18]=AuditTime(r.setup.end.confirmed);
      cells[19]=AuditNumber(r.setup.end.price); cells[20]=AuditNumber(r.setup.zone_low); cells[21]=AuditNumber(r.setup.zone_high);
      cells[22]=AuditNumber(r.setup.fib788); cells[23]=AuditTime(r.setup.touched); cells[24]=AuditTime(r.setup.a.time);
      cells[25]=AuditNumber(r.setup.a.open); cells[26]=AuditNumber(r.setup.a.high); cells[27]=AuditNumber(r.setup.a.low);
      cells[28]=AuditNumber(r.setup.a.close); cells[29]=IntegerToString(r.setup.a_age);
      cells[30]=r.profile?AuditTime(r.profile_from):""; cells[31]=r.profile?AuditTime(r.profile_to):"";
      cells[32]=r.profile?AuditNumber(r.poc):""; cells[33]=r.profile?AuditNumber(r.val):""; cells[34]=r.profile?AuditNumber(r.vah):"";
      cells[35]=AuditNumber(r.plan.requested); cells[36]=AuditNumber(r.plan.volume); cells[37]=AuditNumber(r.plan.stop);
      cells[38]=AuditNumber(r.plan.target); cells[39]=AuditNumber(r.plan.spread); cells[40]=AuditNumber(r.plan.rr);
      cells[41]=AuditNumber(r.plan.risk_cash); cells[42]=StringFormat("%I64u",r.plan.order);
      cells[43]=StringFormat("%I64u",r.deal); cells[44]=StringFormat("%I64u",r.position);
      cells[45]=r.has_execution?AuditNumber(r.executed):""; cells[46]=r.has_execution?AuditNumber(r.executed_volume):"";
      cells[47]=r.has_execution?AuditNumber(r.commission):""; cells[48]=r.has_execution?AuditNumber(r.swap):"";
      cells[49]=r.has_execution?AuditNumber(r.fee):""; cells[50]=r.has_slippage?AuditNumber(r.slippage):"";
      cells[51]=r.exit_reason; cells[52]=r.has_net?AuditNumber(r.net):""; cells[53]=r.has_r?AuditNumber(r.realized_r):"";
      cells[54]=AuditNumber(r.baseline); cells[55]=AuditNumber(r.equity); cells[56]=IntegerToString(r.entries); cells[57]=IntegerToString(r.losses);
      cells[58]=AuditTime(r.b.time); cells[59]=r.b.time>0?AuditNumber(r.b.open):""; cells[60]=r.b.time>0?AuditNumber(r.b.high):"";
      cells[61]=r.b.time>0?AuditNumber(r.b.low):""; cells[62]=r.b.time>0?AuditNumber(r.b.close):"";
      string row="";
      for(int i=0;i<ArraySize(cells);i++) row+=(i>0?",":"")+AuditQuote(cells[i]);
      bool ok=FileWriteString(m_file,row+"\r\n")>0;
      FileFlush(m_file);
      return ok;
     }
  };
#endif

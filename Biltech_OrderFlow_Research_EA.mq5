#property strict
#property version "1.00"
#property description "Research adaptation: completed-bar price rejection; no profitability or exact-replication claim."
#include "Include/Biltech/Types.mqh"
#include "Include/Biltech/Clock.mqh"
#include "Include/Biltech/Strategy.mqh"
#include "Include/Biltech/OrderFlow.mqh"
#include "Include/Biltech/Execution.mqh"
#include "Include/Biltech/Audit.mqh"
#include "Include/Biltech/State.mqh"

input group "Safety and identification"
input DataMode InpDataMode=PRICE_PROXY;
input bool InpAllowLiveTrading=false; // False permits Strategy Tester only, including blocking demo charts.
input string InpConfigId="portable-price-proxy-v1";
input string InpRunId="research-001"; // Change for independent exported runs.
input ulong InpMagic=5102501;
input bool InpBrokerClockAcknowledged=false;
input string InpBrokerOffsetSchedule="broker_offsets.csv";

input group "Completed H1/M5 research assumptions"
input int InpPivotSide=2;
input int InpExpiryBars=12;
input int InpConfirmationBars=3;
input int InpH1Lookback=512;
input bool InpForceFlatAtSessionEnd=true;

input group "Risk and execution"
input double InpRiskPercent=0.25;
input int InpMaxSessionEntries=2;
input int InpMaxConsecutiveSessionLosses=2;
input double InpMaxSessionDrawdownPercent=0.50;
input double InpStopMinimumTicks=2.0;
input double InpStopMaximumTicks=1000.0;
input double InpMaximumSpreadTicks=0.0; // 0 disables absolute cap; 10% relative cap always applies.
input double InpEstimatedCommissionPerLotRoundTurn=0.0; // Account currency; configure for your contract.
input double InpEstimatedSlippageTicksPerSide=1.0;
input uint InpDeviationPoints=20; // MT5 points, not exchange ticks; no guaranteed fill bound.
input TargetMode InpTargetMode=IMPULSE_TARGET;
input double InpFixedR=1.5;
input double InpMinimumNetRR=1.5;

input group "Strict imported exchange data (no fallback)"
input bool InpUseProfile=false;
input string InpExchangeManifest="exchange_manifest.csv";
input string InpExchangeCells="exchange_cells.csv";
input string InpDataCoverageFromUtc=""; // ISO UTC: YYYY-MM-DDTHH:MM:SSZ
input string InpDataCoverageToUtc=""; // Exclusive; declare the entire requested test range.
input double InpProfileBinTicks=1.0;
input double InpImbalanceRatio=4.0;
input double InpMinimumCellVolume=1.0;
input double InpMaximumUnknownFraction=0.0;
input bool InpEnableMNQMinimumVolume=false;
input double InpMNQMinimumBarContracts=20000.0;

input group "Diagnostics"
input bool InpExportCSV=true;
input bool InpChartVisuals=false;

CResearchClock g_clock;
CResearchStrategy g_strategy;
CExchangeProvider g_data;
CResearchExecution g_execution;
CResearchAudit g_audit;
CResearchStateStore g_store;
ResearchState g_state;
bool g_ready=false,g_ledger_ok=false,g_audit_ok=true;
int g_entries=0,g_losses=0,g_profile_day=0,g_preopen_day=0;
datetime g_seen_open=0,g_last_utc=0,g_profile_from=0,g_profile_to=0;
bool g_profile_ok=false;
double g_poc=0,g_val=0,g_vah=0;
string g_config="",g_run="",g_status="INITIALIZING",g_config_manifest="";
MqlRates g_decision_bar;

uint HashText(string value,uint hash=2166136261)
  {
   for(int i=0;i<StringLen(value);i++) { hash^=(uint)StringGetCharacter(value,i); hash*=16777619; }
   return hash;
  }
string SafeName(string value)
  {
   string out="";
   for(int i=0;i<StringLen(value);i++)
     {
      ushort c=StringGetCharacter(value,i);
      out+=((c>='a' && c<='z') || (c>='A' && c<='Z') || (c>='0' && c<='9') || c=='-' || c=='_')?ShortToString(c):"_";
     }
   return StringSubstr(out,0,80);
  }
uint HashFile(string path)
  {
   int handle=FileOpen(path,FILE_READ|FILE_BIN);
   if(handle==INVALID_HANDLE) return 0;
   uint hash=2166136261;
   uchar bytes[];
   while(!FileIsEnding(handle))
     {
      uint n=FileReadArray(handle,bytes,0,8192);
      if(n==0) break;
      for(uint i=0;i<n;i++) { hash^=(uint)bytes[i]; hash*=16777619; }
     }
   FileClose(handle);
   return hash;
  }
string Configuration(void)
  {
   string raw=StringFormat("v1|%s|%d|%I64u|%d|%d|%d|%d|%d|%s|%s",_Symbol,(int)InpDataMode,InpMagic,
                          InpPivotSide,InpExpiryBars,InpConfirmationBars,InpH1Lookback,(int)InpForceFlatAtSessionEnd,
                          InpConfigId,InpBrokerOffsetSchedule);
   double values[]={InpRiskPercent,(double)InpMaxSessionEntries,(double)InpMaxConsecutiveSessionLosses,
                    InpMaxSessionDrawdownPercent,InpStopMinimumTicks,InpStopMaximumTicks,InpMaximumSpreadTicks,
                    InpEstimatedCommissionPerLotRoundTurn,InpEstimatedSlippageTicksPerSide,(double)InpDeviationPoints,
                    (double)InpTargetMode,InpFixedR,InpMinimumNetRR,(double)InpUseProfile,InpProfileBinTicks,
                    InpImbalanceRatio,InpMinimumCellVolume,InpMaximumUnknownFraction,(double)InpEnableMNQMinimumVolume,
                    InpMNQMinimumBarContracts};
   for(int i=0;i<ArraySize(values);i++) raw+="|"+DoubleToString(values[i],12);
   raw+="|"+InpDataCoverageFromUtc+"|"+InpDataCoverageToUtc+"|"+IntegerToString((long)HashFile(InpBrokerOffsetSchedule));
   if(InpDataMode==EXCHANGE_ORDERFLOW || InpUseProfile)
      raw+="|"+IntegerToString((long)HashFile(InpExchangeManifest))+"|"+IntegerToString((long)HashFile(InpExchangeCells));
   g_config_manifest=raw;
   return InpConfigId+"-"+StringFormat("%08X",HashText(raw));
  }
bool ExportConfiguration(string &reason)
  {
   if(MQLInfoInteger(MQL_OPTIMIZATION) || !InpExportCSV) return true;
   string name="Biltech_config_"+g_run+"_"+StringFormat("%08X",HashText(g_config))+".txt";
   int file=FileOpen(name,FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(file==INVALID_HANDLE) { reason="CONFIGURATION_EXPORT_FAILED"; return false; }
   string text="Biltech research V1\r\nconfiguration_id="+g_config+"\r\nrun_id="+InpRunId+"\r\n";
   text+="parameter_order=version,symbol,mode,magic,pivot_side,expiry,confirmation,h1_lookback,force_flat,config_label,clock_file,";
   text+="risk_percent,max_entries,max_losses,max_session_dd,min_stop_ticks,max_stop_ticks,max_spread_ticks,commission_rt_per_lot,";
   text+="slippage_ticks_per_side,deviation_points,target_mode,fixed_r,min_net_rr,use_profile,profile_bin_ticks,imbalance_ratio,";
   text+="min_cell_volume,max_unknown_fraction,mnq_minimum_enabled,mnq_minimum_contracts,coverage_from_utc,coverage_to_utc,clock_file_fnv1a";
   if(InpDataMode==EXCHANGE_ORDERFLOW || InpUseProfile) text+=",manifest_file_fnv1a,cells_file_fnv1a";
   text+="\r\nparameters="+g_config_manifest+"\r\nallow_live_trading="+(InpAllowLiveTrading?"true":"false")+"\r\n";
   text+="terminal_build="+IntegerToString(TerminalInfoInteger(TERMINAL_BUILD))+"\r\naccount_currency="+AccountInfoString(ACCOUNT_CURRENCY)+"\r\n";
   text+="tick_size="+AuditNumber(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE))+"\r\npoint="+AuditNumber(_Point)+"\r\n";
   text+="contract_size="+AuditNumber(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE))+"\r\n";
   text+="volume_min="+AuditNumber(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN))+"\r\nvolume_step="+AuditNumber(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP))+"\r\n";
   text+="estimated_commission_zero="+(InpEstimatedCommissionPerLotRoundTurn==0?"true; configure fees before interpreting results":"false")+"\r\n";
   if(InpDataMode==EXCHANGE_ORDERFLOW || InpUseProfile)
      text+="dataset="+g_data.DatasetId()+"\r\nsource="+g_data.Source()+"\r\nclassifier="+g_data.Classifier()+"\r\nunits="+g_data.Units()+"\r\n";
   bool ok=FileWriteString(file,text)>0; FileFlush(file); FileClose(file);
   if(!ok) reason="CONFIGURATION_EXPORT_WRITE_FAILED";
   return ok;
  }
bool ParseISO(string value,datetime &result)
  {
   if(StringLen(value)!=20 || StringSubstr(value,10,1)!="T" || StringSubstr(value,19,1)!="Z") return false;
   string normalized=StringSubstr(value,0,19);
   StringReplace(normalized,"-","."); StringReplace(normalized,"T"," ");
   result=StringToTime(normalized);
   return result>0 && TimeToString(result,TIME_DATE|TIME_SECONDS)==normalized;
  }

void Record(string event,string reason,datetime utc,datetime server,datetime bar=0)
  {
   AuditRecord r;
   ZeroMemory(r);
   r.event=event; r.reason=reason; r.mode=EnumToString(InpDataMode); r.symbol=_Symbol; r.config=g_config; r.run=g_run;
   r.utc=utc; r.server=server; r.ny=utc>0?g_clock.NewYork(utc):0; r.bar_time=bar;
   r.bias=g_strategy.Bias(); r.setup=g_state.setup; r.plan=g_state.plan;
   r.b=g_decision_bar;
   r.profile=InpUseProfile && g_profile_ok; r.profile_from=g_profile_from; r.profile_to=g_profile_to;
   r.poc=g_poc; r.val=g_val; r.vah=g_vah;
   r.baseline=g_state.baseline; r.equity=AccountInfoDouble(ACCOUNT_EQUITY); r.entries=g_entries; r.losses=g_losses;
   if(!g_audit.Write(r)) { g_audit_ok=false; Print("AUDIT_WRITE_FAILED: entries blocked"); }
   g_status=reason;
  }
bool Persist(void)
  {
   g_state.retired=g_strategy.RetiredState();
   if(g_store.Save(g_state)) return true;
   g_state.blocked=true; g_state.uncertain=true;
   Print("STATE_SAVE_FAILED: entries blocked; do not reset journal mid-session");
   return false;
  }

struct LifeCycle
  {
   ulong id,last_exit,opening_order;
   long closed_msc;
   datetime closed_utc;
   string symbol;
   double in_volume,out_volume,net,risk;
   bool valid_r,mixed;
  };
int FindLife(LifeCycle &items[],ulong id)
  {
   for(int i=0;i<ArraySize(items);i++) if(items[i].id==id) return i;
   return -1;
  }
bool PositionIdOpen(ulong id)
  {
   for(int i=0;i<PositionsTotal();i++)
      if(PositionGetTicket(i)>0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==id) return true;
   return false;
  }

// The terminal's executed deals are authoritative, including all partial fills.
// Full lifecycle P/L includes entry commission and all exit commission/swap/fee.
bool ReadLedger(datetime utc,LifeCycle &items[],int &entries,int &losses,string &reason)
  {
   ArrayResize(items,0); entries=0; losses=0;
   if(!HistorySelect(0,TimeCurrent())) { reason="HISTORY_SELECT_FAILED"; return false; }
   int count=HistoryDealsTotal();
   for(int i=0;i<count;i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic) continue;
      long type=HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(FindLife(items,id)>=0) continue;
      int n=ArraySize(items); ArrayResize(items,n+1); ZeroMemory(items[n]);
      items[n].id=id; items[n].valid_r=true; items[n].symbol=HistoryDealGetString(deal,DEAL_SYMBOL);
     }
   ulong entry_orders[];
   for(int i=0;i<count;i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      int index=FindLife(items,(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID));
      if(index<0) continue;
      long type=HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL)
        {
         // Linked fees can be attributed to a lifecycle without pretending
         // account-level daily/monthly commissions belong to one setup.
         items[index].net+=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_COMMISSION)+
                           HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_FEE);
         continue;
        }
      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
      double volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
      items[index].net+=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_COMMISSION)+
                        HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_FEE);
      if(entry==DEAL_ENTRY_INOUT) { items[index].mixed=true; items[index].valid_r=false; }
      if(entry==DEAL_ENTRY_IN)
        {
         if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagic) items[index].mixed=true;
         items[index].in_volume+=volume;
         ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
         if(items[index].opening_order==0) items[index].opening_order=order;
         datetime deal_utc=0; string map_reason;
         if(!g_clock.ServerToUtc((datetime)HistoryDealGetInteger(deal,DEAL_TIME),deal_utc,map_reason))
           { reason="DEAL_TIME_MAPPING_FAILED:"+map_reason; return false; }
         if(g_clock.SessionKey(deal_utc)==g_state.session)
           {
            bool exists=false;
            for(int j=0;j<ArraySize(entry_orders);j++) if(entry_orders[j]==order) exists=true;
            if(!exists) { int n=ArraySize(entry_orders); ArrayResize(entry_orders,n+1); entry_orders[n]=order; entries++; }
           }
         double stop=HistoryOrderGetDouble(order,ORDER_SL);
         double price=HistoryDealGetDouble(deal,DEAL_PRICE),risk=0;
         int direction=type==DEAL_TYPE_BUY?1:-1;
         double tick=SymbolInfoDouble(items[index].symbol,SYMBOL_TRADE_TICK_SIZE);
         if(stop<=0 || tick<=0 || direction*(price-stop)<=0 ||
            !OrderCalcProfit(type==DEAL_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL,items[index].symbol,volume,price,
                             stop-direction*InpEstimatedSlippageTicksPerSide*tick,risk) || risk>=0)
            items[index].valid_r=false;
         else items[index].risk+=-risk+volume*InpEstimatedCommissionPerLotRoundTurn;
        }
      else if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
        {
         items[index].out_volume+=volume;
         long msc=HistoryDealGetInteger(deal,DEAL_TIME_MSC);
         if(msc>items[index].closed_msc || (msc==items[index].closed_msc && deal>items[index].last_exit))
           {
            items[index].last_exit=deal;
            items[index].closed_msc=msc;
            if(!g_clock.ServerToUtc((datetime)HistoryDealGetInteger(deal,DEAL_TIME),items[index].closed_utc,reason)) return false;
           }
        }
     }
   // Sort by completion time, then deal ticket, independent of history ordering.
   for(int i=0;i<ArraySize(items);i++)
      for(int j=i+1;j<ArraySize(items);j++)
         if(items[j].closed_utc<items[i].closed_utc ||
            (items[j].closed_utc==items[i].closed_utc && items[j].last_exit<items[i].last_exit))
           { LifeCycle temp=items[i]; items[i]=items[j]; items[j]=temp; }
   for(int i=0;i<ArraySize(items);i++)
     {
      if(items[i].mixed) { reason="EXTERNAL_NETTING_OR_REVERSAL_DETECTED"; return false; }
      if(items[i].last_exit==0 || PositionIdOpen(items[i].id) || items[i].out_volume+1e-8<items[i].in_volume) continue;
      if(g_clock.SessionKey(items[i].closed_utc)==g_state.session)
        {
         if(items[i].net<0) losses++; else losses=0; // A flat result breaks the consecutive-loss sequence.
        }
     }
   // Costs not attributed by position cannot be allocated to realized R. Fail
   // closed for that NY session instead of reporting a favorable loss streak.
   for(int i=0;i<count;i++)
     {
      ulong deal=HistoryDealGetTicket(i);
      long type=HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL) continue;
      if(FindLife(items,(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID))>=0) continue;
      double net=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_COMMISSION)+
                 HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_FEE);
      if(net>=0 && type!=DEAL_TYPE_CORRECTION && type!=DEAL_TYPE_BUY_CANCELED && type!=DEAL_TYPE_SELL_CANCELED) continue;
      datetime at=0;
      if(!g_clock.ServerToUtc((datetime)HistoryDealGetInteger(deal,DEAL_TIME),at,reason)) return false;
      if(g_clock.SessionKey(at)==g_state.session)
        { reason="UNALLOCATED_ACCOUNT_COST_OR_CORRECTION_CURRENT_SESSION"; return false; }
     }
   reason=""; return true;
  }

void AuditClosedLife(const LifeCycle &life)
  {
   if(g_state.trade_closed_logged || g_state.plan.order==0 || life.opening_order!=g_state.plan.order ||
      life.last_exit==0 || PositionIdOpen(life.id) || life.out_volume+1e-8<life.in_volume) return;
   AuditRecord r; ZeroMemory(r);
   r.event="TRADE_CLOSED"; r.reason="FULL_POSITION_LIFECYCLE_NET"; r.mode=EnumToString(InpDataMode);
   r.symbol=life.symbol; r.config=g_state.trade_config; r.run=g_state.trade_run; r.utc=life.closed_utc; r.ny=g_clock.NewYork(r.utc);
   string reason; g_clock.UtcToServer(r.utc,r.server,reason);
   r.setup=g_state.trade_setup; r.plan=g_state.plan; r.b=g_state.trade_b; r.bias=g_strategy.Bias();
   r.position=life.id; r.deal=life.last_exit; r.has_net=true; r.net=life.net;
   r.has_r=g_ledger_ok && g_state.trade_position==life.id && g_state.trade_risk_valid && g_state.trade_risk>0 &&
           MathAbs(g_state.trade_filled_volume-life.in_volume)<1e-8;
   if(r.has_r) r.realized_r=life.net/g_state.trade_risk;
   else r.reason+=";INITIAL_RISK_SNAPSHOT_UNAVAILABLE";
   r.baseline=g_state.baseline; r.equity=AccountInfoDouble(ACCOUNT_EQUITY); r.entries=g_entries; r.losses=g_losses;
   if(HistoryDealSelect(life.last_exit))
     {
      r.has_execution=true; r.executed=HistoryDealGetDouble(life.last_exit,DEAL_PRICE);
      r.executed_volume=HistoryDealGetDouble(life.last_exit,DEAL_VOLUME);
      r.commission=HistoryDealGetDouble(life.last_exit,DEAL_COMMISSION); r.swap=HistoryDealGetDouble(life.last_exit,DEAL_SWAP);
      r.fee=HistoryDealGetDouble(life.last_exit,DEAL_FEE);
      r.exit_reason=EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(life.last_exit,DEAL_REASON));
     }
   if(!g_audit.Write(r)) g_audit_ok=false;
   g_state.trade_closed_logged=true; g_state.last_closed_deal=life.last_exit;
  }

void RefreshLedger(datetime utc)
  {
   LifeCycle items[]; string reason;
   g_ledger_ok=ReadLedger(utc,items,g_entries,g_losses,reason);
   if(!g_ledger_ok) { g_state.blocked=true; g_status=reason; }
   if(g_losses>=InpMaxConsecutiveSessionLosses) g_state.blocked=true;
   for(int i=0;i<ArraySize(items);i++) AuditClosedLife(items[i]);
  }

void EstablishSession(datetime utc,datetime server)
  {
   datetime start=g_clock.SessionStartUtc(utc);
   int key=g_clock.SessionKey(utc);
   if(start>0 && utc<start) g_preopen_day=key;
   if(!g_clock.InWindow(utc)) return;
   if(g_state.session!=key)
     {
      g_state.session=key;
      g_state.baseline=AccountInfoDouble(ACCOUNT_EQUITY);
      g_state.blocked=(g_preopen_day!=key);
      // An uncertain previous submission remains blocked until history/exposure
      // can be reviewed; it is never erased by changing the date.
      g_preopen_day=0;
      RefreshLedger(utc);
      Record("SESSION_START",g_state.blocked?"COLD_MID_SESSION_START_BLOCKED":"FIRST_TRADABLE_TICK_EQUITY_BASELINE",utc,server);
      Persist();
     }
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_state.baseline<=0 || equity<=g_state.baseline*(1-InpMaxSessionDrawdownPercent/100.0))
     {
      if(!g_state.blocked) Record("RISK_LIMIT","SESSION_EQUITY_DRAWDOWN_LATCHED",utc,server);
      g_state.blocked=true;
      Persist();
     }
  }

bool ProfileMatchesChart(datetime from,datetime to,string &reason)
  {
   datetime sf=0,st=0;
   if(!g_clock.UtcToServer(from,sf,reason) || !g_clock.UtcToServer(to-1,st,reason)) return false;
   MqlRates bars[];
   ArraySetAsSeries(bars,false);
   int count=CopyRates(_Symbol,PERIOD_M5,sf,st,bars);
   if(count!=(int)((to-from)/300)) { reason="PROFILE_CHART_M5_COVERAGE_INCOMPLETE"; return false; }
   for(int i=0;i<count;i++)
     {
      datetime at=0;
      if(!g_clock.ServerToUtc(bars[i].time,at,reason) || at!=from+i*300 ||
         !g_data.ValidateBar(at,at+300,bars[i].low,bars[i].high,reason))
        { reason="PROFILE_CHART_IMPORT_MISMATCH:"+reason; return false; }
     }
   return true;
  }

void FreezeProfile(datetime utc,datetime server)
  {
   if(!InpUseProfile) return;
   int day=g_clock.SessionKey(utc);
   if(g_profile_day==day) return;
   g_profile_day=day; g_profile_ok=false;
   string reason;
   // Select relative to that day's opening, never the current day's final profile.
   datetime open=g_clock.SessionStartUtc(utc);
   if(open==0 || !g_clock.PreviousCashSession(open,g_profile_from,g_profile_to) || g_profile_to>utc)
     { Record("PROFILE_REJECT","PREVIOUS_COMPLETED_CASH_SESSION_UNAVAILABLE",utc,server); return; }
   g_profile_ok=ProfileMatchesChart(g_profile_from,g_profile_to,reason);
   if(g_profile_ok) g_profile_ok=g_data.Profile(g_profile_from,g_profile_to,InpProfileBinTicks,g_poc,g_val,g_vah,reason);
   Record(g_profile_ok?"PROFILE_FROZEN":"PROFILE_REJECT",reason,utc,server);
  }

void ManagePositions(datetime utc,datetime server,bool mapped)
  {
   if(g_state.close_uncertain)
     {
      bool settled=!PositionIdOpen(g_state.close_position);
      if(!settled && g_state.close_order>0 && !OrderSelect(g_state.close_order) && HistoryOrderSelect(g_state.close_order))
        {
         long status=HistoryOrderGetInteger(g_state.close_order,ORDER_STATE);
         settled=status==ORDER_STATE_FILLED || status==ORDER_STATE_CANCELED || status==ORDER_STATE_REJECTED || status==ORDER_STATE_EXPIRED;
        }
      if(settled) { g_state.close_uncertain=false; Persist(); }
     }
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      bool unprotected=PositionGetDouble(POSITION_SL)<=0;
      if(unprotected || (InpForceFlatAtSessionEnd && (!mapped || !g_clock.InWindow(utc))))
        {
         if(g_state.close_uncertain) continue;
         MqlTradeResult result={}; string reason;
         g_state.close_uncertain=true; g_state.close_order=0;
         g_state.close_position=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
         if(!Persist()) continue;
         bool attempted=false;
         g_execution.Close(ticket,result,attempted,reason);
         g_state.close_order=result.order;
         if(!attempted || result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_DONE_PARTIAL ||
            result.retcode==TRADE_RETCODE_REJECT || result.retcode==TRADE_RETCODE_REQUOTE ||
            result.retcode==TRADE_RETCODE_PRICE_CHANGED || result.retcode==TRADE_RETCODE_PRICE_OFF ||
            result.retcode==TRADE_RETCODE_MARKET_CLOSED || result.retcode==TRADE_RETCODE_TRADE_DISABLED ||
            result.retcode==TRADE_RETCODE_POSITION_CLOSED) g_state.close_uncertain=false;
         Record("CLOSE_REQUEST",(unprotected?"MISSING_PROTECTIVE_SL:":"")+reason,utc,server);
         Persist();
        }
     }
  }

void Visuals(void)
  {
   if(!InpChartVisuals || MQLInfoInteger(MQL_OPTIMIZATION)) return;
   Comment("Biltech research | ",EnumToString(InpDataMode)," | ",g_status,"\n",
           "NY entries 09:30-11:00 | bias ",g_strategy.Bias()," | entries ",g_entries,
           " | losses ",g_losses," | equity baseline ",DoubleToString(g_state.baseline,2));
   if(g_state.setup.id=="") return;
   string names[]={"BILTECH_ZONE_LOW","BILTECH_ZONE_HIGH","BILTECH_FIB_788","BILTECH_IMPULSE_TARGET"};
   double levels[]={g_state.setup.zone_low,g_state.setup.zone_high,g_state.setup.fib788,g_state.setup.end.price};
   for(int i=0;i<ArraySize(names);i++)
     {
      if(ObjectFind(0,names[i])<0) ObjectCreate(0,names[i],OBJ_HLINE,0,0,levels[i]);
      ObjectSetDouble(0,names[i],OBJPROP_PRICE,levels[i]);
      ObjectSetInteger(0,names[i],OBJPROP_COLOR,i==2?clrDarkOrange:clrSteelBlue);
      ObjectSetInteger(0,names[i],OBJPROP_STYLE,STYLE_DOT);
     }
  }

int OnInit(void)
  {
   bool tester=(bool)MQLInfoInteger(MQL_TESTER);
   if(!tester && !InpAllowLiveTrading) { Print("INIT REJECT: InpAllowLiveTrading=false; Strategy Tester only"); return INIT_PARAMETERS_INCORRECT; }
   if(!InpBrokerClockAcknowledged) { Print("INIT REJECT: supply verified historical broker_offsets.csv and set InpBrokerClockAcknowledged=true"); return INIT_PARAMETERS_INCORRECT; }
   if((InpDataMode!=PRICE_PROXY && InpDataMode!=EXCHANGE_ORDERFLOW) ||
      (InpTargetMode!=IMPULSE_TARGET && InpTargetMode!=FIXED_R_TARGET) ||
      InpPivotSide<1 || InpPivotSide>20 || InpExpiryBars<1 || InpConfirmationBars<1 || InpH1Lookback<100 ||
      InpH1Lookback>10000 || InpRiskPercent<=0 || InpRiskPercent>100 || InpMaxSessionEntries<1 ||
      InpMaxConsecutiveSessionLosses<1 || InpMaxSessionDrawdownPercent<=0 || InpMaxSessionDrawdownPercent>100 ||
      InpStopMinimumTicks<=0 || InpStopMaximumTicks<=0 || InpMaximumSpreadTicks<0 ||
      InpEstimatedCommissionPerLotRoundTurn<0 || InpEstimatedSlippageTicksPerSide<0 || InpFixedR<=0 ||
      InpMinimumNetRR<=0 || InpImbalanceRatio<1 || InpMinimumCellVolume<=0 || InpMaximumUnknownFraction<0 ||
      InpMaximumUnknownFraction>1 || InpProfileBinTicks<1 || InpProfileBinTicks!=MathFloor(InpProfileBinTicks) ||
      InpMNQMinimumBarContracts<=0 || InpConfigId=="" || InpRunId=="" || InpMagic==0 ||
      (InpEnableMNQMinimumVolume && InpDataMode!=EXCHANGE_ORDERFLOW))
     { Print("INIT REJECT: invalid research/risk/data parameters"); return INIT_PARAMETERS_INCORRECT; }
   string reason;
   if(!g_clock.Load(InpBrokerOffsetSchedule,reason)) { Print("INIT REJECT: ",reason); return INIT_FAILED; }
   datetime initial_utc=0;
   if(!g_clock.ServerToUtc(TimeCurrent(),initial_utc,reason)) { Print("INIT REJECT: ",reason); return INIT_FAILED; }
   if(InpDataMode==EXCHANGE_ORDERFLOW || InpUseProfile)
     {
      datetime from=0,to=0;
      if(!ParseISO(InpDataCoverageFromUtc,from) || !ParseISO(InpDataCoverageToUtc,to) || from>=to ||
         initial_utc<from || initial_utc>=to)
        { Print("INIT REJECT: declare full UTC data/test range including initialization in InpDataCoverageFromUtc/ToUtc"); return INIT_FAILED; }
      if(!g_data.Load(InpExchangeManifest,InpExchangeCells,_Symbol,SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE),reason) ||
         !g_data.Coverage(from,to,reason)) { Print("INIT REJECT: ",reason); return INIT_FAILED; }
      if(InpEnableMNQMinimumVolume && (g_data.Instrument()!="MNQ" || g_data.Units()!="contracts"))
        { Print("INIT REJECT: MNQ volume threshold requires explicitly selected MNQ contract-volume dataset"); return INIT_FAILED; }
      if(InpUseProfile)
        {
         datetime pf=0,pt=0,open=g_clock.SessionStartUtc(initial_utc);
         if(!g_clock.PreviousCashSession(open>0?open:initial_utc,pf,pt) || !g_data.Coverage(pf,pt,reason))
           { Print("INIT REJECT: previous completed profile session unavailable: ",reason); return INIT_FAILED; }
        }
     }
   g_config=Configuration(); g_run=SafeName(InpRunId);
   g_strategy.Configure(InpPivotSide,InpExpiryBars,InpConfirmationBars);
   ExecutionSettings execution;
   execution.magic=InpMagic; execution.risk_percent=InpRiskPercent; execution.min_stop_ticks=InpStopMinimumTicks;
   execution.max_stop_ticks=InpStopMaximumTicks; execution.max_spread_ticks=InpMaximumSpreadTicks;
   execution.commission_per_lot=InpEstimatedCommissionPerLotRoundTurn; execution.slippage_ticks=InpEstimatedSlippageTicksPerSide;
   execution.min_net_rr=InpMinimumNetRR; execution.fixed_r=InpFixedR; execution.target_mode=InpTargetMode; execution.deviation_points=InpDeviationPoints;
   g_execution.Configure(execution);
   string name=StringFormat("Biltech_state_%I64d_%08X_%I64u",AccountInfoInteger(ACCOUNT_LOGIN),HashText(AccountInfoString(ACCOUNT_SERVER)),InpMagic);
   // Tester files are agent-local, reset on every pass. Live state is durable.
   if(tester) name+="_test_"+g_run;
   bool fresh=false;
   if(!g_store.Open(name+".bin",tester,g_state,fresh,reason)) { Print("INIT REJECT: ",reason); return INIT_FAILED; }
   if(!fresh && g_state.symbol!=_Symbol) { Print("INIT REJECT: account/magic journal belongs to another chart symbol"); return INIT_FAILED; }
   if(!fresh && g_state.config!=g_config)
     {
      // Retain account/session baseline and block this session; never reset a
      // breached limit by changing strategy inputs. Do not restore old signals.
      g_state.blocked=true; g_state.last_bar=0; g_state.retired=""; ZeroMemory(g_state.setup);
     }
   else if(!fresh && !g_strategy.Restore(g_state.retired,g_state.last_bar))
     { Print("INIT REJECT: invalid stored strategy state"); return INIT_FAILED; }
   g_state.config=g_config; g_state.symbol=_Symbol;
   string audit_name="Biltech_audit_"+SafeName(_Symbol)+"_"+g_run+"_"+StringFormat("%08X",HashText(g_config))+".csv";
   if(!g_audit.Open(audit_name,InpExportCSV && !MQLInfoInteger(MQL_OPTIMIZATION),reason))
     { Print("INIT REJECT: ",reason); return INIT_FAILED; }
   if(!ExportConfiguration(reason)) { Print("INIT REJECT: ",reason); return INIT_FAILED; }
   g_ready=true;
   RefreshLedger(initial_utc);
   EstablishSession(initial_utc,TimeCurrent());
   if(!Persist()) return INIT_FAILED;
   Record("INITIALIZED","RESEARCH_ADAPTATION_NOT_EXACT_REPLICATION",initial_utc,TimeCurrent());
   Print("Biltech initialized ",g_config,"; audit ",audit_name,"; no performance claim");
   return INIT_SUCCEEDED;
  }

void OnTick(void)
  {
   if(!g_ready) return;
   MqlTick tick={};
   if(!SymbolInfoTick(_Symbol,tick)) return;
   datetime utc=0; string reason;
   bool mapped=g_clock.ServerToUtc(tick.time,utc,reason);
   ManagePositions(utc,tick.time,mapped);
   if(!mapped) { if(g_status!=reason) Record("TIME_REJECT",reason,0,tick.time); Visuals(); return; }
   if(g_last_utc>utc) { g_state.blocked=true; Record("TIME_REJECT","NONMONOTONIC_UTC_TICKS",utc,tick.time); Persist(); return; }
   g_last_utc=utc;
   EstablishSession(utc,tick.time);
   FreezeProfile(utc,tick.time);
   datetime current_open=iTime(_Symbol,PERIOD_M5,0);
   if(current_open<=0 || current_open==g_seen_open) { Visuals(); return; }
   // Do not acknowledge a new bar until CopyRates/normalization succeeds.
   MqlRates m5[],h1[];
   ArraySetAsSeries(m5,false); ArraySetAsSeries(h1,false);
   int nm=CopyRates(_Symbol,PERIOD_M5,1,512,m5);
   int nh=CopyRates(_Symbol,PERIOD_H1,1,InpH1Lookback,h1);
   if(nm<15 || nh<100) { g_status="WAITING_FOR_SYNCHRONIZED_M5_H1_HISTORY"; Visuals(); return; }
   for(int i=0;i<nm;i++)
      if(!g_clock.ServerToUtc(m5[i].time,m5[i].time,reason)) { Record("HISTORY_REJECT","M5:"+reason,utc,tick.time); return; }
   for(int i=0;i<nh;i++)
      if(!g_clock.ServerToUtc(h1[i].time,h1[i].time,reason)) { Record("HISTORY_REJECT","H1:"+reason,utc,tick.time); return; }
   if(g_state.last_bar>0 && g_state.last_bar<m5[0].time-300)
     {
      g_state.setup.consumed=true; // Retire a potentially stale setup on next Evaluate.
      Record("RESTART_GAP","CATCHUP_EXCEEDS_512_BARS_RETIRE_ACTIVE_SETUP",utc,tick.time);
     }
   RefreshLedger(utc);
   int start=nm-1;
   if(g_state.last_bar>0)
     { start=0; while(start<nm && m5[start].time<=g_state.last_bar) start++; }
   for(int i=start;i<nm;i++)
     {
      datetime decision=m5[i].time+300;
      if(decision>utc) continue;
      bool signal=g_strategy.Evaluate(h1,m5[i],decision,g_state.setup,reason);
      g_decision_bar=m5[i];
      g_state.last_bar=m5[i].time;
      datetime bar_server=0; string map_reason;
      g_clock.UtcToServer(m5[i].time,bar_server,map_reason);
      Record(signal?"B_CONFIRMED":"SIGNAL_STATE",reason,utc,tick.time,bar_server);
      // Journal the consumed signal before any external order submission.
      if(!Persist()) continue;
      if(!signal) continue;
      if(i!=nm-1) reason="MISSED_HISTORICAL_B_NO_RETROSPECTIVE_ENTRY";
      else if(!g_clock.InWindow(utc)) reason="OUTSIDE_NEW_YORK_ENTRY_WINDOW";
      else if(g_state.session!=g_clock.SessionKey(utc) || g_state.blocked) reason="SESSION_EQUITY_OR_COLD_START_LOCK";
      else if(g_state.uncertain) reason="UNRESOLVED_ORDER_SUBMISSION_LOCK";
      else if(g_state.plan.order>0 && !g_state.trade_closed_logged && !PositionIdOpen(g_state.trade_position))
         reason="PREVIOUS_EXECUTION_AUDIT_PENDING";
      else if(!g_audit_ok) reason="AUDIT_UNAVAILABLE";
      else if(!g_ledger_ok) reason="DEAL_LEDGER_UNAVAILABLE";
      else if(g_entries>=InpMaxSessionEntries) reason="MAXIMUM_SESSION_ENTRIES";
      else if(g_losses>=InpMaxConsecutiveSessionLosses) reason="CONSECUTIVE_SESSION_LOSS_LIMIT";
      else if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
              !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) reason="PLATFORM_TRADE_PERMISSION_DISABLED";
      else if(InpUseProfile && (!g_profile_ok ||
              (g_state.setup.direction==1 && g_state.setup.zone_high>=g_val) ||
              (g_state.setup.direction==-1 && g_state.setup.zone_low<=g_vah))) reason="ZONE_NOT_WHOLLY_OUTSIDE_FROZEN_VALUE_AREA";
      else
        {
         bool data_ok=true;
         if(InpDataMode==EXCHANGE_ORDERFLOW)
           {
            data_ok=g_data.ValidateBar(g_state.setup.a.time,g_state.setup.a.time+300,g_state.setup.a.low,g_state.setup.a.high,reason);
            if(data_ok) data_ok=g_data.ValidateBar(m5[i].time,m5[i].time+300,m5[i].low,m5[i].high,reason);
            if(data_ok) data_ok=g_data.CheckFailure(g_state.setup.a.time,g_state.setup.a.time+300,g_state.setup.direction,
                         g_state.setup.zone_low,g_state.setup.zone_high,InpImbalanceRatio,InpMinimumCellVolume,
                         InpMaximumUnknownFraction,InpEnableMNQMinimumVolume,InpMNQMinimumBarContracts,reason);
            if(data_ok) data_ok=g_data.CheckRetest(m5[i].time,m5[i].time+300,g_state.setup.direction,
                         g_state.setup.a.low,g_state.setup.a.high,InpImbalanceRatio,InpMinimumCellVolume,
                         InpMaximumUnknownFraction,InpEnableMNQMinimumVolume,InpMNQMinimumBarContracts,reason);
           }
         if(data_ok)
           {
            // ATR array ends at the completed decision bar, with no current bar.
            MqlRates completed[]; ArrayResize(completed,i+1);
            for(int j=0;j<=i;j++) completed[j]=m5[j];
            TradePlan plan;
            if(g_execution.Prepare(_Symbol,tick,g_state.setup,g_strategy.ATR(completed,14),plan,reason))
              {
               g_state.plan=plan;
               g_state.trade_setup=g_state.setup;
               g_state.trade_b=m5[i];
               g_state.trade_position=0; g_state.trade_risk=0; g_state.trade_risk_valid=true; g_state.last_entry_deal=0;
               g_state.trade_closed_logged=false;
               g_state.trade_config=g_config; g_state.trade_run=g_run;
               g_state.risk_deals=""; g_state.trade_filled_volume=0;
               g_state.uncertain=true; // Crash between send and response must fail closed.
               Record("ORDER_REQUEST","PLAN_READY",utc,tick.time,bar_server);
               if(!Persist()) continue;
               MqlTradeResult result={};
               bool attempted=false;
               bool accepted=g_execution.Send(_Symbol,"BT_"+StringFormat("%08X",HashText(g_state.setup.id)),g_state.plan,result,attempted,reason);
               // PLACED, timeout, lost connection and unexpected responses need
               // reconciliation; never automatically retry a consumed setup.
               if((accepted && (result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_DONE_PARTIAL)) ||
                  (!attempted || (!accepted && (result.retcode==TRADE_RETCODE_REJECT ||
                    result.retcode==TRADE_RETCODE_INVALID || result.retcode==TRADE_RETCODE_INVALID_VOLUME ||
                    result.retcode==TRADE_RETCODE_INVALID_PRICE || result.retcode==TRADE_RETCODE_INVALID_STOPS ||
                    result.retcode==TRADE_RETCODE_NO_MONEY || result.retcode==TRADE_RETCODE_MARKET_CLOSED ||
                    result.retcode==TRADE_RETCODE_TRADE_DISABLED || result.retcode==TRADE_RETCODE_REQUOTE ||
                    result.retcode==TRADE_RETCODE_PRICE_CHANGED || result.retcode==TRADE_RETCODE_PRICE_OFF))))
                  g_state.uncertain=false;
               if(!accepted && !g_state.uncertain) g_state.trade_closed_logged=true;
               Record(accepted?"ORDER_ACCEPTED":"ORDER_REJECTED",reason,utc,tick.time,bar_server);
               Persist(); RefreshLedger(utc);
               continue;
              }
           }
        }
      Record("ENTRY_SKIPPED",reason,utc,tick.time,bar_server);
     }
   g_seen_open=current_open;
   Persist(); Visuals();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(!g_ready || trans.type!=TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;
   ulong position=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   long deal_type=HistoryDealGetInteger(trans.deal,DEAL_TYPE);
   bool is_trade=deal_type==DEAL_TYPE_BUY || deal_type==DEAL_TYPE_SELL;
   bool ours=(ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)==InpMagic;
   // Include manual/SL/TP closure of an EA position even if closing magic differs.
   if(!ours && PositionSelectByTicket(trans.position)) ours=(ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic;
   if(!ours)
     {
      LifeCycle lives[]; int entries,losses; string ignored;
      ReadLedger(0,lives,entries,losses,ignored);
      ours=FindLife(lives,position)>=0;
      if(!HistoryDealSelect(trans.deal)) return;
     }
   if(!ours) return;
   AuditRecord r; ZeroMemory(r);
   r.event=is_trade?"DEAL":"ACCOUNT_DEAL"; r.reason="EXECUTED_TERMINAL_HISTORY"; r.mode=EnumToString(InpDataMode); r.symbol=HistoryDealGetString(trans.deal,DEAL_SYMBOL);
   r.config=g_config; r.run=g_run; r.server=(datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME);
   string reason;
   if(!g_clock.ServerToUtc(r.server,r.utc,reason)) g_state.blocked=true;
   r.ny=r.utc>0?g_clock.NewYork(r.utc):0; r.setup=g_state.trade_setup; r.plan=g_state.plan; r.bias=g_strategy.Bias();
   r.b=g_state.trade_b;
   r.deal=trans.deal; r.position=position; r.has_execution=true;
   r.executed=HistoryDealGetDouble(trans.deal,DEAL_PRICE); r.executed_volume=HistoryDealGetDouble(trans.deal,DEAL_VOLUME);
   r.commission=HistoryDealGetDouble(trans.deal,DEAL_COMMISSION); r.swap=HistoryDealGetDouble(trans.deal,DEAL_SWAP);
   r.fee=HistoryDealGetDouble(trans.deal,DEAL_FEE);
   r.net=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+r.commission+r.swap+r.fee; r.has_net=true;
   r.exit_reason=EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal,DEAL_REASON));
   ulong order=(ulong)HistoryDealGetInteger(trans.deal,DEAL_ORDER);
   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   bool matching=(is_trade && entry==DEAL_ENTRY_IN && order==g_state.plan.order) || (position>0 && position==g_state.trade_position);
   if(!matching)
     { ZeroMemory(r.setup); ZeroMemory(r.plan); ZeroMemory(r.b); r.reason="EXECUTED_TERMINAL_HISTORY;SETUP_CONTEXT_UNAVAILABLE"; }
   else { r.config=g_state.trade_config; r.run=g_state.trade_run; }
   string risk_deal=";"+StringFormat("%I64u",trans.deal)+";";
   if(is_trade && entry==DEAL_ENTRY_IN && StringFind(g_state.risk_deals,risk_deal)<0)
     {
      g_state.risk_deals+=risk_deal;
      g_state.trade_filled_volume+=r.executed_volume;
      if(trans.deal>g_state.last_entry_deal) g_state.last_entry_deal=trans.deal;
      if(g_state.trade_position!=0 && g_state.trade_position!=position) g_state.trade_risk_valid=false;
      g_state.trade_position=position;
      double risk=0,tick_size=SymbolInfoDouble(r.symbol,SYMBOL_TRADE_TICK_SIZE);
      if(g_state.plan.stop<=0 || tick_size<=0 || order!=g_state.plan.order ||
         !OrderCalcProfit(g_state.plan.direction==1?ORDER_TYPE_BUY:ORDER_TYPE_SELL,r.symbol,r.executed_volume,r.executed,
                          g_state.plan.stop-g_state.plan.direction*InpEstimatedSlippageTicksPerSide*tick_size,risk) || risk>=0)
         g_state.trade_risk_valid=false;
      else g_state.trade_risk+=-risk+r.executed_volume*InpEstimatedCommissionPerLotRoundTurn;
      // A filled FOK/IOC with no working remainder is definitive evidence.
      if(order==g_state.plan.order && !OrderSelect(order)) g_state.uncertain=false;
     }
   if(is_trade && entry==DEAL_ENTRY_IN && order==g_state.plan.order && g_state.plan.requested>0)
     {
      r.slippage=g_state.plan.direction*(r.executed-g_state.plan.requested)/SymbolInfoDouble(r.symbol,SYMBOL_TRADE_TICK_SIZE);
      r.has_slippage=true;
     }
   r.baseline=g_state.baseline; r.equity=AccountInfoDouble(ACCOUNT_EQUITY); r.entries=g_entries; r.losses=g_losses;
   if(!g_audit.Write(r)) g_audit_ok=false;
   LifeCycle lives[];
   g_ledger_ok=ReadLedger(r.utc,lives,g_entries,g_losses,reason);
   if(!g_ledger_ok) g_state.blocked=true;
   for(int i=0;i<ArraySize(lives);i++) AuditClosedLife(lives[i]);
   EstablishSession(r.utc,r.server);
   if(g_losses>=InpMaxConsecutiveSessionLosses) g_state.blocked=true;
   Persist();
  }

void OnDeinit(const int reason)
  {
   if(g_ready) Persist();
   g_store.Close(); g_audit.Close(); g_ready=false;
   if(InpChartVisuals && !MQLInfoInteger(MQL_OPTIMIZATION)) { ObjectsDeleteAll(0,"BILTECH_"); Comment(""); }
  }

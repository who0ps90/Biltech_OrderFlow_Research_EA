#ifndef BILTECH_EXECUTION_MQH
#define BILTECH_EXECUTION_MQH
#include "Types.mqh"

struct ExecutionSettings
  {
   ulong magic;
   double risk_percent,min_stop_ticks,max_stop_ticks,max_spread_ticks;
   double commission_per_lot,slippage_ticks,min_net_rr,fixed_r;
   TargetMode target_mode;
   uint deviation_points;
  };

struct TradePlan
  {
   int direction;
   double requested,stop,target,volume,spread,rr,risk_cash,risk_per_lot;
   ulong order;
  };

class CResearchExecution
  {
private:
   ExecutionSettings m_cfg;

   double Down(double price,double tick) { return MathFloor(price/tick+1e-9)*tick; }
   double Up(double price,double tick) { return MathCeil(price/tick-1e-9)*tick; }

   bool Filling(string symbol,ENUM_ORDER_TYPE_FILLING &fill,string &reason)
     {
      long flags=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
      if((flags&SYMBOL_FILLING_FOK)!=0) { fill=ORDER_FILLING_FOK; return true; }
      if((flags&SYMBOL_FILLING_IOC)!=0) { fill=ORDER_FILLING_IOC; return true; }
      // RETURN can leave a residual order. V1 deliberately requires FOK/IOC.
      reason="NO_SUPPORTED_FOK_OR_IOC_POLICY";
      return false;
     }

   bool UnitPL(string symbol,int direction,double volume,double open,double close,double &value)
     {
      return OrderCalcProfit(direction==1?ORDER_TYPE_BUY:ORDER_TYPE_SELL,symbol,volume,open,close,value)
             && MathIsValidNumber(value);
     }

public:
   void Configure(const ExecutionSettings &cfg) { m_cfg=cfg; }

   bool Exposure(string symbol,string &reason)
     {
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         if(PositionGetTicket(i)==0) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC)==m_cfg.magic || PositionGetString(POSITION_SYMBOL)==symbol)
           { reason="EXISTING_EA_OR_SYMBOL_POSITION"; return true; }
        }
      for(int i=OrdersTotal()-1;i>=0;i--)
        {
         if(OrderGetTicket(i)==0) continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC)==m_cfg.magic || OrderGetString(ORDER_SYMBOL)==symbol)
           { reason="EXISTING_EA_OR_SYMBOL_ORDER"; return true; }
        }
      return false;
     }

   bool Prepare(string symbol,const MqlTick &quote,const Setup &setup,double atr,TradePlan &plan,string &reason)
     {
      ZeroMemory(plan);
      plan.direction=setup.direction;
      double tick=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
      double vmin=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
      double vmax=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
      if(tick<=0 || point<=0 || vmin<=0 || vmax<vmin || step<=0 || atr<=0 ||
         quote.ask<=0 || quote.bid<=0 || quote.ask<quote.bid || !setup.has_a)
        { reason="INVALID_SYMBOL_QUOTE_ATR_OR_A"; return false; }
      if(Exposure(symbol,reason)) return false;
      long trade_mode=SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE);
      if(trade_mode==SYMBOL_TRADE_MODE_DISABLED || trade_mode==SYMBOL_TRADE_MODE_CLOSEONLY ||
         (setup.direction==1 && trade_mode==SYMBOL_TRADE_MODE_SHORTONLY) ||
         (setup.direction==-1 && trade_mode==SYMBOL_TRADE_MODE_LONGONLY))
        { reason="SYMBOL_DIRECTION_NOT_TRADEABLE"; return false; }
      long order_mode=SymbolInfoInteger(symbol,SYMBOL_ORDER_MODE);
      if((order_mode&SYMBOL_ORDER_MARKET)==0 || (order_mode&SYMBOL_ORDER_SL)==0 || (order_mode&SYMBOL_ORDER_TP)==0)
        { reason="MARKET_ORDER_WITH_ATTACHED_SL_TP_UNSUPPORTED"; return false; }
      double buffer=MathMax(m_cfg.min_stop_ticks*tick,0.10*atr);
      plan.requested=(setup.direction==1)?quote.ask:quote.bid;
      plan.stop=(setup.direction==1)?Down(setup.a.low-buffer,tick):Up(setup.a.high+buffer,tick);
      double distance=setup.direction*(plan.requested-plan.stop);
      if(distance<tick || (m_cfg.max_stop_ticks>0 && distance>m_cfg.max_stop_ticks*tick))
        { reason="INVALID_OR_EXCESSIVE_STOP_DISTANCE"; return false; }
      plan.spread=quote.ask-quote.bid;
      if(plan.spread>0.10*distance+1e-10 ||
         (m_cfg.max_spread_ticks>0 && plan.spread>m_cfg.max_spread_ticks*tick+1e-10))
        { reason="SPREAD_LIMIT_EXCEEDED"; return false; }
      // Quotes already include spread. Slippage/commission here are screening
      // and sizing estimates only, never subtracted again from actual deal P/L.
      double adverse_open=plan.requested+setup.direction*m_cfg.slippage_ticks*tick;
      double adverse_stop=plan.stop-setup.direction*m_cfg.slippage_ticks*tick;
      double loss=0;
      if(!UnitPL(symbol,setup.direction,vmin,adverse_open,adverse_stop,loss) || loss>=0)
        { reason="ORDERCALCPROFIT_STOP_FAILED"; return false; }
      plan.risk_per_lot=-loss/vmin+m_cfg.commission_per_lot;
      plan.target=setup.end.price;
      if(m_cfg.target_mode==FIXED_R_TARGET)
        {
         double required=m_cfg.fixed_r*plan.risk_per_lot+m_cfg.commission_per_lot;
         double near=plan.requested,far=plan.requested+setup.direction*distance;
         double profit=0;
         for(int i=0;i<32;i++)
           {
            if(!UnitPL(symbol,setup.direction,vmin,adverse_open,far-setup.direction*m_cfg.slippage_ticks*tick,profit))
              { reason="ORDERCALCPROFIT_TARGET_FAILED"; return false; }
            if(profit/vmin>=required) break;
            far=plan.requested+2*(far-plan.requested);
           }
         if(profit/vmin<required) { reason="FIXED_R_TARGET_UNSOLVABLE"; return false; }
         for(int i=0;i<48;i++)
           {
            double middle=(near+far)/2;
            if(!UnitPL(symbol,setup.direction,vmin,adverse_open,middle-setup.direction*m_cfg.slippage_ticks*tick,profit))
              { reason="ORDERCALCPROFIT_TARGET_FAILED"; return false; }
            if(profit/vmin>=required) far=middle; else near=middle;
           }
         plan.target=(setup.direction==1)?Up(far,tick):Down(far,tick);
        }
      else plan.target=(setup.direction==1)?Down(plan.target,tick):Up(plan.target,tick);
      double reward=0;
      if(setup.direction*(plan.target-plan.requested)<=0 ||
         !UnitPL(symbol,setup.direction,vmin,adverse_open,plan.target-setup.direction*m_cfg.slippage_ticks*tick,reward))
        { reason="TARGET_BEHIND_ENTRY_OR_CALC_FAILED"; return false; }
      plan.rr=(reward/vmin-m_cfg.commission_per_lot)/plan.risk_per_lot;
      if(plan.rr+1e-9<m_cfg.min_net_rr)
        { reason="NET_REWARD_RISK_BELOW_MINIMUM"; return false; }
      // Conservative initial attachment check also includes freeze distance.
      double min_distance=MathMax((double)SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                  (double)SymbolInfoInteger(symbol,SYMBOL_TRADE_FREEZE_LEVEL))*point;
      double trigger=(setup.direction==1)?quote.bid:quote.ask;
      if(setup.direction*(trigger-plan.stop)<min_distance ||
         setup.direction*(plan.target-trigger)<min_distance)
        { reason="BROKER_STOP_OR_FREEZE_DISTANCE"; return false; }
      double budget=AccountInfoDouble(ACCOUNT_EQUITY)*m_cfg.risk_percent/100.0;
      double limit=SymbolInfoDouble(symbol,SYMBOL_VOLUME_LIMIT);
      if(limit>0) vmax=MathMin(vmax,limit);
      plan.volume=NormalizeDouble(MathFloor(MathMin(vmax,budget/plan.risk_per_lot)/step+1e-10)*step,8);
      if(plan.volume<vmin-1e-10) { reason="MINIMUM_VOLUME_EXCEEDS_RISK"; return false; }
      double actual_loss=0;
      if(!UnitPL(symbol,setup.direction,plan.volume,adverse_open,adverse_stop,actual_loss))
        { reason="FINAL_RISK_CALC_FAILED"; return false; }
      plan.risk_cash=-actual_loss+plan.volume*m_cfg.commission_per_lot;
      if(plan.risk_cash>budget+1e-8) { reason="ROUNDED_VOLUME_EXCEEDS_RISK"; return false; }
      double margin=0;
      if(!OrderCalcMargin(setup.direction==1?ORDER_TYPE_BUY:ORDER_TYPE_SELL,symbol,plan.volume,plan.requested,margin) ||
         margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
        { reason="INSUFFICIENT_MARGIN_OR_MARGIN_CALC_FAILED"; return false; }
      reason="PLAN_READY";
      return true;
     }

   bool Send(string symbol,string comment,TradePlan &plan,MqlTradeResult &result,bool &attempted,string &reason)
     {
      MqlTradeRequest request={};
      MqlTradeCheckResult check={};
      ZeroMemory(result);
      attempted=false;
      request.action=TRADE_ACTION_DEAL;
      request.magic=m_cfg.magic;
      request.symbol=symbol;
      request.type=plan.direction==1?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      request.volume=plan.volume;
      request.price=plan.requested;
      request.sl=plan.stop;
      request.tp=plan.target;
      request.deviation=m_cfg.deviation_points;
      request.comment=StringSubstr(comment,0,31);
      if(!Filling(symbol,request.type_filling,reason)) return false;
      if(!OrderCheck(request,check))
        { reason=StringFormat("ORDER_CHECK_REJECT:%u:%s",check.retcode,check.comment); return false; }
      attempted=true;
      bool sent=OrderSend(request,result);
      plan.order=result.order;
      reason=StringFormat("ORDER_SEND:%u:%s",result.retcode,result.comment);
      return sent && (result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_DONE_PARTIAL ||
                      result.retcode==TRADE_RETCODE_PLACED);
     }

   bool Close(ulong ticket,MqlTradeResult &result,bool &attempted,string &reason)
     {
      attempted=false;
      ZeroMemory(result);
      if(!PositionSelectByTicket(ticket)) { reason="POSITION_ALREADY_CLOSED"; return true; }
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=m_cfg.magic)
        { reason="CLOSE_MAGIC_MISMATCH"; return false; }
      string symbol=PositionGetString(POSITION_SYMBOL);
      MqlTick quote={};
      if(!SymbolInfoTick(symbol,quote)) { reason="CLOSE_QUOTE_UNAVAILABLE"; return false; }
      MqlTradeRequest request={};
      request.action=TRADE_ACTION_DEAL;
      request.position=ticket;
      request.magic=m_cfg.magic;
      request.symbol=symbol;
      request.type=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
      request.price=request.type==ORDER_TYPE_BUY?quote.ask:quote.bid;
      request.volume=PositionGetDouble(POSITION_VOLUME);
      request.deviation=m_cfg.deviation_points;
      request.comment="BILTECH_SESSION_FLAT";
      if(!Filling(symbol,request.type_filling,reason)) return false;
      attempted=true;
      bool sent=OrderSend(request,result);
      reason=StringFormat("FORCE_FLAT:%u:%s",result.retcode,result.comment);
      return sent && (result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_DONE_PARTIAL);
     }
  };
#endif

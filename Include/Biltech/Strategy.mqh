#ifndef BILTECH_STRATEGY_MQH
#define BILTECH_STRATEGY_MQH
#include "Types.mqh"

// Pure completed-bar price-proxy state machine. Arrays must be oldest first.
// No candle/tick statistic here is called aggressor volume, delta or absorption.
class CResearchStrategy
  {
private:
   int      m_side;
   int      m_expiry;
   int      m_confirmation;
   int      m_bias;
   datetime m_last_bar;
   string   m_retired[];

   bool Retired(string id)
     {
      for(int i=0;i<ArraySize(m_retired);i++)
         if(m_retired[i]==id)
            return true;
      return false;
     }

   void Retire(Setup &setup)
     {
      if(setup.id!="" && !Retired(setup.id))
        {
         int n=ArraySize(m_retired);
         ArrayResize(m_retired,n+1);
         m_retired[n]=setup.id;
        }
      setup.active=false;
     }

   bool ValidRate(const MqlRates &rate)
     {
      return rate.time>0 && MathIsValidNumber(rate.open) && MathIsValidNumber(rate.high) &&
             MathIsValidNumber(rate.low) && MathIsValidNumber(rate.close) &&
             rate.low<=rate.open && rate.low<=rate.close &&
             rate.high>=rate.open && rate.high>=rate.close && rate.high>=rate.low;
     }

   void AddPivot(Pivot &pivots[],datetime time,datetime confirmed,double price)
     {
      int n=ArraySize(pivots);
      ArrayResize(pivots,n+1);
      pivots[n].time=time;
      pivots[n].confirmed=confirmed;
      pivots[n].price=price;
     }

   bool Context(const MqlRates &h1[],datetime decision,Pivot &highs[],Pivot &lows[],string &event)
     {
      ArrayResize(highs,0);
      ArrayResize(lows,0);
      int count=0;
      int size=ArraySize(h1);
      for(int i=0;i<size;i++)
        {
         if(!ValidRate(h1[i]) || (i>0 && h1[i].time<=h1[i-1].time))
           {
            m_bias=0;
            event="INVALID_H1_HISTORY";
            return false;
           }
         if((long)h1[i].time+3600<=decision)
            count=i+1;
         else
            break;
        }
      for(int i=m_side;i<count-m_side;i++)
        {
         bool high=true;
         bool low=true;
         for(int j=1;j<=m_side;j++)
           {
            if(h1[i].high<=h1[i-j].high || h1[i].high<=h1[i+j].high)
               high=false;
            if(h1[i].low>=h1[i-j].low || h1[i].low>=h1[i+j].low)
               low=false;
           }
         datetime confirmed=(datetime)((long)h1[i+m_side].time+3600);
         if(high)
            AddPivot(highs,h1[i].time,confirmed,h1[i].high);
         if(low)
            AddPivot(lows,h1[i].time,confirmed,h1[i].low);
        }
      m_bias=0;
      int nh=ArraySize(highs);
      int nl=ArraySize(lows);
      if(nh>=2 && nl>=2)
        {
         if(highs[nh-1].price>highs[nh-2].price && lows[nl-1].price>lows[nl-2].price)
            m_bias=1;
         else if(highs[nh-1].price<highs[nh-2].price && lows[nl-1].price<lows[nl-2].price)
            m_bias=-1;
        }
      return true;
     }

   bool Arm(const Pivot &highs[],const Pivot &lows[],datetime decision,Setup &setup,string &event)
     {
      Pivot start={},end={};
      bool found=false;
      if(m_bias==1)
        {
         for(int i=ArraySize(highs)-1;i>=0 && !found;i--)
            for(int j=ArraySize(lows)-1;j>=0;j--)
               if(lows[j].time<highs[i].time && lows[j].price<highs[i].price)
                 {
                  start=lows[j];
                  end=highs[i];
                  found=true;
                  break;
                 }
        }
      else if(m_bias==-1)
        {
         for(int i=ArraySize(lows)-1;i>=0 && !found;i--)
            for(int j=ArraySize(highs)-1;j>=0;j--)
               if(highs[j].time<lows[i].time && highs[j].price>lows[i].price)
                 {
                  start=highs[j];
                  end=lows[i];
                  found=true;
                  break;
                 }
        }
      if(!found)
        {
         event=(m_bias==0)?"NEUTRAL_BIAS":"NO_ELIGIBLE_IMPULSE";
         return false;
        }
      string id=StringFormat("%d_%I64d_%I64d",m_bias,(long)start.time,(long)end.time);
      if(Retired(id))
        {
         event="IMPULSE_ALREADY_RETIRED";
         return false;
        }
      ZeroMemory(setup);
      setup.id=id;
      setup.direction=m_bias;
      setup.start=start;
      setup.end=end;
      setup.armed=decision;
      setup.active=true;
      double distance=MathAbs(end.price-start.price);
      if(m_bias==1)
        {
         setup.zone_low=end.price-0.886*distance;
         setup.zone_high=end.price-0.705*distance;
         setup.fib788=end.price-0.788*distance;
        }
      else
        {
         setup.zone_low=end.price+0.705*distance;
         setup.zone_high=end.price+0.886*distance;
         setup.fib788=end.price+0.788*distance;
        }
      event="SETUP_ARMED";
      return true;
     }

public:
   CResearchStrategy(void)
     {
      m_side=2;
      m_expiry=12;
      m_confirmation=3;
      Reset();
     }

   void Configure(int pivot_side,int expiry,int confirmation_window)
     {
      m_side=(pivot_side>0)?pivot_side:2;
      m_expiry=(expiry>0)?expiry:12;
      m_confirmation=(confirmation_window>0)?confirmation_window:3;
      Reset();
     }

   void Reset(void)
     {
      m_bias=0;
      m_last_bar=0;
      ArrayResize(m_retired,0);
     }

   int Bias(void) { return m_bias; }

   string RetiredState(void)
     {
      string state="";
      for(int i=0;i<ArraySize(m_retired);i++)
         state+=(i==0?"":";")+m_retired[i];
      return state;
     }

   // Restored state belongs to the same symbol/configuration/history stream.
   // Setup itself is persisted by the caller; context is recomputed next bar.
   bool Restore(string retired,datetime last_bar)
     {
      if((long)last_bar<0)
         return false;
      string ids[];
      int count=(retired=="")?0:StringSplit(retired,';',ids);
      if(retired!="" && count<1)
         return false;
      for(int i=0;i<count;i++)
        {
         string fields[];
         if(StringSplit(ids[i],'_',fields)!=3 || (fields[0]!="1" && fields[0]!="-1"))
            return false;
         for(int j=1;j<=2;j++)
           {
            if(StringLen(fields[j])==0)
               return false;
            for(int k=0;k<StringLen(fields[j]);k++)
              {
               ushort c=StringGetCharacter(fields[j],k);
               if(c<'0' || c>'9')
                  return false;
              }
           }
         long first=StringToInteger(fields[1]);
         long last=StringToInteger(fields[2]);
         if(first<=0 || first>=last)
            return false;
         for(int j=0;j<i;j++)
            if(ids[j]==ids[i])
               return false;
        }
      ArrayResize(m_retired,count);
      for(int i=0;i<count;i++)
         m_retired[i]=ids[i];
      m_last_bar=last_bar;
      m_bias=0;
      return true;
     }

   // Simple arithmetic mean of the last period true ranges, not Wilder ATR.
   // Caller supplies completed bars only; at least period+1 bars are required.
   double ATR(const MqlRates &m5[],int period=14)
     {
      int n=ArraySize(m5);
      if(period<1 || n<period+1)
         return 0.0;
      double total=0.0;
      for(int i=n-period;i<n;i++)
        {
         if(!ValidRate(m5[i]) || !ValidRate(m5[i-1]) || m5[i].time<=m5[i-1].time)
            return 0.0;
         total+=MathMax(m5[i].high-m5[i].low,
                        MathMax(MathAbs(m5[i].high-m5[i-1].close),MathAbs(m5[i].low-m5[i-1].close)));
        }
      return total/period;
     }

   bool Evaluate(const MqlRates &h1[],const MqlRates &bar,datetime decision,Setup &setup,string &event)
     {
      event="";
      if(!ValidRate(bar) || (long)bar.time+300>decision)
        {
         event="INVALID_OR_INCOMPLETE_M5_BAR";
         return false;
        }
      if(bar.time<=m_last_bar)
        {
         event="DUPLICATE_OR_OUT_OF_ORDER_M5_BAR";
         return false;
        }
      m_last_bar=bar.time;
      Pivot highs[],lows[];
      if(!Context(h1,decision,highs,lows,event))
        {
         if(setup.active)
            Retire(setup);
         return false;
        }
      if(setup.consumed && setup.active)
         Retire(setup);
      if(!setup.active)
        {
         Arm(highs,lows,decision,setup,event);
         // A completed bar preceding arming cannot retrospectively become A/B.
         return false;
        }
      if(bar.time<setup.armed)
        {
         event="BAR_PRECEDES_SETUP_ARMING";
         return false;
        }
      // Exact precedence is deliberate, including when B would otherwise pass.
      if((setup.direction==1 && bar.close<setup.zone_low) ||
         (setup.direction==-1 && bar.close>setup.zone_high))
        {
         Retire(setup);
         event="INVALID_CLOSE_BEYOND_886";
         return false;
        }
      if(m_bias!=setup.direction)
        {
         Retire(setup);
         event="INVALID_BIAS_CHANGED";
         return false;
        }
      bool intersects=bar.low<=setup.zone_high && bar.high>=setup.zone_low;
      if(setup.touched==0 && intersects)
         setup.touched=bar.time;
      if(setup.touched!=0)
        {
         setup.touch_bars=(int)(((long)bar.time-(long)setup.touched)/300);
         if(setup.touch_bars>=m_expiry)
           {
            Retire(setup);
            event="EXPIRED_AFTER_FIRST_TOUCH";
            return false;
           }
        }
      if(setup.has_a)
        {
         setup.a_age=(int)(((long)bar.time-(long)setup.a.time)/300);
         if(setup.a_age>m_confirmation)
           {
            setup.has_a=false;
            event="A_CONFIRMATION_WINDOW_EXPIRED";
           }
         else if(setup.a_age>=1 &&
                 ((setup.direction==1 && bar.low>setup.a.low && bar.close>setup.a.high) ||
                  (setup.direction==-1 && bar.high<setup.a.high && bar.close<setup.a.low)))
           {
            setup.consumed=true;
            Retire(setup);
            event="PRICE_PROXY_B_CONFIRMED";
            return true;
           }
        }
      if(!setup.has_a && intersects &&
         ((setup.direction==1 && bar.close>bar.open) ||
          (setup.direction==-1 && bar.close<bar.open)))
        {
         setup.a=bar;
         setup.a_age=0;
         setup.has_a=true;
         event="PRICE_PROXY_A_CAPTURED";
        }
      if(event=="")
         event=setup.has_a?"WAITING_FOR_B":(setup.touched!=0?"ZONE_TOUCHED_WAITING_FOR_A":"WAITING_FOR_ZONE");
      return false;
     }
  };

#endif

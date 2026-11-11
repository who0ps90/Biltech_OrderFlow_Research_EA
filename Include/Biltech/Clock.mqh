#ifndef BILTECH_CLOCK_MQH
#define BILTECH_CLOCK_MQH

// No use of TimeGMTOffset/TimeCurrent: historical broker offsets must be supplied.
// This calendar supports US DST from 1987 onward and weekdays only. Exchange
// holidays and early closes require an external calendar; they are not inferred.
struct BrokerOffsetPeriod
  {
   datetime from_utc;
   datetime to_utc;
   int      minutes; // Broker-server wall clock minus UTC.
  };

class CResearchClock
  {
private:
   BrokerOffsetPeriod m_periods[];

   string Trim(string value)
     {
      StringTrimLeft(value);
      StringTrimRight(value);
      return value;
     }

   bool ParseDate(string value,datetime &parsed)
     {
      value=Trim(value);
      if(StringLen(value)!=19 || StringSubstr(value,4,1)!="." ||
         StringSubstr(value,7,1)!="." || StringSubstr(value,10,1)!=" " ||
         StringSubstr(value,13,1)!=":" || StringSubstr(value,16,1)!=":")
         return false;
      for(int i=0;i<19;i++)
        {
         if(i==4 || i==7 || i==10 || i==13 || i==16)
            continue;
         ushort c=StringGetCharacter(value,i);
         if(c<'0' || c>'9')
            return false;
        }
      parsed=StringToTime(value);
      return parsed>0 && TimeToString(parsed,TIME_DATE|TIME_SECONDS)==value;
     }

   bool ParseOffset(string value,int &minutes)
     {
      value=Trim(value);
      int n=StringLen(value);
      if(n==0)
         return false;
      int start=(StringSubstr(value,0,1)=="-" || StringSubstr(value,0,1)=="+")?1:0;
      if(start==n || n>5)
         return false;
      for(int i=start;i<n;i++)
        {
         ushort c=StringGetCharacter(value,i);
         if(c<'0' || c>'9')
            return false;
        }
      minutes=(int)StringToInteger(value);
      return minutes>=-840 && minutes<=840;
     }

   datetime WallDate(int year,int month,int day,int hour=0,int minute=0)
     {
      MqlDateTime dt={};
      dt.year=year;
      dt.mon=month;
      dt.day=day;
      dt.hour=hour;
      dt.min=minute;
      return StructToTime(dt);
     }

   int Sunday(int year,int month,int ordinal)
     {
      MqlDateTime dt={};
      TimeToStruct(WallDate(year,month,1),dt);
      return 1+(7-dt.day_of_week)%7+7*(ordinal-1);
     }

   int LastSundayOctober(int year)
     {
      MqlDateTime dt={};
      TimeToStruct(WallDate(year,10,31),dt);
      return 31-dt.day_of_week;
     }

   bool IsDaylight(datetime utc)
     {
      MqlDateTime dt={};
      TimeToStruct(utc,dt);
      int first_month=(dt.year>=2007)?3:4;
      int first_day=Sunday(dt.year,first_month,(dt.year>=2007)?2:1);
      int last_month=(dt.year>=2007)?11:10;
      int last_day=(dt.year>=2007)?Sunday(dt.year,11,1):LastSundayOctober(dt.year);
      // 02:00 EST is 07:00 UTC; 02:00 EDT is 06:00 UTC.
      datetime first=WallDate(dt.year,first_month,first_day,7);
      datetime last=WallDate(dt.year,last_month,last_day,6);
      return utc>=first && utc<last;
     }

   datetime NewYorkWallToUtc(datetime wall)
     {
      // Cash-session hours cannot lie in the repeated/missing 02:00 clock hour.
      datetime standard=(datetime)((long)wall+5*3600);
      return (datetime)((long)wall+(IsDaylight(standard)?4:5)*3600);
     }

public:
   bool Supported(datetime utc,string &reason)
     {
      MqlDateTime dt={};
      if(!TimeToStruct(utc,dt) || dt.year<1987)
        {
         reason="NEW_YORK_CALENDAR_UNSUPPORTED_BEFORE_1987";
         return false;
        }
      reason="";
      return true;
     }

   bool Load(string schedule_file,string &reason)
     {
      ArrayResize(m_periods,0);
      ResetLastError();
      int file=FileOpen(schedule_file,FILE_READ|FILE_TXT|FILE_ANSI,0,CP_UTF8);
      if(file==INVALID_HANDLE)
        {
         reason=StringFormat("OFFSET_SCHEDULE_OPEN_FAILED:%s:%d",schedule_file,GetLastError());
         return false;
        }
      string header=FileReadString(file);
      if(StringLen(header)>0 && StringGetCharacter(header,0)==0xFEFF)
         header=StringSubstr(header,1);
      if(Trim(header)!="utc_from,utc_to,offset_minutes")
        {
         FileClose(file);
         reason="OFFSET_SCHEDULE_HEADER_EXPECTED:utc_from,utc_to,offset_minutes";
         return false;
        }
      int line=1;
      while(!FileIsEnding(file))
        {
         string row=Trim(FileReadString(file));
         line++;
         if(row=="")
            continue;
         string fields[];
         if(StringSplit(row,',',fields)!=3)
           {
            FileClose(file);
            ArrayResize(m_periods,0);
            reason=StringFormat("OFFSET_SCHEDULE_FIELDS_LINE_%d",line);
            return false;
           }
         BrokerOffsetPeriod period;
         if(!ParseDate(fields[0],period.from_utc) || !ParseDate(fields[1],period.to_utc) ||
            !ParseOffset(fields[2],period.minutes) || period.from_utc>=period.to_utc)
           {
            FileClose(file);
            ArrayResize(m_periods,0);
            reason=StringFormat("OFFSET_SCHEDULE_INVALID_LINE_%d",line);
            return false;
           }
         int n=ArraySize(m_periods);
         if(n>0 && period.from_utc!=m_periods[n-1].to_utc)
           {
            FileClose(file);
            ArrayResize(m_periods,0);
            reason=StringFormat("OFFSET_SCHEDULE_GAP_OR_OVERLAP_LINE_%d",line);
            return false;
           }
         ArrayResize(m_periods,n+1);
         m_periods[n]=period;
        }
      FileClose(file);
      if(ArraySize(m_periods)==0)
        {
         reason="OFFSET_SCHEDULE_HAS_NO_INTERVALS";
         return false;
        }
      reason="";
      return true;
     }

   bool UtcToServer(datetime utc,datetime &server,string &reason)
     {
      server=0;
      if(!Supported(utc,reason))
         return false;
      for(int i=0;i<ArraySize(m_periods);i++)
         if(utc>=m_periods[i].from_utc && utc<m_periods[i].to_utc)
           {
            server=(datetime)((long)utc+m_periods[i].minutes*60);
            reason="";
            return true;
           }
      reason="UTC_OUTSIDE_BROKER_OFFSET_SCHEDULE";
      return false;
     }

   bool ServerToUtc(datetime server,datetime &utc,string &reason)
     {
      utc=0;
      int matches=0;
      for(int i=0;i<ArraySize(m_periods);i++)
        {
         datetime candidate=(datetime)((long)server-m_periods[i].minutes*60);
         if(candidate>=m_periods[i].from_utc && candidate<m_periods[i].to_utc)
           {
            utc=candidate;
            matches++;
           }
        }
      if(matches!=1)
        {
         utc=0;
         reason=(matches>1)?"AMBIGUOUS_BROKER_SERVER_TIME":"SERVER_TIME_OUTSIDE_BROKER_OFFSET_SCHEDULE";
         return false;
        }
      if(!Supported(utc,reason))
        {
         utc=0;
         return false;
        }
      reason="";
      return true;
     }

   datetime NewYork(datetime utc)
     {
      string reason;
      if(!Supported(utc,reason))
         return 0;
      return (datetime)((long)utc-(IsDaylight(utc)?4:5)*3600);
     }

   int SessionKey(datetime utc)
     {
      datetime wall=NewYork(utc);
      if(wall==0)
         return 0;
      MqlDateTime dt={};
      TimeToStruct(wall,dt);
      return dt.year*10000+dt.mon*100+dt.day;
     }

   bool InWindow(datetime utc)
     {
      datetime wall=NewYork(utc);
      if(wall==0)
         return false;
      MqlDateTime dt={};
      TimeToStruct(wall,dt);
      int seconds=dt.hour*3600+dt.min*60+dt.sec;
      return dt.day_of_week>=1 && dt.day_of_week<=5 && seconds>=34200 && seconds<39600;
     }

   datetime SessionStartUtc(datetime utc)
     {
      datetime wall=NewYork(utc);
      if(wall==0)
         return 0;
      MqlDateTime dt={};
      TimeToStruct(wall,dt);
      if(dt.day_of_week==0 || dt.day_of_week==6)
         return 0;
      return NewYorkWallToUtc(WallDate(dt.year,dt.mon,dt.day,9,30));
     }

   datetime SessionEndUtc(datetime utc)
     {
      datetime wall=NewYork(utc);
      if(wall==0)
         return 0;
      MqlDateTime dt={};
      TimeToStruct(wall,dt);
      if(dt.day_of_week==0 || dt.day_of_week==6)
         return 0;
      return NewYorkWallToUtc(WallDate(dt.year,dt.mon,dt.day,11));
     }

   bool PreviousCashSession(datetime utc,datetime &from,datetime &to)
     {
      from=0;
      to=0;
      datetime wall=NewYork(utc);
      if(wall==0)
         return false;
      MqlDateTime dt={};
      TimeToStruct(wall,dt);
      datetime day=WallDate(dt.year,dt.mon,dt.day);
      datetime end=NewYorkWallToUtc((datetime)((long)day+16*3600));
      // The most recent fully completed 09:30-16:00 weekday cash session.
      if(dt.day_of_week==0 || dt.day_of_week==6 || utc<end)
         day=(datetime)((long)day-86400);
      for(int i=0;i<8;i++)
        {
         TimeToStruct(day,dt);
         if(dt.year<1987)
            return false;
         if(dt.day_of_week>=1 && dt.day_of_week<=5)
           {
            from=NewYorkWallToUtc((datetime)((long)day+34200));
            to=NewYorkWallToUtc((datetime)((long)day+16*3600));
            return true;
           }
         day=(datetime)((long)day-86400);
        }
      return false;
     }
  };

#endif

#ifndef BILTECH_ORDERFLOW_MQH
#define BILTECH_ORDERFLOW_MQH

// Imported exchange prints only.  No tick-rule or candle-direction classifier.
// All intervals are [from_utc,to_utc); both endpoints must be M5 boundaries.
// Metadata is an importer assertion, not independent proof of provenance.

struct BOFCell
  {
   datetime bar_utc;
   long     price_ticks;
   double   buy;
   double   sell;
   double   unknown;
  };

string BOFTrim(string value)
  {
   StringTrimLeft(value);
   StringTrimRight(value);
   return value;
  }

bool BOFDecimal(const string text,double &value)
  {
   value=0.0;
   int length=StringLen(text);
   if(length==0) return false;
   bool point=false;
   int digits_before=0,digits_after=0;
   for(int i=0;i<length;i++)
     {
      ushort c=StringGetCharacter(text,i);
      if(c==46 && !point) { point=true; continue; }
      if(c<48 || c>57) return false;
      if(point) digits_after++; else digits_before++;
     }
   if(digits_before==0 || (point && digits_after==0)) return false;
   value=StringToDouble(text);
   return MathIsValidNumber(value) && value>=0.0 && value<=1.0e15;
  }

bool BOFUtc(const string value,datetime &result)
  {
   result=0;
   if(StringLen(value)!=20) return false;
   if(StringSubstr(value,4,1)!="-" || StringSubstr(value,7,1)!="-" ||
      StringSubstr(value,10,1)!="T" || StringSubstr(value,13,1)!=":" ||
      StringSubstr(value,16,1)!=":" || StringSubstr(value,19,1)!="Z") return false;
   for(int i=0;i<19;i++)
     {
      if(i==4 || i==7 || i==10 || i==13 || i==16) continue;
      ushort c=StringGetCharacter(value,i);
      if(c<48 || c>57) return false;
     }
   MqlDateTime parts,check;
   ZeroMemory(parts);
   parts.year=(int)StringToInteger(StringSubstr(value,0,4));
   parts.mon=(int)StringToInteger(StringSubstr(value,5,2));
   parts.day=(int)StringToInteger(StringSubstr(value,8,2));
   parts.hour=(int)StringToInteger(StringSubstr(value,11,2));
   parts.min=(int)StringToInteger(StringSubstr(value,14,2));
   parts.sec=(int)StringToInteger(StringSubstr(value,17,2));
   if(parts.year<1971 || parts.year>2099 || parts.mon<1 || parts.mon>12 ||
      parts.day<1 || parts.day>31 || parts.hour>23 || parts.min>59 || parts.sec>59) return false;
   result=StructToTime(parts);
   if(!TimeToStruct(result,check)) return false;
   return check.year==parts.year && check.mon==parts.mon && check.day==parts.day &&
          check.hour==parts.hour && check.min==parts.min && check.sec==parts.sec;
  }

// This is a deliberately restricted CSV dialect: UTF-8, comma separated,
// exact field counts, no quoting/embedded commas, no blank or comment rows.
bool BOFReadRow(const int handle,const int expected,string &fields[],string &reason)
  {
   string line=FileReadString(handle);
   if(StringLen(line)>0 && StringGetCharacter(line,0)==65279) line=StringSubstr(line,1);
   if(StringLen(line)==0 || StringLen(line)>8192)
     { reason="Empty or oversized CSV row"; return false; }
   if(!FileIsLineEnding(handle) && !FileIsEnding(handle))
     { reason="CSV read did not reach a line boundary"; return false; }
   if(StringFind(line,"\"")>=0 || StringFind(line,"\t")>=0)
     { reason="CSV quoting and tab characters are unsupported"; return false; }
   int count=1;
   for(int i=0;i<StringLen(line);i++) if(StringGetCharacter(line,i)==44) count++;
   if(count!=expected || StringSplit(line,44,fields)!=expected)
     { reason="Wrong CSV field count"; return false; }
   for(int i=0;i<expected;i++)
     {
      fields[i]=BOFTrim(fields[i]);
      if(StringLen(fields[i])==0) { reason="Empty CSV field"; return false; }
     }
   return true;
  }

class IOrderFlowProvider
  {
public:
   virtual bool Load(string manifest_file,string cells_file,string symbol,double tick_size,string &reason)=0;
   virtual bool Coverage(datetime from_utc,datetime to_utc,string &reason)=0;
   virtual bool ValidateBar(datetime from_utc,datetime to_utc,double chart_low,double chart_high,string &reason)=0;
   virtual bool CheckFailure(datetime from_utc,datetime to_utc,int direction,double zone_low,double zone_high,
                             double ratio,double min_cell,double max_unknown,bool enable_mnq_min,
                             double min_bar_volume,string &reason)=0;
   virtual bool CheckRetest(datetime from_utc,datetime to_utc,int direction,double a_low,double a_high,
                            double ratio,double min_cell,double max_unknown,bool enable_mnq_min,
                            double min_bar_volume,string &reason)=0;
   virtual bool Profile(datetime from_utc,datetime to_utc,double bin_ticks,double &poc,double &val,double &vah,
                        string &reason)=0;
  };

class CExchangeProvider : public IOrderFlowProvider
  {
private:
   BOFCell m_cells[];
   datetime m_bars[];
   int m_starts[],m_ends[];
   double m_totals[],m_unknown[],m_buys[],m_sells[];
   string m_source,m_dataset,m_symbol,m_instrument,m_units,m_classifier,m_details,m_contract;
   datetime m_from,m_to;
   double m_tick;
   bool m_ready;

   bool FileFailure(const int handle,const string message,string &reason)
     { FileClose(handle); reason=message; return false; }

   int LowerBar(const datetime target)
     {
      int lo=0,hi=ArraySize(m_bars);
      while(lo<hi)
        {
         int mid=lo+(hi-lo)/2;
         if(m_bars[mid]<target) lo=mid+1; else hi=mid;
        }
      return lo;
     }

   bool ReadManifest(const string filename,const string expected_symbol,string &reason)
     {
      ResetLastError();
      int handle=FileOpen(filename,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ,0,CP_UTF8);
      if(handle==INVALID_HANDLE)
        { reason=StringFormat("Cannot open exchange manifest %s (error %d)",filename,GetLastError()); return false; }
      string row[];
      if(FileIsEnding(handle) || !BOFReadRow(handle,2,row,reason))
         return FileFailure(handle,"Invalid manifest header: "+reason,reason);
      if(row[0]!="key" || row[1]!="value") return FileFailure(handle,"Manifest header must be key,value",reason);
      string keys[14]={"source","dataset_id","symbol","instrument","units","classifier","classifier_details",
                       "time_basis","coverage_from_utc","coverage_to_utc","complete","rollover_policy","contract_id","price_basis"};
      string values[14];
      bool seen[14];
      ArrayInitialize(seen,false);
      while(!FileIsEnding(handle))
        {
         if(!BOFReadRow(handle,2,row,reason)) return FileFailure(handle,"Invalid manifest row: "+reason,reason);
         int found=-1;
         for(int i=0;i<14;i++) if(row[0]==keys[i]) { found=i; break; }
         if(found<0) return FileFailure(handle,"Unknown manifest key: "+row[0],reason);
         if(seen[found]) return FileFailure(handle,"Duplicate manifest key: "+row[0],reason);
         seen[found]=true;
         values[found]=row[1];
        }
      FileClose(handle);
      for(int i=0;i<14;i++) if(!seen[i]) { reason="Missing manifest key: "+keys[i]; return false; }
      if(values[2]!=expected_symbol) { reason="Manifest symbol must exactly match the chart symbol including suffix"; return false; }
      if(values[4]!="contracts" && values[4]!="shares")
        { reason="Exchange units must be contracts or shares; tick volume and CFD lots are unsupported"; return false; }
      if(values[5]!="exchange_aggressor_flag" && values[5]!="quote_match_at_trade")
        { reason="Unsupported classifier: require exchange_aggressor_flag or quote_match_at_trade; price-change classification is forbidden"; return false; }
      if(values[7]!="UTC") { reason="Exchange time_basis must be UTC"; return false; }
      if(!BOFUtc(values[8],m_from) || !BOFUtc(values[9],m_to) || m_from>=m_to ||
         ((long)m_from)%300!=0 || ((long)m_to)%300!=0)
        { reason="Manifest coverage must be increasing UTC ISO timestamps aligned to M5 boundaries"; return false; }
      if(values[10]!="true") { reason="Exchange manifest must explicitly declare complete,true"; return false; }
      if(values[11]!="single_contract")
        { reason="V1 requires rollover_policy,single_contract; split tests by unadjusted futures contract"; return false; }
      if(values[13]!="unadjusted") { reason="Exchange price_basis must be unadjusted"; return false; }
      m_source=values[0]; m_dataset=values[1]; m_symbol=values[2]; m_instrument=values[3]; m_units=values[4];
      m_classifier=values[5]; m_details=values[6]; m_contract=values[12];
      return true;
     }

   bool ReadCells(const string filename,string &reason)
     {
      ResetLastError();
      int handle=FileOpen(filename,FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ,0,CP_UTF8);
      if(handle==INVALID_HANDLE)
        { reason=StringFormat("Cannot open exchange cells %s (error %d)",filename,GetLastError()); return false; }
      string row[];
      if(FileIsEnding(handle) || !BOFReadRow(handle,5,row,reason))
         return FileFailure(handle,"Invalid cells header: "+reason,reason);
      if(row[0]!="bar_utc" || row[1]!="price" || row[2]!="buy_volume" || row[3]!="sell_volume" || row[4]!="unknown_volume")
         return FileFailure(handle,"Cells header must be bar_utc,price,buy_volume,sell_volume,unknown_volume",reason);
      int count=0,bar_count=0;
      while(!FileIsEnding(handle))
        {
         if(count>=2000000) return FileFailure(handle,"CSV exceeds V1 in-memory limit of 2000000 cells; split the research period",reason);
         if(!BOFReadRow(handle,5,row,reason)) return FileFailure(handle,"Invalid cells row: "+reason,reason);
         BOFCell cell;
         double price=0.0;
         if(!BOFUtc(row[0],cell.bar_utc) || ((long)cell.bar_utc)%300!=0 || cell.bar_utc<m_from || cell.bar_utc+300>m_to)
            return FileFailure(handle,"Cell timestamp is invalid or outside declared completed-M5 coverage",reason);
         if(!BOFDecimal(row[1],price) || price<=0.0 || price/m_tick>1.0e12 ||
            !BOFDecimal(row[2],cell.buy) || !BOFDecimal(row[3],cell.sell) || !BOFDecimal(row[4],cell.unknown))
            return FileFailure(handle,"Invalid decimal cell value; require positive price and nonnegative finite volumes",reason);
         cell.price_ticks=(long)MathRound(price/m_tick);
         if(MathAbs(price-(double)cell.price_ticks*m_tick)>m_tick*1.0e-6)
            return FileFailure(handle,"Cell price is not aligned to the chart tick size",reason);
         double total=cell.buy+cell.sell+cell.unknown;
         if(!MathIsValidNumber(total) || total<=0.0) return FileFailure(handle,"A cell must contain positive genuine traded volume",reason);
         if(count>0)
           {
            if(cell.bar_utc<m_cells[count-1].bar_utc ||
               (cell.bar_utc==m_cells[count-1].bar_utc && cell.price_ticks<=m_cells[count-1].price_ticks))
               return FileFailure(handle,"Cells must be sorted by UTC then increasing price; duplicates are rejected",reason);
           }
         if(ArrayResize(m_cells,count+1,4096)<0) return FileFailure(handle,"Cannot allocate exchange cell storage",reason);
         m_cells[count]=cell;
         bool new_bar=(bar_count==0);
         if(bar_count>0) new_bar=(m_bars[bar_count-1]!=cell.bar_utc);
         if(new_bar)
           {
            if(ArrayResize(m_bars,bar_count+1,1024)<0 || ArrayResize(m_starts,bar_count+1,1024)<0 ||
               ArrayResize(m_ends,bar_count+1,1024)<0 || ArrayResize(m_totals,bar_count+1,1024)<0 ||
               ArrayResize(m_unknown,bar_count+1,1024)<0 || ArrayResize(m_buys,bar_count+1,1024)<0 ||
               ArrayResize(m_sells,bar_count+1,1024)<0)
               return FileFailure(handle,"Cannot allocate exchange bar storage",reason);
            m_bars[bar_count]=cell.bar_utc; m_starts[bar_count]=count;
            m_totals[bar_count]=0.0; m_unknown[bar_count]=0.0; m_buys[bar_count]=0.0; m_sells[bar_count]=0.0;
            bar_count++;
           }
         m_ends[bar_count-1]=count+1;
         m_totals[bar_count-1]+=total; m_unknown[bar_count-1]+=cell.unknown;
         m_buys[bar_count-1]+=cell.buy; m_sells[bar_count-1]+=cell.sell;
         if(!MathIsValidNumber(m_totals[bar_count-1])) return FileFailure(handle,"Exchange bar volume overflow",reason);
         count++;
        }
      FileClose(handle);
      if(count==0) { reason="Exchange cells file contains no trades"; return false; }
      return true;
     }

   bool CheckFlow(datetime from_utc,datetime to_utc,int direction,double area_low,double area_high,
                  double ratio,double min_cell,double max_unknown,bool enable_mnq_min,double min_bar_volume,
                  bool failure,string &reason)
     {
      if(!MathIsValidNumber(ratio) || ratio<1.0 || !MathIsValidNumber(min_cell) || min_cell<=0.0 ||
         !MathIsValidNumber(max_unknown) || max_unknown<0.0 || max_unknown>1.0 ||
         !MathIsValidNumber(area_low) || !MathIsValidNumber(area_high) || area_low>area_high ||
         (direction!=1 && direction!=-1))
        { reason="Invalid exchange predicate parameters"; return false; }
      if(to_utc-from_utc!=300) { reason="Failure/retest requires exactly one completed M5 interval"; return false; }
      if(!Coverage(from_utc,to_utc,reason)) return false;
      int b=LowerBar(from_utc);
      if(m_unknown[b]/m_totals[b]>max_unknown)
        { reason="Unknown aggressor fraction exceeds explicit per-bar allowance"; return false; }
      if(enable_mnq_min)
        {
         if(m_instrument!="MNQ" || m_units!="contracts")
           { reason="MNQ minimum is permitted only for instrument MNQ with units contracts"; return false; }
         if(!MathIsValidNumber(min_bar_volume) || min_bar_volume<=0.0)
           { reason="Enabled MNQ minimum must be positive and finite"; return false; }
         if(m_totals[b]<min_bar_volume) { reason="MNQ completed-bar contract volume below selected minimum"; return false; }
        }
      bool want_buy=(failure ? direction==-1 : direction==1);
      if((want_buy && m_buys[b]<=m_sells[b]) || (!want_buy && m_sells[b]<=m_buys[b]))
        { reason="Completed bar lacks required aggregate aggressor dominance"; return false; }
      int start=m_starts[b],end=m_ends[b];
      if(failure)
        {
         // 'Near the failed extreme' is defined conservatively as the extreme traded cell itself.
         int extreme=(direction==1 ? start : end-1);
         start=extreme; end=extreme+1;
        }
      for(int i=start;i<end;i++)
        {
         double price=(double)m_cells[i].price_ticks*m_tick;
         if(failure)
           {
            if(price<area_low || price>area_high) continue;
           }
         else
           {
            // Renewed aggression must occur beyond A in the breakout direction.
            if(direction==1 && price<=area_high) continue;
            if(direction==-1 && price>=area_low) continue;
           }
         double numerator=(want_buy ? m_cells[i].buy : m_cells[i].sell);
         double denominator=(want_buy ? m_cells[i].sell : m_cells[i].buy);
         // A zero denominator never manufactures an infinite imbalance.
         if(denominator<=0.0 || numerator<min_cell) continue;
         if(numerator/denominator>=ratio)
           {
            reason=StringFormat("%s horizontal %s imbalance %.6f at %.10f; unknown_fraction=%.6f; bar_volume=%.2f",
                                (failure ? "failure" : "retest"),(want_buy ? "buy" : "sell"),
                                numerator/denominator,price,m_unknown[b]/m_totals[b],m_totals[b]);
            return true;
           }
        }
      reason=(failure ? "No eligible horizontal imbalance at failed traded extreme inside zone" :
                         "No eligible opposing horizontal imbalance beyond A range");
      return false;
     }

public:
   CExchangeProvider(void) { Reset(); }

   void Reset(void)
     {
      m_ready=false; m_from=0; m_to=0; m_tick=0.0;
      m_source=""; m_dataset=""; m_symbol=""; m_instrument=""; m_units=""; m_classifier=""; m_details=""; m_contract="";
      ArrayFree(m_cells); ArrayFree(m_bars); ArrayFree(m_starts); ArrayFree(m_ends);
      ArrayFree(m_totals); ArrayFree(m_unknown); ArrayFree(m_buys); ArrayFree(m_sells);
     }

   virtual bool Load(string manifest_file,string cells_file,string symbol,double tick_size,string &reason)
     {
      Reset(); reason="";
      if(!MathIsValidNumber(tick_size) || tick_size<=0.0 || StringLen(symbol)==0)
        { reason="Exchange provider requires chart symbol and positive tick size"; return false; }
      m_tick=tick_size;
      if(!ReadManifest(manifest_file,symbol,reason) || !ReadCells(cells_file,reason)) { Reset(); return false; }
      m_ready=true;
      reason=StringFormat("Loaded %d imported cells in %d M5 bars; dataset=%s; source=%s",
                          ArraySize(m_cells),ArraySize(m_bars),m_dataset,m_source);
      return true;
     }

   virtual bool Coverage(datetime from_utc,datetime to_utc,string &reason)
     {
      if(!m_ready) { reason="Exchange provider is not initialized"; return false; }
      if(from_utc>=to_utc || ((long)from_utc)%300!=0 || ((long)to_utc)%300!=0)
        { reason="Exchange query must be a nonempty whole-M5 UTC interval"; return false; }
      if(from_utc<m_from || to_utc>m_to) { reason="Exchange query exceeds declared UTC coverage"; return false; }
      int index=LowerBar(from_utc),count=ArraySize(m_bars);
      for(datetime expected=from_utc;expected<to_utc;expected+=300)
        {
         if(index>=count || m_bars[index]!=expected || m_totals[index]<=0.0)
           { reason="Missing positive-volume M5 data at UTC "+TimeToString(expected,TIME_DATE|TIME_MINUTES); return false; }
         index++;
        }
      reason="Complete positive-volume M5 coverage";
      return true;
     }

   virtual bool ValidateBar(datetime from_utc,datetime to_utc,double chart_low,double chart_high,string &reason)
     {
      if(to_utc-from_utc!=300 || !MathIsValidNumber(chart_low) || !MathIsValidNumber(chart_high) ||
         chart_low<=0.0 || chart_high<chart_low)
        { reason="Chart/import validation requires one completed M5 bar with valid low/high"; return false; }
      if(!Coverage(from_utc,to_utc,reason)) return false;
      double low_ticks=chart_low/m_tick,high_ticks=chart_high/m_tick;
      if(low_ticks>1.0e12 || high_ticks>1.0e12 ||
         MathAbs(low_ticks-MathRound(low_ticks))>1.0e-6 || MathAbs(high_ticks-MathRound(high_ticks))>1.0e-6)
        { reason="Chart OHLC extrema are not on the imported chart tick grid"; return false; }
      int b=LowerBar(from_utc);
      long imported_low=m_cells[m_starts[b]].price_ticks;
      long imported_high=m_cells[m_ends[b]-1].price_ticks;
      if(imported_low!=(long)MathRound(low_ticks) || imported_high!=(long)MathRound(high_ticks))
        {
         reason=StringFormat("Chart/import M5 extrema mismatch: chart=[%.10f,%.10f] import=[%.10f,%.10f]",
                             chart_low,chart_high,(double)imported_low*m_tick,(double)imported_high*m_tick);
         return false;
        }
      // Aggregation preserves no within-bar sequence; open/close cannot be authenticated here.
      reason="Chart/import completed-M5 extrema agree on the same UTC interval and tick grid";
      return true;
     }

   virtual bool CheckFailure(datetime from_utc,datetime to_utc,int direction,double zone_low,double zone_high,
                             double ratio,double min_cell,double max_unknown,bool enable_mnq_min,
                             double min_bar_volume,string &reason)
     {
      return CheckFlow(from_utc,to_utc,direction,zone_low,zone_high,ratio,min_cell,max_unknown,
                       enable_mnq_min,min_bar_volume,true,reason);
     }

   virtual bool CheckRetest(datetime from_utc,datetime to_utc,int direction,double a_low,double a_high,
                            double ratio,double min_cell,double max_unknown,bool enable_mnq_min,
                            double min_bar_volume,string &reason)
     {
      return CheckFlow(from_utc,to_utc,direction,a_low,a_high,ratio,min_cell,max_unknown,
                       enable_mnq_min,min_bar_volume,false,reason);
     }

   virtual bool Profile(datetime from_utc,datetime to_utc,double bin_ticks,double &poc,double &val,double &vah,string &reason)
     {
      poc=0.0; val=0.0; vah=0.0;
      if(!MathIsValidNumber(bin_ticks) || bin_ticks<1.0 || bin_ticks>1000000.0 || bin_ticks!=MathRound(bin_ticks))
        { reason="Profile bin_ticks must be an integer from 1 to 1000000"; return false; }
      if(!Coverage(from_utc,to_utc,reason)) return false;
      int first_bar=LowerBar(from_utc),last_bar=LowerBar(to_utc)-1;
      int first=m_starts[first_bar],end=m_ends[last_bar];
      long width=(long)bin_ticks,min_bin=0,max_bin=0;
      for(int i=first;i<end;i++)
        {
         long bin=(long)MathFloor((double)m_cells[i].price_ticks/(double)width);
         if(i==first || bin<min_bin) min_bin=bin;
         if(i==first || bin>max_bin) max_bin=bin;
        }
      if(max_bin-min_bin>199999) { reason="Profile exceeds V1 limit of 200000 contiguous bins"; return false; }
      int size=(int)(max_bin-min_bin+1);
      double volumes[];
      if(ArrayResize(volumes,size)!=size) { reason="Cannot allocate profile bins"; return false; }
      ArrayInitialize(volumes,0.0);
      double total=0.0;
      for(int i=first;i<end;i++)
        {
         long bin=(long)MathFloor((double)m_cells[i].price_ticks/(double)width);
         double volume=m_cells[i].buy+m_cells[i].sell+m_cells[i].unknown;
         volumes[(int)(bin-min_bin)]+=volume; total+=volume;
        }
      if(!MathIsValidNumber(total) || total<=0.0) { reason="Profile total is invalid"; return false; }
      int center=0;
      for(int i=1;i<size;i++) if(volumes[i]>volumes[center]) center=i; // lower-price POC wins ties
      int lower=center,upper=center;
      double included=volumes[center];
      while(included<total*0.70 && (lower>0 || upper<size-1))
        {
         bool take_lower=false;
         if(lower>0 && upper<size-1) take_lower=(volumes[lower-1]>=volumes[upper+1]);
         else take_lower=(lower>0);
         if(take_lower) { lower--; included+=volumes[lower]; }
         else { upper++; included+=volumes[upper]; }
        }
      poc=(double)(min_bin+center)*(double)width*m_tick;
      val=(double)(min_bin+lower)*(double)width*m_tick;
      vah=(double)(min_bin+upper+1)*(double)width*m_tick;
      reason=StringFormat("Frozen-input profile: %d bins; volume=%.2f; included=%.6f; POC is bin lower edge",size,total,included/total);
      return true;
     }

   bool Ready(void) { return m_ready; }
   string DatasetId(void) { return m_dataset; }
   string Instrument(void) { return m_instrument; }
   string Units(void) { return m_units; }
   string Source(void) { return m_source; }
   string Classifier(void) { return m_classifier; }
   string ClassifierDetails(void) { return m_details; }
   string ContractId(void) { return m_contract; }
   datetime CoverageFrom(void) { return m_from; }
   datetime CoverageTo(void) { return m_to; }
  };

#endif

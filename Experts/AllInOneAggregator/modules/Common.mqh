//+------------------------------------------------------------------+
//|                                                       Common.mqh |
//|                                   Common utilities for all modules|
//+------------------------------------------------------------------+
#property strict

const string NL = "\n";

string Trim(const string s)
{
   string t = s;
   StringTrimLeft(t);
   StringTrimRight(t);
   return t;
}

int SplitTickers(const string tickers_csv, string &out[])
{
   ArrayResize(out, 0);
   string csv = Trim(tickers_csv);
   if(csv == "")
      return 0;

   string parts[];
   int n = StringSplit(csv, ',', parts);
   if(n <= 0)
      return 0;

   int count = 0;
   for(int i = 0; i < n; i++)
   {
      string sym = Trim(parts[i]);
      if(sym == "")
         continue;
      ArrayResize(out, count + 1);
      out[count] = sym;
      count++;
   }
   return count;
}

datetime DayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

datetime Midnight(datetime dt)
{
   MqlDateTime s;
   TimeToStruct(dt, s);
   s.hour = 0; s.min = 0; s.sec = 0;
   return StructToTime(s);
}

datetime TodayAt(int hour, int minute)
{
   MqlDateTime s;
   TimeToStruct(TimeCurrent(), s);
   s.hour = hour; s.min = minute; s.sec = 0;
   return StructToTime(s);
}

string JsonEscape(const string s)
{
   string out = "";
   int len = StringLen(s);
   for(int i = 0; i < len; i++)
   {
      ushort c = StringGetCharacter(s, i);
      if(c == 0x5C)
         out += "\\\\";
      else if(c == 0x22)
         out += "\\\"";
      else if(c == 0x0D)
         out += "\\r";
      else if(c == 0x0A)
         out += "\\n";
      else if(c == 0x09)
         out += "\\t";
      else
         out += CharToString((uchar)c);
   }
   return out;
}

string DateTimeToIso(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02d", dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

string PeriodoParaString(ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_M1)  return "M1";
   if(tf == PERIOD_M5)  return "M5";
   if(tf == PERIOD_M15) return "M15";
   if(tf == PERIOD_M30) return "M30";
   if(tf == PERIOD_H1)  return "H1";
   if(tf == PERIOD_H4)  return "H4";
   if(tf == PERIOD_D1)  return "D1";
   if(tf == PERIOD_W1)  return "W1";
   if(tf == PERIOD_MN1) return "MN";
   return "TF" + IntegerToString((int)tf);
}

int OpenLogFile(const string filename, int &handle)
{
   handle = FileOpen(filename, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(handle != INVALID_HANDLE)
      FileSeek(handle, 0, SEEK_END);
   return handle;
}

void CloseLogFile(int &handle)
{
   if(handle != INVALID_HANDLE)
   {
      FileClose(handle);
      handle = INVALID_HANDLE;
   }
}
//+------------------------------------------------------------------+

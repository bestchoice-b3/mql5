//+------------------------------------------------------------------+
//|                                              ObvTurboJsonExporter|
//+------------------------------------------------------------------+
#property strict

input string InpTickers = "ABEV3,ALPA3,ASAI3,AZUL4,BBAS3,BBDC3,BBSE3,BEEF3,B3SA3,BRAP3,BRFS3,BRKM3,CASH3,CMIG3,COGN3,CPFE3,CRFB3,CSNA3,CVCB3,CYRE3,ELET3,EMBR3,EQTL3,EZTC3,FLRY3,GGBR3,GOAU3,GOLL4,HAPV3,HYPE3,ITUB3,JBSS3,KLBN3,LREN3,LWSA3,MGLU3,MRVE3,PCAR3,PETR3,PETZ3,POSI3,PRIO3,QUAL3,RADL3,RAIL3,RDOR3,RECV3,RENT3,SANB3,SBSP3,SUZB3,TAEE3,TIMS3,TOTS3,USIM5,VALE3,VIVT3,WEGE3,YDUQ3";                
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_D1;
input int InpPeriodLookback = 20;
input int InpMinTouchPoints = 2;
input int InpTimerSeconds = 300;
input int InpDailyHour = 18;
input int InpDailyMinute = 0;
input int InpDailyOffsetMinutes = 10;

struct TrendLine
{
   bool   valid;
   int    idx1;
   int    idx2;
   double y1;
   double y2;
   double slope;
   double intercept;
};

datetime g_last_run_day = 0;
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

datetime ScheduledTimeForDay(const datetime day_start)
{
   return day_start + (InpDailyHour * 3600) + (InpDailyMinute * 60) + (InpDailyOffsetMinutes * 60);
}

void MaybeRunToday()
{
   datetime now = TimeCurrent();
   datetime today = DayStart(now);
   if(today == g_last_run_day)
      return;

   datetime scheduled = ScheduledTimeForDay(today);
   if(now < scheduled)
      return;

   RunOnceAllTickers();
   g_last_run_day = today;
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

bool FindLastTwoLocalMinimums(const double &series[], const int current_bar, const int lookback, int &idx1, int &idx2, double &y1, double &y2)
{
   idx1 = -1;
   idx2 = -1;
   y1 = 0.0;
   y2 = 0.0;

   int size = ArraySize(series);
   if(size < 5)
      return false;

   int start = current_bar - lookback;
   if(start < 2)
      start = 2;

   int end = current_bar - 2;
   if(end > size - 2)
      end = size - 2;

   if(start > end)
      return false;

   // arrays are NOT series: 0 is oldest. We scan from older to newer (low index -> high index)
   // and keep the last two extrema found (most recent within the window).
   for(int i = start; i <= end; i++)
   {
      if(series[i] < series[i-1] && series[i] < series[i+1])
      {
         idx1 = idx2;
         y1   = y2;
         idx2 = i;
         y2   = series[i];
      }
   }

   return (idx1 >= 0 && idx2 >= 0 && idx2 != idx1);
}

bool FindLastTwoLocalMaximums(const double &series[], const int current_bar, const int lookback, int &idx1, int &idx2, double &y1, double &y2)
{
   idx1 = -1;
   idx2 = -1;
   y1 = 0.0;
   y2 = 0.0;

   int size = ArraySize(series);
   if(size < 5)
      return false;

   int start = current_bar - lookback;
   if(start < 2)
      start = 2;

   int end = current_bar - 2;
   if(end > size - 2)
      end = size - 2;

   if(start > end)
      return false;

   for(int i = start; i <= end; i++)
   {
      if(series[i] > series[i-1] && series[i] > series[i+1])
      {
         idx1 = idx2;
         y1   = y2;
         idx2 = i;
         y2   = series[i];
      }
   }

   return (idx1 >= 0 && idx2 >= 0 && idx2 != idx1);
}

TrendLine BuildTrendLineFromTwoPoints(const int idx1, const int idx2, const double y1, const double y2)
{
   TrendLine tl;
   tl.valid = false;
   tl.idx1 = idx1;
   tl.idx2 = idx2;
   tl.y1 = y1;
   tl.y2 = y2;
   tl.slope = 0.0;
   tl.intercept = 0.0;

   int dx = idx2 - idx1;
   if(dx == 0)
      return tl;

   tl.slope = (y2 - y1) / dx;
   tl.intercept = y1 - tl.slope * idx1;
   tl.valid = true;
   return tl;
}

double TrendLineValueAt(const TrendLine &tl, const int x)
{
   if(!tl.valid)
      return EMPTY_VALUE;
   return tl.slope * x + tl.intercept;
}

string TrajectoryFromValues(const double obv, const double green, const double red)
{
   if(green != EMPTY_VALUE && obv > green)
      return "ascendente";
   if(red != EMPTY_VALUE && obv < red)
      return "descendente";
   return "neutra";
}

double CalcLinesScale(const double white, const double green, const double red)
{
   double max_abs = MathAbs(white);
   if(green != EMPTY_VALUE)
      max_abs = MathMax(max_abs, MathAbs(green));
   if(red != EMPTY_VALUE)
      max_abs = MathMax(max_abs, MathAbs(red));

   double scale = 1.0;
   while(max_abs / scale >= 10000.0)
      scale *= 1000.0;
   return scale;
}

bool WriteJsonForSymbol(const string symbol,
                        const ENUM_TIMEFRAMES tf,
                        const double obv_white,
                        const double lta_green,
                        const double ltb_red,
                        const string trajectory,
                        const double lines_scale)
{
   string filename = symbol + ".obv.json";

   int h = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      PrintFormat("Falha ao abrir arquivo para escrita: %s. Erro=%d", filename, GetLastError());
      return false;
   }

   string tf_str = EnumToString(tf);

   FileWriteString(h, "{" + NL);
   FileWriteString(h, StringFormat("  \"ticker\": \"%s\",%s", JsonEscape(symbol), NL));
   FileWriteString(h, StringFormat("  \"timeframe\": \"%s\",%s", JsonEscape(tf_str), NL));
   FileWriteString(h, StringFormat("  \"trajectory\": \"%s\",%s", JsonEscape(trajectory), NL));
   FileWriteString(h, StringFormat("  \"generated_at\": \"%s\",%s", DateTimeToIso(TimeCurrent()), NL));
   FileWriteString(h, StringFormat("  \"lines_scale\": %.0f,%s", lines_scale, NL));

   FileWriteString(h, "  \"lines\": {" + NL);
   FileWriteString(h, StringFormat("    \"white\": %.3f,%s", MathAbs(obv_white/lines_scale), NL));
   if(lta_green == EMPTY_VALUE)
      FileWriteString(h, StringFormat("    \"green\": null,%s", NL));
   else
      FileWriteString(h, StringFormat("    \"green\": %.3f,%s", MathAbs(lta_green/lines_scale), NL));

   if(ltb_red == EMPTY_VALUE)
      FileWriteString(h, StringFormat("    \"red\": null%s", NL));
   else
      FileWriteString(h, StringFormat("    \"red\": %.3f%s", MathAbs(ltb_red/lines_scale), NL));
   FileWriteString(h, "  }" + NL);

   FileWriteString(h, "}" + NL);
   FileClose(h);
   return true;
}

bool ComputeForSymbol(const string symbol)
{
   if(!SymbolSelect(symbol, true))
      PrintFormat("Aviso: nao foi possivel selecionar o simbolo %s", symbol);

   int obv_handle = iOBV(symbol, InpTimeframe, VOLUME_REAL);
   if(obv_handle == INVALID_HANDLE)
   {
      PrintFormat("Erro ao criar handle do OBV para %s. Erro=%d", symbol, GetLastError());
      return false;
   }

   int bars_to_copy = MathMax(InpPeriodLookback + 10, 100);
   double obv[];
   ArraySetAsSeries(obv, false);
   int copied = CopyBuffer(obv_handle, 0, 0, bars_to_copy, obv);
   if(copied <= InpPeriodLookback + 5)
   {
      PrintFormat("Dados insuficientes de OBV para %s (copied=%d)", symbol, copied);
      IndicatorRelease(obv_handle);
      return false;
   }

   int current_bar = copied - 2; // ultimo candle fechado (array nao-series: 0=mais antigo, last=atual)
   if(current_bar < 2)
   {
      IndicatorRelease(obv_handle);
      return false;
   }
   double obv_white = obv[current_bar];

   double lta_green = EMPTY_VALUE;
   double ltb_red   = EMPTY_VALUE;

   int idx1, idx2;
   double y1, y2;

   int touch_min = MathMax(2, InpMinTouchPoints);

   if(touch_min <= 2)
   {
      if(FindLastTwoLocalMinimums(obv, current_bar, InpPeriodLookback, idx1, idx2, y1, y2))
      {
         TrendLine tl = BuildTrendLineFromTwoPoints(idx1, idx2, y1, y2);
         lta_green = TrendLineValueAt(tl, current_bar);
      }

      if(FindLastTwoLocalMaximums(obv, current_bar, InpPeriodLookback, idx1, idx2, y1, y2))
      {
         TrendLine tl = BuildTrendLineFromTwoPoints(idx1, idx2, y1, y2);
         ltb_red = TrendLineValueAt(tl, current_bar);
      }
   }
   else
   {
      // Com InpMinTouchPoints > 2, este exportador ainda usa os 2 ultimos pontos (como no indicador).
      if(FindLastTwoLocalMinimums(obv, current_bar, InpPeriodLookback, idx1, idx2, y1, y2))
      {
         TrendLine tl = BuildTrendLineFromTwoPoints(idx1, idx2, y1, y2);
         lta_green = TrendLineValueAt(tl, current_bar);
      }

      if(FindLastTwoLocalMaximums(obv, current_bar, InpPeriodLookback, idx1, idx2, y1, y2))
      {
         TrendLine tl = BuildTrendLineFromTwoPoints(idx1, idx2, y1, y2);
         ltb_red = TrendLineValueAt(tl, current_bar);
      }
   }

   string trajectory = TrajectoryFromValues(obv_white, lta_green, ltb_red);

   double lines_scale = CalcLinesScale(obv_white, lta_green, ltb_red);
   bool ok = WriteJsonForSymbol(symbol, InpTimeframe, obv_white, lta_green, ltb_red, trajectory, lines_scale);

   IndicatorRelease(obv_handle);
   return ok;
}

void RunOnceAllTickers()
{
   string syms[];
   int n = SplitTickers(InpTickers, syms);
   if(n <= 0)
   {
      Print("Nenhum ticker informado em InpTickers");
      return;
   }

   for(int i = 0; i < n; i++)
   {
      string symbol = syms[i];
      bool ok = ComputeForSymbol(symbol);
      if(ok)
         PrintFormat("JSON gerado: %s.obj.json", symbol);
   }
}

int OnInit()
{
   EventSetTimer(MathMax(1, InpTimerSeconds));
   g_last_run_day = 0;

   MaybeRunToday();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   MaybeRunToday();
}

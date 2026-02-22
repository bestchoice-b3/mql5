//+------------------------------------------------------------------+
//|                                                    AdxJsonExporter|
//+------------------------------------------------------------------+
#property strict

input string Ativos = "ABEV3,ALPA3,ASAI3,AZUL4,BBAS3,BBDC3,BBSE3,BEEF3,B3SA3,BRAP3,BRFS3,BRKM3,CASH3,CMIG3,COGN3,CPFE3,CRFB3,CSNA3,CVCB3,CYRE3,ELET3,EMBR3,EQTL3,EZTC3,FLRY3,GGBR3,GOAU3,GOLL4,HAPV3";
input string Ativos2 = "HYPE3,ITUB3,JBSS3,KLBN3,LREN3,LWSA3,MGLU3,MRVE3,PCAR3,PETR3,PETZ3,POSI3,PRIO3,QUAL3,RADL3,RAIL3,RDOR3,RECV3,RENT3,SANB3,SBSP3,SUZB3,TAEE3,TIMS3,TOTS3,USIM5";
input string Ativos3 = "VALE3,VIVT3,WEGE3,YDUQ3";
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_D1;
input int InpAdxPeriod = 21;
input int InpTimerSeconds = 300;
input int InpDailyHour = 12;
input int InpDailyMinute = 0;
input int InpDailyOffsetMinutes = 4;
input int InpDailyHour2 = 16;
input int InpDailyMinute2 = 0;
input int InpDailyOffsetMinutes2 = 4;

datetime g_last_run_day = 0;
datetime g_last_run_day2 = 0;
const string NL = "\n";

string LogFileName = "AdxJsonExporterLog.txt";
int log_handle = INVALID_HANDLE;

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

datetime ScheduledTimeForDay2(const datetime day_start)
{
   return day_start + (InpDailyHour2 * 3600) + (InpDailyMinute2 * 60) + (InpDailyOffsetMinutes2 * 60);
}

void MaybeRunToday()
{
   datetime now = TimeCurrent();
   datetime today = DayStart(now);

   datetime scheduled2 = ScheduledTimeForDay2(today);
   if(now >= scheduled2 && today != g_last_run_day2)
   {
      RunOnceAllTickers();
      g_last_run_day2 = today;
      return;
   }

   datetime scheduled1 = ScheduledTimeForDay(today);
   if(now >= scheduled1 && today != g_last_run_day)
   {
      RunOnceAllTickers();
      g_last_run_day = today;
      return;
   }
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

bool WriteJsonForSymbol(const string symbol,
                        const ENUM_TIMEFRAMES tf,
                        const int adx_period,
                        const double adx,
                        const double plus_di,
                        const double minus_di,
                        const bool plus_di_signal,
                        const bool minus_di_signal)
{
   string filename = symbol + ".adx.json";

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
   FileWriteString(h, StringFormat("  \"generated_at\": \"%s\",%s", DateTimeToIso(TimeCurrent()), NL));
   FileWriteString(h, "  \"params\": {" + NL);
   FileWriteString(h, StringFormat("    \"adx_period\": %d%s", adx_period, NL));
   FileWriteString(h, "  }," + NL);

   FileWriteString(h, "  \"values\": {" + NL);
   FileWriteString(h, StringFormat("    \"adx\": %.3f,%s", adx, NL));
   FileWriteString(h, StringFormat("    \"plus_di\": %.3f,%s", plus_di, NL));
   FileWriteString(h, StringFormat("    \"minus_di\": %.3f,%s", minus_di, NL));
   FileWriteString(h, StringFormat("    \"plus_di_signal\": %s,%s", plus_di_signal ? "true" : "false", NL));
   FileWriteString(h, StringFormat("    \"minus_di_signal\": %s%s", minus_di_signal ? "true" : "false", NL));
   FileWriteString(h, "  }" + NL);

   FileWriteString(h, "}" + NL);
   FileClose(h);
   return true;
}

bool ComputeForSymbol(const string symbol)
{
   if(!SymbolSelect(symbol, true))
      PrintFormat("Aviso: nao foi possivel selecionar o simbolo %s", symbol);

   int adx_handle = iADX(symbol, InpTimeframe, InpAdxPeriod);
   if(adx_handle == INVALID_HANDLE)
   {
      PrintFormat("Erro ao criar handle do ADX para %s. Erro=%d", symbol, GetLastError());
      return false;
   }

   int bars_to_copy = MathMax(InpAdxPeriod + 10, 100);

   double adx[];
   double plus_di[];
   double minus_di[];
   ArraySetAsSeries(adx, false);
   ArraySetAsSeries(plus_di, false);
   ArraySetAsSeries(minus_di, false);

   int copied_adx = CopyBuffer(adx_handle, 0, 0, bars_to_copy, adx);
   int copied_pdi = CopyBuffer(adx_handle, 1, 0, bars_to_copy, plus_di);
   int copied_mdi = CopyBuffer(adx_handle, 2, 0, bars_to_copy, minus_di);

   int copied = MathMin(copied_adx, MathMin(copied_pdi, copied_mdi));
   if(copied <= InpAdxPeriod + 2)
   {
      PrintFormat("Dados insuficientes de ADX para %s (copied=%d). Erro=%d", symbol, copied, GetLastError());
      IndicatorRelease(adx_handle);
      return false;
   }

   int bar = copied - 2; // ultimo candle fechado
   if(bar < 0)
   {
      IndicatorRelease(adx_handle);
      return false;
   }

   double adx_v = adx[bar];
   double pdi_v = plus_di[bar];
   double mdi_v = minus_di[bar];

   bool signal = (pdi_v > mdi_v && (pdi_v * 1.8) < adx_v);
   bool minus_signal = (mdi_v > pdi_v && (mdi_v * 1.8) < adx_v);

   bool ok = WriteJsonForSymbol(symbol, InpTimeframe, InpAdxPeriod, adx_v, pdi_v, mdi_v, signal, minus_signal);

   IndicatorRelease(adx_handle);
   return ok;
}

void RunOnceAllTickers()
{
   log_handle = FileOpen(LogFileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(log_handle != INVALID_HANDLE)
      FileSeek(log_handle, 0, SEEK_END);

   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "=== Inicio da rotina: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), " ===");

   string tickers_all = Ativos;
   if(StringLen(Ativos2) > 0)
      tickers_all = tickers_all + "," + Ativos2;
   if(StringLen(Ativos3) > 0)
      tickers_all = tickers_all + "," + Ativos3;

   string syms[];
   int n = SplitTickers(tickers_all, syms);
   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Total ativos lidos: ", IntegerToString(n));
   if(n <= 0)
   {
      Print("Nenhum ticker informado em Ativos/Ativos2/Ativos3");
      if(log_handle != INVALID_HANDLE)
      {
         FileWrite(log_handle, "Nenhum ticker informado");
         FileWrite(log_handle, "=== Rotina finalizada ===");
         FileClose(log_handle);
         log_handle = INVALID_HANDLE;
      }
      return;
   }

   for(int i = 0; i < n; i++)
   {
      string symbol = syms[i];
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "Ativo: ", symbol);
      bool ok = ComputeForSymbol(symbol);
      if(ok)
      {
         PrintFormat("JSON gerado: %s.adx.json", symbol);
         if(log_handle != INVALID_HANDLE)
            FileWrite(log_handle, "OK: ", symbol);
      }
      else
      {
         int err = GetLastError();
         if(log_handle != INVALID_HANDLE)
            FileWrite(log_handle, "FALHA ao processar: ", symbol, " erro=", IntegerToString(err));
      }
   }

   if(log_handle != INVALID_HANDLE)
   {
      FileWrite(log_handle, "=== Rotina finalizada ===");
      FileClose(log_handle);
      log_handle = INVALID_HANDLE;
   }
}

int OnInit()
{
   EventSetTimer(MathMax(1, InpTimerSeconds));
   g_last_run_day = 0;
   g_last_run_day2 = 0;

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

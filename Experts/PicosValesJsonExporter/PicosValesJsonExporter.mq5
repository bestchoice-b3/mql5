//+------------------------------------------------------------------+
//|                                             PicosValesJsonExporter|
//+------------------------------------------------------------------+
#property strict

input string Ativos = "ABEV3,ALPA3,ASAI3,AZUL4,BBAS3,BBDC3,BBSE3,BEEF3,B3SA3,BRAP3,BRFS3,BRKM3,CASH3,CMIG3,COGN3,CPFE3,CRFB3,CSNA3,CVCB3,CYRE3,ELET3,EMBR3,EQTL3,EZTC3,FLRY3,GGBR3,GOAU3,GOLL4,HAPV3";
input string Ativos2 = "HYPE3,ITUB3,JBSS3,KLBN3,LREN3,LWSA3,MGLU3,MRVE3,PCAR3,PETR3,PETZ3,POSI3,PRIO3,QUAL3,RADL3,RAIL3,RDOR3,RECV3,RENT3,SANB3,SBSP3,SUZB3,TAEE3,TIMS3,TOTS3,USIM5";
input string Ativos3 = "VALE3,VIVT3,WEGE3,YDUQ3";
input int    InpMAPeriod = 200;              // Periodo da Media Movel
input ENUM_MA_METHOD InpMAMethod = MODE_SMA; // Metodo da Media Movel
input int    InpMinDaysBetweenPeaks = 7;     // Minimo de dias entre picos/vales
input int    InpTopCount = 5;                // Quantidade maxima de picos e vales
input int    InpScanBars = 1500;             // Quantidade de candles D1 para analisar
input int    InpTimerSeconds = 300;          // Intervalo do timer (segundos). EA roda no max 1x/dia
input int    InpDailyHour = 18;
input int    InpDailyMinute = 0;
input int    InpDailyOffsetMinutes = 0;

struct PeakValley
{
   datetime time;
   double   price;
   double   ma_value;
   double   percentage;
};

datetime g_last_run_day = 0;

const string NL = "\n";

string LogFileName = "PicosValesJsonExporterLog.txt";
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

      int new_size = count + 1;
      ArrayResize(out, new_size);
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

bool IsValidTimeDistance(datetime t, PeakValley &existing[], int count, int min_days)
{
   for(int i = 0; i < count; i++)
   {
      int days_diff = (int)((t - existing[i].time) / (24 * 3600));
      if(MathAbs(days_diff) < min_days)
         return false;
   }
   return true;
}

int FindMinIndexByPercentage(PeakValley &arr[], int count)
{
   if(count <= 0)
      return -1;

   int idx = 0;
   double minp = arr[0].percentage;
   for(int i = 1; i < count; i++)
   {
      if(arr[i].percentage < minp)
      {
         minp = arr[i].percentage;
         idx = i;
      }
   }
   return idx;
}

void SortByPercentageDesc(PeakValley &arr[], int count)
{
   for(int i = 0; i < count - 1; i++)
   {
      for(int j = i + 1; j < count; j++)
      {
         if(arr[j].percentage > arr[i].percentage)
         {
            PeakValley tmp = arr[i];
            arr[i] = arr[j];
            arr[j] = tmp;
         }
      }
   }
}

string JsonEscape(const string s)
{
   string out = "";
   int len = StringLen(s);
   for(int i = 0; i < len; i++)
   {
      ushort c = StringGetCharacter(s, i);
      if(c == 0x5C) // \
         out += "\\\\";
      else if(c == 0x22) // "
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
                               const PeakValley &peaks[], int peaks_count,
                               const PeakValley &valleys[], int valleys_count,
                               const double ma_current,
                               const double price_current,
                               const double current_percentage,
                               const bool signal_sell,
                               const bool signal_buy,
                               const int ma_period,
                               const ENUM_MA_METHOD ma_method,
                               const int min_days,
                               const int scan_bars)
{
   string filename = symbol + ".pico_vale.json";

   int h = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      PrintFormat("Falha ao abrir arquivo para escrita: %s. Erro=%d", filename, GetLastError());
      return false;
   }

   FileWriteString(h, "{" + NL);
   FileWriteString(h, StringFormat("  \"ticker\": \"%s\",%s", JsonEscape(symbol), NL));
   FileWriteString(h, "  \"timeframe\": \"D1\"," + NL);
   FileWriteString(h, StringFormat("  \"ma_current\": %.10f,%s", ma_current, NL));
   FileWriteString(h, StringFormat("  \"price_current\": %.10f,%s", price_current, NL));
   FileWriteString(h, StringFormat("  \"current_price\": %.10f,%s", price_current, NL));
   FileWriteString(h, StringFormat("  \"current_percentage\": %.6f,%s", current_percentage, NL));
   FileWriteString(h, StringFormat("  \"signal_sell\": %s,%s", (signal_sell ? "true" : "false"), NL));
   FileWriteString(h, StringFormat("  \"signal_buy\": %s,%s", (signal_buy ? "true" : "false"), NL));
   FileWriteString(h, StringFormat("  \"generated_at\": \"%s\",%s", DateTimeToIso(TimeCurrent()), NL));
   FileWriteString(h, "  \"params\": {" + NL);
   FileWriteString(h, StringFormat("    \"ma_period\": %d,%s", ma_period, NL));
   FileWriteString(h, StringFormat("    \"ma_method\": %d,%s", (int)ma_method, NL));
   FileWriteString(h, StringFormat("    \"min_days_between_peaks\": %d,%s", min_days, NL));
   FileWriteString(h, StringFormat("    \"scan_bars\": %d%s", scan_bars, NL));
   FileWriteString(h, "  }," + NL);

   FileWriteString(h, "  \"peaks\": [" + NL);
   for(int i = 0; i < peaks_count; i++)
   {
      string comma = (i < peaks_count - 1) ? "," : "";
      FileWriteString(h, "    {" + NL);
      FileWriteString(h, StringFormat("      \"time\": \"%s\",%s", DateTimeToIso(peaks[i].time), NL));
      FileWriteString(h, StringFormat("      \"price\": %.10f,%s", peaks[i].price, NL));
      FileWriteString(h, StringFormat("      \"ma\": %.10f,%s", peaks[i].ma_value, NL));
      FileWriteString(h, StringFormat("      \"percentage\": %.6f%s", peaks[i].percentage, NL));
      FileWriteString(h, StringFormat("    }%s%s", comma, NL));
   }
   FileWriteString(h, "  ]," + NL);

   FileWriteString(h, "  \"valleys\": [" + NL);
   for(int i = 0; i < valleys_count; i++)
   {
      string comma = (i < valleys_count - 1) ? "," : "";
      FileWriteString(h, "    {" + NL);
      FileWriteString(h, StringFormat("      \"time\": \"%s\",%s", DateTimeToIso(valleys[i].time), NL));
      FileWriteString(h, StringFormat("      \"price\": %.10f,%s", valleys[i].price, NL));
      FileWriteString(h, StringFormat("      \"ma\": %.10f,%s", valleys[i].ma_value, NL));
      FileWriteString(h, StringFormat("      \"percentage\": %.6f%s", valleys[i].percentage, NL));
      FileWriteString(h, StringFormat("    }%s%s", comma, NL));
   }
   FileWriteString(h, "  ]" + NL);

   FileWriteString(h, "}" + NL);
   FileClose(h);

   return true;
}

bool ComputeForSymbol(const string symbol)
{
   if(!SymbolSelect(symbol, true))
      PrintFormat("Aviso: nao foi possivel selecionar o simbolo %s", symbol);

   int ma_handle = iMA(symbol, PERIOD_D1, InpMAPeriod, 0, InpMAMethod, PRICE_CLOSE);
   if(ma_handle == INVALID_HANDLE)
   {
      PrintFormat("Erro ao criar handle da MA para %s. Erro=%d", symbol, GetLastError());
      return false;
   }

   int need_bars = MathMax(InpScanBars, InpMAPeriod + 10);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, PERIOD_D1, 0, need_bars, rates);
   if(copied <= InpMAPeriod + 2)
   {
      PrintFormat("Dados insuficientes para %s (copied=%d)", symbol, copied);
      IndicatorRelease(ma_handle);
      return false;
   }

   double ma[];
   ArraySetAsSeries(ma, true);
   int ma_copied = CopyBuffer(ma_handle, 0, 0, copied, ma);
   if(ma_copied <= InpMAPeriod + 2)
   {
      PrintFormat("Falha ao copiar MA para %s (ma_copied=%d). Erro=%d", symbol, ma_copied, GetLastError());
      IndicatorRelease(ma_handle);
      return false;
   }

   int bars_common = MathMin(copied, ma_copied);
   if(bars_common <= InpMAPeriod + 2)
   {
      PrintFormat("Dados insuficientes apos copiar MA para %s (bars_common=%d)", symbol, bars_common);
      IndicatorRelease(ma_handle);
      return false;
   }

   PeakValley peaks[50];
   PeakValley valleys[50];
   int peaks_count = 0;
   int valleys_count = 0;

   int topN = MathMax(1, InpTopCount);
   topN = MathMin(topN, 50);

   // i=0 eh candle atual. Procuramos picos/vales nos candles fechados.
   // Vamos varrer do mais antigo pro mais recente para manter a regra de distancia em dias.
   for(int i = bars_common - 2; i >= 1; i--)
   {
      if(ma[i] <= 0.0 || ma[i] == EMPTY_VALUE)
         continue;

      bool is_peak   = (rates[i].high > rates[i+1].high && rates[i].high > rates[i-1].high);
      bool is_valley = (rates[i].low  < rates[i+1].low  && rates[i].low  < rates[i-1].low);

      if(is_peak)
      {
         double pct = ((rates[i].high - ma[i]) / ma[i]) * 100.0;
         if(pct > 0.0 && IsValidTimeDistance(rates[i].time, peaks, peaks_count, InpMinDaysBetweenPeaks))
         {
            if(peaks_count < topN)
            {
               peaks[peaks_count].time       = rates[i].time;
               peaks[peaks_count].price      = rates[i].high;
               peaks[peaks_count].ma_value   = ma[i];
               peaks[peaks_count].percentage = pct;
               peaks_count++;
            }
            else
            {
               int min_idx = FindMinIndexByPercentage(peaks, peaks_count);
               if(min_idx >= 0 && pct > peaks[min_idx].percentage)
               {
                  peaks[min_idx].time       = rates[i].time;
                  peaks[min_idx].price      = rates[i].high;
                  peaks[min_idx].ma_value   = ma[i];
                  peaks[min_idx].percentage = pct;
               }
            }
         }
      }

      if(is_valley)
      {
         double pct = ((ma[i] - rates[i].low) / ma[i]) * 100.0;
         if(pct > 0.0 && IsValidTimeDistance(rates[i].time, valleys, valleys_count, InpMinDaysBetweenPeaks))
         {
            if(valleys_count < topN)
            {
               valleys[valleys_count].time       = rates[i].time;
               valleys[valleys_count].price      = rates[i].low;
               valleys[valleys_count].ma_value   = ma[i];
               valleys[valleys_count].percentage = pct;
               valleys_count++;
            }
            else
            {
               int min_idx = FindMinIndexByPercentage(valleys, valleys_count);
               if(min_idx >= 0 && pct > valleys[min_idx].percentage)
               {
                  valleys[min_idx].time       = rates[i].time;
                  valleys[min_idx].price      = rates[i].low;
                  valleys[min_idx].ma_value   = ma[i];
                  valleys[min_idx].percentage = pct;
               }
            }
         }
      }
   }

   SortByPercentageDesc(peaks, peaks_count);
   SortByPercentageDesc(valleys, valleys_count);

   double ma_current = ma[0];
   if((ma_current <= 0.0 || ma_current == EMPTY_VALUE) && bars_common > 1)
      ma_current = ma[1];

   double price_current = 0.0;
   if(!SymbolInfoDouble(symbol, SYMBOL_LAST, price_current) || price_current <= 0.0)
   {
      if(!SymbolInfoDouble(symbol, SYMBOL_BID, price_current) || price_current <= 0.0)
         price_current = rates[0].close;
   }

   double current_percentage = 0.0;
   if(ma_current > 0.0 && ma_current != EMPTY_VALUE)
      current_percentage = ((price_current - ma_current) / ma_current) * 100.0;

   bool signal_sell = false;
   if(price_current > ma_current)
   {
      for(int i = 0; i < peaks_count; i++)
      {
         if(current_percentage > (peaks[i].percentage * 0.9))
         {
            signal_sell = true;
            break;
         }
      }
   }

   bool signal_buy = false;
   if(price_current < ma_current)
   {
      double current_pct_abs = MathAbs(current_percentage);
      for(int i = 0; i < valleys_count; i++)
      {
         if(current_pct_abs > (valleys[i].percentage * 0.9))
         {
            signal_buy = true;
            break;
         }
      }
   }

   bool ok = WriteJsonForSymbol(symbol, peaks, peaks_count, valleys, valleys_count, ma_current, price_current, current_percentage, signal_sell, signal_buy, InpMAPeriod, InpMAMethod, InpMinDaysBetweenPeaks, need_bars);

   IndicatorRelease(ma_handle);
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
         FileWrite(log_handle, "Nenhum ticker informado");

      if(log_handle != INVALID_HANDLE)
      {
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
         PrintFormat("JSON gerado: %s.json", symbol);
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

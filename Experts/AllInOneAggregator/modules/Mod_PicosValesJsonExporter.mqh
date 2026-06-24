//+------------------------------------------------------------------+
//|                                   Mod_PicosValesJsonExporter.mqh |
//|                                   Picos Vales JSON Exporter Module|
//+------------------------------------------------------------------+
#property strict

#include "Common.mqh"
#include <TickersProvider.mqh>

input int    InpPvMAPeriod = 200;
input ENUM_MA_METHOD InpPvMAMethod = MODE_SMA;
input int    InpPvMinDaysBetweenPeaks = 7;
input int    InpPvTopCount = 5;
input int    InpPvScanBars = 1500;

string PvLogFileName = "PicosValesJsonExporterLog.txt";

struct PeakValley
{
   datetime time;
   double   price;
   double   ma_value;
   double   percentage;
};

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

bool WritePvJsonForSymbol(const string symbol,
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

bool ComputePvForSymbol(const string symbol)
{
   if(!SymbolSelect(symbol, true))
      PrintFormat("Aviso: nao foi possivel selecionar o simbolo %s", symbol);

   int ma_handle = iMA(symbol, PERIOD_D1, InpPvMAPeriod, 0, InpPvMAMethod, PRICE_CLOSE);
   if(ma_handle == INVALID_HANDLE)
   {
      PrintFormat("Erro ao criar handle da MA para %s. Erro=%d", symbol, GetLastError());
      return false;
   }

   int need_bars = MathMax(InpPvScanBars, InpPvMAPeriod + 10);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, PERIOD_D1, 0, need_bars, rates);
   if(copied <= InpPvMAPeriod + 2)
   {
      PrintFormat("Dados insuficientes para %s (copied=%d)", symbol, copied);
      IndicatorRelease(ma_handle);
      return false;
   }

   double ma[];
   ArraySetAsSeries(ma, true);
   int ma_copied = CopyBuffer(ma_handle, 0, 0, copied, ma);
   if(ma_copied <= InpPvMAPeriod + 2)
   {
      PrintFormat("Falha ao copiar MA para %s (ma_copied=%d). Erro=%d", symbol, ma_copied, GetLastError());
      IndicatorRelease(ma_handle);
      return false;
   }

   int bars_common = MathMin(copied, ma_copied);
   if(bars_common <= InpPvMAPeriod + 2)
   {
      PrintFormat("Dados insuficientes apos copiar MA para %s (bars_common=%d)", symbol, bars_common);
      IndicatorRelease(ma_handle);
      return false;
   }

   PeakValley peaks[50];
   PeakValley valleys[50];
   int peaks_count = 0;
   int valleys_count = 0;

   int topN = MathMax(1, InpPvTopCount);
   topN = MathMin(topN, 50);

   for(int i = bars_common - 2; i >= 1; i--)
   {
      if(ma[i] <= 0.0 || ma[i] == EMPTY_VALUE)
         continue;

      bool is_peak   = (rates[i].high > rates[i+1].high && rates[i].high > rates[i-1].high);
      bool is_valley = (rates[i].low  < rates[i+1].low  && rates[i].low  < rates[i-1].low);

      if(is_peak)
      {
         double pct = ((rates[i].high - ma[i]) / ma[i]) * 100.0;
         if(pct > 0.0 && IsValidTimeDistance(rates[i].time, peaks, peaks_count, InpPvMinDaysBetweenPeaks))
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
         if(pct > 0.0 && IsValidTimeDistance(rates[i].time, valleys, valleys_count, InpPvMinDaysBetweenPeaks))
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

   bool ok = WritePvJsonForSymbol(symbol, peaks, peaks_count, valleys, valleys_count, ma_current, price_current, current_percentage, signal_sell, signal_buy, InpPvMAPeriod, InpPvMAMethod, InpPvMinDaysBetweenPeaks, need_bars);

   IndicatorRelease(ma_handle);
   return ok;
}

void RunPicosValesJsonExporter()
{
   int log_handle = INVALID_HANDLE;
   OpenLogFile(PvLogFileName, log_handle);

   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "=== Inicio da rotina Picos/Vales: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), " ===");

   string syms[];
   int n = GetTickers(syms);

   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Total ativos lidos: ", IntegerToString(n));

   if(n <= 0)
   {
      Print("Nenhum ticker obtido da API/cache");
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "Nenhum ticker obtido da API/cache");

      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "=== Rotina Picos/Vales finalizada ===");
      CloseLogFile(log_handle);
      return;
   }

   for(int i = 0; i < n; i++)
   {
      string symbol = syms[i];
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "Ativo: ", symbol);
      bool ok = ComputePvForSymbol(symbol);
      if(ok)
      {
         PrintFormat("JSON gerado: %s.pico_vale.json", symbol);
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
      FileWrite(log_handle, "=== Rotina Picos/Vales finalizada ===");
   CloseLogFile(log_handle);
}
//+------------------------------------------------------------------+

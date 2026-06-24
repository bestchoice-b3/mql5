//+------------------------------------------------------------------+
//|                                    Mod_ObvTurboJsonExporter.mqh  |
//|                                   OBV Turbo JSON Exporter Module |
//+------------------------------------------------------------------+
#property strict

#include "Common.mqh"
#include <TickersProvider.mqh>

input ENUM_TIMEFRAMES InpObvTimeframe = PERIOD_D1;
input int InpObvPeriodLookback = 20;
input int InpObvMinTouchPoints = 2;

string ObvLogFileName = "ObvTurboJsonExporterLog.txt";

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

bool WriteObvJsonForSymbol(const string symbol,
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

bool ComputeObvForSymbol(const string symbol)
{
   if(!SymbolSelect(symbol, true))
      PrintFormat("Aviso: nao foi possivel selecionar o simbolo %s", symbol);

   int obv_handle = iOBV(symbol, InpObvTimeframe, VOLUME_REAL);
   if(obv_handle == INVALID_HANDLE)
   {
      int err = GetLastError();
      PrintFormat("Erro ao criar handle do OBV (VOLUME_REAL) para %s. Erro=%d", symbol, err);
      SetUserError(err);
      return false;
   }

   int bars_to_copy = MathMax(InpObvPeriodLookback + 10, 100);
   double obv[];
   ArraySetAsSeries(obv, false);
   int copied = CopyBuffer(obv_handle, 0, 0, bars_to_copy, obv);
   if(copied <= InpObvPeriodLookback + 5)
   {
      PrintFormat("Dados insuficientes de OBV para %s (copied=%d)", symbol, copied);
      IndicatorRelease(obv_handle);
      return false;
   }

   int current_bar = copied - 2;
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

   int touch_min = MathMax(2, InpObvMinTouchPoints);

   if(touch_min <= 2)
   {
      if(FindLastTwoLocalMinimums(obv, current_bar, InpObvPeriodLookback, idx1, idx2, y1, y2))
      {
         TrendLine tl = BuildTrendLineFromTwoPoints(idx1, idx2, y1, y2);
         lta_green = TrendLineValueAt(tl, current_bar);
      }

      if(FindLastTwoLocalMaximums(obv, current_bar, InpObvPeriodLookback, idx1, idx2, y1, y2))
      {
         TrendLine tl = BuildTrendLineFromTwoPoints(idx1, idx2, y1, y2);
         ltb_red = TrendLineValueAt(tl, current_bar);
      }
   }

   string trajectory = TrajectoryFromValues(obv_white, lta_green, ltb_red);

   double lines_scale = CalcLinesScale(obv_white, lta_green, ltb_red);
   bool ok = WriteObvJsonForSymbol(symbol, InpObvTimeframe, obv_white, lta_green, ltb_red, trajectory, lines_scale);

   IndicatorRelease(obv_handle);
   return ok;
}

void RunObvTurboJsonExporter()
{
   int log_handle = INVALID_HANDLE;
   OpenLogFile(ObvLogFileName, log_handle);

   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "=== Inicio da rotina OBV: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), " ===");

   string syms[];
   int n = GetTickers(syms);
   
   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Total ativos lidos: ", IntegerToString(n));
   if(n <= 0)
   {
      Print("Nenhum ticker obtido da API/cache");
      if(log_handle != INVALID_HANDLE)
      {
         FileWrite(log_handle, "Nenhum ticker obtido da API/cache");
         FileWrite(log_handle, "=== Rotina OBV finalizada ===");
      }
      CloseLogFile(log_handle);
      return;
   }

   for(int i = 0; i < n; i++)
   {
      string symbol = syms[i];
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "Ativo: ", symbol);
      bool ok = ComputeObvForSymbol(symbol);
      if(ok)
      {
         PrintFormat("JSON gerado: %s.obv.json", symbol);
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
      FileWrite(log_handle, "=== Rotina OBV finalizada ===");
   CloseLogFile(log_handle);
}
//+------------------------------------------------------------------+

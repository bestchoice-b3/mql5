//+------------------------------------------------------------------+
//|                                          Mod_AdxJsonExporter.mqh |
//|                                   ADX JSON Exporter Module       |
//+------------------------------------------------------------------+
#property strict

#include "Common.mqh"
#include <TickersProvider.mqh>

input ENUM_TIMEFRAMES InpAdxTimeframe = PERIOD_D1;
input int InpAdxPeriod = 21;

string AdxLogFileName = "AdxJsonExporterLog.txt";

bool WriteAdxJsonForSymbol(const string symbol,
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

bool ComputeAdxForSymbol(const string symbol)
{
   if(!SymbolSelect(symbol, true))
      PrintFormat("Aviso: nao foi possivel selecionar o simbolo %s", symbol);

   int adx_handle = iADX(symbol, InpAdxTimeframe, InpAdxPeriod);
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

   int bar = copied - 2;
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

   bool ok = WriteAdxJsonForSymbol(symbol, InpAdxTimeframe, InpAdxPeriod, adx_v, pdi_v, mdi_v, signal, minus_signal);

   IndicatorRelease(adx_handle);
   return ok;
}

void RunAdxJsonExporter()
{
   int log_handle = INVALID_HANDLE;
   OpenLogFile(AdxLogFileName, log_handle);

   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "=== Inicio da rotina ADX: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), " ===");

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
         FileWrite(log_handle, "=== Rotina ADX finalizada ===");
      }
      CloseLogFile(log_handle);
      return;
   }

   for(int i = 0; i < n; i++)
   {
      string symbol = syms[i];
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "Ativo: ", symbol);
      bool ok = ComputeAdxForSymbol(symbol);
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
      FileWrite(log_handle, "=== Rotina ADX finalizada ===");
   CloseLogFile(log_handle);
}
//+------------------------------------------------------------------+

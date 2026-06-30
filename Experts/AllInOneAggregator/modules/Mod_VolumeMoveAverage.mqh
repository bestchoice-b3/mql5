//+------------------------------------------------------------------+
//|                                       Mod_VolumeMoveAverage.mqh  |
//|                                   Volume Move Average Module     |
//+------------------------------------------------------------------+
#property strict

#include "Common.mqh"
#include <TickersProvider.mqh>

input string InpVolumeN8N_URL = "http://127.0.0.1:5678/webhook/volume-ma-monitor";
input ENUM_TIMEFRAMES InpVolumeTimeframe = PERIOD_D1;
input int    InpVolumeMA_Period = 90;
input int    InpVolume_Shift = 0;

 string VolumeLogFileName = "VolumeMoveAverageLog.txt";

bool SendToN8N_Volume(const string json_body, int log_handle)
{
   char post_data[];
   char result[];
   string result_headers;

   int len = StringToCharArray(json_body, post_data, 0, WHOLE_ARRAY, CP_UTF8);
   if(len > 0 && ArraySize(post_data) > 0)
   {
      int last = ArraySize(post_data) - 1;
      if(post_data[last] == 0)
         ArrayResize(post_data, last);
   }

   ResetLastError();
   int res = WebRequest("POST", InpVolumeN8N_URL, "Content-Type: application/json\r\n", 10000, post_data, result, result_headers);

   if(res == -1)
   {
      int err = GetLastError();
      Print("[volumeMoveAverage] WebRequest falhou. Erro: ", err);
      Print("[volumeMoveAverage] IMPORTANTE: Habilite a URL em Tools -> Options -> Expert Advisors -> Allow WebRequest");
      Print("[volumeMoveAverage] Adicione: ", InpVolumeN8N_URL);

      if(log_handle != INVALID_HANDLE)
      {
         FileWrite(log_handle, "ERRO WebRequest. Código: ", IntegerToString(err));
         FileWrite(log_handle, "IMPORTANTE: Habilite Allow WebRequest e adicione a URL: ", InpVolumeN8N_URL);
      }
      return false;
   }

   if(res != 200)
   {
      string resp = CharArrayToString(result);
      Print("[volumeMoveAverage] Webhook retornou HTTP ", res, " | resposta: ", resp);
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "HTTP != 200. HTTP=", IntegerToString(res), " resposta=", resp);
      return false;
   }
   else
   {
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "OK Webhook HTTP 200");
      return true;
   }
}

bool ComputeVolumeSignal(const string symbol, string &out_json, int log_handle)
{
   out_json = "";

   int need = InpVolumeMA_Period + InpVolume_Shift + 5;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(symbol, InpVolumeTimeframe, 0, need, rates);
   if(copied <= InpVolumeMA_Period + InpVolume_Shift)
   {
      PrintFormat("[volumeMoveAverage] CopyRates falhou/insuficiente para %s (copied=%d) err=%d", symbol, copied, GetLastError());
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "FALHA CopyRates/insuficiente. Symbol=", symbol, " copied=", IntegerToString(copied), " err=", IntegerToString(GetLastError()));
      return false;
   }

   double vol = (double)rates[InpVolume_Shift].real_volume;

   double sum = 0.0;
   for(int i = InpVolume_Shift; i < InpVolume_Shift + InpVolumeMA_Period; i++)
      sum += (double)rates[i].real_volume;

   double vol_ma = sum / (double)InpVolumeMA_Period;

   string signal = (vol > vol_ma) ? "HIGH_VOLUME" : "LOW_VOLUME";
   double ratio = (vol_ma > 0.0) ? (vol / vol_ma) : 0.0;

   string dt_server = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   string dt_bar = TimeToString(rates[InpVolume_Shift].time, TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   int    dt_bar_unix = (int)rates[InpVolume_Shift].time;

   out_json = StringFormat("{\"symbol\":\"%s\",\"timeframe\":\"%s\",\"timestamp_server\":\"%s\",\"timestamp_bar\":\"%s\",\"timestamp_bar_unix\":%d,\"volume_shift\":%d,\"volume_real\":%.0f,\"volume_ma_period\":%d,\"volume_ma\":%.2f,\"volume_ratio\":%.4f,\"signal\":\"%s\"}",
                          symbol,
                          EnumToString(InpVolumeTimeframe),
                          dt_server,
                          dt_bar,
                          dt_bar_unix,
                          InpVolume_Shift,
                          vol,
                          InpVolumeMA_Period,
                          vol_ma,
                          ratio,
                          signal);

   return true;
}

void RunVolumeMoveAverage()
{
   int log_handle = INVALID_HANDLE;
   OpenLogFile(VolumeLogFileName, log_handle);

   if(log_handle != INVALID_HANDLE)
   {
      FileWrite(log_handle, "=== Início da rotina Volume Move Average: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), " ===");
      FileWrite(log_handle, "URL: ", InpVolumeN8N_URL);
      FileWrite(log_handle, "Timeframe: ", EnumToString(InpVolumeTimeframe));
      FileWrite(log_handle, "MA Period: ", IntegerToString(InpVolumeMA_Period));
      FileWrite(log_handle, "Shift: ", IntegerToString(InpVolume_Shift));
      FileWrite(log_handle, "");
   }

   string tickers[];
   int count = GetTickers(tickers);

   if(count <= 0)
   {
      Print("[volumeMoveAverage] Nenhum ticker obtido da API/cache");
      if(log_handle != INVALID_HANDLE)
      {
         FileWrite(log_handle, "Nenhum ticker obtido da API/cache");
         FileWrite(log_handle, "=== Rotina Volume Move Average finalizada ===");
      }
      CloseLogFile(log_handle);
      return;
   }

   PrintFormat("[volumeMoveAverage] Processando %d tickers...", count);

   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Total tickers lidos: ", IntegerToString(count));

   int processados = 0;
   int enviados_ok = 0;
   int erros = 0;

   for(int i = 0; i < count; i++)
   {
      string symbol = tickers[i];
      StringTrimLeft(symbol);
      StringTrimRight(symbol);
      if(symbol == "")
         continue;

      processados++;

      if(log_handle != INVALID_HANDLE)
      {
         FileWrite(log_handle, "---");
         FileWrite(log_handle, "Ativo: ", symbol);
      }

      if(!SymbolSelect(symbol, true))
      {
         int err = GetLastError();
         Print("[volumeMoveAverage] SymbolSelect falhou: ", symbol, " err=", err);
         if(log_handle != INVALID_HANDLE)
            FileWrite(log_handle, "FALHA SymbolSelect. err=", IntegerToString(err));
         erros++;
         continue;
      }

      string payload;
      if(!ComputeVolumeSignal(symbol, payload, log_handle))
      {
         erros++;
         continue;
      }

      if(StringLen(payload) > 2)
         payload = StringSubstr(payload, 0, StringLen(payload) - 1) + ",\"trigger\":\"SCHEDULED\"}";

      if(SendToN8N_Volume(payload, log_handle))
         enviados_ok++;
      else
         erros++;
      Sleep(150);
   }

   if(log_handle != INVALID_HANDLE)
   {
      FileWrite(log_handle, "");
      FileWrite(log_handle, "Resumo: processados=", IntegerToString(processados), " enviados=", IntegerToString(enviados_ok), " erros=", IntegerToString(erros));
      FileWrite(log_handle, "=== Rotina Volume Move Average finalizada ===");
   }
   CloseLogFile(log_handle);
}
//+------------------------------------------------------------------+

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

void SendToN8N_Volume(const string json_body)
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
      return;
   }

   if(res != 200)
      Print("[volumeMoveAverage] Webhook retornou HTTP ", res, " | resposta: ", CharArrayToString(result));
}

bool ComputeVolumeSignal(const string symbol, string &out_json)
{
   out_json = "";

   int need = InpVolumeMA_Period + InpVolume_Shift + 5;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(symbol, InpVolumeTimeframe, 0, need, rates);
   if(copied <= InpVolumeMA_Period + InpVolume_Shift)
   {
      PrintFormat("[volumeMoveAverage] CopyRates falhou/insuficiente para %s (copied=%d) err=%d", symbol, copied, GetLastError());
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

   out_json = StringFormat("{\"symbol\":\"%s\",\"timeframe\":\"%s\",\"timestamp_server\":\"%s\",\"volume_shift\":%d,\"volume_real\":%.0f,\"volume_ma_period\":%d,\"volume_ma\":%.2f,\"volume_ratio\":%.4f,\"signal\":\"%s\"}",
                          symbol,
                          EnumToString(InpVolumeTimeframe),
                          dt_server,
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
   string tickers[];
   int count = GetTickers(tickers);

   if(count <= 0)
   {
      Print("[volumeMoveAverage] Nenhum ticker obtido da API/cache");
      return;
   }

   PrintFormat("[volumeMoveAverage] Processando %d tickers...", count);

   for(int i = 0; i < count; i++)
   {
      string symbol = tickers[i];
      StringTrimLeft(symbol);
      StringTrimRight(symbol);
      if(symbol == "")
         continue;

      if(!SymbolSelect(symbol, true))
      {
         Print("[volumeMoveAverage] SymbolSelect falhou: ", symbol, " err=", GetLastError());
         continue;
      }

      string payload;
      if(!ComputeVolumeSignal(symbol, payload))
         continue;

      if(StringLen(payload) > 2)
         payload = StringSubstr(payload, 0, StringLen(payload) - 1) + ",\"trigger\":\"SCHEDULED\"}";

      SendToN8N_Volume(payload);
      Sleep(150);
   }
}
//+------------------------------------------------------------------+

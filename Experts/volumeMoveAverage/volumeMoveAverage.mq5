//+------------------------------------------------------------------+
//|                                            volumeMoveAverage.mq5 |
//|      EA que dispara às 10h e 14h e envia dados de volume ao n8n   |
//+------------------------------------------------------------------+
#property copyright "EA Monitor Volume MA"
#property version   "1.00"
#property strict

#include <TickersProvider.mqh>

// ──────────────────────────────────────────────
//  Parâmetros de entrada
// ──────────────────────────────────────────────

input string N8N_Webhook_URL = "http://127.0.0.1:5678/webhook/volume-ma-monitor";
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_D1;
input int    VolumeMA_Period = 90;
input int    Volume_Shift = 0; // 0 = candle atual em formação, 1 = último candle fechado, etc.

// Horários de execução (hora do servidor MT5)
input int    Hour1 = 10;
input int    Min1  = 8;
input int    Hour2 = 14;
input int    Min2  = 8;

input bool   SendOnStart = true;

// ──────────────────────────────────────────────
//  Variáveis globais
// ──────────────────────────────────────────────
datetime g_last_sent_slot1 = 0;
datetime g_last_sent_slot2 = 0;

//+------------------------------------------------------------------+
//| Retorna meia-noite do dia de uma datetime                         |
//+------------------------------------------------------------------+
datetime Midnight(datetime dt)
{
   MqlDateTime s;
   TimeToStruct(dt, s);
   s.hour = 0; s.min = 0; s.sec = 0;
   return StructToTime(s);
}

//+------------------------------------------------------------------+
//| Retorna datetime de hoje às HH:MM:00 (horário servidor)           |
//+------------------------------------------------------------------+
datetime TodayAt(int hour, int minute)
{
   MqlDateTime s;
   TimeToStruct(TimeCurrent(), s);
   s.hour = hour; s.min = minute; s.sec = 0;
   return StructToTime(s);
}

//+------------------------------------------------------------------+
//| Envia POST JSON para o webhook do n8n                             |
//+------------------------------------------------------------------+
void SendToN8N(const string json_body)
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
   int res = WebRequest("POST", N8N_Webhook_URL, "Content-Type: application/json\r\n", 10000, post_data, result, result_headers);

   if(res == -1)
   {
      int err = GetLastError();
      Print("[volumeMoveAverage] WebRequest falhou. Erro: ", err);
      Print("[volumeMoveAverage] IMPORTANTE: Habilite a URL em Tools -> Options -> Expert Advisors -> Allow WebRequest");
      Print("[volumeMoveAverage] Adicione: ", N8N_Webhook_URL);
      return;
   }

   if(res != 200)
      Print("[volumeMoveAverage] Webhook retornou HTTP ", res, " | resposta: ", CharArrayToString(result));
}

//+------------------------------------------------------------------+
//| Calcula VOLUME_REAL em um shift específico                        |
//+------------------------------------------------------------------+
double GetRealVolume(const string symbol, const ENUM_TIMEFRAMES tf, const int shift)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, shift, 1, rates);
   if(copied < 1)
      return 0.0;
   return (double)rates[0].real_volume;
}

//+------------------------------------------------------------------+
//| Calcula volume real (real_volume) e SMA dos últimos N candles     |
//+------------------------------------------------------------------+
bool ComputeVolumeSignal(const string symbol, string &out_json)
{
   out_json = "";

   int need = VolumeMA_Period + Volume_Shift + 5;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);

   int copied = CopyRates(symbol, InpTimeframe, 0, need, rates);
   if(copied <= VolumeMA_Period + Volume_Shift)
   {
      PrintFormat("[volumeMoveAverage] CopyRates falhou/insuficiente para %s (copied=%d) err=%d", symbol, copied, GetLastError());
      return false;
   }

   double vol = (double)rates[Volume_Shift].real_volume;

   double sum = 0.0;
   for(int i = Volume_Shift; i < Volume_Shift + VolumeMA_Period; i++)
      sum += (double)rates[i].real_volume;

   double vol_ma = sum / (double)VolumeMA_Period;

   string signal = (vol > vol_ma) ? "HIGH_VOLUME" : "LOW_VOLUME";
   double ratio = (vol_ma > 0.0) ? (vol / vol_ma) : 0.0;

   string dt_server = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS);

   out_json = StringFormat("{\"symbol\":\"%s\",\"timeframe\":\"%s\",\"timestamp_server\":\"%s\",\"volume_shift\":%d,\"volume_real\":%.0f,\"volume_ma_period\":%d,\"volume_ma\":%.2f,\"volume_ratio\":%.4f,\"signal\":\"%s\"}",
                          symbol,
                          EnumToString(InpTimeframe),
                          dt_server,
                          Volume_Shift,
                          vol,
                          VolumeMA_Period,
                          vol_ma,
                          ratio,
                          signal);

   return true;
}

//+------------------------------------------------------------------+
//| Processa todos os símbolos                                        |
//+------------------------------------------------------------------+
void SendForAllSymbols(const string trigger)
{
   string tickers[];
   int count = GetTickers(tickers);

   if(count <= 0)
   {
      Print("[volumeMoveAverage] Nenhum ticker obtido da API/cache");
      return;
   }

   PrintFormat("[volumeMoveAverage] Trigger=%s | Processando %d tickers...", trigger, count);

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

      // injeta trigger no JSON sem alterar estrutura demais
      // (mantendo padrão simples: adiciona campo trigger)
      if(StringLen(payload) > 2)
         payload = StringSubstr(payload, 0, StringLen(payload) - 1) + StringFormat(",\"trigger\":\"%s\"}", trigger);

      SendToN8N(payload);
      Sleep(150);
   }
}

//+------------------------------------------------------------------+
//| Verifica agenda (slot 1 / slot 2) e dispara se estiver no horário|
//+------------------------------------------------------------------+
void CheckSchedule()
{
   datetime now   = TimeCurrent();
   datetime today = Midnight(now);

   datetime slot1_time = TodayAt(Hour1, Min1);
   bool slot1_due = (now >= slot1_time) && (now < slot1_time + 60) && (Midnight(g_last_sent_slot1) < today);

   if(slot1_due)
   {
      g_last_sent_slot1 = now;
      SendForAllSymbols(StringFormat("%02d:%02d", Hour1, Min1));
   }

   datetime slot2_time = TodayAt(Hour2, Min2);
   bool slot2_due = (now >= slot2_time) && (now < slot2_time + 60) && (Midnight(g_last_sent_slot2) < today);

   if(slot2_due)
   {
      g_last_sent_slot2 = now;
      SendForAllSymbols(StringFormat("%02d:%02d", Hour2, Min2));
   }
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   PrintFormat("EA volumeMoveAverage iniciado | Disparos: %02d:%02d e %02d:%02d | TF=%s | Period=%d | Shift=%d",
               Hour1, Min1, Hour2, Min2, EnumToString(InpTimeframe), VolumeMA_Period, Volume_Shift);

   EventSetTimer(1);

   if(SendOnStart)
   {
      Sleep(2000);
      SendForAllSymbols("MANUAL_START");
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("EA volumeMoveAverage finalizado. Razão: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick — verifica se chegou a hora de disparar               |
//+------------------------------------------------------------------+
void OnTick()
{
   CheckSchedule();
}

//+------------------------------------------------------------------+
//| Timer — garante checagem mesmo sem ticks                          |
//+------------------------------------------------------------------+
void OnTimer()
{
   CheckSchedule();
}

//+------------------------------------------------------------------+
//|                                                   movingAverage.mq5 |
//|         EA que dispara às 10h e 14h e envia dados ao n8n          |
//+------------------------------------------------------------------+
#property copyright "EA Monitor MA"
#property version   "1.10"
#property strict

#include <TickersProvider.mqh>

// ──────────────────────────────────────────────
//  Parâmetros de entrada
// ──────────────────────────────────────────────
input string N8N_Webhook_URL = "http://127.0.0.1:5678/webhook/ma9-monitor"; // URL do webhook n8n
input int    MA_Period        = 9;            // Período da média móvel
input ENUM_MA_METHOD   MA_Method  = MODE_SMA;       // Tipo de MA
input ENUM_APPLIED_PRICE MA_Price = PRICE_CLOSE;    // Preço aplicado


// Horários de execução (hora do servidor MT5)
input int    Hour1 = 10;   // 1º disparo — hora
input int    Min1  = 28;    // 1º disparo — minuto
input int    Hour2 = 14;   // 2º disparo — hora
input int    Min2  = 28;    // 2º disparo — minuto

input bool   SendOnStart = true; // Enviar ao iniciar o EA

// ──────────────────────────────────────────────
//  Variáveis globais
// ──────────────────────────────────────────────
int      g_ma_handle    = INVALID_HANDLE;
string   g_ticker       = "";

// Controle de disparos: guarda a última data em que cada slot foi enviado
datetime g_last_sent_slot1 = 0;  // último envio do slot 10h
datetime g_last_sent_slot2 = 0;  // último envio do slot 14h

//+------------------------------------------------------------------+
//| Trim simples                                                      |
//+------------------------------------------------------------------+
string Trim(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

//+------------------------------------------------------------------+
//| Divide CSV em array                                               |
//+------------------------------------------------------------------+
int SplitCsv(const string csv, string &out[])
{
   string tmp[];
   int n = StringSplit(csv, ',', tmp);
   ArrayResize(out, 0);
   if(n <= 0)
      return 0;

   int added = 0;
   for(int i = 0; i < n; i++)
   {
      string v = Trim(tmp[i]);
      if(v == "")
         continue;
      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k] = v;
      added++;
   }
   return added;
}

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
//| Verifica agenda (slot 1 / slot 2) e dispara se estiver no horário|
//+------------------------------------------------------------------+
void CheckSchedule()
{
   datetime now   = TimeCurrent();
   datetime today = Midnight(now);

   // ── Slot 1 ─────────────────────────────────
   datetime slot1_time = TodayAt(Hour1, Min1);

   // Considera uma janela de 60 segundos após o horário alvo
   bool slot1_due = (now >= slot1_time) &&
                    (now < slot1_time + 60) &&
                    (Midnight(g_last_sent_slot1) < today);

   if(slot1_due)
   {
      g_last_sent_slot1 = now;
      SendForAllSymbols(StringFormat("%02d:%02d", Hour1, Min1));
   }

   // ── Slot 2 ─────────────────────────────────
   datetime slot2_time = TodayAt(Hour2, Min2);

   bool slot2_due = (now >= slot2_time) &&
                    (now < slot2_time + 60) &&
                    (Midnight(g_last_sent_slot2) < today);

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
   g_ticker = Symbol();

   g_ma_handle = iMA(g_ticker, PERIOD_D1, MA_Period, 0, MA_Method, MA_Price);
   if(g_ma_handle == INVALID_HANDLE)
   {
      Print("Erro ao criar handle da MA: ", GetLastError());
      return INIT_FAILED;
   }

   PrintFormat("EA movingAverage iniciado para %s | Disparos: %02d:%02d e %02d:%02d (horário servidor)",
               g_ticker, Hour1, Min1, Hour2, Min2);

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
   if(g_ma_handle != INVALID_HANDLE)
      IndicatorRelease(g_ma_handle);

   EventKillTimer();
   Print("EA movingAverage finalizado. Razão: ", reason);
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

//+------------------------------------------------------------------+
//| Coleta dados, monta JSON e envia                                  |
//+------------------------------------------------------------------+
void CheckAndSend(string trigger)
{
   double ma_buffer[];
   ArraySetAsSeries(ma_buffer, true);

   int copied = CopyBuffer(g_ma_handle, 0, 0, 3, ma_buffer);
   if(copied < 3)
   {
      int err = GetLastError();

      // Em especial no OnInit, o indicador pode ainda não estar calculado
      for(int attempt = 0; attempt < 10 && copied < 3; attempt++)
      {
         ResetLastError();
         Sleep(300);
         copied = CopyBuffer(g_ma_handle, 0, 0, 3, ma_buffer);
         if(copied >= 3)
            break;
         err = GetLastError();
      }

      if(copied < 3)
      {
         PrintFormat("Erro ao copiar buffer da MA (copied=%d): %d", copied, err);
         return;
      }
   }

   double ma_value      = ma_buffer[0];
   double ma_prev       = ma_buffer[1];
   double current_price = iClose(g_ticker, PERIOD_D1, 0);
   double prev_price    = iClose(g_ticker, PERIOD_D1, 1);
   double ask_price     = SymbolInfoDouble(g_ticker, SYMBOL_ASK);

   if(ma_value <= 0 || current_price <= 0)
   {
      Print("Dados inválidos — MA: ", ma_value, " | Preço: ", current_price);
      return;
   }

   string signal = "";
   if(current_price < ma_value && prev_price > ma_prev)
      signal = "SELL";
   else if(current_price > ma_value && prev_price < ma_prev)
      signal = "BUY";
   else
      signal = "NEUTRAL";
   double distance_pct = ((current_price - ma_value) / ma_value) * 100.0;

   string dt_server = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   string dt_local  = TimeToString(TimeLocal(),   TIME_DATE|TIME_MINUTES|TIME_SECONDS);

   string json = "{";
   json += "\"ticker\":\""      + g_ticker                         + "\",";
   json += "\"trigger\":\""     + trigger                          + "\",";
   json += "\"signal\":\""      + signal                           + "\",";
   json += "\"current_price\":" + DoubleToString(current_price, 5) + ",";
   json += "\"ask_price\":"     + DoubleToString(ask_price, 5)     + ",";
   json += "\"ma_value\":"      + DoubleToString(ma_value, 5)      + ",";
   json += "\"ma_prev\":"       + DoubleToString(ma_prev, 5)       + ",";
   json += "\"distance_pct\":"  + DoubleToString(distance_pct, 4)  + ",";
   json += "\"ma_period\":"     + IntegerToString(MA_Period)        + ",";
   json += "\"timeframe\":\"D1\",";
   json += "\"server_time\":\"" + dt_server                        + "\",";
   json += "\"local_time\":\""  + dt_local                         + "\"";
   json += "}";

   PrintFormat("[%s] Trigger: %s | Sinal: %s | Preço: %.5f | MA: %.5f | Dist: %.2f%%",
               g_ticker, trigger, signal, current_price, ma_value, distance_pct);

   SendToN8N(json);
}

//+------------------------------------------------------------------+
//| Coleta dados e envia para um símbolo específico                   |
//+------------------------------------------------------------------+
void CheckAndSendForSymbol(const string symbol, const string trigger)
{
   string sym = symbol;
   if(sym == "")
      return;

   if(!SymbolSelect(sym, true))
   {
      PrintFormat("Falha ao selecionar símbolo %s", sym);
      return;
   }

   int handle = INVALID_HANDLE;
   bool reuse = (sym == g_ticker && g_ma_handle != INVALID_HANDLE);
   if(reuse)
      handle = g_ma_handle;
   else
      handle = iMA(sym, PERIOD_D1, MA_Period, 0, MA_Method, MA_Price);

   if(handle == INVALID_HANDLE)
   {
      PrintFormat("Erro ao criar handle da MA para %s: %d", sym, GetLastError());
      return;
   }

   double ma_buffer[];
   ArraySetAsSeries(ma_buffer, true);

   int copied = CopyBuffer(handle, 0, 0, 3, ma_buffer);
   if(copied < 3)
   {
      int err = GetLastError();
      for(int attempt = 0; attempt < 10 && copied < 3; attempt++)
      {
         ResetLastError();
         Sleep(300);
         copied = CopyBuffer(handle, 0, 0, 3, ma_buffer);
         if(copied >= 3)
            break;
         err = GetLastError();
      }

      if(copied < 3)
      {
         PrintFormat("Erro ao copiar buffer da MA para %s (copied=%d): %d", sym, copied, err);
         if(!reuse)
            IndicatorRelease(handle);
         return;
      }
   }

   double ma_value      = ma_buffer[0];
   double ma_prev       = ma_buffer[1];
   double current_price = iClose(sym, PERIOD_D1, 0);
   double prev_price    = iClose(sym, PERIOD_D1, 1);
   double ask_price     = SymbolInfoDouble(sym, SYMBOL_ASK);

   if(ma_value <= 0 || current_price <= 0)
   {
      PrintFormat("Dados inválidos (%s) — MA: %.5f | Preço: %.5f", sym, ma_value, current_price);
      if(!reuse)
         IndicatorRelease(handle);
      return;
   }

   string signal = "";
   if(current_price < ma_value && prev_price > ma_prev)
      signal = "SELL";
   else if(current_price > ma_value && prev_price < ma_prev)
      signal = "BUY";
   else
   {
      signal = "NEUTRAL";
   }

   double distance_pct = ((current_price - ma_value) / ma_value) * 100.0;

   string dt_server = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   string dt_local  = TimeToString(TimeLocal(),   TIME_DATE|TIME_MINUTES|TIME_SECONDS);

   string json = "{";
   json += "\"ticker\":\""      + sym                             + "\",";
   json += "\"trigger\":\""     + trigger                         + "\",";
   json += "\"signal\":\""      + signal                          + "\",";
   json += "\"current_price\":" + DoubleToString(current_price, 5) + ",";
   json += "\"ask_price\":"     + DoubleToString(ask_price, 5)     + ",";
   json += "\"ma_value\":"      + DoubleToString(ma_value, 5)      + ",";
   json += "\"ma_prev\":"       + DoubleToString(ma_prev, 5)       + ",";
   json += "\"distance_pct\":"  + DoubleToString(distance_pct, 4)  + ",";
   json += "\"ma_period\":"     + IntegerToString(MA_Period)        + ",";
   json += "\"timeframe\":\"D1\",";
   json += "\"server_time\":\"" + dt_server                        + "\",";
   json += "\"local_time\":\""  + dt_local                         + "\"";
   json += "}";

   PrintFormat("[%s] Trigger: %s | Sinal: %s | Preço: %.5f | MA: %.5f | Dist: %.2f%%",
               sym, trigger, signal, current_price, ma_value, distance_pct);

   SendToN8N(json);

   if(!reuse)
      IndicatorRelease(handle);
}

//+------------------------------------------------------------------+
//| Envia para todos os ativos configurados                           |
//+------------------------------------------------------------------+
void SendForAllSymbols(const string trigger)
{
   string tickers[];
   int count = GetTickers(tickers);
   
   if(count <= 0)
   {
      Print("[movingAverage] Nenhum ticker obtido da API/cache");
      return;
   }
   
   PrintFormat("[movingAverage] Processando %d tickers...", count);
   
   for(int i = 0; i < count; i++)
      CheckAndSendForSymbol(tickers[i], trigger);
}

//+------------------------------------------------------------------+
//| Envia POST JSON para o webhook do n8n                             |
//+------------------------------------------------------------------+
void SendToN8N(string json_body)
{
   char   post_data[];
   char   result[];
   string result_headers;

   StringToCharArray(json_body, post_data, 0, StringLen(json_body));

   string headers = "Content-Type: application/json\r\n";

   int res = WebRequest("POST", N8N_Webhook_URL, headers, 10000,
                        post_data, result, result_headers);

   if(res == -1)
   {
      PrintFormat("Erro WebRequest %d | Libere a URL em: Ferramentas > Opções > Expert Advisors",
                  GetLastError());
      return;
   }

   string response = CharArrayToString(result);
   PrintFormat("HTTP %d | Resposta: %s", res, StringSubstr(response, 0, 120));
}

//+------------------------------------------------------------------+
//| F5 no gráfico força envio imediato                                |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam,
                  const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_KEYDOWN && lparam == 116)
   {
      Print("Envio manual solicitado via F5");
      SendForAllSymbols("MANUAL_F5");
   }
}
//+------------------------------------------------------------------+

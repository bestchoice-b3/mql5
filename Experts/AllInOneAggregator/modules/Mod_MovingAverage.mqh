//+------------------------------------------------------------------+
//|                                         Mod_MovingAverage.mqh    |
//|                                   Moving Average Module          |
//+------------------------------------------------------------------+
#property strict

#include "Common.mqh"
#include <TickersProvider.mqh>

input string InpN8N_Webhook_URL = "http://127.0.0.1:5678/webhook/ma9-monitor";
input int    InpMA_Period        = 9;
input ENUM_MA_METHOD   InpMA_Method  = MODE_SMA;
input ENUM_APPLIED_PRICE InpMA_Price = PRICE_CLOSE;

void SendToN8N_MA(string json_body)
{
   char   post_data[];
   char   result[];
   string result_headers;

   StringToCharArray(json_body, post_data, 0, StringLen(json_body));

   string headers = "Content-Type: application/json\r\n";

   int res = WebRequest("POST", InpN8N_Webhook_URL, headers, 10000,
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

void CheckAndSendForSymbol_MA(const string symbol, const string trigger)
{
   string sym = symbol;
   if(sym == "")
      return;

   if(!SymbolSelect(sym, true))
   {
      PrintFormat("Falha ao selecionar símbolo %s", sym);
      return;
   }

   int handle = iMA(sym, PERIOD_D1, InpMA_Period, 0, InpMA_Method, InpMA_Price);

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
      IndicatorRelease(handle);
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
   json += "\"ticker\":\""      + sym                             + "\",";
   json += "\"trigger\":\""     + trigger                         + "\",";
   json += "\"signal\":\""      + signal                          + "\",";
   json += "\"current_price\":" + DoubleToString(current_price, 5) + ",";
   json += "\"ask_price\":"     + DoubleToString(ask_price, 5)     + ",";
   json += "\"ma_value\":"      + DoubleToString(ma_value, 5)      + ",";
   json += "\"ma_prev\":"       + DoubleToString(ma_prev, 5)       + ",";
   json += "\"distance_pct\":"  + DoubleToString(distance_pct, 4)  + ",";
   json += "\"ma_period\":"     + IntegerToString(InpMA_Period)        + ",";
   json += "\"timeframe\":\"D1\",";
   json += "\"server_time\":\"" + dt_server                        + "\",";
   json += "\"local_time\":\""  + dt_local                         + "\"";
   json += "}";

   PrintFormat("[%s] Trigger: %s | Sinal: %s | Preço: %.5f | MA: %.5f | Dist: %.2f%%",
               sym, trigger, signal, current_price, ma_value, distance_pct);

   SendToN8N_MA(json);

   IndicatorRelease(handle);
}

void RunMovingAverage()
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
      CheckAndSendForSymbol_MA(tickers[i], "SCHEDULED");
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                    Mod_OptionsDataCollector.mqh  |
//|                                    Options Data Collector Module |
//+------------------------------------------------------------------+
#property strict

#include "Common.mqh"
#include <TickersProvider.mqh>

input string   InpOptionsWebhookURL = "http://127.0.0.1:5678/webhook/optionDataCollector";
input bool     InpOptionsCargaInicial = false;
input int      InpOptionsDiasCarga  = 60;

string OptionsLogFileName = "OptionsDataCollectorLog.txt";

void ExecutarCargaInicial_Options(int log_handle, const string &tickers[])
{
   datetime data_inicio = TimeCurrent() - (InpOptionsDiasCarga * 86400);
   datetime data_fim    = TimeCurrent();

   PrintFormat("[OptionsDataCollector] Período da carga: %s até %s", TimeToString(data_inicio), TimeToString(data_fim));
   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Período da carga: ", TimeToString(data_inicio), " até ", TimeToString(data_fim));

   int opcoes_encontradas = 0;
   int ticker_count = ArraySize(tickers);
   int enviados = 0;

   PrintFormat("[OptionsDataCollector] Processando %d tickers para carga inicial...", ticker_count);

   for(int t = 0; t < ticker_count; t++)
   {
      string ativo_base = tickers[t];
      string base_4_letras = StringSubstr(ativo_base, 0, 4);
      int total_simbolos = SymbolsTotal(false);
      int opcoes_ticker = 0;
      int opcoes_com_dados = 0;

      PrintFormat("[OptionsDataCollector] [%d/%d] Processando %s...", t+1, ticker_count, ativo_base);

      for(int i = 0; i < total_simbolos; i++)
      {
         string simbolo = SymbolName(i, false);

         if(StringFind(simbolo, base_4_letras) == 0 && IsOpcao_Options(simbolo, ativo_base))
         {
            opcoes_encontradas++;
            opcoes_ticker++;
            
            MqlRates rates[];
            int copiados = CopyRates(simbolo, PERIOD_D1, data_inicio, data_fim, rates);

            if(copiados > 0)
            {
               opcoes_com_dados++;
               string tipo = ObterTipoOpcao_Options(simbolo, ativo_base);
               
               if(tipo == "CALL" || tipo == "PUT")
               {
                  for(int d = 0; d < copiados; d++)
                  {
                     PrintFormat("[OptionsDataCollector] Enviando: %s | Data: %s | Close: %.4f", 
                                 simbolo, 
                                 TimeToString(rates[d].time, TIME_DATE), 
                                 rates[d].close);
                     
                     string json = MontarJSON_Options(simbolo, ativo_base, tipo, rates[d].close, rates[d].time, 0, 0, true);
                     EnviarParaN8N_Options(json, log_handle);
                     enviados++;
                     Sleep(50);
                  }
               }
               else
               {
                  if(log_handle != INVALID_HANDLE)
                     FileWrite(log_handle, "Opção ignorada (tipo desconhecido): ", simbolo, " - Tipo: ", tipo);
               }
            }
         }
      }
      
      if(opcoes_ticker > 0)
         PrintFormat("[OptionsDataCollector] %s: %d opções encontradas, %d com dados históricos", ativo_base, opcoes_ticker, opcoes_com_dados);
      else
         PrintFormat("[OptionsDataCollector] %s: nenhuma opção encontrada", ativo_base);
   }

   PrintFormat("[OptionsDataCollector] Carga inicial concluída. Opções: %d, Registros enviados: %d", opcoes_encontradas, enviados);
   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Carga inicial concluída. Opções processadas: ", IntegerToString(opcoes_encontradas));
}

void ColetarDadosOpcoes_Options(datetime timestamp, int log_handle, const string &tickers[])
{
   int enviados = 0;
   int ticker_count = ArraySize(tickers);

   PrintFormat("[OptionsDataCollector] Iniciando coleta para %d tickers", ticker_count);
   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Iniciando coleta para ", IntegerToString(ticker_count), " tickers");

   for(int t = 0; t < ticker_count; t++)
   {
      string ativo_base = tickers[t];
      string base_4_letras = StringSubstr(ativo_base, 0, 4);
      int total_simbolos = SymbolsTotal(false);
      int opcoes_encontradas_ticker = 0;

      PrintFormat("[OptionsDataCollector] [%d/%d] Processando %s...", t+1, ticker_count, ativo_base);
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "Processando ticker: ", ativo_base, " - Total símbolos disponíveis: ", IntegerToString(total_simbolos));

      for(int i = 0; i < total_simbolos; i++)
      {
         string simbolo = SymbolName(i, false);

         if(StringFind(simbolo, ativo_base) == 0 && IsOpcao_Options(simbolo, ativo_base))
         {
            opcoes_encontradas_ticker++;
            
            double preco_bid    = SymbolInfoDouble(simbolo, SYMBOL_BID);
            double preco_ask    = SymbolInfoDouble(simbolo, SYMBOL_ASK);
            double preco_ultimo = SymbolInfoDouble(simbolo, SYMBOL_LAST);
            double preco_medio  = (preco_bid + preco_ask) / 2.0;

            double preco_coleta = (preco_ultimo > 0) ? preco_ultimo : preco_medio;

            if(preco_coleta > 0)
            {
               string tipo = ObterTipoOpcao_Options(simbolo, ativo_base);
               if(tipo == "CALL" || tipo == "PUT")
               {
                  string json = MontarJSON_Options(simbolo, ativo_base, tipo, preco_coleta, timestamp, preco_bid, preco_ask, false);
                  EnviarParaN8N_Options(json, log_handle);
                  enviados++;
                  Sleep(50);
               }
               else
               {
                  if(log_handle != INVALID_HANDLE)
                     FileWrite(log_handle, "Opção ignorada (tipo desconhecido): ", simbolo, " - Tipo: ", tipo);
               }
            }
            else
            {
               if(log_handle != INVALID_HANDLE)
                  FileWrite(log_handle, "Opção sem preço: ", simbolo);
            }
         }
      }
      
      PrintFormat("[OptionsDataCollector] Ticker %s: %d opções encontradas", ativo_base, opcoes_encontradas_ticker);
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "Ticker ", ativo_base, ": ", IntegerToString(opcoes_encontradas_ticker), " opções encontradas");
   }

   PrintFormat("[OptionsDataCollector] Coleta concluída. Registros enviados: %d", enviados);
   if(enviados == 0)
      PrintFormat("[OptionsDataCollector] AVISO: Nenhuma opção foi enviada. Verifique se há opções disponíveis no broker.");
   
   if(log_handle != INVALID_HANDLE)
   {
      FileWrite(log_handle, "Coleta concluída. Registros enviados: ", IntegerToString(enviados));
      if(enviados == 0)
         FileWrite(log_handle, "AVISO: Nenhuma opção foi enviada. Verifique se há opções disponíveis no broker.");
   }
}

bool IsOpcao_Options(string simbolo, string ativo_base)
{
   int tamanho = StringLen(simbolo);
   if(tamanho < 6) return false;

   string base_4_letras = StringSubstr(ativo_base, 0, 4);
   
   if(StringFind(simbolo, base_4_letras) != 0)
      return false;
   
   if(tamanho > StringLen(base_4_letras) + 1)
      return true;

   return false;
}

string ObterTipoOpcao_Options(string simbolo, string ativo_base)
{
   string base_4_letras = StringSubstr(ativo_base, 0, 4);
   string sufixo = StringSubstr(simbolo, StringLen(base_4_letras), 1);
   
   if(sufixo == "C" || sufixo == "c") return "CALL";
   if(sufixo == "P" || sufixo == "p") return "PUT";
   
   uchar letra = StringGetCharacter(sufixo, 0);
   if(letra >= 65 && letra <= 76) return "CALL";
   if(letra >= 77 && letra <= 88) return "PUT";
   
   return "UNKNOWN";
}

string MontarJSON_Options(string simbolo, string ativo_base, string tipo, double preco, datetime timestamp,
                  double bid, double ask, bool carga_historica)
{
   string strike = ExtrairStrike_Options(simbolo, ativo_base);
   string vencimento = ExtrairVencimento_Options(simbolo);

   string json = StringFormat(
      "{\"simbolo\":\"%s\",\"ativo_base\":\"%s\",\"tipo\":\"%s\","
      "\"preco\":%.4f,\"bid\":%.4f,\"ask\":%.4f,"
      "\"strike\":\"%s\",\"vencimento\":\"%s\","
      "\"timestamp\":\"%s\",\"carga_historica\":%s}",
      simbolo,
      ativo_base,
      tipo,
      preco,
      bid,
      ask,
      strike,
      vencimento,
      TimeToString(timestamp, TIME_DATE | TIME_SECONDS),
      carga_historica ? "true" : "false"
   );

   return json;
}

string ExtrairStrike_Options(string simbolo, string ativo_base)
{
   string base_4_letras = StringSubstr(ativo_base, 0, 4);
   int offset = StringLen(base_4_letras) + 1;
   if(StringLen(simbolo) > offset)
      return StringSubstr(simbolo, offset);
   return "0";
}

string ExtrairVencimento_Options(string simbolo)
{
   datetime exp = (datetime)SymbolInfoInteger(simbolo, SYMBOL_EXPIRATION_TIME);
   if(exp > 0)
      return TimeToString(exp, TIME_DATE);
   
   return "";
}

void EnviarParaN8N_Options(string json_payload, int log_handle)
{
   char   post_data[];
   char   result[];
   string result_headers;

   int len = StringToCharArray(json_payload, post_data, 0, WHOLE_ARRAY, CP_UTF8);
   if(len > 0 && ArraySize(post_data) > 0)
   {
      int last = ArraySize(post_data) - 1;
      if(post_data[last] == 0)
         ArrayResize(post_data, last);
   }

   ResetLastError();
   int res = WebRequest(
      "POST",
      InpOptionsWebhookURL,
      "Content-Type: application/json\r\n",
      10000,
      post_data,
      result,
      result_headers
   );

   if(res == -1)
   {
      int erro = GetLastError();
      PrintFormat("[OptionsDataCollector] ERRO WebRequest: %d - URL: %s", erro, InpOptionsWebhookURL);
      if(erro == 4060)
         PrintFormat("[OptionsDataCollector] ERRO 4060: URL não permitida! Adicione '%s' nas configurações do MT5", InpOptionsWebhookURL);
      
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "Erro ao enviar para n8n. Código: ", IntegerToString(erro));
   }
   else if(res != 200)
   {
      PrintFormat("[OptionsDataCollector] HTTP %d - URL: %s", res, InpOptionsWebhookURL);
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "Webhook retornou HTTP ", IntegerToString(res));
   }
   else
   {
      PrintFormat("[OptionsDataCollector] ✓ Enviado com sucesso (HTTP 200)");
   }
}

void RunOptionsDataCollector()
{
   PrintFormat("[OptionsDataCollector] === INÍCIO DA ROTINA ===");
   
   int log_handle = INVALID_HANDLE;
   OpenLogFile(OptionsLogFileName, log_handle);

   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "=== Início da rotina Options Data Collector: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), " ===");

   string tickers[];
   int ticker_count = GetTickers(tickers);
   
   PrintFormat("[OptionsDataCollector] Tickers carregados: %d", ticker_count);

   if(ticker_count <= 0)
   {
      PrintFormat("[OptionsDataCollector] ERRO: Nenhum ticker disponível!");
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "ERRO: Nenhum ticker disponível. Verifique TickersProvider.");
      CloseLogFile(log_handle);
      return;
   }

   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Tickers carregados: ", IntegerToString(ticker_count));

   if(InpOptionsCargaInicial)
   {
      PrintFormat("[OptionsDataCollector] Modo: CARGA INICIAL (%d dias)", InpOptionsDiasCarga);
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, ">>> Iniciando CARGA INICIAL dos últimos ", IntegerToString(InpOptionsDiasCarga), " dias...");
      ExecutarCargaInicial_Options(log_handle, tickers);
   }
   else
   {
      PrintFormat("[OptionsDataCollector] Modo: COLETA EM TEMPO REAL");
      ColetarDadosOpcoes_Options(TimeCurrent(), log_handle, tickers);
   }

   PrintFormat("[OptionsDataCollector] === ROTINA FINALIZADA ===");
   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "=== Rotina Options Data Collector finalizada ===");
   CloseLogFile(log_handle);
}
//+------------------------------------------------------------------+

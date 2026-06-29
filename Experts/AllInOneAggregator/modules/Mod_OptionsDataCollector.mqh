//+------------------------------------------------------------------+
//|                                    Mod_OptionsDataCollector.mqh  |
//|                                    Options Data Collector Module |
//+------------------------------------------------------------------+
#property strict

#include "Common.mqh"
#include <TickersProvider.mqh>

input string   InpOptionsWebhookURL = "http://127.0.0.1:5678/webhook/optionDataCollector";
input bool     InpOptionsCargaInicial = false;
input int      InpOptionsDiasCarga  = 21;
input string   InpOptionsTickersIgnorados = "";

input bool     InpOptionsDebugLogs = false;

string OptionsLogFileName = "OptionsDataCollectorLog.txt";

string OptionsSentCacheFileName = "OptionsDataCollectorSentCache.txt";
string g_options_sent_keys[];
string g_options_sent_keys_pending[];
bool   g_options_cache_loaded = false;
int    g_options_cache_write_handle = INVALID_HANDLE;

int BinarySearchString_Options(const string &arr[], const string key)
{
   int left = 0;
   int right = ArraySize(arr) - 1;

   while(left <= right)
   {
      int mid = (left + right) / 2;
      int cmp = StringCompare(arr[mid], key);
      if(cmp == 0)
         return mid;
      if(cmp < 0)
         left = mid + 1;
      else
         right = mid - 1;
   }
   return -1;
}

void FlushPendingSentKeys_Options(int log_handle)
{
   int pending_n = ArraySize(g_options_sent_keys_pending);
   if(pending_n <= 0)
      return;

   ArraySort(g_options_sent_keys_pending);

   int main_n = ArraySize(g_options_sent_keys);
   string merged[];
   ArrayResize(merged, main_n + pending_n);

   int i = 0;
   int j = 0;
   int k = 0;
   string last = "";
   bool has_last = false;

   while(i < main_n || j < pending_n)
   {
      string v;
      if(j >= pending_n)
         v = g_options_sent_keys[i++];
      else if(i >= main_n)
         v = g_options_sent_keys_pending[j++];
      else
      {
         int cmp = StringCompare(g_options_sent_keys[i], g_options_sent_keys_pending[j]);
         if(cmp <= 0)
            v = g_options_sent_keys[i++];
         else
            v = g_options_sent_keys_pending[j++];
      }

      if(!has_last || v != last)
      {
         merged[k++] = v;
         last = v;
         has_last = true;
      }
   }

   ArrayResize(merged, k);
   ArrayResize(g_options_sent_keys, k);
   if(k > 0)
      ArrayCopy(g_options_sent_keys, merged, 0, 0, k);
   ArrayResize(g_options_sent_keys_pending, 0);

   if(InpOptionsDebugLogs && log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Cache flush. Itens totais: ", IntegerToString(ArraySize(g_options_sent_keys)));
}

void OpenSentCacheWriter_Options(int log_handle)
{
   if(g_options_cache_write_handle != INVALID_HANDLE)
      return;

   g_options_cache_write_handle = FileOpen(OptionsSentCacheFileName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(g_options_cache_write_handle != INVALID_HANDLE)
      FileSeek(g_options_cache_write_handle, 0, SEEK_END);
   else
   {
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "Falha ao abrir cache de enviados para escrita (writer): ", OptionsSentCacheFileName, " Erro: ", IntegerToString(GetLastError()));
   }
}

void CloseSentCacheWriter_Options()
{
   if(g_options_cache_write_handle == INVALID_HANDLE)
      return;

   FileFlush(g_options_cache_write_handle);
   FileClose(g_options_cache_write_handle);
   g_options_cache_write_handle = INVALID_HANDLE;
}

string NormalizeTicker_Options(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   StringToUpper(s);
   return s;
}

bool IsTickerIgnored_Options(const string ticker)
{
   string t = NormalizeTicker_Options(ticker);
   if(t == "")
      return false;

   string list = InpOptionsTickersIgnorados;
   StringReplace(list, ";", ",");

   string parts[];
   int n = StringSplit(list, ',', parts);
   for(int i = 0; i < n; i++)
   {
      string p = NormalizeTicker_Options(parts[i]);
      if(p != "" && p == t)
         return true;
   }

   return false;
}

string BuildSentKey_Options(const string simbolo, const datetime timestamp, const bool carga_historica)
{
   return simbolo + "|" + IntegerToString((int)timestamp) + "|" + (carga_historica ? "H" : "R");
}

void LoadSentCache_Options(int log_handle)
{
   if(g_options_cache_loaded)
      return;

   g_options_cache_loaded = true;
   ArrayResize(g_options_sent_keys, 0);
   ArrayResize(g_options_sent_keys_pending, 0);

   int h = FileOpen(OptionsSentCacheFileName, FILE_READ | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      int hc = FileOpen(OptionsSentCacheFileName, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
      if(hc != INVALID_HANDLE)
         FileClose(hc);
      return;
   }

   while(!FileIsEnding(h))
   {
      string key = FileReadString(h);
      if(key == "")
         continue;

      int n = ArraySize(g_options_sent_keys);
      ArrayResize(g_options_sent_keys, n + 1);
      g_options_sent_keys[n] = key;
   }

   FileClose(h);

   if(ArraySize(g_options_sent_keys) > 1)
      ArraySort(g_options_sent_keys);

   int total = ArraySize(g_options_sent_keys);
   if(total > 1)
   {
      string unique[];
      ArrayResize(unique, total);
      int k = 0;
      string last = "";
      for(int i = 0; i < total; i++)
      {
         string v = g_options_sent_keys[i];
         if(k == 0 || v != last)
         {
            unique[k++] = v;
            last = v;
         }
      }
      ArrayResize(unique, k);
      ArrayResize(g_options_sent_keys, k);
      if(k > 0)
         ArrayCopy(g_options_sent_keys, unique, 0, 0, k);
   }

   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Cache de enviados carregado. Itens: ", IntegerToString(ArraySize(g_options_sent_keys)));
}

bool HasSentKey_Options(const string key)
{
   if(BinarySearchString_Options(g_options_sent_keys, key) >= 0)
      return true;

   int pending_n = ArraySize(g_options_sent_keys_pending);
   for(int i = 0; i < pending_n; i++)
   {
      if(g_options_sent_keys_pending[i] == key)
         return true;
   }

   return false;
}

void AddSentKey_Options(const string key, int log_handle)
{
   if(HasSentKey_Options(key))
      return;

   int n = ArraySize(g_options_sent_keys_pending);
   ArrayResize(g_options_sent_keys_pending, n + 1);
   g_options_sent_keys_pending[n] = key;

   if(g_options_cache_write_handle == INVALID_HANDLE)
      OpenSentCacheWriter_Options(log_handle);

   if(g_options_cache_write_handle != INVALID_HANDLE)
      FileWrite(g_options_cache_write_handle, key);

   if(ArraySize(g_options_sent_keys_pending) >= 500)
      FlushPendingSentKeys_Options(log_handle);
}

void ExecutarCargaInicial_Options(int log_handle, const string &tickers[])
{
   LoadSentCache_Options(log_handle);

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
      if(IsTickerIgnored_Options(ativo_base))
      {
         if(log_handle != INVALID_HANDLE)
            FileWrite(log_handle, "Ticker ignorado (config): ", ativo_base);
         continue;
      }

      string base_4_letras = StringSubstr(ativo_base, 0, 4);
      int total_simbolos = SymbolsTotal(false);
      int opcoes_ticker = 0;
      int opcoes_com_dados = 0;
      int simbolos_com_base = 0;
      int scan_yield = 0;
      int rates_yield = 0;

      if(InpOptionsDebugLogs)
      {
         PrintFormat("[OptionsDataCollector] [%d/%d] Processando %s (base: %s)...", t+1, ticker_count, ativo_base, base_4_letras);
         if(log_handle != INVALID_HANDLE)
            FileWrite(log_handle, "Processando ticker: ", ativo_base, " - Base 4 letras: ", base_4_letras, " - Total símbolos no broker: ", IntegerToString(total_simbolos));
      }

      for(int i = 0; i < total_simbolos; i++)
      {
         string simbolo = SymbolName(i, false);

         scan_yield++;
         if((scan_yield % 2000) == 0)
            Sleep(1);

         if(StringFind(simbolo, base_4_letras) == 0)
         {
            simbolos_com_base++;
            
            if(IsOpcao_Options(simbolo, ativo_base))
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
                     rates_yield++;
                     if((rates_yield % 500) == 0)
                        Sleep(1);

                     string sent_key = BuildSentKey_Options(simbolo, rates[d].time, true);
                     if(HasSentKey_Options(sent_key))
                        continue;

                     if(InpOptionsDebugLogs)
                        PrintFormat("[OptionsDataCollector] Enviando: %s | Data: %s | Close: %.4f", simbolo, TimeToString(rates[d].time, TIME_DATE), rates[d].close);
                     
                     string json = MontarJSON_Options(simbolo, ativo_base, tipo, rates[d].close, rates[d].time, 0, 0, true);
                     if(EnviarParaN8N_Options(json, log_handle))
                     {
                        AddSentKey_Options(sent_key, log_handle);
                        enviados++;
                     }
                     Sleep(50);
                  }
               }
               else
               {
                  if(InpOptionsDebugLogs && log_handle != INVALID_HANDLE)
                     FileWrite(log_handle, "Opção ignorada (tipo desconhecido): ", simbolo, " - Tipo: ", tipo);
               }
            }
            else
            {
               if(InpOptionsDebugLogs && log_handle != INVALID_HANDLE)
                  FileWrite(log_handle, "Opção sem dados históricos: ", simbolo);
            }
            }
         }
      }
      
      if(opcoes_ticker > 0)
      {
         PrintFormat("[OptionsDataCollector] %s: símbolos com base=%d, opções válidas=%d, com dados=%d", ativo_base, simbolos_com_base, opcoes_ticker, opcoes_com_dados);
         if(log_handle != INVALID_HANDLE)
            FileWrite(log_handle, "Ticker ", ativo_base, ": símbolos_com_base=", IntegerToString(simbolos_com_base), ", opções_válidas=", IntegerToString(opcoes_ticker), ", com_dados=", IntegerToString(opcoes_com_dados));
      }
      else
      {
         PrintFormat("[OptionsDataCollector] %s: símbolos com base=%d, mas NENHUMA opção válida encontrada", ativo_base, simbolos_com_base);
         if(log_handle != INVALID_HANDLE)
            FileWrite(log_handle, "Ticker ", ativo_base, ": símbolos_com_base=", IntegerToString(simbolos_com_base), ", mas NENHUMA opção válida");
      }
   }

   PrintFormat("[OptionsDataCollector] Carga inicial concluída. Opções: %d, Registros enviados: %d", opcoes_encontradas, enviados);
   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Carga inicial concluída. Opções processadas: ", IntegerToString(opcoes_encontradas));
}

void ColetarDadosOpcoes_Options(datetime timestamp, int log_handle, const string &tickers[])
{
   LoadSentCache_Options(log_handle);

   int enviados = 0;
   int ticker_count = ArraySize(tickers);

   PrintFormat("[OptionsDataCollector] Iniciando coleta para %d tickers", ticker_count);
   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Iniciando coleta para ", IntegerToString(ticker_count), " tickers");

   for(int t = 0; t < ticker_count; t++)
   {
      string ativo_base = tickers[t];
      if(IsTickerIgnored_Options(ativo_base))
      {
         if(log_handle != INVALID_HANDLE)
            FileWrite(log_handle, "Ticker ignorado (config): ", ativo_base);
         continue;
      }

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
                  string sent_key = BuildSentKey_Options(simbolo, timestamp, false);
                  if(HasSentKey_Options(sent_key))
                     continue;

                  string json = MontarJSON_Options(simbolo, ativo_base, tipo, preco_coleta, timestamp, preco_bid, preco_ask, false);
                  if(EnviarParaN8N_Options(json, log_handle))
                  {
                     AddSentKey_Options(sent_key, log_handle);
                     enviados++;
                  }
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

bool EnviarParaN8N_Options(string json_payload, int log_handle)
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

      return false;
   }
   else if(res != 200)
   {
      PrintFormat("[OptionsDataCollector] HTTP %d - URL: %s", res, InpOptionsWebhookURL);
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, "Webhook retornou HTTP ", IntegerToString(res));

      return false;
   }
   else
   {
      PrintFormat("[OptionsDataCollector] ✓ Enviado com sucesso (HTTP 200)");
   }

   return true;
}

void RunOptionsDataCollector()
{
   PrintFormat("[OptionsDataCollector] === INÍCIO DA ROTINA v1 ===");
   
   int log_handle = INVALID_HANDLE;
   OpenLogFile(OptionsLogFileName, log_handle);

   if(log_handle == INVALID_HANDLE)
      PrintFormat("[OptionsDataCollector] ERRO: não foi possível abrir arquivo de log (%s). Erro: %d", OptionsLogFileName, GetLastError());
   
   PrintFormat("[OptionsDataCollector] DATA_PATH: %s", TerminalInfoString(TERMINAL_DATA_PATH));
   PrintFormat("[OptionsDataCollector] COMMONDATA_PATH: %s", TerminalInfoString(TERMINAL_COMMONDATA_PATH));

   LoadSentCache_Options(log_handle);

   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Tickers ignorados (config): ", InpOptionsTickersIgnorados);

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

   FlushPendingSentKeys_Options(log_handle);
   CloseSentCacheWriter_Options();
   CloseLogFile(log_handle);
}
//+------------------------------------------------------------------+

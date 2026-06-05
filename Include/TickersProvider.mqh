//+------------------------------------------------------------------+
//|                                              TickersProvider.mqh |
//|                        Provedor centralizado de lista de tickers |
//+------------------------------------------------------------------+
#property copyright "TickersProvider"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Configuração da API                                              |
//+------------------------------------------------------------------+
string TICKERS_API_URL = "http://127.0.0.1:5678/webhook/get-tickers";
string TICKERS_CACHE_FILE = "tickers_cache.txt";
int    TICKERS_CACHE_MAX_AGE_MINUTES = 60; // cache válido por 60min

//+------------------------------------------------------------------+
//| Trim string                                                       |
//+------------------------------------------------------------------+
string TickersProviderTrim(const string s)
{
   string t = s;
   StringTrimLeft(t);
   StringTrimRight(t);
   return t;
}

//+------------------------------------------------------------------+
//| Extrai array de tickers do JSON retornado pela API               |
//| Formato esperado: {"ok":true,"tickers":["ABEV3","VALE3",...]}    |
//+------------------------------------------------------------------+
bool ParseTickersFromJson(const string json, string &out[])
{
   ArrayResize(out, 0);
   
   int pos_tickers = StringFind(json, "\"tickers\":");
   if(pos_tickers < 0)
   {
      Print("[TickersProvider] JSON não contém campo 'tickers'");
      return false;
   }
   
   int pos_array_start = StringFind(json, "[", pos_tickers);
   if(pos_array_start < 0)
   {
      Print("[TickersProvider] Array de tickers não encontrado");
      return false;
   }
   
   int pos_array_end = StringFind(json, "]", pos_array_start);
   if(pos_array_end < 0)
   {
      Print("[TickersProvider] Fim do array de tickers não encontrado");
      return false;
   }
   
   string array_content = StringSubstr(json, pos_array_start + 1, pos_array_end - pos_array_start - 1);
   
   string items[];
   int n = StringSplit(array_content, ',', items);
   if(n <= 0)
      return false;
   
   int count = 0;
   for(int i = 0; i < n; i++)
   {
      string item = TickersProviderTrim(items[i]);
      
      StringReplace(item, "\"", "");
      StringReplace(item, "'", "");
      item = TickersProviderTrim(item);
      
      if(item == "")
         continue;
      
      ArrayResize(out, count + 1);
      out[count] = item;
      count++;
   }
   
   return (count > 0);
}

//+------------------------------------------------------------------+
//| Salva lista de tickers em cache (FILE_COMMON)                    |
//+------------------------------------------------------------------+
bool SaveTickersToCache(const string &tickers[])
{
   int count = ArraySize(tickers);
   if(count <= 0)
      return false;
   
   int h = FileOpen(TICKERS_CACHE_FILE, FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      Print("[TickersProvider] Falha ao abrir cache para escrita: ", GetLastError());
      return false;
   }
   
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS));
   
   for(int i = 0; i < count; i++)
      FileWrite(h, tickers[i]);
   
   FileClose(h);
   return true;
}

//+------------------------------------------------------------------+
//| Carrega lista de tickers do cache (FILE_COMMON)                  |
//+------------------------------------------------------------------+
bool LoadTickersFromCache(string &out[], int &cache_age_minutes)
{
   ArrayResize(out, 0);
   cache_age_minutes = 0;
   
   if(!FileIsExist(TICKERS_CACHE_FILE, FILE_COMMON))
      return false;
   
   int h = FileOpen(TICKERS_CACHE_FILE, FILE_READ|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      Print("[TickersProvider] Falha ao abrir cache para leitura: ", GetLastError());
      return false;
   }
   
   string timestamp_str = "";
   if(!FileIsEnding(h))
      timestamp_str = FileReadString(h);
   
   datetime cache_time = StringToTime(timestamp_str);
   if(cache_time > 0)
      cache_age_minutes = (int)((TimeCurrent() - cache_time) / 60);
   
   int count = 0;
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      line = TickersProviderTrim(line);
      if(line == "")
         continue;
      
      ArrayResize(out, count + 1);
      out[count] = line;
      count++;
   }
   
   FileClose(h);
   return (count > 0);
}

//+------------------------------------------------------------------+
//| Busca tickers da API via WebRequest                              |
//+------------------------------------------------------------------+
bool FetchTickersFromAPI(string &out[])
{
   ArrayResize(out, 0);
   
   char result[];
   char data[];
   string result_headers;
   
   ResetLastError();
   int res = WebRequest("GET", TICKERS_API_URL, "", 10000, data, result, result_headers);
   
   if(res == -1)
   {
      int err = GetLastError();
      Print("[TickersProvider] WebRequest falhou. Erro: ", err);
      Print("[TickersProvider] IMPORTANTE: Habilite a URL em Tools -> Options -> Expert Advisors -> Allow WebRequest");
      Print("[TickersProvider] Adicione: ", TICKERS_API_URL);
      return false;
   }
   
   if(res != 200)
   {
      Print("[TickersProvider] API retornou HTTP ", res);
      return false;
   }
   
   string json = CharArrayToString(result);
   
   if(!ParseTickersFromJson(json, out))
   {
      Print("[TickersProvider] Falha ao parsear JSON da API");
      return false;
   }
   
   Print("[TickersProvider] API retornou ", ArraySize(out), " tickers");
   return true;
}

//+------------------------------------------------------------------+
//| Função principal: retorna lista de tickers                       |
//| Tenta API primeiro, se falhar usa cache, se cache expirado avisa |
//+------------------------------------------------------------------+
int GetTickers(string &out[])
{
   ArrayResize(out, 0);
   
   bool api_ok = FetchTickersFromAPI(out);
   
   if(api_ok)
   {
      SaveTickersToCache(out);
      return ArraySize(out);
   }
   
   Print("[TickersProvider] API indisponível, tentando cache...");
   
   int cache_age = 0;
   bool cache_ok = LoadTickersFromCache(out, cache_age);
   
   if(!cache_ok)
   {
      Print("[TickersProvider] ERRO: API falhou e cache não disponível");
      return 0;
   }
   
   if(cache_age > TICKERS_CACHE_MAX_AGE_MINUTES)
   {
      Print("[TickersProvider] AVISO: Cache com ", cache_age, " minutos (máx: ", TICKERS_CACHE_MAX_AGE_MINUTES, ")");
   }
   else
   {
      Print("[TickersProvider] Cache carregado (", cache_age, " min) com ", ArraySize(out), " tickers");
   }
   
   return ArraySize(out);
}
//+------------------------------------------------------------------+

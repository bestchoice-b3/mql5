//+------------------------------------------------------------------+
//|                                         OptionsDataCollector.mq5 |
//|                                    Esqueleto - Coletor de Opções |
//|                          Envia dados 2x/dia via HTTP para o n8n  |
//+------------------------------------------------------------------+
#property copyright "Seu Nome"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Inputs
input string   N8N_WEBHOOK_URL     = "https://SEU-N8N.com/webhook/options-data"; // URL do Webhook n8n
input string   ACAO_BASE           = "PETR4";       // Ativo base (ex: PETR4, VALE3)
input int      HORA_COLETA_1       = 10;            // Hora da 1ª coleta (ex: 10 = 10:00)
input int      HORA_COLETA_2       = 16;            // Hora da 2ª coleta (ex: 16 = 16:00)
input bool     CARGA_INICIAL       = false;         // FLAG: ativar carga dos últimos 60 dias
input int      DIAS_CARGA_INICIAL  = 60;            // Quantidade de dias na carga inicial

//--- Sufixos de opções para escanear (ajuste conforme seu broker)
string prefixos_opcoes[] = {
   "PETR4C", "PETR4P",   // Calls e Puts da PETR4 (exemplo)
   "VALE3C", "VALE3P"    // Adicione outros conforme necessário
};

//--- Controle de horário
datetime ultima_coleta_1 = 0;
datetime ultima_coleta_2 = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== OptionsDataCollector Iniciado ===");
   Print("Ativo base: ", ACAO_BASE);
   Print("Coleta 1: ", HORA_COLETA_1, ":00 | Coleta 2: ", HORA_COLETA_2, ":00");
   Print("Carga Inicial ativa: ", CARGA_INICIAL ? "SIM" : "NÃO");

   if(CARGA_INICIAL)
   {
      Print(">>> Iniciando CARGA INICIAL dos últimos ", DIAS_CARGA_INICIAL, " dias...");
      ExecutarCargaInicial();
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Verifica se está no horário das coletas programadas
   MqlDateTime agora_struct;
   TimeToStruct(TimeCurrent(), agora_struct);

   datetime hoje_coleta_1 = StringToTime(
      StringFormat("%04d.%02d.%02d %02d:00", agora_struct.year, agora_struct.mon, agora_struct.day, HORA_COLETA_1)
   );
   datetime hoje_coleta_2 = StringToTime(
      StringFormat("%04d.%02d.%02d %02d:00", agora_struct.year, agora_struct.mon, agora_struct.day, HORA_COLETA_2)
   );

   // Janela de 5 minutos para não perder a coleta
   if(TimeCurrent() >= hoje_coleta_1 && TimeCurrent() < hoje_coleta_1 + 300 && ultima_coleta_1 < hoje_coleta_1)
   {
      Print(">>> Executando Coleta 1 (", HORA_COLETA_1, ":00)");
      ColetarDadosOpcoes(TimeCurrent());
      ultima_coleta_1 = TimeCurrent();
   }

   if(TimeCurrent() >= hoje_coleta_2 && TimeCurrent() < hoje_coleta_2 + 300 && ultima_coleta_2 < hoje_coleta_2)
   {
      Print(">>> Executando Coleta 2 (", HORA_COLETA_2, ":00)");
      ColetarDadosOpcoes(TimeCurrent());
      ultima_coleta_2 = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Carga Inicial: coleta histórico dos últimos N dias               |
//+------------------------------------------------------------------+
void ExecutarCargaInicial()
{
   // Na carga inicial, você pode enviar dados históricos de fechamento
   // O MT5 não guarda cotações de opções históricas nativamente,
   // então iteramos pelas opções disponíveis e enviamos o que tiver em cache
   
   datetime data_inicio = TimeCurrent() - (DIAS_CARGA_INICIAL * 86400);
   datetime data_fim    = TimeCurrent();

   Print("Período da carga: ", TimeToString(data_inicio), " até ", TimeToString(data_fim));

   // Escaneia todos os símbolos disponíveis procurando opções do ativo base
   int total_simbolos = SymbolsTotal(false); // false = todos, não apenas os do Market Watch
   int opcoes_encontradas = 0;

   for(int i = 0; i < total_simbolos; i++)
   {
      string simbolo = SymbolName(i, false);

      // Filtra apenas opções do ativo base
      if(StringFind(simbolo, ACAO_BASE) == 0 && IsOpcao(simbolo))
      {
         opcoes_encontradas++;
         
         // Coleta dados históricos diários
         MqlRates rates[];
         int copiados = CopyRates(simbolo, PERIOD_D1, data_inicio, data_fim, rates);

         if(copiados > 0)
         {
            for(int d = 0; d < copiados; d++)
            {
               string tipo = ObterTipoOpcao(simbolo);
               string json = MontarJSON(simbolo, tipo, rates[d].close, rates[d].time, 0, 0, true);
               EnviarParaN8N(json);
               Sleep(100); // Evita sobrecarga no webhook
            }
         }
      }
   }

   Print("Carga inicial concluída. Opções processadas: ", opcoes_encontradas);
}

//+------------------------------------------------------------------+
//| Coleta dados em tempo real das opções                            |
//+------------------------------------------------------------------+
void ColetarDadosOpcoes(datetime timestamp)
{
   int total_simbolos = SymbolsTotal(true); // true = apenas Market Watch
   int enviados = 0;

   for(int i = 0; i < total_simbolos; i++)
   {
      string simbolo = SymbolName(i, true);

      if(StringFind(simbolo, ACAO_BASE) == 0 && IsOpcao(simbolo))
      {
         double preco_bid    = SymbolInfoDouble(simbolo, SYMBOL_BID);
         double preco_ask    = SymbolInfoDouble(simbolo, SYMBOL_ASK);
         double preco_ultimo = SymbolInfoDouble(simbolo, SYMBOL_LAST);
         double preco_medio  = (preco_bid + preco_ask) / 2.0;
         long   volume       = SymbolInfoInteger(simbolo, SYMBOL_VOLUME);

         // Usa o preço do último negócio ou a média bid/ask
         double preco_coleta = (preco_ultimo > 0) ? preco_ultimo : preco_medio;

         if(preco_coleta > 0)
         {
            string tipo = ObterTipoOpcao(simbolo);
            string json = MontarJSON(simbolo, tipo, preco_coleta, timestamp, preco_bid, preco_ask, false);
            EnviarParaN8N(json);
            enviados++;
            Sleep(50);
         }
      }
   }

   Print("Coleta concluída. Registros enviados: ", enviados);
}

//+------------------------------------------------------------------+
//| Verifica se um símbolo é uma opção                               |
//+------------------------------------------------------------------+
bool IsOpcao(string simbolo)
{
   // No Brasil, opções geralmente têm o padrão: PETR4C350 ou PETR4P320
   // Ajuste a lógica conforme o padrão do seu broker
   ENUM_SYMBOL_CALC_MODE calc_mode = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(simbolo, SYMBOL_TRADE_CALC_MODE);
   
   // Alternativamente, verifica pelo tamanho do nome ou padrão de sufixo
   int tamanho = StringLen(simbolo);
   if(tamanho < 6) return false;

   // Heurística: ativo base tem 5 chars (ex: PETR4), opção tem mais
   if(tamanho > StringLen(ACAO_BASE) + 1) return true;

   return false;
}

//+------------------------------------------------------------------+
//| Identifica se é CALL ou PUT pelo nome do símbolo                 |
//+------------------------------------------------------------------+
string ObterTipoOpcao(string simbolo)
{
   // Padrão B3: letra após o ticker indica o tipo
   // C = Call, P = Put
   string sufixo = StringSubstr(simbolo, StringLen(ACAO_BASE), 1);
   
   if(sufixo == "C" || sufixo == "c") return "CALL";
   if(sufixo == "P" || sufixo == "p") return "PUT";
   
   // Fallback: analisa posição da letra no alfabeto (padrão antigo B3)
   // A-L = Call (Jan-Dez), M-X = Put (Jan-Dez)
   uchar letra = StringGetCharacter(sufixo, 0);
   if(letra >= 65 && letra <= 76) return "CALL"; // A-L
   if(letra >= 77 && letra <= 88) return "PUT";  // M-X
   
   return "UNKNOWN";
}

//+------------------------------------------------------------------+
//| Monta o payload JSON para envio                                  |
//+------------------------------------------------------------------+
string MontarJSON(string simbolo, string tipo, double preco, datetime timestamp,
                  double bid, double ask, bool carga_historica)
{
   string strike = ExtrairStrike(simbolo);
   string vencimento = ExtrairVencimento(simbolo);

   string json = StringFormat(
      "{\"simbolo\":\"%s\",\"ativo_base\":\"%s\",\"tipo\":\"%s\","
      "\"preco\":%.4f,\"bid\":%.4f,\"ask\":%.4f,"
      "\"strike\":\"%s\",\"vencimento\":\"%s\","
      "\"timestamp\":\"%s\",\"carga_historica\":%s}",
      simbolo,
      ACAO_BASE,
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

//+------------------------------------------------------------------+
//| Extrai o strike do nome do símbolo                               |
//+------------------------------------------------------------------+
string ExtrairStrike(string simbolo)
{
   // Ex: PETR4C350 -> "350"
   // Ajuste o offset conforme o padrão do seu broker
   int offset = StringLen(ACAO_BASE) + 1;
   if(StringLen(simbolo) > offset)
      return StringSubstr(simbolo, offset);
   return "0";
}

//+------------------------------------------------------------------+
//| Extrai/estima o vencimento do símbolo                            |
//+------------------------------------------------------------------+
string ExtrairVencimento(string simbolo)
{
   // O MT5 pode ter a data de vencimento via SymbolInfoInteger
   // SYMBOL_EXPIRATION_TIME está disponível para alguns brokers
   datetime exp = (datetime)SymbolInfoInteger(simbolo, SYMBOL_EXPIRATION_TIME);
   if(exp > 0)
      return TimeToString(exp, TIME_DATE);
   
   // Fallback: retorna vazio para ser resolvido no n8n/banco
   return "";
}

//+------------------------------------------------------------------+
//| Envia JSON para o webhook do n8n via HTTP POST                   |
//+------------------------------------------------------------------+
void EnviarParaN8N(string json_payload)
{
   char   post_data[];
   char   result[];
   string result_headers;

   StringToCharArray(json_payload, post_data, 0, StringLen(json_payload));

   string headers = "Content-Type: application/json\r\n";

   int res = WebRequest(
      "POST",
      N8N_WEBHOOK_URL,
      headers,
      5000,        // timeout ms
      post_data,
      result,
      result_headers
   );

   if(res == -1)
   {
      int erro = GetLastError();
      Print("Erro ao enviar para n8n. Código: ", erro, 
            " | Verifique se a URL está nas URLs permitidas no MT5.");
      // IMPORTANTE: Adicione a URL do n8n em:
      // Ferramentas > Opções > Expert Advisors > URLs permitidas
   }
   else
   {
      string resposta = CharArrayToString(result);
      Print("n8n respondeu [", res, "]: ", StringSubstr(resposta, 0, 100));
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== OptionsDataCollector Encerrado. Razão: ", reason, " ===");
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                  OBV_TrendLines_EA.mq5           |
//|                                     Copyright 2024, Seu Nome     |
//|                                     https://www.mql5.com         |
//+------------------------------------------------------------------+
#property version "1.03"
#property strict

//--- Parâmetros de entrada do EA
input double InpLotSize = 100;       // Volume de negociação (número de contratos)
input int InpMagicNumber = 12345;    // Número Mágico para identificar trades
input int InpPeriodLookback = 21;    // Período para buscar pontos
input int InpMinTouchPoints = 2;     // Mínimo de pontos para formar linha

//--- Variáveis globais do EA
int obv_handle;
double obv_buffer[];
double lta_buffer[];
double ltb_buffer[];
static datetime last_time = 0; // Controle de nova barra
static double prev_obv = 0;    // OBV anterior para detectar rompimento
static double prev_ltb = 0;    // OBVLTB anterior para detectar rompimento
static double prev_lta = 0;    // OBVLTA anterior para detectar rompimento
static bool trade_allowed = true; // Controle para evitar múltiplas ordens

//+------------------------------------------------------------------+
//| Funções de Cálculo de Tendência (Declaração)                     |
//+------------------------------------------------------------------+
void CalculateTrendLines(const int rates_total);
void CalculateUpTrendLine(const int current_bar, const int rates_total);
void CalculateDownTrendLine(const int current_bar, const int rates_total);
void FindLocalMinimums(const int current_bar, double &min_points[], int &min_indices[]);
void FindLocalMaximums(const int current_bar, double &max_points[], int &max_indices[]);

//+------------------------------------------------------------------+
//| Funções de Negociação (Declaração)                              |
//+------------------------------------------------------------------+
void TradeBuy();
void ClosePosition();
long GetCurrentPositionTicket();

//+------------------------------------------------------------------+
//| Funções para Desenhar Linhas de Tendência                        |
//+------------------------------------------------------------------+
void DrawTrendLines(const int rates_total);

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Criar handle do OBV
    obv_handle = iOBV(_Symbol, _Period, VOLUME_TICK);
    if(obv_handle == INVALID_HANDLE)
    {
        Print("Erro ao criar handle do OBV");
        return(INIT_FAILED);
    }
    
    // Redimensionar buffers
    ArrayResize(obv_buffer, InpPeriodLookback + 10); 
    ArrayResize(lta_buffer, InpPeriodLookback + 10);
    ArrayResize(ltb_buffer, InpPeriodLookback + 10);

    // Criar janela separada para OBV
    IndicatorSetString(INDICATOR_SHORTNAME, "OBV com Linhas de Tendência");
    ChartIndicatorAdd(0, 0, obv_handle);

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(obv_handle != INVALID_HANDLE)
        IndicatorRelease(obv_handle);
    // Remover objetos gráficos
    ObjectsDeleteAll(0, "LTA_");
    ObjectsDeleteAll(0, "LTB_");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- 1. Verificar se é uma nova barra
    datetime current_time = iTime(_Symbol, _Period, 0);
    if(last_time == current_time)
        return;
    last_time = current_time;

    //--- 2. Copiar dados dos buffers
    int bars_to_copy = InpPeriodLookback + 10;
    int bars_copied = CopyBuffer(obv_handle, 0, 0, bars_to_copy, obv_buffer);
    if(bars_copied < bars_to_copy)
    {
        Print("Dados insuficientes do OBV. Copiados: ", bars_copied, ", Necessários: ", bars_to_copy);
        return;
    }
    
    // Configurar arrays como séries temporais (índice 0 = mais recente)
    ArraySetAsSeries(obv_buffer, true);
    ArraySetAsSeries(lta_buffer, true);
    ArraySetAsSeries(ltb_buffer, true);

    //--- 3. Calcular as linhas de tendência
    CalculateTrendLines(bars_to_copy);
    
    //--- 4. Desenhar as linhas de tendência no gráfico
    DrawTrendLines(bars_to_copy);

    //--- 5. Obter o status da posição atual
    long position_ticket = GetCurrentPositionTicket();

    //--- 6. Log para depuração
    double current_obv = obv_buffer[0];
    double current_lta = (lta_buffer[0] != EMPTY_VALUE) ? lta_buffer[0] : 0;
    double current_ltb = (ltb_buffer[0] != EMPTY_VALUE) ? ltb_buffer[0] : 0;
    
    Print("OBV=", current_obv, " LTA=", current_lta, " LTB=", current_ltb);
    Print("Prev_OBV=", prev_obv, " Prev_LTA=", prev_lta, " Prev_LTB=", prev_ltb);

    //--- 7. Verificar rompimento do OBV na OBVLTB (de cima para baixo) - apenas se temos valores válidos
    if(current_ltb != 0 && prev_ltb != 0 && prev_obv > prev_ltb && current_obv < current_ltb)
    {
        Print("OBV rompeu OBVLTB de cima para baixo - Fechando posicao!");
        ClosePosition();
    }
    
    //--- 8. Lógica de Negociação - Rompimento OBV na LTAOBV (de baixo para cima)
    if(trade_allowed && current_lta != 0 && prev_lta != 0 && prev_obv < prev_lta && current_obv > current_lta)
    {
        Print("OBV rompeu LTAOBV de baixo para cima - Abrindo COMPRA!");
        TradeBuy();
        trade_allowed = false; // Bloquear novas ordens até a posição ser fechada
    }
   
    //--- 9. Atualizar valores anteriores para próxima verificação
    prev_obv = current_obv;
    prev_ltb = current_ltb;
    prev_lta = current_lta;
}

//+------------------------------------------------------------------+
//| Funções de Negociação                                            |
//+------------------------------------------------------------------+
void TradeBuy()
{
    MqlTradeRequest request;
    MqlTradeResult result;
    
    ZeroMemory(request);
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = MathMax((int)InpLotSize, (int)SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
    request.type = ORDER_TYPE_BUY;
    request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.sl = 0; // Sem Stop Loss
    request.tp = 0; // Sem Take Profit
    request.magic = InpMagicNumber;

    if(OrderSend(request, result))
    {
        if(result.retcode == TRADE_RETCODE_DONE)
            Print("Ordem de COMPRA executada com sucesso! Ticket: ", result.order);
        else
            Print("Falha na ordem de COMPRA. Código de retorno: ", result.retcode);
    }
    else
        Print("Erro ao enviar ordem de COMPRA. Erro do sistema: ", GetLastError());
}

void ClosePosition()
{
    // Buscar apenas a posição atual do símbolo e magic number
    long current_ticket = GetCurrentPositionTicket();
    if(current_ticket > 0)
    {
      trade_allowed = true; 
        if(PositionSelect(current_ticket))
        {
            MqlTradeRequest request;
            MqlTradeResult result;
            
            ZeroMemory(request);
            request.action = TRADE_ACTION_DEAL;
            request.symbol = _Symbol;
            request.volume = PositionGetDouble(POSITION_VOLUME);
            request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = (request.type == ORDER_TYPE_SELL) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            request.position = current_ticket;
            request.magic = InpMagicNumber;
            
            if(OrderSend(request, result))
            {
                if(result.retcode == TRADE_RETCODE_DONE)
                {
                    Print("Posição ", current_ticket, " fechada com sucesso!");
                    trade_allowed = true; // Permitir nova negociação após fechar posição
                }
                else
                    Print("Falha ao fechar posição ", current_ticket, ". Código de retorno: ", result.retcode);
            }
            else
                Print("Erro ao enviar ordem de fechamento para posição ", current_ticket, ". Erro do sistema: ", GetLastError());
        }
    }
    else
    {
        Print("Nenhuma posição encontrada para fechar");
    }
}

long GetCurrentPositionTicket()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelect(ticket))
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            {
                return ticket;
            }
        }
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Funções de Cálculo de Tendência                                  |
//+------------------------------------------------------------------+
void CalculateTrendLines(const int rates_total)
{
    ArrayInitialize(lta_buffer, EMPTY_VALUE);
    ArrayInitialize(ltb_buffer, EMPTY_VALUE);
    
    if (rates_total < InpPeriodLookback + 2) return;

    // Calcular apenas para as barras mais recentes (índices menores em array como série)
    CalculateUpTrendLine(0, rates_total);
    CalculateDownTrendLine(0, rates_total);
}

void CalculateUpTrendLine(const int current_bar, const int rates_total)
{
    double min_points[];
    int min_indices[];
    
    FindLocalMinimums(current_bar, min_points, min_indices);
    
    if(ArraySize(min_indices) >= InpMinTouchPoints)
    {
        int count = ArraySize(min_indices);
        int idx1 = min_indices[0];  // Mais antigo
        int idx2 = min_indices[count-1];  // Mais recente
        
        double y1 = min_points[0];
        double y2 = min_points[count-1];
        
        if (idx2 == idx1) return;

        // Calcular linha de tendência e projetar para barra atual
        double slope = (y2 - y1) / (double)(idx2 - idx1);
        
        // Calcular valor da linha de tendência para a barra atual (índice 0)
        lta_buffer[0] = y2 + slope * (0 - idx2);
    }
    else
    {
        lta_buffer[0] = EMPTY_VALUE;
    }
}

void CalculateDownTrendLine(const int current_bar, const int rates_total)
{
    double max_points[];
    int max_indices[];
    
    FindLocalMaximums(current_bar, max_points, max_indices);
    
    if(ArraySize(max_indices) >= InpMinTouchPoints)
    {
        int count = ArraySize(max_indices);
        int idx1 = max_indices[0];  // Mais antigo
        int idx2 = max_indices[count-1];  // Mais recente
        
        double y1 = max_points[0];
        double y2 = max_points[count-1];
        
        if (idx2 == idx1) return;

        // Calcular linha de tendência e projetar para barra atual
        double slope = (y2 - y1) / (double)(idx2 - idx1);
        
        // Calcular valor da linha de tendência para a barra atual (índice 0)
        ltb_buffer[0] = y2 + slope * (0 - idx2);
    }
    else
    {
        ltb_buffer[0] = EMPTY_VALUE;
    }
}

void FindLocalMinimums(const int current_bar, double &min_points[], int &min_indices[])
{
    ArrayResize(min_points, 0);
    ArrayResize(min_indices, 0);
    
    int lookback = MathMin(InpPeriodLookback, ArraySize(obv_buffer) - 5);
    
    // Procurar mínimos locais nas barras mais antigas (índices maiores)
    for(int i = 2; i < lookback; i++) 
    {
        if(i >= ArraySize(obv_buffer) - 2) continue;

        if(obv_buffer[i] < obv_buffer[i-1] && obv_buffer[i] < obv_buffer[i+1] &&
           obv_buffer[i] < obv_buffer[i-2] && obv_buffer[i] < obv_buffer[i+2])
        {
            int size = ArraySize(min_points);
            ArrayResize(min_points, size + 1);
            ArrayResize(min_indices, size + 1);
            
            min_points[size] = obv_buffer[i];
            min_indices[size] = i;
        }
    }
}

void FindLocalMaximums(const int current_bar, double &max_points[], int &max_indices[])
{
    ArrayResize(max_points, 0);
    ArrayResize(max_indices, 0);
    
    int lookback = MathMin(InpPeriodLookback, ArraySize(obv_buffer) - 5);
    
    // Procurar máximos locais nas barras mais antigas (índices maiores)
    for(int i = 2; i < lookback; i++)
    {
        if(i >= ArraySize(obv_buffer) - 2) continue;

        if(obv_buffer[i] > obv_buffer[i-1] && obv_buffer[i] > obv_buffer[i+1] &&
           obv_buffer[i] > obv_buffer[i-2] && obv_buffer[i] > obv_buffer[i+2])
        {
            int size = ArraySize(max_points);
            ArrayResize(max_points, size + 1);
            ArrayResize(max_indices, size + 1);
            
            max_points[size] = obv_buffer[i];
            max_indices[size] = i;
        }
    }
}

//+------------------------------------------------------------------+
//| Função para Desenhar Linhas de Tendência no Gráfico              |
//+------------------------------------------------------------------+
void DrawTrendLines(const int rates_total)
{
    // Remover linhas antigas
    ObjectsDeleteAll(0, "LTA_");
    ObjectsDeleteAll(0, "LTB_");

    // Encontrar os pontos válidos mais recentes para LTA e LTB
    double lta_start = EMPTY_VALUE, lta_end = EMPTY_VALUE;
    double ltb_start = EMPTY_VALUE, ltb_end = EMPTY_VALUE;
    datetime time_start = 0, time_end = 0;
    int start_idx = -1, end_idx = -1;

    // Procurar pontos válidos para LTA
    for(int i = rates_total - 1; i >= 0; i--)
    {
        if(lta_buffer[i] != EMPTY_VALUE)
        {
            if(lta_end == EMPTY_VALUE)
            {
                lta_end = lta_buffer[i];
                end_idx = i;
                time_end = iTime(_Symbol, _Period, i);
            }
            else if(lta_start == EMPTY_VALUE)
            {
                lta_start = lta_buffer[i];
                start_idx = i;
                time_start = iTime(_Symbol, _Period, i);
                break;
            }
        }
    }

    // Desenhar LTA
    if(lta_start != EMPTY_VALUE && lta_end != EMPTY_VALUE)
    {
        string name = "LTA_" + TimeToString(time_end);
        ObjectCreate(0, name, OBJ_TREND, 1, time_start, lta_start, time_end, lta_end);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrLime);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, name, OBJPROP_RAY, false);
    }

    // Procurar pontos válidos para LTB
    start_idx = -1;
    end_idx = -1;
    for(int i = rates_total - 1; i >= 0; i--)
    {
        if(ltb_buffer[i] != EMPTY_VALUE)
        {
            if(ltb_end == EMPTY_VALUE)
            {
                ltb_end = ltb_buffer[i];
                end_idx = i;
                time_end = iTime(_Symbol, _Period, i);
            }
            else if(ltb_start == EMPTY_VALUE)
            {
                ltb_start = ltb_buffer[i];
                start_idx = i;
                time_start = iTime(_Symbol, _Period, i);
                break;
            }
        }
    }

    // Desenhar LTB
    if(ltb_start != EMPTY_VALUE && ltb_end != EMPTY_VALUE)
    {
        string name = "LTB_" + TimeToString(time_end);
        ObjectCreate(0, name, OBJ_TREND, 1, time_start, ltb_start, time_end, ltb_end);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
        ObjectSetInteger(0, name, OBJPROP_RAY, false);
    }
}
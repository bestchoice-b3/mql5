//+------------------------------------------------------------------+
//|                                          DailyScreenShot.mq5    |
//|                               Copyright 2025, Seu Nome / Grok help |
//|                                             https://www.mql5.com |
// as imagens ficam na pasta C:\Users\anael\AppData\Roaming\MetaQuotes\Terminal\38FF261A42172F3478E54D3A1A8FE02B\MQL5\Files
// os logs ficam na pasta C:\Users\anael\AppData\Roaming\MetaQuotes\Terminal\Common\Files
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Seu Nome / Grok help"
#property link      "https://www.mql5.com"
#property version   "1.01"
#property strict
#property description "Tira screenshot diário dos gráficos com template aplicada + teste imediato"

//------------------------------------------------------------------------
input string   Ativos                  = "ABEV3,ALPA3,ASAI3,AZUL4,BBAS3,BBDC3,BBSE3,BEEF3,B3SA3,BRAP3,BRFS3,BRKM3,CASH3,CMIG3,COGN3,CPFE3,CRFB3,CSNA3,CVCB3,CYRE3,ELET3,EMBR3,EQTL3,EZTC3,FLRY3,GGBR3,GOAU3,GOLL4,HAPV3";      
input string   Ativos2                 = "HYPE3,ITUB3,JBSS3,KLBN3,LREN3,LWSA3,MGLU3,MRVE3,PCAR3,PETR3,PETZ3,POSI3,PRIO3,QUAL3,RADL3,RAIL3,RDOR3,RECV3,RENT3,SANB3,SBSP3,SUZB3,TAEE3,TIMS3,TOTS3,USIM5";
input string   Ativos3                 = "VALE3,VIVT3,WEGE3,YDUQ3";
input int      Hora_Execucao           = 18;                       // 0–23 (horário do servidor da corretora)
input int      Minuto_Execucao         = 5;                        // 0–59
input int      Offset_Minutos          = 30;                       // offset para escalonar execucoes (ex: +30min)
input ENUM_TIMEFRAMES Timeframe        = PERIOD_D1;                // Período dos gráficos
input string   Nome_Template           = "default.tpl";            // ← Nome exato da sua template (com .tpl)
input int      Largura_Imagem          = 1280;
input int      Altura_Imagem           = 720;
input int      Delay_Apos_Abrir_ms     = 3000;                     // milissegundos
input int      Delay_Apos_Template_ms  = 3500;                     // tempo extra após template (ajuste se necessário)
input bool     TestarAgora             = true;                    // true = executa IMEDIATAMENTE ao anexar/reiniciar (para teste)
input int      Timer_Intervalo_Seg     = 60;                       // verifica a cada N segundos
string LogFileName = "ScreenshotLog.txt";
int log_handle = INVALID_HANDLE;
//------------------------------------------------------------------------

datetime ultimo_dia_executado = 0;

datetime DayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
}

datetime ScheduledTimeForDay(const datetime day_start)
{
   return day_start + (Hora_Execucao * 3600) + (Minuto_Execucao * 60) + (Offset_Minutos * 60);
}

void MaybeRunToday()
{
   datetime now = TimeCurrent();
   datetime today = DayStart(now);
   if(today == ultimo_dia_executado)
      return;

   datetime scheduled = ScheduledTimeForDay(today);
   if(now < scheduled)
      return;

   ultimo_dia_executado = today;

   Print("══════════════════════════════════════════════");
   Print("Rotina diária iniciada (horário agendado) – ", TimeToString(TimeCurrent()));
   Print("══════════════════════════════════════════════");

   ExecutarRotinaDeScreenshots();

   Print("Próxima execução prevista para amanhã ≈ ", Hora_Execucao, ":", StringFormat("%02d", Minuto_Execucao), " (offset ", Offset_Minutos, "min)");
   Print("══════════════════════════════════════════════");
}

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(MathMax(1, Timer_Intervalo_Seg)); // verifica a cada N segundos
   Print("EA DailyScreenShot iniciado");
   Print("Agendamento: ", Hora_Execucao, ":", StringFormat("%02d", Minuto_Execucao), " (offset ", Offset_Minutos, "min)");
   Print("Template: ", Nome_Template);
   Print("TestarAgora = ", TestarAgora ? "SIM (executará agora)" : "não");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
}

//+------------------------------------------------------------------+
//| Timer function – lógica principal                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   // ──────────────────────────────────────────────
   // TESTE IMEDIATO (só executa uma vez ao iniciar se ativado)
   static bool ja_testou = false;
   if(TestarAgora && !ja_testou)
   {
      ja_testou = true;
      Print("══════════════════════════════════════════════");
      Print("MODO TESTE IMEDIATO ATIVADO – executando agora");
      Print("══════════════════════════════════════════════");
      ExecutarRotinaDeScreenshots();
      Print("Teste imediato concluído.");
      return; // sai para não executar o agendamento normal nesta chamada
   }
   // ──────────────────────────────────────────────

   MaybeRunToday();
}

//+------------------------------------------------------------------+
//| Função principal que faz os screenshots                            |
//+------------------------------------------------------------------+
void ExecutarRotinaDeScreenshots()
{
   log_handle = FileOpen(LogFileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_ANSI);
   if(log_handle == INVALID_HANDLE)
   {
      Print("Falha ao abrir log: ", LogFileName, " erro=", GetLastError());
      return;
   }

   FileSeek(log_handle, 0, SEEK_END);
   
   FileWrite(log_handle, "=== Início da rotina: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), " ===");
   FileWrite(log_handle, "Timeframe: ", EnumToString(Timeframe));
   FileWrite(log_handle, "Template: ", Nome_Template);
   FileWrite(log_handle, "");

   string ativos_all = Ativos;
   if(StringLen(Ativos2) > 0)
      ativos_all = ativos_all + "," + Ativos2;
   if(StringLen(Ativos3) > 0)
      ativos_all = ativos_all + "," + Ativos3;

   string lista_ativos[];
   int count = StringSplit(ativos_all, ',', lista_ativos);
   FileWrite(log_handle, "Total ativos lidos: ", IntegerToString(count));
   
   for(int i = 0; i < count; i++)
   {
      string simbolo = lista_ativos[i];
      StringTrimLeft(simbolo);
      StringTrimRight(simbolo);
      if(simbolo == "") continue;

      FileWrite(log_handle, "---");
      FileWrite(log_handle, "Ativo: ", simbolo);

      string msg = "Processando: " + simbolo + " " + EnumToString(Timeframe);
      Print(msg);
      FileWrite(log_handle, msg);

      if(!SymbolSelect(simbolo, true))
      {
         int err = GetLastError();
         msg = "→ SymbolSelect falhou " + simbolo + "  erro = " + IntegerToString(err);
         Print(msg);
         FileWrite(log_handle, msg);
      }
      
      ResetLastError();
      long chart_id = ChartOpen(simbolo, Timeframe);
      if(chart_id <= 0)
      {
         int err = GetLastError();
         msg = "→ FALHA AO ABRIR GRÁFICO " + simbolo + "  erro = " + IntegerToString(err);
         Print(msg);
         FileWrite(log_handle, msg);
         continue;
      }
      
      Sleep(Delay_Apos_Abrir_ms);
      
      ResetLastError();
      if(!ChartApplyTemplate(chart_id, Nome_Template))
      {
         int err = GetLastError();
         msg = "→ ERRO AO APLICAR TEMPLATE '" + Nome_Template + "' em " + simbolo + "  erro = " + IntegerToString(err);
         Print(msg);
         FileWrite(log_handle, msg);
         ChartClose(chart_id);
         continue;
      }
      
      msg = "  Template aplicada → aguardando...";
      Print(msg);
      FileWrite(log_handle, msg);
      Sleep(Delay_Apos_Template_ms);
      
      string filename = StringFormat("%s_%s_%s.png", simbolo, PeriodoParaString(Timeframe), TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES));
      StringReplace(filename, ":", "-");
      StringReplace(filename, " ", "_");
      // StringReplace(filename, ".", "-");  // comentei pois pode quebrar se quiser .png
      
      ResetLastError();
      if(ChartScreenShot(chart_id, filename, Largura_Imagem, Altura_Imagem, ALIGN_CENTER))
      {
         msg = "  OK → salvo: " + filename;
         Print(msg);
         FileWrite(log_handle, msg);
      }
      else
      {
         int err = GetLastError();
         msg = "  FALHA screenshot " + simbolo + "  erro = " + IntegerToString(err);
         Print(msg);
         FileWrite(log_handle, msg);
      }
      
      ChartClose(chart_id);
      Sleep(300);
   }
   
   FileWrite(log_handle, "");
   FileWrite(log_handle, "=== Rotina finalizada ===");
   FileClose(log_handle);
   log_handle = INVALID_HANDLE;
   
   Print("Rotina de screenshots finalizada. Log salvo em: ", LogFileName);
}

//+------------------------------------------------------------------+
//| Converte timeframe para string curta                               |
//+------------------------------------------------------------------+
string PeriodoParaString(ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_M1)  return "M1";
   if(tf == PERIOD_M5)  return "M5";
   if(tf == PERIOD_M15) return "M15";
   if(tf == PERIOD_M30) return "M30";
   if(tf == PERIOD_H1)  return "H1";
   if(tf == PERIOD_H4)  return "H4";
   if(tf == PERIOD_D1)  return "D1";
   if(tf == PERIOD_W1)  return "W1";
   if(tf == PERIOD_MN1) return "MN";
   return "TF" + IntegerToString((int)tf);
}
//+------------------------------------------------------------------+
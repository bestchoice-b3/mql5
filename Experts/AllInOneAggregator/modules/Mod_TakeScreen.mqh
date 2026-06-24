//+------------------------------------------------------------------+
//|                                              Mod_TakeScreen.mqh  |
//|                                   Take Screen Module             |
//+------------------------------------------------------------------+
#property strict

#include "Common.mqh"
#include <TickersProvider.mqh>

input ENUM_TIMEFRAMES InpScreenTimeframe = PERIOD_D1;
input string   InpScreenTemplate = "default.tpl";
input int      InpScreenWidth = 1280;
input int      InpScreenHeight = 720;
input int      InpScreenDelayOpen = 3000;
input int      InpScreenDelayTemplate = 3500;

string ScreenLogFileName = "ScreenshotLog.txt";

void RunTakeScreen()
{
   int log_handle = INVALID_HANDLE;
   OpenLogFile(ScreenLogFileName, log_handle);
   
   if(log_handle != INVALID_HANDLE)
   {
      FileWrite(log_handle, "=== Início da rotina Screenshot: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), " ===");
      FileWrite(log_handle, "Timeframe: ", EnumToString(InpScreenTimeframe));
      FileWrite(log_handle, "Template: ", InpScreenTemplate);
      FileWrite(log_handle, "");
   }

   string lista_ativos[];
   int count = GetTickers(lista_ativos);
   
   if(log_handle != INVALID_HANDLE)
      FileWrite(log_handle, "Total ativos lidos: ", IntegerToString(count));
   
   if(count <= 0)
   {
      if(log_handle != INVALID_HANDLE)
      {
         FileWrite(log_handle, "Nenhum ticker obtido da API/cache");
         FileWrite(log_handle, "=== Rotina Screenshot finalizada ===");
      }
      CloseLogFile(log_handle);
      Print("Nenhum ticker obtido da API/cache");
      return;
   }
   
   for(int i = 0; i < count; i++)
   {
      string simbolo = lista_ativos[i];
      StringTrimLeft(simbolo);
      StringTrimRight(simbolo);
      if(simbolo == "") continue;

      if(log_handle != INVALID_HANDLE)
      {
         FileWrite(log_handle, "---");
         FileWrite(log_handle, "Ativo: ", simbolo);
      }

      string msg = "Processando: " + simbolo + " " + EnumToString(InpScreenTimeframe);
      Print(msg);
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, msg);

      if(!SymbolSelect(simbolo, true))
      {
         int err = GetLastError();
         msg = "→ SymbolSelect falhou " + simbolo + "  erro = " + IntegerToString(err);
         Print(msg);
         if(log_handle != INVALID_HANDLE)
            FileWrite(log_handle, msg);
      }
      
      ResetLastError();
      long chart_id = ChartOpen(simbolo, InpScreenTimeframe);
      if(chart_id <= 0)
      {
         int err = GetLastError();
         msg = "→ FALHA AO ABRIR GRÁFICO " + simbolo + "  erro = " + IntegerToString(err);
         Print(msg);
         if(log_handle != INVALID_HANDLE)
            FileWrite(log_handle, msg);
         continue;
      }
      
      Sleep(InpScreenDelayOpen);
      
      ResetLastError();
      if(!ChartApplyTemplate(chart_id, InpScreenTemplate))
      {
         int err = GetLastError();
         msg = "→ ERRO AO APLICAR TEMPLATE '" + InpScreenTemplate + "' em " + simbolo + "  erro = " + IntegerToString(err);
         Print(msg);
         if(log_handle != INVALID_HANDLE)
            FileWrite(log_handle, msg);
         ChartClose(chart_id);
         continue;
      }
      
      msg = "  Template aplicada → aguardando...";
      Print(msg);
      if(log_handle != INVALID_HANDLE)
         FileWrite(log_handle, msg);
      Sleep(InpScreenDelayTemplate);
      
      string filename = StringFormat("%s_%s.png", simbolo, PeriodoParaString(InpScreenTimeframe));
      
      ResetLastError();
      if(ChartScreenShot(chart_id, filename, InpScreenWidth, InpScreenHeight, ALIGN_CENTER))
      {
         msg = "  OK → salvo: " + filename;
         Print(msg);
         if(log_handle != INVALID_HANDLE)
            FileWrite(log_handle, msg);
      }
      else
      {
         int err = GetLastError();
         msg = "  FALHA screenshot " + simbolo + "  erro = " + IntegerToString(err);
         Print(msg);
         if(log_handle != INVALID_HANDLE)
            FileWrite(log_handle, msg);
      }
      
      ChartClose(chart_id);
      Sleep(300);
   }
   
   if(log_handle != INVALID_HANDLE)
   {
      FileWrite(log_handle, "");
      FileWrite(log_handle, "=== Rotina Screenshot finalizada ===");
   }
   CloseLogFile(log_handle);
   
   Print("Rotina de screenshots finalizada. Log salvo em: ", ScreenLogFileName);
}
//+------------------------------------------------------------------+

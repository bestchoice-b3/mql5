//+------------------------------------------------------------------+
//|                                           AllInOneAggregator.mq5 |
//|                      Aggregator EA - Runs all modules sequentially|
//+------------------------------------------------------------------+
#property copyright "AllInOneAggregator"
#property version   "1.00"
#property strict

#include "modules/Scheduler.mqh"
#include "modules/Common.mqh"
#include "modules/Mod_AdxJsonExporter.mqh"
#include "modules/Mod_MovingAverage.mqh"
#include "modules/Mod_ObvTurboJsonExporter.mqh"
#include "modules/Mod_PicosValesJsonExporter.mqh"
#include "modules/Mod_TakeScreen.mqh"
#include "modules/Mod_VolumeMoveAverage.mqh"

input int InpTimerSeconds = 60;
input int InpDailyHour = 12;
input int InpDailyMinute = 0;
input int InpDailyHour2 = 16;
input int InpDailyMinute2 = 0;

enum MODULE_ID
{
   MODULE_ADX = 0,
   MODULE_MOVING_AVERAGE = 1,
   MODULE_OBV_TURBO = 2,
   MODULE_PICOS_VALES = 3,
   MODULE_TAKE_SCREEN = 4,
   MODULE_VOLUME_MA = 5
};

CScheduler g_scheduler;
datetime g_last_run_day = 0;
datetime g_last_run_day2 = 0;

void ScheduleAllModules(datetime scheduled_time)
{
   g_scheduler.ClearTasks();
   
   g_scheduler.AddTask("ADX JSON Exporter", MODULE_ADX, scheduled_time);
   g_scheduler.AddTask("Moving Average", MODULE_MOVING_AVERAGE, scheduled_time);
   g_scheduler.AddTask("OBV Turbo JSON Exporter", MODULE_OBV_TURBO, scheduled_time);
   g_scheduler.AddTask("Picos Vales JSON Exporter", MODULE_PICOS_VALES, scheduled_time);
   g_scheduler.AddTask("Take Screen", MODULE_TAKE_SCREEN, scheduled_time);
   g_scheduler.AddTask("Volume Move Average", MODULE_VOLUME_MA, scheduled_time);
   
   PrintFormat("[AllInOneAggregator] Agendadas 6 tarefas para execução sequencial");
}

void ExecuteModule(int module_id)
{
   switch(module_id)
   {
      case MODULE_ADX:
         PrintFormat("[AllInOneAggregator] Executando: ADX JSON Exporter");
         RunAdxJsonExporter();
         break;
         
      case MODULE_MOVING_AVERAGE:
         PrintFormat("[AllInOneAggregator] Executando: Moving Average");
         RunMovingAverage();
         break;
         
      case MODULE_OBV_TURBO:
         PrintFormat("[AllInOneAggregator] Executando: OBV Turbo JSON Exporter");
         RunObvTurboJsonExporter();
         break;
         
      case MODULE_PICOS_VALES:
         PrintFormat("[AllInOneAggregator] Executando: Picos Vales JSON Exporter");
         RunPicosValesJsonExporter();
         break;
         
      case MODULE_TAKE_SCREEN:
         PrintFormat("[AllInOneAggregator] Executando: Take Screen");
         RunTakeScreen();
         break;
         
      case MODULE_VOLUME_MA:
         PrintFormat("[AllInOneAggregator] Executando: Volume Move Average");
         RunVolumeMoveAverage();
         break;
         
      default:
         PrintFormat("[AllInOneAggregator] ERRO: Módulo desconhecido ID=%d", module_id);
         break;
   }
}

void ProcessScheduler()
{
   if(!g_scheduler.IsRunning())
   {
      if(g_scheduler.StartNextTask())
      {
         int module_id = g_scheduler.GetCurrentTaskModuleId();
         if(module_id >= 0)
         {
            ExecuteModule(module_id);
            g_scheduler.CompleteCurrentTask(true);
         }
      }
      else
      {
         int pending = g_scheduler.GetPendingTaskCount();
         if(pending == 0 && g_scheduler.GetCompletedTaskCount() > 0)
         {
            PrintFormat("[AllInOneAggregator] Todas as tarefas foram concluídas!");
            g_scheduler.ClearTasks();
         }
      }
   }
}

void MaybeRunToday()
{
   datetime now = TimeCurrent();
   datetime today = DayStart(now);

   datetime scheduled2 = today + (InpDailyHour2 * 3600) + (InpDailyMinute2 * 60);
   if(now >= scheduled2 && today != g_last_run_day2)
   {
      g_last_run_day2 = today;
      PrintFormat("[AllInOneAggregator] Iniciando rotina agendada #2 às %s", TimeToString(now, TIME_DATE|TIME_MINUTES));
      ScheduleAllModules(now);
      return;
   }

   datetime scheduled1 = today + (InpDailyHour * 3600) + (InpDailyMinute * 60);
   if(now >= scheduled1 && today != g_last_run_day)
   {
      g_last_run_day = today;
      PrintFormat("[AllInOneAggregator] Iniciando rotina agendada #1 às %s", TimeToString(now, TIME_DATE|TIME_MINUTES));
      ScheduleAllModules(now);
      return;
   }
}

int OnInit()
{
   EventSetTimer(MathMax(1, InpTimerSeconds));
   g_last_run_day = 0;
   g_last_run_day2 = 0;
   
   PrintFormat("═══════════════════════════════════════════════════════════");
   PrintFormat("  AllInOneAggregator EA Iniciado");
   PrintFormat("═══════════════════════════════════════════════════════════");
   PrintFormat("  Horário 1: %02d:%02d", InpDailyHour, InpDailyMinute);
   PrintFormat("  Horário 2: %02d:%02d", InpDailyHour2, InpDailyMinute2);
   PrintFormat("  Timer: %d segundos", InpTimerSeconds);
   PrintFormat("  Módulos: 6 (ADX, MA, OBV, Picos/Vales, Screenshot, Volume)");
   PrintFormat("  Execução: Sequencial (um de cada vez)");
   PrintFormat("═══════════════════════════════════════════════════════════");
   
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   PrintFormat("[AllInOneAggregator] EA finalizado. Razão: %d", reason);
}

void OnTimer()
{
   MaybeRunToday();
   ProcessScheduler();
}
//+------------------------------------------------------------------+

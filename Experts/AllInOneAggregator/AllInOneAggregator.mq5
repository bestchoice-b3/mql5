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
#include "modules/Mod_OptionsDataCollector.mqh"

input int InpTimerSeconds = 60;
input int InpDailyHour = 12;
input int InpDailyMinute = 0;
input int InpDailyHour2 = 16;
input int InpDailyMinute2 = 0;
input bool InpRunOnInit = false;

input group "=== Ativar/Desativar Módulos ==="
input bool InpEnableAdx = false;
input bool InpEnableMovingAverage = false;
input bool InpEnableObvTurbo = false;
input bool InpEnablePicosVales = false;
input bool InpEnableTakeScreen = false;
input bool InpEnableVolumeMA = false;
input bool InpEnableOptionsData = true;

enum MODULE_ID
{
   MODULE_ADX = 0,
   MODULE_MOVING_AVERAGE = 1,
   MODULE_OBV_TURBO = 2,
   MODULE_PICOS_VALES = 3,
   MODULE_TAKE_SCREEN = 4,
   MODULE_VOLUME_MA = 5,
   MODULE_OPTIONS_DATA = 6
};

CScheduler g_scheduler;
datetime g_last_run_day = 0;
datetime g_last_run_day2 = 0;

void ScheduleAllModules(datetime scheduled_time)
{
   g_scheduler.ClearTasks();
   int count = 0;
   
   if(InpEnableAdx)
   {
      g_scheduler.AddTask("ADX JSON Exporter", MODULE_ADX, scheduled_time);
      count++;
   }
   
   if(InpEnableMovingAverage)
   {
      g_scheduler.AddTask("Moving Average", MODULE_MOVING_AVERAGE, scheduled_time);
      count++;
   }
   
   if(InpEnableObvTurbo)
   {
      g_scheduler.AddTask("OBV Turbo JSON Exporter", MODULE_OBV_TURBO, scheduled_time);
      count++;
   }
   
   if(InpEnablePicosVales)
   {
      g_scheduler.AddTask("Picos Vales JSON Exporter", MODULE_PICOS_VALES, scheduled_time);
      count++;
   }
   
   if(InpEnableTakeScreen)
   {
      g_scheduler.AddTask("Take Screen", MODULE_TAKE_SCREEN, scheduled_time);
      count++;
   }
   
   if(InpEnableVolumeMA)
   {
      g_scheduler.AddTask("Volume Move Average", MODULE_VOLUME_MA, scheduled_time);
      count++;
   }
   
   if(InpEnableOptionsData)
   {
      g_scheduler.AddTask("Options Data Collector", MODULE_OPTIONS_DATA, scheduled_time);
      count++;
   }
   
   PrintFormat("[AllInOneAggregator] Agendadas %d tarefas para execução sequencial", count);
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
         
      case MODULE_OPTIONS_DATA:
         PrintFormat("[AllInOneAggregator] Executando: Options Data Collector");
         RunOptionsDataCollector();
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
   ENUM_TIMEFRAMES chart_period = Period();
   
   if(chart_period != PERIOD_D1)
   {
      PrintFormat("╔═══════════════════════════════════════════════════════════╗");
      PrintFormat("║  ERRO: AllInOneAggregator DEVE rodar em gráfico D1!      ║");
      PrintFormat("╚═══════════════════════════════════════════════════════════╝");
      PrintFormat("");
      PrintFormat("  Timeframe atual: %s", EnumToString(chart_period));
      PrintFormat("  Timeframe necessário: D1 (Daily)");
      PrintFormat("");
      PrintFormat("  SOLUÇÃO:");
      PrintFormat("  1. Abra um gráfico DIÁRIO (D1)");
      PrintFormat("  2. Adicione o AllInOneAggregator neste gráfico D1");
      PrintFormat("");
      PrintFormat("  IMPORTANTE: Todos os módulos trabalham com dados D1!");
      PrintFormat("");
      Alert("ERRO: AllInOneAggregator deve rodar em gráfico D1!\nTimeframe atual: ", EnumToString(chart_period));
      return INIT_FAILED;
   }
   
   EventSetTimer(MathMax(1, InpTimerSeconds));
   g_last_run_day = 0;
   g_last_run_day2 = 0;
   
   PrintFormat("═══════════════════════════════════════════════════════════");
   PrintFormat("  AllInOneAggregator EA Iniciado");
   PrintFormat("═══════════════════════════════════════════════════════════");
   PrintFormat("  Timeframe: D1 (Daily) ✓");
   PrintFormat("  Horário 1: %02d:%02d", InpDailyHour, InpDailyMinute);
   PrintFormat("  Horário 2: %02d:%02d", InpDailyHour2, InpDailyMinute2);
   PrintFormat("  Timer: %d segundos", InpTimerSeconds);
   PrintFormat("  Executar ao iniciar: %s", InpRunOnInit ? "SIM" : "NÃO");
   
   int enabled_count = 0;
   if(InpEnableAdx) enabled_count++;
   if(InpEnableMovingAverage) enabled_count++;
   if(InpEnableObvTurbo) enabled_count++;
   if(InpEnablePicosVales) enabled_count++;
   if(InpEnableTakeScreen) enabled_count++;
   if(InpEnableVolumeMA) enabled_count++;
   if(InpEnableOptionsData) enabled_count++;
   
   PrintFormat("  Módulos ativos: %d de 7", enabled_count);
   if(InpEnableAdx) PrintFormat("    ✓ ADX JSON Exporter");
   if(InpEnableMovingAverage) PrintFormat("    ✓ Moving Average");
   if(InpEnableObvTurbo) PrintFormat("    ✓ OBV Turbo JSON Exporter");
   if(InpEnablePicosVales) PrintFormat("    ✓ Picos Vales JSON Exporter");
   if(InpEnableTakeScreen) PrintFormat("    ✓ Take Screen");
   if(InpEnableVolumeMA) PrintFormat("    ✓ Volume Move Average");
   if(InpEnableOptionsData) PrintFormat("    ✓ Options Data Collector");
   PrintFormat("  Execução: Sequencial (um de cada vez)");
   PrintFormat("═══════════════════════════════════════════════════════════");
   
   if(InpRunOnInit)
   {
      PrintFormat("[AllInOneAggregator] Executando imediatamente (RunOnInit=true)...");
      ScheduleAllModules(TimeCurrent());
      
      while(g_scheduler.GetPendingTaskCount() > 0)
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
            break;
         }
      }
      
      PrintFormat("[AllInOneAggregator] Execução inicial concluída!");
   }
   
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

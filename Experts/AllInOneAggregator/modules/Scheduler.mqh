//+------------------------------------------------------------------+
//|                                                    Scheduler.mqh |
//|                          Sequential task scheduler for modules   |
//+------------------------------------------------------------------+
#property strict

enum TASK_STATUS
{
   TASK_PENDING,
   TASK_RUNNING,
   TASK_COMPLETED,
   TASK_FAILED
};

struct Task
{
   string name;
   TASK_STATUS status;
   datetime scheduled_time;
   int module_id;
};

class CScheduler
{
private:
   Task m_tasks[];
   int m_task_count;
   int m_current_task_index;
   bool m_is_running;
   
public:
   CScheduler()
   {
      m_task_count = 0;
      m_current_task_index = -1;
      m_is_running = false;
      ArrayResize(m_tasks, 0);
   }
   
   void AddTask(const string name, const int module_id, const datetime scheduled_time)
   {
      ArrayResize(m_tasks, m_task_count + 1);
      m_tasks[m_task_count].name = name;
      m_tasks[m_task_count].status = TASK_PENDING;
      m_tasks[m_task_count].scheduled_time = scheduled_time;
      m_tasks[m_task_count].module_id = module_id;
      m_task_count++;
   }
   
   void ClearTasks()
   {
      ArrayResize(m_tasks, 0);
      m_task_count = 0;
      m_current_task_index = -1;
      m_is_running = false;
   }
   
   bool IsRunning()
   {
      return m_is_running;
   }
   
   int GetCurrentTaskModuleId()
   {
      if(m_current_task_index >= 0 && m_current_task_index < m_task_count)
         return m_tasks[m_current_task_index].module_id;
      return -1;
   }
   
   string GetCurrentTaskName()
   {
      if(m_current_task_index >= 0 && m_current_task_index < m_task_count)
         return m_tasks[m_current_task_index].name;
      return "";
   }
   
   bool StartNextTask()
   {
      if(m_is_running)
         return false;
         
      for(int i = 0; i < m_task_count; i++)
      {
         if(m_tasks[i].status == TASK_PENDING)
         {
            datetime now = TimeCurrent();
            if(now >= m_tasks[i].scheduled_time)
            {
               m_current_task_index = i;
               m_tasks[i].status = TASK_RUNNING;
               m_is_running = true;
               PrintFormat("[Scheduler] Iniciando tarefa: %s (módulo %d)", m_tasks[i].name, m_tasks[i].module_id);
               return true;
            }
         }
      }
      return false;
   }
   
   void CompleteCurrentTask(bool success = true)
   {
      if(m_current_task_index >= 0 && m_current_task_index < m_task_count)
      {
         m_tasks[m_current_task_index].status = success ? TASK_COMPLETED : TASK_FAILED;
         PrintFormat("[Scheduler] Tarefa %s: %s", 
                     m_tasks[m_current_task_index].name, 
                     success ? "CONCLUÍDA" : "FALHOU");
         m_is_running = false;
         m_current_task_index = -1;
      }
   }
   
   int GetPendingTaskCount()
   {
      int count = 0;
      for(int i = 0; i < m_task_count; i++)
      {
         if(m_tasks[i].status == TASK_PENDING)
            count++;
      }
      return count;
   }
   
   int GetCompletedTaskCount()
   {
      int count = 0;
      for(int i = 0; i < m_task_count; i++)
      {
         if(m_tasks[i].status == TASK_COMPLETED)
            count++;
      }
      return count;
   }
   
   void PrintStatus()
   {
      PrintFormat("[Scheduler] Total: %d | Pendentes: %d | Concluídas: %d | Rodando: %s",
                  m_task_count, GetPendingTaskCount(), GetCompletedTaskCount(),
                  m_is_running ? "SIM" : "NÃO");
   }
};
//+------------------------------------------------------------------+

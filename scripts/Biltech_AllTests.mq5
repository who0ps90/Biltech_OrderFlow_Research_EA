#property strict
#property description "Offline synthetic native assertions. No orders. No account credentials required."

// Included-file properties are ignored by MQL5; this main module intentionally
// omits script_show_inputs so it can run from a startup configuration.
#define OnStart CoreOnStart
#include "Biltech_CoreTests.mq5"
#undef OnStart
#define OnStart FlowOnStart
#include "Biltech_OrderFlowTests.mq5"
#undef OnStart
#define OnStart JournalOnStart
#include "Biltech_ExecutionTests.mq5"
#undef OnStart

void OnStart(void)
  {
   if(AccountInfoInteger(ACCOUNT_LOGIN)!=0 || TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
     {
      PrintFormat("BILTECH_NATIVE_REFUSED: account_present=%d automated_trading_allowed=%d dll_imports_allowed=%d. Require a logged-out offline terminal.",
                  (int)(AccountInfoInteger(ACCOUNT_LOGIN)!=0),(int)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED),
                  (int)TerminalInfoInteger(TERMINAL_DLLS_ALLOWED));
      return;
     }
   Print("BILTECH_NATIVE_BEGIN: synthetic fixtures only; no account, orders or market backtest.");
   CoreOnStart();
   FlowOnStart();
   JournalOnStart();
   int handle=FileOpen("Biltech_native_result.csv",FILE_WRITE|FILE_TXT|FILE_ANSI,0,CP_UTF8);
   if(handle==INVALID_HANDLE) { Print("BILTECH_NATIVE_RESULT_WRITE_FAILED"); return; }
   FileWriteString(handle,"suite,passed,failed\r\n");
   FileWriteString(handle,StringFormat("clock_strategy,%d,%d\r\n",passed,failed));
   FileWriteString(handle,StringFormat("orderflow_profile,%d,%d\r\n",g_passed,g_failed));
   FileWriteString(handle,StringFormat("journal,%d,%d\r\n",state_passed,state_failed));
   FileWriteString(handle,StringFormat("total,%d,%d\r\n",passed+g_passed+state_passed,failed+g_failed+state_failed));
   FileFlush(handle);
   FileClose(handle);
   PrintFormat("BILTECH_NATIVE_COMPLETE: %d passed; %d failed. No market backtest.",
               passed+g_passed+state_passed,failed+g_failed+state_failed);
  }

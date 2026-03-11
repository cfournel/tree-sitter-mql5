//+------------------------------------------------------------------+
//|                                                EA OrderBlock.mq5 |
//|                     Copyright 2025, Charles-antoine fournel Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

/*
   Changelog:
   - v1.24 (2025.07.03): Improved loss with ATR, multiple MA and ADX filter
   - v1.25 (2025.07.03): Fix issues and improve performance
   - v1.26 (2025.07.11): Fix an issue with the right day of the week to close positive trade before end of market
   - v1.27 (2025.07.11): Fix an issue with ATR management for stop loss
   - v1.34 (2025.07.12): hard time passing all the validation process to publish
   - v1.35 (2025.07.12): Improvee trailing stop system
   - v1.36 (2025.07.14): Fix an issue on sell trade where upgrade and trailing were malfunctionning
   - v1.37 (2025.07.14): Fix another issue on validating distance between bidprice and entry price for sell stop, regarding broker stop level distance
   - v1.39 (2025.07.30): Introduce new features and fix problems
   - v1.40 (2025.07.31): fix problems
   - v1.41 (2025.07.31): Implement over extended fibo features + rework + multi-timer
   - v1.42 (2025.08.10): Implement PD Arrays to raise winrate . Starting an admin panel (not available right now but soon)
   - v1.43 (2025.08.13): Implement an input to limit trade to buy only, sell only or both). Implement a custom filter for strategy tester to get win rate
   - v1.44 (2025.09.03): Fix a case where OB was deleted without reason, preventing taking a trade. Fix a case where Resistance R2 was not displayed. Fix a case where trying to delete an HTF OB even if HTF detection is disabled
   - v1.45 (2025.09.13): Fix a case in objectDelete and status string
   - v1.46 (2025.09.17): Bug fixes, add more reason
   - v1.47 (2025.09.27): Add market selection, remove some unused code for better performance
   - v1.48 (2025.09.30): Remove high timeframe confirmation as it was not enough efficient , will bring it back later if succeed. Improve ADX indicator with minusDI and plusDI ( to better confirm signal ). Change the way of handling expiration order and order block to candles instead of hours.
   - v1.49 (2025.10.05): Small update to automatically set the chart to the selected timeframe
   - v1.50 (2025.10.10): Remove a test of entry price which must be higher than slow MA. Remove show debug input as somehow is slowed the EA and avoid trading ( still figuring why )
   - v1.51 (2025.10.13): Add a mitigation mode. protection mode for ranging ternd
   - v1.52 (2025.10.14): Fix an issue with trailing stop not checking minimum distance and add a input to choose news to filter by currency
   - v1.53 (2025.10.16): Fix news display. Add a fix to orders if symbol is not gold ( index with tick size greater than 1 ), add icon
   - V1.54 (2025.10.29): Fix the upgrading take profit system, add a new input parameter to choose how to trigger Trailing Stop
   - v1.55 (2025.10.31): Fix an issue when one does a withdrawal, it was interpreted as a daily loss. Fix a case where news panel doesn t disappear at the end of the freeze time
   - v1.56 (2025.11.08): Add ATR Max and sqlite support. delete csv file which stored order block buffer. remove history bar parameter has its not used anymore
   - v1.57 (2025.11.14): Fix an issue in news panel text display (a newline missing for title). Add ICT Macro display (not in algorithme yet). fix DB name with timeframe as suffix (useful if load EA on multi timeframe). Fix a bug on dailystoploss with trading time
   - v1.58 (2025.11.18): Hotfix for mqlite not correctly initialized sometimes.
   - v1.59 (): Fix notifications sending in loop. Add a Warning panel to display message. Add a panel for daily stop loss limit reach. Add a switch to enable risk reduction during Q4 from october to december included. Fix some typos. Add another trigger to prevent trading in hyper volatility (ATR / AverageATRSMA )
   - v1.62 (): Full auto multi-symbol spawner (issue #37). inpAutoMultiSymbol=true opens all watchlist charts,
               auto-assigns magic via symbol hash, calibrates ATR_max per category. New: autoSpawner.mqh.
               Fix KZ TimeGMT bug. Add isAllGood() reason codes.
    - v1.61 (): Add ENUM_SL_SWEEP stop loss mode — SL placed at LTF (M5) liquidity sweep level + 0.15 ATR buffer.
              Backtested 2022-2026: balance $33.6k vs $26.6k FIBO, Sharpe 18.46 vs 15.56, DD 10.22% vs 11.37%.
              Add ENUM_EM_CISD entry mode — waits for CISD retest of LTF MSS break level (experimental).
   - v1.60 (): Fix an issue in the warning panel not desapearing in january. Recode BOS Detection & display. Disable bullish or bearish if type of trade is not BOTH for performance improvement. CPU / Memory usage optimzations. fix an issue in daily stop loss features ( if you withdraw some money i did count as a loss ). Add a minimal distance of 60points in ATR trailing stop loss Composite OnTester() scoring (winRate x PF x (1-DD) x log10(trades+1)). Configurable DD kill switch for optimizer (inpMaxTesterDD, default 40%). Removed unused Fast/Slow MA inputs. HTF trend (mHTFTrend) refresh on HTOB bar change only. ATR trailing stop clamped to broker stop level. Trade frequency improvements: (A) MSS lookback 6→12 bars. (B) FVG-on-MSS optional (inpMSSRequireFVG). (C) OB re-entry after mitigation with momentum guard (inpAllowMitigatedReentry). (D) outdatedOB default 80→120 bars. (E) Range trading (isRangeTradingOK) now properly gates isAllGood() and isRangeTrend().

*/

#property copyright "Copyright 2025, charles-Antoine fournel Ltd."
#property link      "https://www.mql5.com/en/market/product/143851/"
#property version   "1.61"
//#property description "Smart money concept Order Block strategy \n Last settings files : https://www.mql5.com/en/blogs/post/764473"
#property icon "OBInclude/icon.ico"
#resource "\\OBInclude\\qrcode.bmp"

#include "OBInclude/inputs.mqh"
#include "OBInclude/sqlite.mqh"
#include "OBInclude/helpers.mqh"
#include "OBInclude/drawOB.mqh"
#include "OBInclude/types.mqh"
#include "OBInclude/globals.mqh"
#include "OBInclude/exportOB.mqh"  // OB lifecycle CSV export
#include "OBInclude/diagnosticPanel.mqh"  // startup diagnostic warnings
#include "OBInclude/langs.mqh"
#include "test/TestOrderBlock.mqh"


int totalOb = 0;
int purgedOb = 0;
int counterTrend = 0;
int tp127 = 0;
int tp161 = 0;
int tp238 = 0;
Lang language;

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Apply risk profile — overrides filter settings into g_ globals.  |
//| Called first in OnInit(); filters read g_ instead of inp*.       |
//+------------------------------------------------------------------+
void ApplyRiskProfile()
  {
   switch(inpRiskProfile)
     {
      //── Very Aggressive: no filters, maximum trade count ──────────
      case PROFILE_VERY_AGGRESSIVE:
         g_kzEnabled        = false;
         g_kz1Start=8;
         g_kz1End=15;
         g_kz2Start=18;
         g_kz2End=22;
         g_dailyBiasEnabled  = false;
         g_macroTrendEnabled = false;
         g_d1TrendEnabled    = false;
         g_h4TrendEnabled    = false;
         break;
      //── Aggressive: wide KZ, bias off, macro on ───────────────────
      case PROFILE_AGGRESSIVE:
         g_kzEnabled        = true;
         g_kz1Start=8;
         g_kz1End=17;
         g_kz2Start=18;
         g_kz2End=23;
         g_dailyBiasEnabled  = false;
         g_macroTrendEnabled = true;
         g_d1TrendEnabled    = false;
         g_h4TrendEnabled    = false;
         break;
      //── Balanced: medium KZ + daily bias + macro ──────────────────
      case PROFILE_BALANCED:
         g_kzEnabled        = true;
         g_kz1Start=9;
         g_kz1End=15;
         g_kz2Start=20;
         g_kz2End=23;
         g_dailyBiasEnabled  = true;
         g_macroTrendEnabled = true;
         g_d1TrendEnabled    = false;
         g_h4TrendEnabled    = false;
         break;
      //── Conservative (recommended): tight KZ + all key filters ────
      case PROFILE_CONSERVATIVE:
         g_kzEnabled        = true;
         g_kz1Start=11;
         g_kz1End=14;
         g_kz2Start=20;
         g_kz2End=23;
         g_dailyBiasEnabled  = true;
         g_macroTrendEnabled = true;
         g_d1TrendEnabled    = true;
         g_h4TrendEnabled    = false;
         break;
      //── Very Conservative: same KZ + H4 trend added ───────────────
      case PROFILE_VERY_CONSERVATIVE:
         g_kzEnabled        = true;
         g_kz1Start=11;
         g_kz1End=14;
         g_kz2Start=20;
         g_kz2End=23;
         g_dailyBiasEnabled  = true;
         g_macroTrendEnabled = true;
         g_d1TrendEnabled    = true;
         g_h4TrendEnabled    = true;
         break;
      //── Custom: use individual input values as-is ─────────────────
      default:
         g_kzEnabled        = inpKillZoneEnabled;
         g_kz1Start=inpKZ1Start;
         g_kz1End=inpKZ1End;
         g_kz2Start=inpKZ2Start;
         g_kz2End=inpKZ2End;
         g_dailyBiasEnabled  = inpDailyBiasEnabled;
         g_macroTrendEnabled = inpMacroTrendEnabled;
         g_d1TrendEnabled    = inpRequireD1Trend;
         g_h4TrendEnabled    = inpRequireH4Trend;
         break;
     }
   string name = (inpRiskProfile==PROFILE_VERY_AGGRESSIVE) ? "Very Aggressive" :
                 (inpRiskProfile==PROFILE_AGGRESSIVE)       ? "Aggressive"      :
                 (inpRiskProfile==PROFILE_BALANCED)         ? "Balanced"        :
                 (inpRiskProfile==PROFILE_CONSERVATIVE)     ? "Conservative"    :
                 (inpRiskProfile==PROFILE_VERY_CONSERVATIVE)? "Very Conservative":
                 "Custom";
   Print("Risk profile: ", name,
         "  KZ=", g_kzEnabled ? (string)g_kz1Start+"-"+(string)g_kz1End+"+"+(string)g_kz2Start+"-"+(string)g_kz2End : "off",
         "  DailyBias=", g_dailyBiasEnabled,
         "  Macro=", g_macroTrendEnabled,
         "  D1=", g_d1TrendEnabled,
         "  H4=", g_h4TrendEnabled);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   TesterHideIndicators(true);
   Comment(T("initializing..."));
   language = DetectLanguage();
   Print("Language : ", (Lang)language);
   ApplyRiskProfile();

   MaxBars = MaxTheoreticalBars(dptf, CTOB);
   sql = new MqlLite();
   drawHTFChannel();
   drawLiquidityLevel();
   obj_Trade.SetTypeFilling(ORDER_FILLING_FOK);
   obj_Trade.SetDeviationInPoints(10);

   ObjectsDeleteAll(0,"ob-range");
   ObjectsDeleteAll(0,"Rectangle");
   ObjectsDeleteAll(0,"OB");
   ObjectsDeleteAll(0,"Sweep_");
   ObjectsDeleteAll(0,"ob-p");
   ObjectsDeleteAll(0, "ICT-");
   ObjectsDeleteAll(0, "ICT_");
   ObjectsDeleteAll(0, "OBEA_");
   ObjectsDeleteAll(0, "SPBPP_2_extended_");
   ObjectDelete(0, "clock");
   ObjectDelete(0, "NewsAlert");
   ObjectsDeleteAll(0, "WarningAlert");
   ObjectsDeleteAll(0,"OBEA_");
   ClearDiagnosticPanel();
   ClearDiagStatusIcon();
   ObjectsDeleteAll(0, "ICTmacro-");
   ObjectsDeleteAll(0, "CPR");

   if(uniqueMagicNumber == 819288)
     {
      debugMode = true;
      testOrderBlock();
     }

   if(! MQLInfoInteger(MQL_TESTER))
     {
      DrawPWDHL();
      drawCPR();
      drawPivotPoints();
     }

   ChartSetSymbolPeriod(0, _Symbol,CTOB);
   ChartSetInteger(ChartID(), CHART_SHOW_TRADE_HISTORY, false);
   ChartSetInteger(ChartID(), CHART_SHOW_GRID, false);
   checkLiquidity();
   drawLiquidityLevel();
   drawMacro();

   if(sql != NULL && sql.createDB() == true)
     {
      Print("DB created");
     }
   else
     {
      sql.alterDB("OrderBlock", "color", "TEXT");
      sql.alterDB("OrderBlock", "reason", "TEXT");
     }


   lotsize = inpMinimallotsize;
   AdaptiveRiskByTrade = riskByTrade;
   EventSetTimer(30);

   obj_Trade.SetExpertMagicNumber(uniqueMagicNumber);
   CreateFolderIfNeeded(FolderName);
// Suppression des labels de texte
   for(int i = 0; i < 6; i++)
     {
      string labelName = "NewsAlertText_" + IntegerToString(i);
      if(!ObjectDelete(0, labelName))
         break; // Plus de labels à supprimer
     }

   sql.getLastOB();
   InitOpenCL();
   GPU_ScanHistoricalCandles(inpHistoricalScanBars);

   htfTrend = GetMarketTrend();
   DrawLabelProfit();
   ProfitForPeriod();

   if(EnableClock == true)
     {
      // Configuration du panneau (fond)
      int chartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int chartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      int xPos = chartWidth  / 2; // Centrage horizontal
      ObjectSetInteger(0, "WarningAlertPanel", OBJPROP_XDISTANCE, xPos);
      if(ObjectFind(0,"clock")<0)
        {
         ObjectCreate(0,"clock", OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,"clock",OBJPROP_XDISTANCE,xPos);
         ObjectSetInteger(0,"clock",OBJPROP_YDISTANCE,chartHeight - 20);
         ObjectSetString(0,"clock",OBJPROP_TEXT,TimeToString(TimeTradeServer()));
         ObjectSetInteger(0,"clock",OBJPROP_COLOR,clrWhite);
         ObjectSetString(0,"clock",OBJPROP_FONT,InpFont);
         ObjectSetInteger(0,"clock",OBJPROP_FONTSIZE,25);
         ObjectSetInteger(0, "clock",OBJPROP_ANCHOR,  ANCHOR_CENTER);
         ObjectSetInteger(0, "clock",OBJPROP_ALIGN,ALIGN_CENTER);
        }
     }

   AddLogicalTimer(Timer30s,30);
   AddLogicalTimer(Timer1m, 60);
   AddLogicalTimer(Timer2m, 120);
   AddLogicalTimer(Timer5m, 300);
   AddLogicalTimer(Timer10m, 600);
   AddLogicalTimer(Timer1h, 3600);
   AddLogicalTimer(Timer1d, 86400);
   AddLogicalTimer(TimerCTOB, PeriodSeconds(CTOB));
   AddLogicalTimer(TimerHTOB, PeriodSeconds(HTOB));


// Initial news check
   if(EnableCheckNews == true)
      CheckNews();

//---
   timeToTrade();

   if(StopTradingDailyLoss() == true)
     {
      Comment(T("Daily loss limit reached !"));
     }
   drawQrCode();
   ExportOBInit();

// Input validation
   if(g_kzEnabled && (g_kz1Start >= g_kz1End || g_kz2Start >= g_kz2End))
     { Print("ERROR: Kill zone start must be < end (KZ1: ",g_kz1Start,"-",g_kz1End,", KZ2: ",g_kz2Start,"-",g_kz2End,")"); return(INIT_PARAMETERS_INCORRECT); }
   if(inpDynamicLot && inpDynLotHighMult < 1.0)
     { Print("WARNING: inpDynLotHighMult < 1.0 reduces size on best setups — check config"); }
   if(inpMaxSpread > 0 && inpMaxSpread < 10)
     { Print("WARNING: inpMaxSpread=",inpMaxSpread," seems very low (points) — check config"); }

   RunAndDisplayDiagnostics();

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ExportOBClose();
//---
   Print(T("Reason "), getUninitReasonText(reason));

   EventKillTimer();
   ObjectsDeleteAll(0, "CPR");
   ObjectsDeleteAll(0,"Rectangle");
   ObjectsDeleteAll(0,"OB");
   ObjectsDeleteAll(0,"Sweep_");
   ObjectsDeleteAll(0,"ob-p");
   ObjectsDeleteAll(0, "SPBPP_2_extended_");
   ObjectDelete(0,"lastObInfo");
   ObjectsDeleteAll(0,"ob-range");
   ObjectDelete(0, "clock");
   ObjectDelete(0, "NewsAlertPanel");
   ObjectsDeleteAll(0, "NewsAlert");
   ObjectsDeleteAll(0, "Pivot-");
   ObjectsDeleteAll(0,"OBEA_");
   ClearDiagnosticPanel();
   ObjectsDeleteAll(0, "ICTmacro-");
   ObjectsDeleteAll(0, "ICT-");
   ObjectsDeleteAll(0, "ICT_");
   ObjectDelete(0, "qrCode");
   IndicatorRelease(zz_handle);
// Suppression des labels de texte
   for(int i = 0; i < 100; i++) // Limite arbitraire pour éviter une boucle infinie
     {
      string labelName = "NewsAlertText_" + IntegerToString(i);
      if(!ObjectDelete(0, labelName))
         break; // Plus de labels à supprimer
     }

   for(int i = 0; i < ArraySize(obBuffer); i++)
     {
      sql.updateOB(obBuffer[i]);
     }

//GaugeDelete(g0);
   if(sql != NULL)
     {
      delete sql;
      sql = NULL;
     }

   DeinitOpenCL();
   PrintOBReasonSummary();
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {

   if(timeToTradeBl ==  false || IsTradingAllowed() == false)
     {
      return;
     }
   bidPrice         = Bid(); // bear
   askPrice         = Ask(); // bull
   spread           = (int)Spread();

// OPTI: rA[] is bar-level data — only re-copy when a new bar opens
   static datetime lastRaBarOpen = 0;
   datetime curRaBarOpen = iTime(_Symbol, CTOB, 0);
   isNewBar = (curRaBarOpen != lastRaBarOpen);
   if(isNewBar)
     {
      CopyRates(_Symbol, CTOB, 0, 5, rA);
      lastRaBarOpen = curRaBarOpen;
     }
//---
   for(int i = 0 ; i < ArraySize(obBuffer); i++)
     {
      // #43: Fast-path overdue OBs — mark done immediately, hourly clean removes later
      if(!hasOnGoingPosition(i) && !obBuffer[i].isDone)
        {
         if(CountBarsSince(obBuffer[i].startTime, _Symbol, CTOB) >= outdatedOB)
           { obBuffer[i].isDone = true; obBuffer[i].reason = ENUM_REASON_IS_OVERDUE; drawReason(i); continue; }
        }

      // #26 Cancel pending limit order if daily bias has flipped since placement.
      // gated on isNewBar (once per M15 bar) to prevent tick-by-tick oscillation
      // when price hovers near the daily open.
      if(g_dailyBiasEnabled && isNewBar
         && obBuffer[i].tradeTicket != INVALID_TICKET
         && OrderSelect(obBuffer[i].tradeTicket))  // true only for pending (not yet filled)
        {
         double dailyOpen = iOpen(_Symbol, PERIOD_D1, 0);
         bool bullishBias = (bidPrice > dailyOpen);
         if((obBuffer[i].isBear && bullishBias) || (!obBuffer[i].isBear && !bullishBias))
           {
            if(obj_Trade.OrderDelete(obBuffer[i].tradeTicket))
              {
               obBuffer[i].tradeTicket = INVALID_TICKET;
               obBuffer[i].allChecks   = false;
               obBuffer[i].isDone      = false;  // allow re-detection if bias realigns
               obBuffer[i].reason      = obBuffer[i].isBear
                                         ? ENUM_REASON_IS_COUNTER_BULLISH
                                         : ENUM_REASON_IS_COUNTER_BEARISH;
              }
           }
        }

      if(obBuffer[i].isDone == false)
        {
         //OPTI +profit +dd +trades
         // Try order first when OB passed all checks â prevents fib50/midline mitigation-entry race
         if(obBuffer[i].allChecks == true && obBuffer[i].tradeTicket == INVALID_TICKET)
           {
            setOBOrder(i);
            if(obBuffer[i].tradeTicket != INVALID_TICKET)
               continue;
           }
         if(checkMitigated(i) == true)
           {
            continue;
           }

         if(isFirstOB(i) == false && tradeSecondaryOB == false)
           {
            obBuffer[i].OBcolor = clrPurple;
            obBuffer[i].reason = ENUM_REASON_IS_PURPLE;
            drawReason(i);
            obBuffer[i].isDone = true;
            obBuffer[i].stars = 0;
            continue;
           }

         // check if ob is valid with previous candle
         if(obBuffer[i].lsscValid == false)
            if(obBuffer[i].checkValidLssc() == false)
              {
               continue;
              }

         if(obBuffer[i].isMSS == false && MSSMandatory == true)
           {
            bool bearishMss = (obBuffer[i].isBear == true) ? true : false;
            if(obBuffer[i].checkForMSSBefore(20) == false)
              {
               obBuffer[i].reason = ENUM_REASON_NO_MSS;
               continue;
              }

           }

         if(bar(obBuffer[i].MSSEnd, CTOB) == 2 && obBuffer[i].isImbalanced == false)
           {
            if(obBuffer[i].checkValidImbalance() == false)
              {
               continue;
              }
           }

         // if top impulse has 3 bar old , we consider that is the real top
         if(obBuffer[i].topImpValid == false)
            if(obBuffer[i].getMaxImpulsion() == -DBL_MAX)
               continue;

         drawLiquiditySweep(i);
         //OPTI make less trade and less profit , to optimize or remove
         //if ( isRangeTrend(i) == true)
         //   return;
         if(obBuffer[i].ImbalancedFilled == false)
           {
            if(obBuffer[i].IsFairValueGapFilled() == false)
               continue;
            else
              {
               if(obBuffer[i].topImpValid == true)
                 {
                  getFibLevels(i);
                 }
              }
           }




         //detectFVG(i);

         // AUTO / CISD entry modes: wait for LTF MSS confirmed on each tick
         // When not in AUTO/CISD mode this block is skipped entirely
         if((inpEntryMode == ENUM_EM_AUTO || inpEntryMode == ENUM_EM_CISD) &&
            obBuffer[i].isLowerMss == false)
           {
            // ImbalancedFilled is a prerequisite — skip rest of loop until ready
            if(!obBuffer[i].ImbalancedFilled)
               continue;
            // Price must be on the correct side of the MSS level
            if(obBuffer[i].isBear == false && askPrice > obBuffer[i].MSSLevel)
               continue;
            if(obBuffer[i].isBear == true  && bidPrice < obBuffer[i].MSSLevel)
               continue;
            // LTF MSS scan — runs every tick (intrabar price-action driven)
            bool bearishMss = (obBuffer[i].isBear == true);
            if(!obBuffer[i].checkForMSSEntry(bearishMss, iTime(_Symbol,ltf,0), ltf))
               continue;
           }
         // CISD mode: after MSS break, wait for retest of break level before entering
         if(inpEntryMode == ENUM_EM_CISD && obBuffer[i].isLowerMss == true &&
            obBuffer[i].isCISD == false)
           {
            bool bearishMss2 = (obBuffer[i].isBear == true);
            if(!obBuffer[i].checkForCISDEntry(bearishMss2, ltf))
               continue;
           }

         //OPTI very important
         if(isOverExtended(i) == true)
            continue;

         checkFibRehearsal(i);

         // All flags set on this tick — trade immediately if ready
         if(obBuffer[i].isAllGood(i) == true)
           { setOBOrder(i); continue; }

         // Sub-quality trade: MSS+FVG+impulse without sweep — conservative fib100 TP
         if(inpLowQualityTrades && !obBuffer[i].allChecks && obBuffer[i].isMinQuality())
           {
            obBuffer[i].takeProfit = obBuffer[i].fib100;
            setOBOrder(i);
            continue;
           }
        }

      if(hasOnGoingPosition(i))
        {
         // OPTI: TP upgrade and partial close only need to run on new bars
         if(isNewBar)
           {
            obBuffer[i].ManagePartialTP();
            upgradeCurrentOrder(i);
           }

         //--- Early break-even check on every tick
         applyEarlyBreakEven(i);

         //--- Apply trailing stop to open positions if enabled
         if(enableTrailingStop == true)
           {
            //OPTI trailing reduce maximum profit, reduce dd by 2%
            applyTrailingStop(i);
           }
        }

     }

  }

//+------------------------------------------------------------------+
//| Chart event handler                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      // Status icon: toggle panel
      if(sparam == DIAG_ICON_NAME)
        {
         ObjectSetInteger(0, DIAG_ICON_NAME, OBJPROP_STATE, false);
         if(ObjectFind(0, DIAG_PANEL_PREFIX + "BG") >= 0)
            ClearDiagnosticPanel();
         else
            DrawDiagnosticPanel(g_diagWarnings, g_diagCount);
         ChartRedraw(0);
         return;
        }
      // Close button: hide panel, keep icon
      if(sparam == DIAG_PANEL_PREFIX + "Close")
        {
         ObjectSetInteger(0, DIAG_PANEL_PREFIX + "Close", OBJPROP_STATE, false);
         ClearDiagnosticPanel();
         ChartRedraw(0);
         return;
        }
     }

   if(id == CHARTEVENT_CHART_CHANGE)
     {
      int chartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int chartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      int xCentrum = chartWidth  / 2; // Centrage horizontal
      ObjectSetInteger(0, "clock", OBJPROP_XDISTANCE, xCentrum);
      ObjectSetInteger(0, "clock", OBJPROP_YDISTANCE, chartHeight - 20);
      ObjectSetInteger(0, "Diag_Ico", OBJPROP_XDISTANCE, xCentrum);
     
      // Recalculer la position lors du redimensionnement du graphique
      int panelWidth = 300;
      int fontSize = 12;
      int lineHeight = fontSize + 4;

      // Compter les lignes en vérifiant les labels existants
      int lineCount = 0;
      for(int i = 0; i < 100; i++)
        {
         string labelName = "NewsAlertText_" + IntegerToString(i);
         if(ObjectFind(0, labelName) < 0)
            break;
         lineCount++;
        }

      int panelHeight = lineCount * lineHeight + 20;
      int xPos = (chartWidth - panelWidth) / 2;
      int yPos = (chartHeight - panelHeight) / 2;

      ObjectSetInteger(0, "NewsAlertPanel", OBJPROP_XDISTANCE, xPos);
      ObjectSetInteger(0, "NewsAlertPanel", OBJPROP_YDISTANCE, yPos);
      ObjectSetInteger(0, "NewsAlertPanel", OBJPROP_YSIZE, panelHeight);

      // Repositionner chaque label
      for(int i = 0; i < lineCount +1; i++)
        {
         string labelName = "NewsAlertText_" + IntegerToString(i);
         ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, xPos + 10);
         ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, yPos + 10 + i * lineHeight);
        }

      ObjectSetInteger(0, "NewsAlertBackground", OBJPROP_XSIZE, chartWidth);
      ObjectSetInteger(0, "NewsAlertBackground", OBJPROP_YSIZE, chartHeight);


      // Compter les lignes en vérifiant les labels existants
      lineCount = 0;
      for(int i = 0; i < 100; i++)
        {
         string labelName = "WarningAlertText_" + IntegerToString(i);
         if(ObjectFind(0, labelName) < 0)
            break;
         lineCount++;
        }

      panelHeight = lineCount * lineHeight + 20;
      xPos = (chartWidth - panelWidth) / 2;
      yPos = 0;

      ObjectSetInteger(0, "WarningAlertPanel", OBJPROP_XDISTANCE, xPos);
      ObjectSetInteger(0, "WarningAlertPanel", OBJPROP_YDISTANCE, yPos);
      ObjectSetInteger(0, "WarningAlertPanel", OBJPROP_YSIZE, panelHeight);

      // Repositionner chaque label
      for(int i = 0; i < lineCount +1; i++)
        {
         string labelName = "WarningAlertText_" + IntegerToString(i);
         ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, xPos + 10);
         ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, yPos + 10 + i * lineHeight);
        }

     }


//if(GaugeCalcLocation(g0)==true)
//  {
//   GaugeRelocation(g0);
//  }
  }

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Tick-level early break-even — runs on every tick.               |
//| Moves SL to break-even once price reaches inpBreakEvenRatio of  |
//| the TP1 distance, regardless of whether TP1 was previously hit. |
//+------------------------------------------------------------------+
void applyEarlyBreakEven(int i)
  {
   if(!inpEarlyBreakEven)
      return;
   if(!PositionSelectByTicket(obBuffer[i].tradeTicket))
      return;

   if(obBuffer[i].isBear == false)
     {
      if(obBuffer[i].stopLoss >= obBuffer[i].entryPrice)
         return;   // already at break-even or better
      if(obBuffer[i].fib127 <= obBuffer[i].entryPrice)
         return;   // fib levels not set yet
      double beThreshold = obBuffer[i].entryPrice +
                           inpBreakEvenRatio * (obBuffer[i].fib127 - obBuffer[i].entryPrice);
      double bidNow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double newSL  = NormalizeDouble(obBuffer[i].entryPrice + 20 * _Point, _Digits);
      if(bidNow >= beThreshold &&
         IsValidStopLevels(obBuffer[i].tradeTicket, newSL, obBuffer[i].takeProfit))
        {
         obBuffer[i].stopLoss = newSL;
         Print(T("Early BE BUY ") + obBuffer[i].name + " SL -> " + DoubleToString(newSL, _Digits));
         obj_Trade.PositionModify(obBuffer[i].tradeTicket, newSL, obBuffer[i].takeProfit);
        }
     }
   else
     {
      if(obBuffer[i].stopLoss <= obBuffer[i].entryPrice)
         return;
      if(obBuffer[i].fib127 >= obBuffer[i].entryPrice)
         return;
      double beThreshold = obBuffer[i].entryPrice -
                           inpBreakEvenRatio * (obBuffer[i].entryPrice - obBuffer[i].fib127);
      double askNow = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double newSL  = NormalizeDouble(obBuffer[i].entryPrice - 20 * _Point, _Digits);
      if(askNow <= beThreshold &&
         IsValidStopLevels(obBuffer[i].tradeTicket, newSL, obBuffer[i].takeProfit))
        {
         obBuffer[i].stopLoss = newSL;
         Print(T("Early BE SELL ") + obBuffer[i].name + " SL -> " + DoubleToString(newSL, _Digits));
         obj_Trade.PositionModify(obBuffer[i].tradeTicket, newSL, obBuffer[i].takeProfit);
        }
     }
  }

void upgradeCurrentOrder(int i)
  {
// #42: Ensure ADX indicator arrays are current for this bar
   getAdx();

   int stopLevel              = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDistance     = stopLevel * _Point;

   if(PositionSelectByTicket(obBuffer[i].tradeTicket) == false)
     {
      // Pending order not yet triggered â nothing to manage yet
      if(OrderSelect(obBuffer[i].tradeTicket))
         return;
      return;
     }

   double profit              = PositionGetDouble(POSITION_PROFIT);

   double currentPrice = (obBuffer[i].isBear == false) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(maxGain == false)
     {
      return ;
     }


   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY &&
      plusDI[0] > minusDI[0] &&
      adx[0] > 25 &&
      (trend == TREND_RANGE || trend == TREND_BULLISH) &&
      obBuffer[i].isBear == false)
     {

      // BREAK EVEN enable protection
      if(enableProtection == true)
        {
         if(currentPrice > obBuffer[i].fib100 &&
            obBuffer[i].cross127   == true &&
            obBuffer[i].cross50    == true &&
            obBuffer[i].stopLoss   < obBuffer[i].mitigatedLine &&
            IsValidStopLevels(obBuffer[i].tradeTicket, obBuffer[i].stopLoss,obBuffer[i].takeProfit) == true)
           {
            obBuffer[i].stopLoss    = obBuffer[i].entryPrice + (30 *  _Point);
            Print(T("Activate protection ") + obBuffer[i].name + " tp  " + DoubleToString(obBuffer[i].takeProfit));
            obBuffer[i].entryPrice = getPriceNormalizedbySymbol(obBuffer[i].entryPrice);
            obBuffer[i].stopLoss    = getPriceNormalizedbySymbol(obBuffer[i].stopLoss);
            obBuffer[i].takeProfit    = getPriceNormalizedbySymbol(obBuffer[i].takeProfit);
            obj_Trade.PositionModify(obBuffer[i].tradeTicket,obBuffer[i].stopLoss, obBuffer[i].takeProfit);
            return;
           }
        }

      if(currentPrice > obBuffer[i].fib100 &&
         obBuffer[i].takeProfit == obBuffer[i].fib127 &&
         obBuffer[i].cross161   == true &&
         IsValidStopLevels(obBuffer[i].tradeTicket, obBuffer[i].stopLoss,obBuffer[i].fib1618) == true)
        {
         obBuffer[i].takeProfit  = obBuffer[i].fib1618;
         Print(T("Upgrade 161 ") + obBuffer[i].name + " tp  " + DoubleToString(obBuffer[i].takeProfit));
         obBuffer[i].reason = ENUM_REASON_TRADE_UPGRADE_161;
         obBuffer[i].entryPrice = getPriceNormalizedbySymbol(obBuffer[i].entryPrice);
         obBuffer[i].stopLoss    = getPriceNormalizedbySymbol(obBuffer[i].stopLoss);
         obBuffer[i].takeProfit    = getPriceNormalizedbySymbol(obBuffer[i].takeProfit);
         obj_Trade.PositionModify(obBuffer[i].tradeTicket,obBuffer[i].stopLoss, obBuffer[i].takeProfit);
         if(obBuffer[i].DoTrailing == false  &&
            enableTrailingStop == true)
           {
            obBuffer[i].DoTrailing = true;
           }
         tp127 = tp127+1;
         return;
        }
      if(currentPrice > obBuffer[i].fib140 &&
         obBuffer[i].takeProfit == obBuffer[i].fib1618 &&
         obBuffer[i].cross50    == true &&
         obBuffer[i].stopLoss   <= obBuffer[i].fib127 &&
         IsValidStopLevels(obBuffer[i].tradeTicket, obBuffer[i].stopLoss,obBuffer[i].fib23812) == true)
        {


         obBuffer[i].takeProfit  = obBuffer[i].fib23812;
         obBuffer[i].reason = ENUM_REASON_TRADE_UPGRADE_238;
         obBuffer[i].entryPrice = getPriceNormalizedbySymbol(obBuffer[i].entryPrice);
         obBuffer[i].stopLoss    = getPriceNormalizedbySymbol(obBuffer[i].stopLoss);
         obBuffer[i].takeProfit    = getPriceNormalizedbySymbol(obBuffer[i].takeProfit);
         obj_Trade.PositionModify(obBuffer[i].tradeTicket,obBuffer[i].stopLoss, obBuffer[i].takeProfit);
         if(obBuffer[i].DoTrailing == false  &&
            enableTrailingStop == true)
           {
            obBuffer[i].DoTrailing = true;
           }
         Print(T("Upgrade 238 ") + obBuffer[i].name + " tp  " + DoubleToString(obBuffer[i].takeProfit));
         tp161 = tp161+1;
         return;
        }

      if(currentPrice > obBuffer[i].fib200 && obBuffer[i].DoTrailing == false &&
         IsValidStopLevels(obBuffer[i].tradeTicket, obBuffer[i].stopLoss,0.0) == true)
        {
         obBuffer[i].takeProfit = getPriceNormalizedbySymbol(0.0);
         obBuffer[i].stopLoss    = getPriceNormalizedbySymbol(obBuffer[i].stopLoss);
         obj_Trade.PositionModify(obBuffer[i].tradeTicket,obBuffer[i].stopLoss, obBuffer[i].takeProfit);
         if(obBuffer[i].DoTrailing == false  &&
            enableTrailingStop == true)
           {
            obBuffer[i].DoTrailing = true;
           }
         Print("LET GO " + DoubleToString(obBuffer[i].fib200));
         tp238 = tp238 + 1;
         return;
        }
     }

   /**********************************************************
   *
   *              SELLL STOP
   *
   ***********************************************************/

   if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL &&
      plusDI[0] < minusDI[0] &&
      adx[0] > 25 &&
      (trend == TREND_RANGE || trend == TREND_BEARISH) &&
      obBuffer[i].isBear == true)
     {
      // Activate Protection
      if(enableProtection == true)
        {
         if(currentPrice < obBuffer[i].fib80 &&
            obBuffer[i].takeProfit  == obBuffer[i].fib1618 &&
            obBuffer[i].cross127    == true &&
            obBuffer[i].cross50     == true &&
            obBuffer[i].stopLoss    > obBuffer[i].mitigatedLine &&
            IsValidStopLevels(obBuffer[i].tradeTicket, obBuffer[i].stopLoss,obBuffer[i].takeProfit) == true)
           {

            obBuffer[i].stopLoss    = obBuffer[i].entryPrice - (30 *  _Point);
            obBuffer[i].entryPrice = getPriceNormalizedbySymbol(obBuffer[i].entryPrice);
            obBuffer[i].stopLoss    = getPriceNormalizedbySymbol(obBuffer[i].stopLoss);
            obBuffer[i].takeProfit    = getPriceNormalizedbySymbol(obBuffer[i].takeProfit);
            Print(T("Activate protection ") + obBuffer[i].name + " tp  " + DoubleToString(obBuffer[i].takeProfit));
            obj_Trade.PositionModify(obBuffer[i].tradeTicket,obBuffer[i].stopLoss, obBuffer[i].takeProfit);
            return;
           }
        }

      if(currentPrice < obBuffer[i].fib100 &&
         obBuffer[i].takeProfit == obBuffer[i].fib127 &&
         obBuffer[i].cross161   == true &&
         IsValidStopLevels(obBuffer[i].tradeTicket, obBuffer[i].stopLoss,obBuffer[i].fib1618) == true)
        {

         //obBuffer[i].stopLoss    = obBuffer[i].fibn027;
         obBuffer[i].takeProfit  = obBuffer[i].fib1618;
         obBuffer[i].reason = ENUM_REASON_TRADE_UPGRADE_161;
         obBuffer[i].entryPrice = getPriceNormalizedbySymbol(obBuffer[i].entryPrice);
         obBuffer[i].stopLoss    = getPriceNormalizedbySymbol(obBuffer[i].stopLoss);
         obBuffer[i].takeProfit    = getPriceNormalizedbySymbol(obBuffer[i].takeProfit);
         Print(T("Upgrade 161 ") + obBuffer[i].name + " tp  " + DoubleToString(obBuffer[i].takeProfit));
         obj_Trade.PositionModify(obBuffer[i].tradeTicket,obBuffer[i].stopLoss, obBuffer[i].takeProfit);
         if(obBuffer[i].DoTrailing == false  &&
            enableTrailingStop == true)
           {
            obBuffer[i].DoTrailing = true;
           }
         tp127 = tp127 + 1;
         return;
        }

      if(currentPrice < obBuffer[i].fib140 &&
         obBuffer[i].takeProfit == obBuffer[i].fib1618 &&
         obBuffer[i].cross50    == true &&
         obBuffer[i].stopLoss   >= obBuffer[i].fib127 &&
         IsValidStopLevels(obBuffer[i].tradeTicket, obBuffer[i].stopLoss,obBuffer[i].fib23812) == true)
        {
         // obBuffer[i].stopLoss    = obBuffer[i].entryPrice - 15 * Point();
         obBuffer[i].takeProfit  = obBuffer[i].fib23812;
         obBuffer[i].reason = ENUM_REASON_TRADE_UPGRADE_238;
         obBuffer[i].entryPrice = getPriceNormalizedbySymbol(obBuffer[i].entryPrice);
         obBuffer[i].stopLoss    = getPriceNormalizedbySymbol(obBuffer[i].stopLoss);
         obBuffer[i].takeProfit    = getPriceNormalizedbySymbol(obBuffer[i].takeProfit);
         Print(T("Upgrade 238") + obBuffer[i].name + " tp  " + DoubleToString(obBuffer[i].takeProfit));
         obj_Trade.PositionModify(obBuffer[i].tradeTicket,obBuffer[i].stopLoss, obBuffer[i].takeProfit);
         if(obBuffer[i].DoTrailing == false  &&
            enableTrailingStop == true)
           {
            obBuffer[i].DoTrailing = true;
           }
         tp161 = tp161 + 1;
         return;
        }

      if(currentPrice < obBuffer[i].fib200 && obBuffer[i].DoTrailing == false &&
         IsValidStopLevels(obBuffer[i].tradeTicket, obBuffer[i].stopLoss,0.0) == true)
        {
         Print("LET's GO " + DoubleToString(obBuffer[i].fib200));
         obBuffer[i].takeProfit = getPriceNormalizedbySymbol(0.0);
         obBuffer[i].entryPrice = getPriceNormalizedbySymbol(obBuffer[i].entryPrice);
         obBuffer[i].stopLoss    = getPriceNormalizedbySymbol(obBuffer[i].stopLoss);
         obj_Trade.PositionModify(obBuffer[i].tradeTicket,obBuffer[i].stopLoss, obBuffer[i].takeProfit);
         if(obBuffer[i].DoTrailing == false  &&
            enableTrailingStop == true)
           {
            obBuffer[i].DoTrailing = true;
           }
         tp238 = tp238 + 1;
         return;
        }
     }


  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void detectBOS(int length = 60)
  {
   isNuBar();

   int right_index, left_index;
   bool isSwingHigh = true, isSwingLow = true;
   int curr_bar = length;

   if(isNewBar)
     {
      for(int j=1; j<=length; j++)
        {
         right_index = curr_bar - j;
         left_index = curr_bar + j;
         if((high(curr_bar) <= high(right_index)) || (high(curr_bar) < high(left_index)))
           {
            isSwingHigh = false;
           }
         if((low(curr_bar) >= low(right_index)) || (low(curr_bar) > low(left_index)))
           {
            isSwingLow = false;
           }
        }


      if(isSwingHigh)
        {
         int size  = ArraySize(bosBuffer);
         ArrayResize(bosBuffer, size + 1);
         bosBuffer[size].startTime = iTime(_Symbol,CTOB,curr_bar);
         bosBuffer[size].priceLevel = high(curr_bar);
         bosBuffer[size].isBear     = false;
         drawSwingPoint("ICT_" + TimeToString(time(curr_bar)),time(curr_bar),high(curr_bar),77,clrBlue,-1);
        }
      if(isSwingLow)
        {
         int size  = ArraySize(bosBuffer);
         ArrayResize(bosBuffer, size + 1);
         bosBuffer[size].startTime = iTime(_Symbol,CTOB,curr_bar);
         bosBuffer[size].priceLevel = low(curr_bar);
         bosBuffer[size].isBear     = true;
         drawSwingPoint("ICT_" + TimeToString(time(curr_bar)),time(curr_bar),low(curr_bar),77,clrRed,1);
        }

      for(int a = 0 ; a < ArraySize(bosBuffer);a++)
        {
         if(bosBuffer[a].breakTime != NULL)
            continue;
         if(bosBuffer[a].priceLevel > 0 && bosBuffer[a].isBear == false)
           {
            int startIndex = iBarShift(_Symbol,CTOB,bosBuffer[a].startTime);
            for(int i = startIndex -1; i >= 0 ; i--)
              {
               double hh = high(i);
               if(hh >= bosBuffer[a].priceLevel)
                 {
                  bosBuffer[a].breakTime = iTime(_Symbol,CTOB,i);
                  drawBreakLevel("ICT_" + "OB-break" + TimeToString(bosBuffer[a].startTime),bosBuffer[a].startTime,bosBuffer[a].priceLevel,
                                 bosBuffer[a].breakTime,bosBuffer[a].priceLevel,clrBlue,-1);
                  break;
                 }
              }
           }
         if(bosBuffer[a].priceLevel > 0 && bosBuffer[a].isBear == true)
           {
            int startIndex = iBarShift(_Symbol,CTOB,bosBuffer[a].startTime);
            for(int i = startIndex -1; i >= 0 ; i--)
              {
               double ll = low(i);
               if(ll <= bosBuffer[a].priceLevel)
                 {
                  bosBuffer[a].breakTime = iTime(_Symbol,CTOB,i);
                  drawBreakLevel("ICT_" + "OB-break" + TimeToString(bosBuffer[a].startTime),bosBuffer[a].startTime,bosBuffer[a].priceLevel,
                                 bosBuffer[a].breakTime,bosBuffer[a].priceLevel,clrRed,-1);
                  break;
                 }
              }
           }
        }
     }

   return;

  }

//+-------------------------  -----------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void detectTrend()
  {
   switch(mHTFTrend)
     {
      case TREND_BEARISH :
         trendD = "Bearish";
         trendDirection = -1;
         break;
      case TREND_BULLISH :
         trendD = "Bullish";
         trendDirection = 1;
         break;
      case TREND_RANGE:
         trendD = "Range";
         trendDirection = 0;
         break;
      default:
         trendD = "Unkown";
         trendDirection = 0;
         break;
     }
   trendD = "\nTrend HTF (" + EnumToString(HTOB) + ") : " + trendD +
            "\nTrend Daily " + EnumToString(DailyTrend);
   trendDirection = 0;

  }


//+------------------------------------------------------------------+
//|       Detection for current time frame                           |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Replay the last N bars through detectNewOB so any OBs that formed
//| before the EA started are loaded into obBuffer at init time.      |
//+------------------------------------------------------------------+
void scanHistoricalCandles(int lookback)
  {
   if(lookback <= 0)
      return;

// Save and restore rA so the live tick path is unaffected
   MqlRates savedRA[5];
   for(int k = 0; k < 5; k++)
      savedRA[k] = rA[k];
   gHistoricalScan = true;

// Scan from oldest to newest so duplicate guards work correctly
   for(int shift = lookback - 1; shift >= 0; shift--)
     {
      if(CopyRates(_Symbol, CTOB, shift, 5, rA) < 5)
         continue;
      detectNewOB();
     }

   gHistoricalScan = false;
   for(int k = 0; k < 5; k++)
      rA[k] = savedRA[k];
  }

//+------------------------------------------------------------------+
//| GPU_ScanHistoricalCandles                                         |
//| Replaces scanHistoricalCandles when a GPU is available.           |
//| Uses Kernel 1 (detect_ob_patterns) to evaluate all shifts in      |
//| parallel — only calls CopyRates+detectNewOB for pattern hits,     |
//| skipping the ~98% of shifts that carry no OB signal.              |
//| Falls back to scanHistoricalCandles() if GPU is unavailable.      |
//+------------------------------------------------------------------+
void GPU_ScanHistoricalCandles(int lookback)
  {
   if(g_clKernelOBScan == INVALID_HANDLE)
     {
      scanHistoricalCandles(lookback);
      return;
     }
   if(lookback <= 0) return;

   int total_bars = lookback + 5;

   // 1. Fetch all bars at once (single CopyRates instead of lookback calls)
   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   if(CopyRates(_Symbol, CTOB, 0, total_bars, bars) < total_bars)
     {
      scanHistoricalCandles(lookback);
      return;
     }

   // 2. Unpack open/close into flat double arrays for GPU
   double open_a[], close_a[];
   ArrayResize(open_a,  total_bars);
   ArrayResize(close_a, total_bars);
   for(int j = 0; j < total_bars; j++)
     {
      open_a[j]  = bars[j].open;
      close_a[j] = bars[j].close;
     }

   // 3. Create GPU buffers
   uint dbl_sz = (uint)(total_bars * sizeof(double));
   uint int_sz = (uint)(lookback   * sizeof(int));
   int cl_open  = CLBufferCreate(g_clContext, dbl_sz, CL_MEM_READ_WRITE);
   int cl_close = CLBufferCreate(g_clContext, dbl_sz, CL_MEM_READ_WRITE);
   int cl_bull  = CLBufferCreate(g_clContext, int_sz, CL_MEM_READ_WRITE);
   int cl_bear  = CLBufferCreate(g_clContext, int_sz, CL_MEM_READ_WRITE);

   if(cl_open == INVALID_HANDLE || cl_close == INVALID_HANDLE ||
      cl_bull == INVALID_HANDLE || cl_bear  == INVALID_HANDLE)
     {
      if(cl_open  != INVALID_HANDLE) CLBufferFree(cl_open);
      if(cl_close != INVALID_HANDLE) CLBufferFree(cl_close);
      if(cl_bull  != INVALID_HANDLE) CLBufferFree(cl_bull);
      if(cl_bear  != INVALID_HANDLE) CLBufferFree(cl_bear);
      scanHistoricalCandles(lookback);
      return;
     }

   // 4. Upload data — new MT5 API: data array is 2nd param (was 3rd)
   CLBufferWrite(cl_open,  open_a,  0, 0, total_bars);
   CLBufferWrite(cl_close, close_a, 0, 0, total_bars);

   CLSetKernelArgMem(g_clKernelOBScan, 0, cl_open);
   CLSetKernelArgMem(g_clKernelOBScan, 1, cl_close);
   CLSetKernelArg   (g_clKernelOBScan, 2, (int)total_bars);
   CLSetKernelArg   (g_clKernelOBScan, 3, (int)typeOfTrade);
   CLSetKernelArgMem(g_clKernelOBScan, 4, cl_bull);
   CLSetKernelArgMem(g_clKernelOBScan, 5, cl_bear);

   uint cl_offset[1] = {0};
   uint cl_size[1]   = {(uint)lookback};
   CLExecute(g_clKernelOBScan, 1, cl_offset, cl_size);

   // 5. Read hit bitmap — new MT5 API: data array is 2nd param (was 3rd)
   int bull_hits[], bear_hits[];
   ArrayResize(bull_hits, lookback);
   ArrayResize(bear_hits, lookback);
   CLBufferRead(cl_bull, bull_hits, 0, 0, lookback);
   CLBufferRead(cl_bear, bear_hits, 0, 0, lookback);

   CLBufferFree(cl_open);
   CLBufferFree(cl_close);
   CLBufferFree(cl_bull);
   CLBufferFree(cl_bear);

   // 6. Process only GPU hits (same scan order: lookback-1 → 0)
   MqlRates savedRA[5];
   for(int k = 0; k < 5; k++) savedRA[k] = rA[k];
   gHistoricalScan = true;

   for(int shift = lookback - 1; shift >= 0; shift--)
     {
      if(bull_hits[shift] == 0 && bear_hits[shift] == 0)
         continue;  // no OB pattern at this shift — skip CopyRates entirely
      if(CopyRates(_Symbol, CTOB, shift, 5, rA) < 5)
         continue;
      detectNewOB();
     }

   gHistoricalScan = false;
   for(int k = 0; k < 5; k++) rA[k] = savedRA[k];
  }

//+------------------------------------------------------------------+
void detectNewOB()
  {
// Pre-flight: KZ check once for both directions
   if(g_kzEnabled)
     {
      MqlDateTime gmt;
      TimeToStruct(rA[1].time, gmt);
      bool inKZ = (gmt.hour >= g_kz1Start && gmt.hour <= g_kz1End) ||
                  (gmt.hour >= g_kz2Start && gmt.hour <= g_kz2End);
      if(!inKZ) return;
     }

// bullish mode
   if(typeOfTrade == BUY_STOP  || typeOfTrade == BOTH)
     {
      if(
         rA[1].close < rA[1].open &&   // last candle bearish
         rA[2].close > rA[2].open && // first candle bullish
         rA[3].close > rA[2].close) // second candle has to close higher than first bull
        {

         // Duplicate guard: skip if a bullish OB from this candle already exists
         bool bullDup = false;
         for(int k = 0; k < ArraySize(obBuffer); k++)
            if(obBuffer[k].startTime == rA[1].time && obBuffer[k].isBear == false)
              { bullDup = true; break; }
         if(bullDup)
            return;

         // Volume confirmation: OB candle volume must exceed recent 3-bar average
         if(inpVolumeFilter)
           {
            double avgVol = (rA[2].tick_volume + rA[3].tick_volume + rA[4].tick_volume) / 3.0;
            if(rA[1].tick_volume < avgVol * inpVolumeMinMult)
               return;
           }

         // HTF trend check before allocating slot
         if(mHTFTrend == TREND_BEARISH && isRangeTradingOK == false) return;

         int i = ArraySize(obBuffer);
         ArrayResize(obBuffer,i + 1);
         obBuffer[i].init(i,rA[1].time, rA[1].high, rA[1].low, rA[3].low, rA[1].high,  false);
         ExportOBEvent("DETECTED", i);
         totalOb = totalOb + 1;
         obBuffer[i].addStars();
         obBuffer[i].checkInZone();
        }
     }
//  bearish OB
   if(typeOfTrade == SELL_STOP  || typeOfTrade == BOTH /*|| typeOfTrade == DAILY_BIAS */)
     {


      if(
         rA[1].close > rA[1].open &&   // last candle bullish
         rA[2].close < rA[2].open && // first candle bearish
         rA[3].close < rA[2].close)  // second candle has to close higher than first bear
        {

         // Duplicate guard: skip if a bearish OB from this candle already exists
         bool bearDup = false;
         for(int k = 0; k < ArraySize(obBuffer); k++)
            if(obBuffer[k].startTime == rA[1].time && obBuffer[k].isBear == true)
              { bearDup = true; break; }
         if(bearDup)
            return;

         // Volume confirmation: OB candle volume must exceed recent 3-bar average
         if(inpVolumeFilter)
           {
            double avgVol = (rA[2].tick_volume + rA[3].tick_volume + rA[4].tick_volume) / 3.0;
            if(rA[1].tick_volume < avgVol * inpVolumeMinMult)
               return;
           }

         // HTF trend check before allocating slot
         if(mHTFTrend == TREND_BULLISH && isRangeTradingOK == false) return;

         int i = ArraySize(obBuffer);
         ArrayResize(obBuffer,i + 1);

         obBuffer[i].init(i,rA[1].time, rA[1].high, rA[1].low, rA[1].low, rA[3].high, true,clrRed);
         ExportOBEvent("DETECTED", i);
         totalOb = totalOb + 1;
         obBuffer[i].addStars();

         obBuffer[i].checkInZone();
        }
     }
   return;
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void cleanOBBuffer(int b = -1)
  {
// #37 Fast-path: nothing to clean
   if(b == -1 && ArraySize(obBuffer) == 0)
      return;

   if(b > -1 && hasOnGoingPosition(b) == false)
     {
      g_reasonCounters[(int)obBuffer[b].reason]++;
      g_finalCheckList[(int)obBuffer[b].finalCheck]++;
      cleanObjects(b);
      sql.updateOB(obBuffer[b]);
      ExportOBCloseWithOutcome(b);
      ArrayRemove(obBuffer,b, 1);
      return;
     }

// OPTI: iterate backwards so ArrayRemove(i) never skips an element
   for(int i = ArraySize(obBuffer) - 1; i >= 0; i--)
     {
      if(obBuffer[i].stars < 1 ||
         (obBuffer[i].isDone == true && hasOnGoingPosition(i) == false))
        {
         g_reasonCounters[(int)obBuffer[i].reason]++;
         g_finalCheckList[(int)obBuffer[i].finalCheck]++;
         cleanObjects(i);
         obBuffer[i].reason = ENUM_REASON_ISDONE;
         drawReason(i);
         sql.updateOB(obBuffer[i]);
         ExportOBCloseWithOutcome(i);
         ArrayRemove(obBuffer,i, 1);
         continue;
        }
      int totalCandles = CountBarsSince(obBuffer[i].startTime, _Symbol, CTOB);
      if(totalCandles >= outdatedOB && hasOnGoingPosition(i) == false)
        {
         obBuffer[i].reason = ENUM_REASON_IS_OVERDUE;
         g_reasonCounters[(int)obBuffer[i].reason]++;
         g_finalCheckList[(int)obBuffer[i].finalCheck]++;
         obBuffer[i].isDone = true;
         drawReason(i);
         cleanObjects(i);
         sql.updateOB(obBuffer[i]);
         ExportOBCloseWithOutcome(i);
         ArrayRemove(obBuffer,i, 1);
         continue;
        }
     }
  }


//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void checkFibRehearsal(int i, double lastPrice = 0.0)
  {

   if(obBuffer[i].isMitigated == true ||
      obBuffer[i].isDone == true ||
      obBuffer[i].isMSS == false ||
      timeToTradeBl == false
     )
     {
      return;
     }

   int stopLevel           = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minStopDistance  = (stopLevel + (stopLevel / 2) + 1) * _Point;
   double AtrStopLoss      = (getAtr() * ATR_multiplier) * _Point;
   int OBcolor             = (obBuffer[i].isBear == false) ? clrBlue : clrRed;
   tradeType OBTradeType         = (obBuffer[i].isBear == false) ? BUY_STOP : SELL_STOP;
   double OBPriceAction    = (obBuffer[i].isBear == false) ? askPrice + spread : bidPrice - spread;

   if(typeOfTrade == BOTH || typeOfTrade == OBTradeType)
     {
      if(crossed(i, OBPriceAction, obBuffer[i].fib127) == true &&
         obBuffer[i].cross127 == false)
        {
         obBuffer[i].cross127 = true;
        }
      if(crossed(i, OBPriceAction, obBuffer[i].fib1618) == true  &&
         obBuffer[i].cross161== false)
        {
         obBuffer[i].cross161= true;
        }

      if(crossed(i, OBPriceAction, obBuffer[i].fib23812) == true  &&
         obBuffer[i].cross238== false)
        {
         obBuffer[i].cross238 = true;
        }
      //
      //      if(isCounterHTFTrend(i) == true)
      //           return;

      if(obBuffer[i].isAllGood(i) == false)
         return;

      obBuffer[i].OBcolor = clrGreen;
      // #39: only set waiting-reason while no order has been placed yet
      if(obBuffer[i].tradeTicket == INVALID_TICKET)
         obBuffer[i].reason = (inpEntryMode == ENUM_EM_AUTO || inpEntryMode == ENUM_EM_CISD)
                              ? ENUM_REASON_WAIT_AUTO_ENTRY
                              : ENUM_REASON_NOT_CROSSED_50;
      setOBOrder(i);
     }
  }



//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool checkMitigated(int i, double lastPrice = 0.0)
  {
   if(obBuffer[i].isMitigated == true)
     {
      if(inpAllowMitigatedReentry == true)
        {
         // Expire re-entry window after 20 bars to avoid performance hit
         int barsSinceMit = CountBarsSince(obBuffer[i].mitigatedTime, _Symbol, CTOB);
         if(barsSinceMit > 20)
           {
            obBuffer[i].isDone = true;
            return true;
           }
         // Check recovery only on new bar (skip mid-bar noise)
         if(isNewBar)
           {
            bool momentumOK = false;
            if(obBuffer[i].isBear == false)  // bullish: recover above mitigation line
               momentumOK = (bidPrice > obBuffer[i].mitigatedLine && isBullishCandle(1));
            else                              // bearish: recover below mitigation line
               momentumOK = (askPrice < obBuffer[i].mitigatedLine && !isBullishCandle(1));
            if(momentumOK)
              {
               obBuffer[i].isMitigated = false;
               obBuffer[i].isDone      = false;
               obBuffer[i].OBcolor     = (obBuffer[i].isBear == false) ? clrBlue : clrRed;
               DrawOB(i);
               return false;
              }
           }
        }
      return true;
     }

   MitigatedDL mode =    MitigatedMode;

   if(obBuffer[i].isBear == false &&
      bidPrice <= obBuffer[i].mitigatedLine && // #41: use bid (lower price) for bullish mitigation
      mode == OB_MITIGATED_MIDLINE)
     {
      obBuffer[i].isMitigated = true;
     }

   if(obBuffer[i].isBear == false &&
      bidPrice <= obBuffer[i].highPrice && // #41
      mode == OB_MITIGATED_HIGH)
     {
      obBuffer[i].isMitigated = true;
     }

   if(obBuffer[i].isBear == false &&
      bidPrice <= obBuffer[i].lowPrice && // #41
      mode == OB_MITIGATED_LOW)
     {
      obBuffer[i].isMitigated = true;
     }

   if(obBuffer[i].isBear == true &&
      askPrice >= obBuffer[i].mitigatedLine && // #41: use ask (higher price) for bearish mitigation
      mode == OB_MITIGATED_MIDLINE)
     {
      obBuffer[i].isMitigated = true;
     }

   if(obBuffer[i].isBear == true &&
      askPrice >= obBuffer[i].lowPrice && // #41
      mode == OB_MITIGATED_HIGH)
     {
      obBuffer[i].isMitigated = true;
     }

   if(obBuffer[i].isBear == true &&
      askPrice >= obBuffer[i].highPrice && // #41
      mode == OB_MITIGATED_LOW)
     {
      obBuffer[i].isMitigated = true;
     }

   if(obBuffer[i].isMitigated == true)
     {
      obBuffer[i].OBcolor = clrGray;
      obBuffer[i].isMitigated = true;
      obBuffer[i].reason = ENUM_REASON_ISMITIGATED;
      obBuffer[i].mitigatedTime = iTime(_Symbol,CTOB,0);
      obBuffer[i].stars   = 0;
      obBuffer[i].finalCheck = 2;
      DrawOB(i);
      drawReason(i);
      if(inpAllowMitigatedReentry == false)
         obBuffer[i].isDone = true;
      if(obBuffer[i].tradeTicket != INVALID_TICKET)
        {
         CancelPendingIfExists(obBuffer[i].tradeTicket);
         obBuffer[i].tradeTicket = INVALID_TICKET;
        }
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
  {
// Check if this is a deal transaction
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      // Get deal properties
      ulong dealTicket = trans.deal;
      if(HistoryDealSelect(dealTicket))
        {
         long dealType = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
         long dealReason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
         double profit     = HistoryDealGetDouble(dealTicket,DEAL_PROFIT);
         string dealSymbol = HistoryDealGetString(dealTicket,DEAL_SYMBOL);
         ulong position_id = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
         long   magic       = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);

         // Export trade outcome directly from deal — fires in both backtest and live
         if(dealSymbol == _Symbol && magic == uniqueMagicNumber &&
            (dealReason == DEAL_REASON_SL || dealReason == DEAL_REASON_TP))
           {
            int ob_idx = getOBbyDealTicket(position_id);
            if(ob_idx >= 0)
              {
               string ev_outcome = (profit >= 0.0) ? "WIN" : "LOSS";
               double risk = MathAbs(obBuffer[ob_idx].entryPrice - obBuffer[ob_idx].stopLoss)
                             * obBuffer[ob_idx].lotSize
                             * SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE)
                             / SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
               double r_mult = (risk > 0) ? profit / risk : 0.0;
               ExportOBEvent("CLOSED", ob_idx, ev_outcome, r_mult);
               // OPTI: reset ticket so hasOnGoingPosition() returns false immediately
               obBuffer[ob_idx].tradeTicket = INVALID_TICKET;
              }
           }

         // Check if position was closed by stoploss
         if(dealSymbol == _Symbol && enableScreenshot == true && magic == uniqueMagicNumber)
           {

            ChartRedraw(); // force redraw chart before take picture
            Sleep(1000); // just to be sure the arrow appears
            string filename = "";

            int j = 0;
            int macroTotal = ArraySize(macroP);
            if(macroTotal > 0)
              {

               for(j = 0 ; j < macroTotal; j++)
                 {
                  // A position is already created
                  if(macroP[j].macroTicket == dealTicket)
                     break;
                 }
              }
            int f = 0;
            switch((int)dealReason)
              {
               case DEAL_REASON_SL:
                  //saveFailedOBPatternToCSV(getHistoricOBCandle(getOBbyDealTicket(position_id)));
                  //HistoryForOBMeter();
                  ArrayRemove(macroP,j);
                  sendNotif("Trade ended with a " + ((profit > 0) ? "profit" : "loss") + " of " + DoubleToString(profit, 2));
                  filename = FolderName + "/" + _Symbol + "/sl/" + _Symbol + IntegerToString(dealTicket) + ".PNG";

                  break;

               case DEAL_REASON_TP:
                  //HistoryForOBMeter();
                  ArrayRemove(macroP,j);
                  filename = FolderName + "/" + _Symbol + "/tp/" + _Symbol + IntegerToString(dealTicket) + ".PNG";
                  sendNotif("Trade ended with a profit of " + DoubleToString(profit, 2));
                  break;
              }

            if(!MQLInfoInteger(MQL_TESTER) && ChartScreenShot(0, filename, ScreenshotWidth,ScreenshotHeight,ALIGN_CENTER))
              {
               Print("Screenshot saved: ", filename);
               cleanOBBuffer(getOBbyDealTicket(dealTicket));
              }
            else
              {
               Print("Failed to save screenshot. Error: ", GetLastError());
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Trailing stop function                                           |
//+------------------------------------------------------------------+
void applyTrailingStop(int obindex = -1)
  {
   if(obindex < 0)
      return;

   ulong ticket = obBuffer[obindex].tradeTicket;
   if(ticket == 0 || !obBuffer[obindex].DoTrailing)
      return;
   if(!PositionSelectByTicket(ticket))
      return;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return;
   if(uniqueMagicNumber != 0 && PositionGetInteger(POSITION_MAGIC) != uniqueMagicNumber)
      return;

   int    posType    = (int)PositionGetInteger(POSITION_TYPE);
   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL  = PositionGetDouble(POSITION_SL);
   double currentTP  = getPriceNormalizedbySymbol(obBuffer[obindex].takeProfit);

   int    stopLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = MathMax(stopLevel, 1) * _Point;

//--- Check tslTrigger: only activate TSL once price reaches the chosen level
   bool triggered = (tslTrigger == TLS_TRIGGER_ALWAYS);
   if(!triggered)
     {
      double trigPrice = 0.0;
      if(tslTrigger == TLS_TRIGGER_FIB127)  trigPrice = obBuffer[obindex].fib127;
      if(tslTrigger == TLS_TRIGGER_FIB161)  trigPrice = obBuffer[obindex].fib1618;
      if(tslTrigger == TLS_TRIGGER_FIB238)  trigPrice = obBuffer[obindex].fib23812;
      if(trigPrice > 0.0)
         triggered = (posType == POSITION_TYPE_BUY) ? (bidPrice >= trigPrice)
                     : (askPrice <= trigPrice);
     }
   if(!triggered)
      return;

//--- Calculate trailing distance in price units (distance from current price)
   double trailDist = 0.0;
   if(trailingStrat == ATR_BASED_TRAILING_STOP)
     {
      double atrVal = getAtr();
      if(atrVal <= 0.0)
         return;
      trailDist = ATR_multiplier * atrVal; // getAtr() returns price units — no extra _Point
      if(trailDist < minDist)
         trailDist = minDist;
     }
   else // CLASSIC_TRAILING_STOP
     {
      trailDist = trailingStopPoints * _Point;
      if(trailDist < minDist)
         trailDist = minDist;
     }

   double newSL = 0.0;

   if(posType == POSITION_TYPE_BUY)
     {
      // Trail SL from current bid — distance is from current price, not entry
      newSL = NormalizeDouble(bidPrice - trailDist, _Digits);
      // Only move SL upward; SL must be above entry (natural break-even once trailDist in profit)
      if(newSL <= currentSL || newSL <= entryPrice)
         return;
     }
   else // POSITION_TYPE_SELL
     {
      // Trail SL from current ask
      newSL = NormalizeDouble(askPrice + trailDist, _Digits);
      // Only move SL downward; SL must be below entry
      if((currentSL > 0.0 && newSL >= currentSL) || newSL >= entryPrice)
         return;
     }

   if(!IsValidStopLevels(ticket, newSL, currentTP))
      return;

   obj_Trade.PositionModify(ticket, getPriceNormalizedbySymbol(newSL), currentTP);
  }

//"SELECT id from orderblock WHERE startime = '2025.01.02 07:48' limit 1;" (length: 70)
// Close all positive trades
void ClosePositiveTrades()
  {

   if(clsPositiveTradeOnClose == false)
      return;

   int CloseMinutesBeforeMarketClose = 30 ; // In minutes
   MqlDateTime open;
   MqlDateTime close;
   MqlDateTime now;
   datetime openDT, closeDT;
   TimeToStruct(TimeCurrent(), now);
   bool sessionTrade = SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)now.day_of_week, 0, openDT, closeDT);

   TimeToStruct(openDT, open);
   TimeToStruct(closeDT, close);
   TimeToStruct(nowDT, now);

// Close only if within CloseMinutesBeforeMarketClose minutes before market close
   if(close.min - now.min <= CloseMinutesBeforeMarketClose &&
      now.hour == close.hour) // same hour
     {


      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(PositionSelectByTicket(ticket) && PositionGetInteger(POSITION_MAGIC) == uniqueMagicNumber)
           {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit > 0)
               obj_Trade.PositionClose(ticket);
           }
        }
     }

  }
//+------------------------------------------------------------------+
void OnTimer()
  {
   datetime now = Time();

   for(int i = 0; i < timerCount; i++)
     {
      if(now - timers[i].lastTriggered >= timers[i].intervalSeconds)
        {
         timers[i].lastTriggered = now;
         ExecuteTimer(timers[i].id); // Appelle la bonne fonction
        }
     }
  }
//+------------------------------------------------------------------+

//---------------------------------------------------------------------
//  The handler of the event of completion of another test pass:
//---------------------------------------------------------------------
double OnTester()
  {
   double totalTrades  = TesterStatistics(STAT_TRADES);
   double winTrades    = TesterStatistics(STAT_PROFIT_TRADES);
   double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
// STAT_BALANCE_DD_RELATIVE returns absolute dollar drawdown (not %) in this MT5 build.
// Divide by initial deposit for a conservative fractional estimate (slightly overstates real DD).
   double initialDepo  = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double relDD        = (initialDepo > 0) ? (TesterStatistics(STAT_BALANCE_DD_RELATIVE) / initialDepo) : 1.0;

   if(relDD >= (inpMaxTesterDD / 100.0))
     {
      Print("Drawdown ", DoubleToString(relDD * 100.0, 1), "% >= limit ",
            DoubleToString(inpMaxTesterDD, 1), "%. EA removed.");
      ExpertRemove();
     }

   if(totalTrades < 5)
      return 0;

   double winRate = winTrades / totalTrades;
   if(profitFactor <= 0.0)
      profitFactor = 0.0;
   if(profitFactor > 10.0)
      profitFactor = 10.0;

   double score = winRate * profitFactor * (1.0 - relDD) * MathLog10(totalTrades + 1.0);
   return NormalizeDouble(score, 4);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
LiquidityLevel DetectBuySideLiquidity(
   string symbol,
   ENUM_TIMEFRAMES tf,
   int lookbackBars = 10,
   int swingDepth   = 2,
   double tolerancePoints = 10
)
  {
   LiquidityLevel lvl;
   lvl.found = false;
   lvl.price = DBL_MAX;
   lvl.time  = 0;
   int lvlIndex = -1;

   lvlIndex = iHighest(_Symbol,tf, MODE_HIGH,lookbackBars,0);

   if(lvlIndex > 0)
     {
      lvl.time = time(lvlIndex, tf);
      lvl.price = high(lvlIndex, tf);
      lvl.found = true;
     }

   return lvl;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
LiquidityLevel DetectSellSideLiquidity(
   string symbol,
   ENUM_TIMEFRAMES tf,
   int lookbackBars = 10,
   int swingDepth   = 2,
   double tolerancePoints = 10
)
  {
   LiquidityLevel lvl;
   lvl.found = false;
   lvl.price = DBL_MIN;
   lvl.time  = 0;
   int lvlIndex = -1;

   lvlIndex = iLowest(_Symbol,tf, MODE_LOW,lookbackBars,0);

   if(lvlIndex > 0)
     {
      lvl.time = time(lvlIndex,tf);
      lvl.price = low(lvlIndex, tf);
      lvl.found = true;
     }

   return lvl;
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| FXTT_PivotPoints.mq5                                             |
//| Copyright 2026, Carlos Oliveira                                  |
//| https://www.forextradingtools.eu                                 |
//|                                                                  |
//| Draws classic/Fibonacci/Camarilla/Woodie/DeMark pivot levels     |
//| for Daily, Weekly (default) or Monthly periods.                  |
//| All resistance and support groups can be hidden independently.   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Carlos Oliveira"
#property link      "https://www.forextradingtools.eu/"
#property version   "1.0"
#property description "Configurable Pivot Points — Classic, Fibonacci, Camarilla, Woodie, DeMark"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+
enum ENUM_PIVOT_TIMEFRAME
  {
   PIVOT_TF_DAILY   = 0,  // Daily
   PIVOT_TF_WEEKLY  = 1,  // Weekly
   PIVOT_TF_MONTHLY = 2,  // Monthly
  };

enum ENUM_PIVOT_METHOD
  {
   PIVOT_METHOD_CLASSIC   = 0,  // Classic (Standard)
   PIVOT_METHOD_FIBONACCI = 1,  // Fibonacci
   PIVOT_METHOD_CAMARILLA = 2,  // Camarilla
   PIVOT_METHOD_WOODIE    = 3,  // Woodie
   PIVOT_METHOD_DEMARK    = 4,  // DeMark
  };

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input group "=== Pivot Settings ==="
input ENUM_PIVOT_TIMEFRAME InpPivotTF  = PIVOT_TF_WEEKLY;     // Pivot Timeframe
input ENUM_PIVOT_METHOD    InpMethod   = PIVOT_METHOD_CLASSIC; // Calculation Method
input int                  InpLookback = 3;                    // Historical Periods (1–50)

input group "=== Visibility ==="
input bool InpShowPP          = true;   // Show Pivot Point (PP)
input bool InpShowResistance  = true;   // Show Resistance Levels (R1–R4)
input bool InpShowSupport     = true;   // Show Support Levels (S1–S4)
input bool InpShowLabels      = true;   // Show Price Labels
input bool InpExtendRight     = true;   // Extend Current Period Lines to Right Edge

input group "=== Pivot Point Style ==="
input color           InpColorPP = C'140,140,140'; // PP Color
input ENUM_LINE_STYLE InpStylePP = STYLE_SOLID;    // PP Style
input int             InpWidthPP = 2;              // PP Width (px)

input group "=== Resistance Style ==="
input color           InpColorR1 = C'220,90,90';   // R1 Color
input color           InpColorR2 = C'190,50,50';   // R2 Color
input color           InpColorR3 = C'155,15,15';   // R3 Color
input color           InpColorR4 = C'100,0,0';     // R4 Color (Camarilla only)
input ENUM_LINE_STYLE InpStyleR  = STYLE_DASH;     // Resistance Style
input int             InpWidthR  = 1;              // Resistance Width (px)

input group "=== Support Style ==="
input color           InpColorS1 = C'90,150,230';  // S1 Color
input color           InpColorS2 = C'50,110,195';  // S2 Color
input color           InpColorS3 = C'15,75,160';   // S3 Color
input color           InpColorS4 = C'0,40,110';    // S4 Color (Camarilla only)
input ENUM_LINE_STYLE InpStyleS  = STYLE_DASH;     // Support Style
input int             InpWidthS  = 1;              // Support Width (px)

input group "=== Labels ==="
input string InpLabelFont = "Segoe UI";  // Font
input int    InpLabelSize = 8;           // Font Size (pts)

//+------------------------------------------------------------------+
//| Constants                                                         |
//+------------------------------------------------------------------+
#define MAX_LEVELS   9          // PP + R1,R2,R3,R4 + S1,S2,S3,S4
#define OBJ_PREFIX   "FXTT_PP_"

// Level index aliases
#define LV_PP  0
#define LV_R1  1
#define LV_R2  2
#define LV_R3  3
#define LV_R4  4  // Camarilla only
#define LV_S1  5
#define LV_S2  6
#define LV_S3  7
#define LV_S4  8  // Camarilla only

//+------------------------------------------------------------------+
//| Pivot data for one period                                         |
//+------------------------------------------------------------------+
struct SPivotData
  {
   datetime timeStart;             // Open of the drawn period
   datetime timeEnd;               // Projected end (or next period's open)
   double   levels[MAX_LEVELS];    // Calculated price levels
   bool     active[MAX_LEVELS];    // Whether the level is valid for this method
  };

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES g_tf;
datetime        g_lastPeriodTime = 0;

//+------------------------------------------------------------------+
//| Map pivot timeframe to MT5 timeframe constant                     |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES TFToMT5(const ENUM_PIVOT_TIMEFRAME ptf)
  {
   switch(ptf)
     {
      case PIVOT_TF_DAILY:   return PERIOD_D1;
      case PIVOT_TF_MONTHLY: return PERIOD_MN1;
      default:               return PERIOD_W1;
     }
  }

//+------------------------------------------------------------------+
//| Return the display label for a level index                        |
//+------------------------------------------------------------------+
string LevelLabel(const int idx)
  {
   static const string camLabels[MAX_LEVELS] = {"PP","R1","R2","R3","R4","S1","S2","S3","S4"};
   static const string stdLabels[MAX_LEVELS] = {"PP","R1","R2","R3","",  "S1","S2","S3",""  };
   return (InpMethod == PIVOT_METHOD_CAMARILLA) ? camLabels[idx] : stdLabels[idx];
  }

//+------------------------------------------------------------------+
//| Visibility: is this level enabled by user settings?              |
//+------------------------------------------------------------------+
bool LevelVisible(const int idx)
  {
   if(idx == LV_PP)          return InpShowPP;
   if(idx >= LV_R1 && idx <= LV_R4) return InpShowResistance;
   return InpShowSupport;
  }

//+------------------------------------------------------------------+
//| Color for each level                                              |
//+------------------------------------------------------------------+
color LevelColor(const int idx)
  {
   const color palette[MAX_LEVELS] = {InpColorPP,
                                      InpColorR1, InpColorR2, InpColorR3, InpColorR4,
                                      InpColorS1, InpColorS2, InpColorS3, InpColorS4};
   return palette[idx];
  }

//+------------------------------------------------------------------+
//| Line style per group                                              |
//+------------------------------------------------------------------+
ENUM_LINE_STYLE LevelStyle(const int idx)
  {
   if(idx == LV_PP) return InpStylePP;
   if(idx <= LV_R4) return InpStyleR;
   return InpStyleS;
  }

//+------------------------------------------------------------------+
//| Line width per group                                              |
//+------------------------------------------------------------------+
int LevelWidth(const int idx)
  {
   if(idx == LV_PP) return InpWidthPP;
   if(idx <= LV_R4) return InpWidthR;
   return InpWidthS;
  }

//+------------------------------------------------------------------+
//| Calculate pivot levels from previous period's OHLC               |
//+------------------------------------------------------------------+
bool CalcPivots(const double H, const double L, const double C, const double O,
                SPivotData &pv)
  {
   for(int i = 0; i < MAX_LEVELS; i++) { pv.levels[i] = 0; pv.active[i] = false; }

   if(H <= 0 || L <= 0 || C <= 0) return false;

   double PP, R1, R2, R3, R4, S1, S2, S3, S4;
   R4 = S4 = 0;

   switch(InpMethod)
     {
      //--- Classic (Standard)
      case PIVOT_METHOD_CLASSIC:
         PP = (H + L + C) / 3.0;
         R1 = 2.0*PP - L;        S1 = 2.0*PP - H;
         R2 = PP + (H - L);      S2 = PP - (H - L);
         R3 = H + 2.0*(PP - L);  S3 = L - 2.0*(H - PP);
         pv.active[LV_PP] = pv.active[LV_R1] = pv.active[LV_R2] = pv.active[LV_R3] = true;
         pv.active[LV_S1] = pv.active[LV_S2] = pv.active[LV_S3] = true;
         break;

      //--- Fibonacci
      case PIVOT_METHOD_FIBONACCI:
         PP = (H + L + C) / 3.0;
         R1 = PP + 0.382*(H - L); S1 = PP - 0.382*(H - L);
         R2 = PP + 0.618*(H - L); S2 = PP - 0.618*(H - L);
         R3 = PP + 1.000*(H - L); S3 = PP - 1.000*(H - L);
         pv.active[LV_PP] = pv.active[LV_R1] = pv.active[LV_R2] = pv.active[LV_R3] = true;
         pv.active[LV_S1] = pv.active[LV_S2] = pv.active[LV_S3] = true;
         break;

      //--- Camarilla (includes R4, S4)
      case PIVOT_METHOD_CAMARILLA:
         PP = (H + L + C) / 3.0;
         R1 = C + (H - L) * 1.1 / 12.0; S1 = C - (H - L) * 1.1 / 12.0;
         R2 = C + (H - L) * 1.1 / 6.0;  S2 = C - (H - L) * 1.1 / 6.0;
         R3 = C + (H - L) * 1.1 / 4.0;  S3 = C - (H - L) * 1.1 / 4.0;
         R4 = C + (H - L) * 1.1 / 2.0;  S4 = C - (H - L) * 1.1 / 2.0;
         for(int i = 0; i < MAX_LEVELS; i++) pv.active[i] = true;
         break;

      //--- Woodie (no R3/S3)
      case PIVOT_METHOD_WOODIE:
         PP = (H + L + 2.0*C) / 4.0;
         R1 = 2.0*PP - L; S1 = 2.0*PP - H;
         R2 = PP + (H - L); S2 = PP - (H - L);
         R3 = S3 = R4 = S4 = 0;
         pv.active[LV_PP] = pv.active[LV_R1] = pv.active[LV_R2] = true;
         pv.active[LV_S1] = pv.active[LV_S2] = true;
         break;

      //--- DeMark (PP and one R/S only)
      case PIVOT_METHOD_DEMARK:
         {
            double X = (C < O) ? H + 2.0*L + C
                     : (C > O) ? 2.0*H + L + C
                     :           H + L + 2.0*C;
            PP = X / 4.0;
            R1 = X / 2.0 - L; S1 = X / 2.0 - H;
            R2 = R3 = R4 = S2 = S3 = S4 = 0;
         }
         pv.active[LV_PP] = pv.active[LV_R1] = pv.active[LV_S1] = true;
         break;

      default: return false;
     }

   pv.levels[LV_PP] = PP;
   pv.levels[LV_R1] = R1; pv.levels[LV_R2] = R2;
   pv.levels[LV_R3] = R3; pv.levels[LV_R4] = R4;
   pv.levels[LV_S1] = S1; pv.levels[LV_S2] = S2;
   pv.levels[LV_S3] = S3; pv.levels[LV_S4] = S4;
   return true;
  }

//+------------------------------------------------------------------+
//| Object name helpers                                               |
//+------------------------------------------------------------------+
string ObjLineName(const int period, const int idx)
  {
   return OBJ_PREFIX + (string)period + "_" + LevelLabel(idx);
  }

string ObjLabelName(const int period, const int idx)
  {
   return OBJ_PREFIX + (string)period + "_" + LevelLabel(idx) + "_L";
  }

//+------------------------------------------------------------------+
//| Create or update a horizontal trend-line segment                  |
//+------------------------------------------------------------------+
void SetLine(const string name, const datetime t1, const datetime t2,
             const double price, const color clr,
             const ENUM_LINE_STYLE style, const int width, const bool rayRight)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price)) return;
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,   false);
     }
   ObjectMove(0, name, 0, t1, price);
   ObjectMove(0, name, 1, t2, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,     style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, rayRight);
  }

//+------------------------------------------------------------------+
//| Create or update a text label anchored above the line            |
//+------------------------------------------------------------------+
void SetLabel(const string name, const datetime t, const double price,
              const string text, const color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price)) return;
      ObjectSetInteger(0, name, OBJPROP_BACK,       false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,   false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ANCHOR_LEFT_LOWER);
      ObjectSetString(0,  name, OBJPROP_FONT,       InpLabelFont);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   InpLabelSize);
     }
   ObjectMove(0, name, 0, t, price);
   ObjectSetString(0,  name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
//| Remove a single object if it exists                               |
//+------------------------------------------------------------------+
void SafeDelete(const string name)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
  }

//+------------------------------------------------------------------+
//| Delete every object that belongs to this indicator                |
//+------------------------------------------------------------------+
void DeleteAllObjects()
  {
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i);
      if(StringFind(name, OBJ_PREFIX) == 0) ObjectDelete(0, name);
     }
  }

//+------------------------------------------------------------------+
//| Draw (or remove) all levels for one pivot period                  |
//+------------------------------------------------------------------+
void DrawPeriod(const int periodIdx, const SPivotData &pv, const bool isCurrent)
  {
   const bool ray = isCurrent && InpExtendRight;

   // Place label 10% into the period so it clears the period boundary line
   datetime labelOffset = (datetime)((pv.timeEnd - pv.timeStart) * 0.10);
   datetime labelTime   = pv.timeStart + labelOffset;

   for(int lv = 0; lv < MAX_LEVELS; lv++)
     {
      if(!pv.active[lv]) continue;

      const string lname = ObjLineName(periodIdx, lv);
      const string tname = ObjLabelName(periodIdx, lv);

      if(LevelVisible(lv))
        {
         SetLine(lname, pv.timeStart, pv.timeEnd, pv.levels[lv],
                 LevelColor(lv), LevelStyle(lv), LevelWidth(lv), ray);

         if(InpShowLabels)
            SetLabel(tname, labelTime, pv.levels[lv],
                     LevelLabel(lv) + "  " + DoubleToString(pv.levels[lv], _Digits),
                     LevelColor(lv));
         else
            SafeDelete(tname);
        }
      else
        {
         SafeDelete(lname);
         SafeDelete(tname);
        }
     }
  }

//+------------------------------------------------------------------+
//| Full recalculation and redraw of all periods                      |
//+------------------------------------------------------------------+
void Redraw()
  {
   const int tfBars = Bars(_Symbol, g_tf);
   if(tfBars < 2) return;

   DeleteAllObjects();

   const int periods = MathMin(InpLookback, tfBars - 1);

   for(int p = 0; p < periods; p++)
     {
      // Bar p on g_tf = the period we are DRAWING onto
      // Bar p+1 on g_tf = the previous closed period whose OHLC we use to calculate pivots
      const int calcBar = p + 1;
      if(calcBar >= tfBars) break;

      const double H = iHigh(_Symbol,  g_tf, calcBar);
      const double L = iLow(_Symbol,   g_tf, calcBar);
      const double C = iClose(_Symbol, g_tf, calcBar);
      const double O = iOpen(_Symbol,  g_tf, calcBar);

      SPivotData pv;
      pv.timeStart = iTime(_Symbol, g_tf, p);
      // Historical end = next more-recent period's open; current = estimated period boundary
      pv.timeEnd   = (p == 0) ? pv.timeStart + PeriodSeconds(g_tf)
                               : iTime(_Symbol, g_tf, p - 1);

      if(!CalcPivots(H, L, C, O, pv)) continue;

      DrawPeriod(p, pv, p == 0);
     }

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Indicator initialisation                                          |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLookback < 1 || InpLookback > 50)
     {
      Alert("FXTT Pivot Points: Lookback must be between 1 and 50.");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_tf = TFToMT5(InpPivotTF);

   if(PeriodSeconds(g_tf) <= PeriodSeconds(_Period))
     {
      Alert("FXTT Pivot Points: Pivot timeframe must be higher than the current chart timeframe.");
      return INIT_PARAMETERS_INCORRECT;
     }

   IndicatorSetString(INDICATOR_SHORTNAME, "FXTT Pivots");

   Redraw();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Indicator deinitialisation — clean up all chart objects           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   DeleteAllObjects();
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Called on every tick; redraws only when the pivot period changes  |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   datetime curPeriodTime = iTime(_Symbol, g_tf, 0);
   if(prev_calculated == 0 || curPeriodTime != g_lastPeriodTime)
     {
      g_lastPeriodTime = curPeriodTime;
      Redraw();
     }
   return rates_total;
  }

//+------------------------------------------------------------------+
//| Redraw on chart zoom / scroll so labels stay positioned correctly |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam,
                  const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE) Redraw();
  }
//+------------------------------------------------------------------+

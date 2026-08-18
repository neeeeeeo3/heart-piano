#Requires AutoHotkey v2.0
#SingleInstance Force
ListLines 0
ProcessSetPriority "Realtime"
SetKeyDelay -1, -1
#MaxThreadsPerHotkey 50

; ============================================================
; 【EVENT BUS】
; 各コンポーネント間の疎結合な通信を実現
; ============================================================
class EventBus 
{
    static listeners := Map()
    
    static On(eventName, callback) 
    {
        if (!this.listeners.Has(eventName)) 
        {
            this.listeners[eventName] := []
        }
        this.listeners[eventName].Push(callback)
    }
    
    static Emit(eventName, params*) 
    {
        if (this.listeners.Has(eventName)) 
        {
            for cb in this.listeners[eventName] 
            {
                cb(params*)
            }
        }
    }
}

; ============================================================
; 【APP CONTEXT】
; プラグイン間で共有されるグローバル状態
; ============================================================
class AppContext 
{
    static Config := {
        Title: "CHIMERA V99.0 ULTIMA",
        MaxDurationMs: 298000,
        WindowBg: "010101",
        AccentColor: "FFAA00"
    }
    static Flags := {
        ActiveStyle: "Romantic", ; 【スタイルセレクター】 Romantic / Mechanical / OldTimey
        UseHumanize: true,       ; ゆらぎの有効/無効
        UseRubato: true          ; ルバートの有効/無効
    }
    static RawNotes := []
    static Events := []
    static SustainEvents := []
    static TempoEvents := Map()
    static MelodyMap := Map()
    static TotalTimeMs := 0
    static IsReady := false
    static StopRequested := false
}

; ============================================================
; 【KEY MAP】
; ============================================================
class KeyMap 
{
    static SC := Map(
        48,"033", 49,"026", 50,"034", 51,"027", 52,"035", 53,"018", 54,"00B", 55,"019", 
        56,"00C", 57,"01A", 58,"00D", 59,"01B", 60,"02C", 61,"01F", 62,"02D", 63,"020", 
        64,"02E", 65,"02F", 66,"022", 67,"030", 68,"023", 69,"031", 70,"024", 71,"032", 
        72,"010", 73,"003", 74,"011", 75,"004", 76,"012", 77,"013", 78,"006", 79,"014", 
        80,"007", 81,"015", 82,"008", 83,"016", 84,"017"
    )
}

; ============================================================
; 【SYSTEM UTILITY】
; ============================================================
class SysTimer 
{
    static StartQPC := 0
    static QPC_Freq := 0

    static Init() 
    {
        DllCall("QueryPerformanceFrequency", "Int64*", &freq := 0)
        this.QPC_Freq := freq
        DllCall("winmm\timeBeginPeriod", "UInt", 1)
        OnExit(ObjBindMethod(this, "CleanUp"))
    }
    
    static CleanUp(*) 
    {
        Loop 128 
        {
            try 
            {
                SendEvent("{Blind}{sc" Format("{:03X}", A_Index) " Up}")
            }
        }
        DllCall("winmm\timeEndPeriod", "UInt", 1)
    }
    
    static NowMs() 
    {
        DllCall("QueryPerformanceCounter", "Int64*", &counter := 0)
        if (!this.QPC_Freq) 
        {
            return 0
        }
        if (!this.StartQPC) 
        {
            this.StartQPC := counter
        }
        return (counter - this.StartQPC) * 1000 / this.QPC_Freq
    }
    
    static Reset() 
    {
        this.StartQPC := 0
    }
}

class DialogHelper 
{
    static SmallFileSelect(TitleText, Filter) 
    {
        fn := ObjBindMethod(this, "ResizeDialog", TitleText)
        SetTimer(fn, 10)
        try 
        {
            Selected := FileSelect(3, A_ScriptDir, TitleText, Filter)
        } 
        catch 
        {
            Selected := ""
        }
        SetTimer(fn, 0)
        return Selected
    }
    
    static ResizeDialog(Title) 
    {
        if (WinExist(Title)) 
        {
            WinMove(,, 800, 550, Title)
            SetTimer(,, 0)
        }
    }
}

; ============================================================
; 【UI COMPONENT】
; ============================================================
class HarmonyGUI 
{
    static GuiObj := "", TitleText := "", SubText := "", TimeText := "", Progress := ""

    static Init() 
    {
        this.GuiObj := Gui("+AlwaysOnTop -Caption +ToolWindow")
        this.GuiObj.BackColor := AppContext.Config.WindowBg
        this.GuiObj.SetFont("s10 w900 cFFD700", "Segoe UI")
        this.TitleText := this.GuiObj.Add("Text", "x0 y15 w500 Center", AppContext.Config.Title)
        this.GuiObj.SetFont("s38 w900 c" AppContext.Config.AccentColor, "Segoe UI")
        this.GuiObj.Add("Text", "x0 y45 w500 Center", "🔮")
        this.GuiObj.SetFont("s14 cFFFFFF", "Consolas")
        this.SubText := this.GuiObj.Add("Text", "x0 y115 w500 Center", "WAITING CSV")
        this.GuiObj.SetFont("s16 w700 cFFFFFF", "Consolas")
        this.TimeText := this.GuiObj.Add("Text", "x0 y135 w500 Center", "00:00 / 00:00")
        this.Progress := this.GuiObj.Add("Progress", "x50 y175 w400 h4 Range0-100 vProg c" AppContext.Config.AccentColor " Background331A00", 0)
        this.GuiObj.Show("xCenter y40 w500 h200 NoActivate")
        WinSetTransColor(AppContext.Config.WindowBg, this.GuiObj)
        WinSetTransparent(190, this.GuiObj)
        
        EventBus.On("App_StatusChanged", ObjBindMethod(this, "UpdateStatus"))
        EventBus.On("App_FileLoaded", ObjBindMethod(this, "UpdateTitle"))
        EventBus.On("Engine_Progress", ObjBindMethod(this, "UpdateTimer"))
        EventBus.On("Engine_BeatPulse", ObjBindMethod(this, "PulseEffect"))
    }
    
    static UpdateStatus(msg) 
    {
        this.SubText.Value := msg
    }
    
    static UpdateTitle(name) 
    {
        this.TitleText.Value := name
    }
    
    static UpdateTimer(curMs) 
    {
        if (AppContext.TotalTimeMs <= 0) 
        {
            return
        }
        curSec := Floor(curMs / 1000)
        totSec := Floor(AppContext.TotalTimeMs / 1000)
        this.TimeText.Value := Format("{:02d}:{:02d} / {:02d}:{:02d}", Floor(curSec/60), Mod(curSec,60), Floor(totSec/60), Mod(totSec,60))
        this.Progress.Value := Min(100, (curMs / AppContext.TotalTimeMs) * 100)
    }
    
    static PulseEffect(alphaValue) 
    {
        WinSetTransparent(alphaValue, this.GuiObj)
    }
}

; ============================================================
; 【EXTENSIBLE PIPELINE ARCHITECTURE】
; 優先度付き動的モジュール実行エンジン
; ============================================================
class ProcessingPipeline 
{
    static modules := []
    
    ; priorityが小さいほど先に実行される（10が最初、90が最後など）
    static Register(processorClass, priority := 50) 
    {
        this.modules.Push({cls: processorClass, prio: priority})
    }
    
    static Execute(ctx) 
    {
        ; バブルソートによる優先度順の並び替え
        Loop this.modules.Length 
        {
            i := A_Index
            Loop this.modules.Length - i 
            {
                j := A_Index
                if (this.modules[j].prio > this.modules[j+1].prio) 
                {
                    temp := this.modules[j]
                    this.modules[j] := this.modules[j+1]
                    this.modules[j+1] := temp
                }
            }
        }
        
        ; 順番にモジュールを適用
        for modItem in this.modules 
        {
            modItem.cls.Apply(ctx)
        }
    }
}

; ============================================================
; 【PROCESSOR PLUGINS】
; ============================================================

class StyleSelectorProcessor 
{
    ; 【優先度10】一番最初に全体の設定とパラメータを書き換える
    static Apply(ctx) 
    {
        style := ctx.Flags.ActiveStyle
        if (style == "Mechanical") 
        {
            ctx.Flags.UseHumanize := false
            ctx.Flags.UseRubato := false
            for N in ctx.RawNotes 
            {
                N.Velo := 100 ; 感情を排除した均一な打鍵
            }
        } 
        else if (style == "Romantic") 
        {
            ctx.Flags.UseHumanize := true
            ctx.Flags.UseRubato := true
            for N in ctx.RawNotes 
            {
                N.Velo := Min(127, Round(N.Velo * 1.1)) ; 全体的に強く、情熱的に
                N.Dur := Round(N.Dur * 1.05)            ; 余韻を長く
            }
        } 
        else if (style == "OldTimey") 
        {
            ctx.Flags.UseHumanize := true
            ctx.Flags.UseRubato := false
            for N in ctx.RawNotes 
            {
                N.Velo := Max(20, Min(127, N.Velo + Random(-20, 20))) ; ランダムな劣化
                N.T += Random(-30, 30)                                ; リズムのブレ
            }
        }
    }
}

class MelodyAnalyzerProcessor 
{
    ; 【優先度20】
    static Apply(ctx) 
    {
        melody := Map()
        for N in ctx.RawNotes 
        {
            if (!melody.Has(N.T) || N.Midi > melody[N.T]) 
            {
                melody[N.T] := N.Midi
            }
        }
        ctx.MelodyMap := melody
        for N in ctx.RawNotes 
        {
            N.isMelody := (melody.Has(N.T) && N.Midi = melody[N.T])
        }
    }
}

class PassiveSkylineProcessor 
{
    ; 【優先度30】
    static Apply(ctx) 
    {
        for N in ctx.RawNotes 
        {
            m := N.Midi
            if (N.isMelody) 
            {
                while (m > 84) 
                { 
                    m -= 12 
                }
                while (m < 48) 
                { 
                    m += 12 
                }
                N.Midi := m
                continue
            }
            while (m > 84) 
            { 
                m -= 12 
            }
            while (m < 48) 
            { 
                m += 12 
            }
            if (ctx.MelodyMap.Has(N.T)) 
            {
                mPitch := ctx.MelodyMap[N.T]
                if (m >= mPitch - 2 && m - 12 >= 48) 
                {
                    m -= 12
                }
            }
            N.Midi := m
        }
    }
}

class DynamicRubatoProcessor 
{
    ; 【優先度40】フレーズの中間を加速させ、終わりを遅くする
    static Apply(ctx) 
    {
        if (!ctx.Flags.UseRubato) 
        {
            return
        }
        
        phrase := []
        prevT := -1000
        for N in ctx.RawNotes 
        {
            if (N.isMelody) 
            {
                if (N.T - prevT > 800 && phrase.Length > 3) 
                {
                    this.ApplyRubatoCurve(phrase)
                    phrase := []
                }
                phrase.Push(N)
                prevT := N.T
            }
        }
        if (phrase.Length > 3) 
        {
            this.ApplyRubatoCurve(phrase)
        }
    }
    
    static ApplyRubatoCurve(phraseList) 
    {
        len := phraseList.Length
        Loop len 
        {
            N := phraseList[A_Index]
            progress := A_Index / len
            
            ; サイン波を使った時間の歪み（中央付近で時間がマイナス方向にズレる＝加速、最後でプラス＝減速）
            ; -1.0 ~ 1.0 のカーブを時間加算する
            warpFactor := Sin(progress * 3.14159 * 2) * 20 
            
            if (A_Index > 1 && A_Index < len) 
            {
                N.T += Round(warpFactor)
            }
            
            ; フレーズの最後の音は名残惜しそうに少し伸ばす
            if (A_Index == len) 
            {
                N.Dur := Round(N.Dur * 1.2)
                N.T += 15
            }
        }
    }
}

class ArticulationLogicProcessor 
{
    ; 【優先度50】レガート（スラー）とスタッカートの物理モデリング
    static Apply(ctx) 
    {
        if (!ctx.Flags.UseHumanize) 
        {
            return
        }
        
        notes := ctx.RawNotes
        Loop notes.Length 
        {
            if (A_Index == 1) 
            {
                continue
            }
            curr := notes[A_Index]
            prev := notes[A_Index - 1]
            
            if (curr.isMelody && prev.isMelody) 
            {
                dist := Abs(curr.Midi - prev.Midi)
                timeGap := curr.T - prev.T
                
                ; インターバルが狭く(2半音以内)、すぐ次に弾く場合はスラー（前の音を伸ばして重ねる）
                if (dist <= 2 && timeGap < 300) 
                {
                    prev.Dur := Max(prev.Dur, timeGap + 40)
                }
                ; インターバルが広く(7半音以上)、跳躍する場合はスタッカート気味に切る
                else if (dist >= 7) 
                {
                    prev.Dur := Round(prev.Dur * 0.7)
                }
            }
        }
    }
}

class AdvancedGrooveProcessor 
{
    ; 【優先度60】
    static Apply(ctx) 
    {
        if (!ctx.Flags.UseHumanize) 
        {
            return
        }
        for N in ctx.RawNotes 
        {
            beatPos := Mod(N.T, 500)
            if (beatPos > 200 && beatPos < 350) 
            {
                N.T += Random(5, 15)
            }
        }
    }
}

class EventCompilerProcessor 
{
    ; 【優先度90】最終イベント変換
    static Apply(ctx) 
    {
        SortStr := ""
        Active := Map()
        TempStr := ""
        
        for i, N in ctx.RawNotes 
        {
            if (!KeyMap.SC.Has(N.Midi)) 
            { 
                continue 
            }
            TempStr .= Format("{1:010d}|{2}`n", N.T, i)
        }
        TempStr := Sort(RTrim(TempStr, "`n"), "N")
        SortedNotes := []
        Loop Parse, TempStr, "`n" 
        {
            if (A_LoopField != "") 
            {
                idx := Number(StrSplit(A_LoopField, "|")[2])
                SortedNotes.Push(ctx.RawNotes[idx])
            }
        }
        
        for N in SortedNotes 
        {
            sc := KeyMap.SC[N.Midi]
            dur := Max(30, N.Dur)
            if (Active.Has(sc) && Active[sc] > N.T) 
            {
                releaseTime := Max(0, N.T - 15)
                SortStr .= Format("{1:010d}|0|{2}|0`n", releaseTime, sc)
                Active[sc] := Max(Active[sc], N.T + dur)
            } 
            else 
            {
                Active[sc] := N.T + dur
            }
            SortStr .= Format("{1:010d}|1|{2}|{3}`n", N.T, sc, N.Midi)
            SortStr .= Format("{1:010d}|0|{2}|0`n", Active[sc], sc)
        }
        
        SortStr := Sort(RTrim(SortStr, "`n"), "N")
        ctx.Events := []
        LastUp := Map() 
        
        Loop Parse, SortStr, "`n" 
        {
            if (A_LoopField != "") 
            {
                D := StrSplit(A_LoopField, "|")
                t := Number(D[1])
                type := Number(D[2])
                sc := D[3]
                midi := Number(D[4])
                
                if (type == 0) 
                {
                    if (LastUp.Has(sc) && LastUp[sc] >= t) 
                    { 
                        continue 
                    }
                    LastUp[sc] := t
                }
                ctx.Events.Push({T: t, Type: type, Act: sc, Midi: midi})
            }
        }
        ctx.IsReady := true
    }
}

; 処理パイプラインへのモジュール動的登録（優先度順）
ProcessingPipeline.Register(StyleSelectorProcessor, 10)
ProcessingPipeline.Register(MelodyAnalyzerProcessor, 20)
ProcessingPipeline.Register(PassiveSkylineProcessor, 30)
ProcessingPipeline.Register(DynamicRubatoProcessor, 40)
ProcessingPipeline.Register(ArticulationLogicProcessor, 50)
ProcessingPipeline.Register(AdvancedGrooveProcessor, 60)
ProcessingPipeline.Register(EventCompilerProcessor, 90)

; ============================================================
; 【PERFORMANCE ENGINE】
; ============================================================
class PerformanceEngine 
{
    static Play(ctx) 
    {
        if (!ctx.IsReady) 
        { 
            return 
        }
        ctx.StopRequested := false
        EventBus.Emit("App_StatusChanged", "✧ ULTIMA: " StrUpper(ctx.Flags.ActiveStyle) " ✧")
        SoundBeep(1200, 60)
        SysTimer.Reset()
        
        idx := 1
        total := ctx.Events.Length
        lastM := 60
        lastUpdate := -100
        
        Loop 
        {
            cur := SysTimer.NowMs()
            while (idx <= total && cur >= ctx.Events[idx].T) 
            {
                e := ctx.Events[idx]
                if (e.Type == 1) 
                { 
                    lastM := e.Midi 
                }
                SendEvent("{Blind}{sc" e.Act (e.Type ? " Down}" : " Up}"))
                idx++
            }
            
            if (idx > total || ctx.StopRequested) 
            { 
                break 
            }
            
            if (cur - lastUpdate >= 100) 
            {
                EventBus.Emit("Engine_Progress", cur)
                lastUpdate := cur
                bpm := this.GetBPM(ctx, cur)
                beat := 60000 / bpm
                alpha := 150 + Floor(Sin(3.14 * Mod(cur, beat) / beat) * 40)
                EventBus.Emit("Engine_BeatPulse", alpha)
            }
            
            diff := (idx <= total) ? ctx.Events[idx].T - cur : 0
            if (diff > 1) 
            {
                Sleep(diff - 1)
            } 
            else 
            {
                DllCall("Sleep", "UInt", 0)
            }
        }
        this.Finish(ctx, lastM)
    }
    
    static GetBPM(ctx, ms) 
    {
        res := 120
        for t, bpm in ctx.TempoEvents 
        {
            if (ms >= t) 
            { 
                res := bpm 
            } 
            else 
            { 
                break 
            }
        }
        return res
    }
    
    static Finish(ctx, lm) 
    {
        SysTimer.CleanUp()
        if (ctx.StopRequested) 
        {
            arp := [lm, lm + 4, lm + 7, lm + 12]
            played := []
            for n in arp 
            {
                v := n
                while (v > 84) 
                { 
                    v -= 12 
                }
                while (v < 48) 
                { 
                    v += 12 
                }
                if (KeyMap.SC.Has(v)) 
                {
                    sc := KeyMap.SC[v]
                    SendEvent("{Blind}{sc" sc " Down}")
                    played.Push(sc)
                    Sleep(80)
                }
            }
            Sleep(300)
            for sc in played 
            { 
                SendEvent("{Blind}{sc" sc " Up}")
                Sleep(20) 
            }
        }
        EventBus.Emit("App_StatusChanged", ctx.StopRequested ? "STOPPED" : "FINISHED")
        Sleep(1000)
        ExitApp()
    }
}

; ============================================================
; 【I/O COMPONENT】
; ============================================================
class CSVParser 
{
    static Load(ctx, path) 
    {
        tempNotes := []
        ctx.SustainEvents := []
        ctx.TempoEvents := Map()
        
        try 
        {
            content := FileRead(path)
        } 
        catch 
        {
            return false
        }
        
        lines := StrSplit(StrReplace(content, "`r", ""), "`n")
        for L in lines 
        {
            R := StrSplit(Trim(L), ",")
            if (R.Length < 7 || !IsNumber(R[7])) 
            { 
                continue 
            }
            type := Trim(R[2])
            time := Round(Float(R[7]) * 1000)
            
            if (type = "note_on" && Number(R[5]) > 0) 
            {
                tempNotes.Push({T: time, Dur: Round(Float(R[6]) * 1000), Midi: Number(R[3]), Velo: Number(R[5]), Track: Trim(R[1])})
            } 
            else if (type = "Tempo") 
            {
                ctx.TempoEvents[time] := Round(60000000 / Number(R[3]))
            } 
            else if (type = "Control_c" && Number(R[5]) = 64) 
            {
                ctx.SustainEvents.Push({T: time, State: (Number(R[6]) >= 64)})
            }
        }
        
        ctx.RawNotes := tempNotes
        
        maxT := 0
        for N in ctx.RawNotes 
        { 
            if (N.T + N.Dur > maxT) 
            { 
                maxT := N.T + N.Dur 
            } 
        }
        if (maxT > ctx.Config.MaxDurationMs) 
        {
            ratio := ctx.Config.MaxDurationMs / maxT
            for N in ctx.RawNotes 
            { 
                N.T := Round(N.T * ratio)
                N.Dur := Round(N.Dur * ratio) 
            }
            tTemp := Map()
            for t, bpm in ctx.TempoEvents 
            { 
                tTemp[Round(t * ratio)] := bpm 
            }
            ctx.TempoEvents := tTemp
            maxT := ctx.Config.MaxDurationMs
        }
        ctx.TotalTimeMs := Round(maxT)
        return (ctx.RawNotes.Length > 0)
    }
}

; ============================================================
; 【MAIN BOOTSTRAP】
; ============================================================
SysTimer.Init()
HarmonyGUI.Init()
HarmonyGUI.GuiObj.Opt("+OwnDialogs")

Selected := DialogHelper.SmallFileSelect("SELECT_CSV_FILE", "CSV (*.csv)")
if (Selected == "") 
{
    ExitApp()
}

EventBus.Emit("App_StatusChanged", "LOADING...")

if (CSVParser.Load(AppContext, Selected)) 
{
    SplitPath(Selected, , , , &Name)
    EventBus.Emit("App_FileLoaded", Name)
    ProcessingPipeline.Execute(AppContext)
    EventBus.Emit("Engine_Progress", 0)
    EventBus.Emit("App_StatusChanged", "READY: F1 TO START")
} 
else 
{
    ExitApp()
}

$F1:: PerformanceEngine.Play(AppContext)
$Esc:: (AppContext.IsReady && !AppContext.StopRequested ? AppContext.StopRequested := true : ExitApp())
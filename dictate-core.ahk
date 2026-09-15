#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode "Input"
DetectHiddenWindows true

; ------------------------------------------------------------------
; claude-dictate: global voice dictation via Claude Code's /voice.
;
; Universal script, knows nothing about profiles or OpenChamber.
; Start it once: it opens Claude Code (settings from dictate-settings.json
; next to this script) in a classic console window and waits for the hotkey.
; Keys are posted straight into that console, so the focus never leaves
; the window you are dictating into.
;
; Not meant to be run by hand: dictate-start.ahk starts it with one argument,
;   dictate-core.ahk default        Claude Code with its default config (~/.claude)
;   dictate-core.ahk <configDir>    Claude Code with CLAUDE_CONFIG_DIR=<configDir>
;
;   Ctrl+Space   1st press: start recording
;                2nd press: stop, paste the text into the window that
;                was active on the 1st press
;   Escape       only while recording: abort, paste nothing
;
; Exiting the script (tray icon -> Exit) closes the Claude Code window.
; ------------------------------------------------------------------

; All settings live in dictate.ini next to this script (see the comments there).
; The values below are only the defaults used when a key is missing.
global StateIni    := A_ScriptDir "\dictate.ini"
global ClaudeExe         := Cfg("claudeExe", "")            ; "" = look up claude.exe in PATH
global HotkeyToggle      := Cfg("hotkey", "^Space")         ; start / stop and paste
global HotkeyCancel      := Cfg("cancelKey", "Escape")      ; abort, only while recording
global WindowMode        := Cfg("windowMode", "minimized")  ; hidden | minimized | visible
global IndicatorXPercent := Cfg("indicatorXPercent", 90)
global IndicatorYPercent := Cfg("indicatorYPercent", 90)
global IndicatorOpacity  := Cfg("indicatorOpacity", 170)
global IndicatorBorder   := Cfg("indicatorBorder", 0x909090)
global RecLimitSec       := Cfg("recLimitSec", 120)
global RecWarnSec        := Cfg("recWarnSec", 10)
global RecForceStopAt    := Cfg("recForceStopAt", -15)

Cfg(key, default) {
    return IniRead(StateIni, "settings", key, default)
}

if (A_Args.Length < 1) {
    MsgBox "This is the core. Run dictate-start.ahk instead.", "claude-dictate", "Iconi"
    ExitApp
}
global ConfigDir   := (A_Args[1] = "default") ? "" : A_Args[1]
global Settings    := A_ScriptDir "\dictate-settings.json"
global OutFile     := A_ScriptDir "\dictate-out.txt"
global LogFile     := A_ScriptDir "\dictate.log"      ; shared with the hook
global DictHwnd    := 0        ; window handle of the Claude Code console
global Recording   := false
global RecStartTick := 0       ; A_TickCount when the current recording started
global MicSeen     := false    ; the microphone was observed in use during this recording
global TargetHwnd  := 0
global Indicator   := 0        ; Gui of the status indicator
global IndText     := 0        ; its text control
global IndState    := {text: "○ ready", color: "A0A0A0"}   ; current state, survives rebuilds

if (ClaudeExe = "")
    ClaudeExe := FindClaudeExe()
if !FileExist(ClaudeExe) {
    MsgBox "claude.exe not found" (ClaudeExe != "" ? ": " ClaudeExe : " in PATH") ".`nSet claudeExe in dictate.ini.", "claude-dictate", "Iconx"
    ExitApp
}

; claude.exe from PATH, then the usual native-installer location.
FindClaudeExe() {
    Loop Parse EnvGet("PATH"), ";" {
        dir := Trim(A_LoopField, ' "')
        if (dir != "" && FileExist(dir "\claude.exe"))
            return dir "\claude.exe"
    }
    if FileExist(A_MyDocuments "\..\.local\bin\claude.exe")
        return A_MyDocuments "\..\.local\bin\claude.exe"
    return ""
}
if (ConfigDir != "" && !DirExist(ConfigDir)) {
    MsgBox "Config directory not found: " ConfigDir, "claude-dictate", "Iconx"
    ExitApp
}
if (WindowMode != "hidden" && WindowMode != "minimized" && WindowMode != "visible") {
    MsgBox 'WindowMode must be "hidden", "minimized" or "visible", got: ' WindowMode, "claude-dictate", "Iconx"
    ExitApp
}

A_IconTip := "claude-dictate (" (ConfigDir != "" ? ConfigDir : "default config") ")"
CreateTrayMenu()      ; before StartClaudeWindow: ApplyWindowMode marks the menu
OnExit CloseClaudeWindow   ; registered first, so any later failure still closes Claude Code

; Hotkeys are live from the moment the script loads, so the indicator must
; exist before the slow part (starting Claude Code) and the hotkey must wait.
global Ready := false
IndState.text := "… starting"
IndState.color := "E0B050"
CreateIndicator()
WatchDisplayChanges()

if !StartClaudeWindow() {
    MsgBox "Could not start the Claude Code window.", "claude-dictate", "Iconx"
    ExitApp
}

Ready := true
IndicatorIdle()

; Hotkeys come from dictate.ini (AutoHotkey notation: ^ Ctrl, + Shift, ! Alt, # Win).
; The cancel key is registered only while a recording is running (Recording = true);
; outside of that window it does not exist and reaches the app as usual.
try {
    Hotkey HotkeyToggle, (*) => ToggleDictation()
    HotIf (*) => Recording
    Hotkey HotkeyCancel, (*) => CancelDictation()
    HotIf
} catch as e {
    MsgBox "Bad hotkey in dictate.ini: " e.Message, "claude-dictate", "Iconx"
    ExitApp
}

; ---- tray menu ----------------------------------------------------

; Right-click the tray icon or the indicator: profiles, window mode, autostart.
; Profiles come from [profiles] dir in dictate.ini (subfolders that have a
; .credentials.json); picking one restarts the core through the launcher.
CreateTrayMenu() {
    A_TrayMenu.Delete()
    for name, dir in ProfileList()
        A_TrayMenu.Add("Profile: " name, ((d, *) => SwitchProfile(d)).Bind(dir))
    A_TrayMenu.Check("Profile: " ProfileName())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Claude window: visible",   (*) => ApplyWindowMode("visible"))
    A_TrayMenu.Add("Claude window: minimized", (*) => ApplyWindowMode("minimized"))
    A_TrayMenu.Add("Claude window: hidden",    (*) => ApplyWindowMode("hidden"))
    A_TrayMenu.Add()
    A_TrayMenu.Add("Autostart", (*) => ToggleAutostart())   ; shortcut in the Startup folder
    A_TrayMenu.Add()
    A_TrayMenu.Add("Reload", (*) => Restart())   ; re-read this file, restart Claude Code
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    MarkWindowMode()
    MarkAutostart()
}

; Last folder name of the config dir, or "default".
ProfileName() {
    if (ConfigDir = "")
        return "default"
    SplitPath ConfigDir, &name
    return name
}

; name -> config dir. Always includes the running one, so the menu can show it.
ProfileList() {
    list := Map()
    dir := IniRead(StateIni, "profiles", "dir", "")
    if (dir != "" && DirExist(dir)) {
        Loop Files dir "\*", "D"
            if FileExist(A_LoopFileFullPath "\.credentials.json")
                list[A_LoopFileName] := A_LoopFileFullPath
    }
    list[ProfileName()] := ConfigDir
    return list
}

; The launcher starts a new core with that config dir; #SingleInstance Force
; makes it replace this one (and OnExit closes this one's Claude Code).
SwitchProfile(dir) {
    if (dir = ConfigDir)
        return
    Run '"' A_AhkPath '" "' A_ScriptDir '\dictate-start.ahk" "' (dir != "" ? dir : "default") '"'
}

; Same as SwitchProfile with the current profile. AutoHotkey's own Reload
; would drop the command-line argument, and the core refuses to run without it.
Restart() {
    Run '"' A_AhkPath '" "' A_ScriptDir '\dictate-start.ahk" "' (ConfigDir != "" ? ConfigDir : "default") '"'
}

; Autostart = a shortcut to dictate-start.ahk in the user's Startup folder.
AutostartLnk() {
    return A_Startup "\dictate-start.ahk.lnk"
}

MarkAutostart() {
    if FileExist(AutostartLnk())
        A_TrayMenu.Check("Autostart")
    else
        A_TrayMenu.Uncheck("Autostart")
}

ToggleAutostart() {
    lnk := AutostartLnk()
    if FileExist(lnk) {
        FileDelete lnk
        LogEvent("autostart removed: " lnk)
    } else {
        ; Shortcut to the .ahk file itself (runs via the .ahk file association),
        ; same as a shortcut made by hand with "Send to > Desktop".
        FileCreateShortcut A_ScriptDir "\dictate-start.ahk", lnk, A_ScriptDir, , "claude-dictate: voice dictation via Claude Code"
        LogEvent("autostart installed: " lnk)
    }
    MarkAutostart()
}

MarkWindowMode() {
    for mode in ["visible", "minimized", "hidden"] {
        item := "Claude window: " mode
        if (mode = WindowMode)
            A_TrayMenu.Check(item)
        else
            A_TrayMenu.Uncheck(item)
    }
}

; Puts the Claude Code console into the given state and remembers it.
ApplyWindowMode(mode) {
    global WindowMode
    WindowMode := mode
    if ClaudeWindowAlive() {
        switch mode {
            case "visible":
                WinShow "ahk_id " DictHwnd
                WinRestore "ahk_id " DictHwnd
            case "minimized":
                WinShow "ahk_id " DictHwnd
                WinMinimize "ahk_id " DictHwnd
            case "hidden":
                WinHide "ahk_id " DictHwnd
        }
    }
    MarkWindowMode()
}

; ---- status indicator ---------------------------------------------

CreateIndicator() {
    global Indicator, IndText
    ; -Caption: no frame; +ToolWindow: no taskbar button.
    Indicator := Gui("+AlwaysOnTop -Caption +ToolWindow +Owner", "claude-dictate indicator")
    Indicator.BackColor := "1E1E1E"
    Indicator.MarginX := 10
    Indicator.MarginY := 5
    Indicator.SetFont("s10 bold", "Segoe UI")
    IndText := Indicator.AddText("w88 Center c" IndState.color, IndState.text)
    ; Lay it out hidden first to learn its real (DPI-scaled) size, then place it.
    Indicator.Show("Hide")
    WinGetPos , , &w, &h, Indicator
    MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
    ; A dragged position saved in dictate.ini wins over the defaults at the top.
    xPct := IniRead(StateIni, "indicator", "xPercent", IndicatorXPercent)
    yPct := IniRead(StateIni, "indicator", "yPercent", IndicatorYPercent)
    x := Max(left, Min(left + (right - left) * xPct / 100, right - w))
    y := Max(top,  Min(top + (bottom - top) * yPct / 100, bottom - h))
    Indicator.Show("NoActivate x" Round(x) " y" Round(y))
    WinSetTransparent IndicatorOpacity, Indicator
    ; Rounded corners: DWMWA_WINDOW_CORNER_PREFERENCE (33) = DWMWCP_ROUND (2).
    ; Windows 11 only; on older systems the call fails silently and corners stay square.
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", Indicator.Hwnd, "uint", 33, "uint*", 2, "uint", 4)
    ; Thin border along that contour: DWMWA_BORDER_COLOR (34), COLORREF 0x00BBGGRR.
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", Indicator.Hwnd, "uint", 34, "uint*", IndicatorBorder, "uint", 4)
    OnMessage 0x0201, OnIndicatorMouseDown   ; WM_LBUTTONDOWN: start dragging
    OnMessage 0x0232, OnIndicatorMoved       ; WM_EXITSIZEMOVE: drag finished
    Indicator.OnEvent("ContextMenu", (*) => A_TrayMenu.Show())   ; right-click: same menu as the tray icon
}

; Left button on the indicator: let Windows drag it as if by its title bar.
OnIndicatorMouseDown(wParam, lParam, msg, hwnd) {
    if (hwnd != Indicator.Hwnd)
        return
    PostMessage 0x00A1, 2, 0, , Indicator      ; WM_NCLBUTTONDOWN, HTCAPTION
}

; Drag finished: remember where it landed (percent of the primary work area).
OnIndicatorMoved(wParam, lParam, msg, hwnd) {
    if (hwnd != Indicator.Hwnd)
        return
    WinGetPos &x, &y, , , Indicator
    MonitorGetWorkArea(MonitorGetPrimary(), &left, &top, &right, &bottom)
    IniWrite Round((x - left) * 100 / (right - left), 2), StateIni, "indicator", "xPercent"
    IniWrite Round((y - top) * 100 / (bottom - top), 2), StateIni, "indicator", "yPercent"
}

; Monitors, resolution, DPI or work area changed (laptop <-> external screen,
; taskbar moved): rebuild the indicator in the right place and size.
; These messages arrive in bursts, so the rebuild is debounced.
WatchDisplayChanges() {
    OnMessage 0x007E, OnDisplayChange   ; WM_DISPLAYCHANGE
    OnMessage 0x001A, OnDisplayChange   ; WM_SETTINGCHANGE
    OnMessage 0x02E0, OnDisplayChange   ; WM_DPICHANGED
}

OnDisplayChange(*) {
    SetTimer RebuildIndicator, -500
}

RebuildIndicator() {
    global Indicator
    try Indicator.Destroy()
    CreateIndicator()
}

; Shows a state; with resetMs > 0 it falls back to idle after that delay.
SetIndicator(text, color, resetMs := 0) {
    IndState.text := text
    IndState.color := color
    IndText.Opt("c" color)
    IndText.Text := text
    if (resetMs > 0)
        SetTimer IndicatorIdle, -resetMs
    else
        SetTimer IndicatorIdle, 0
}

IndicatorIdle() {
    SetIndicator("○ ready", "A0A0A0")
}

; Recording countdown: "● REC 1:53" from RecLimitSec down to zero, updated every
; second; the last RecWarnSec seconds are shown in the warning colour. At zero
; the recording is finished exactly as if Ctrl+Space had been pressed again.
StartRecClock() {
    global RecStartTick, MicSeen
    RecStartTick := A_TickCount
    MicSeen := false
    RecTick()
    SetTimer RecTick, 1000
}

StopRecClock() {
    SetTimer RecTick, 0
}

; Is Claude Code recording right now? Windows keeps a per-app microphone usage
; record in the registry (the same data drives the tray microphone icon):
; LastUsedTimeStop = 0 means the app is using the microphone at this moment.
; The value is a 64-bit FILETIME, which RegRead cannot read, hence RegGetValue.
MicInUse() {
    sub := "Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone\NonPackaged\" StrReplace(ClaudeExe, "\", "#")
    val := 0
    size := 8
    rc := DllCall("advapi32\RegGetValueW", "ptr", 0x80000001, "str", sub, "str", "LastUsedTimeStop"
        , "uint", 0x40, "ptr", 0, "int64*", &val, "uint*", &size, "int")   ; HKCU, RRF_RT_REG_QWORD
    return (rc = 0 && val = 0)
}

RecTick() {
    global MicSeen
    ; Claude Code stopped and submitted on its own (15 s of silence or its
    ; 2-minute cap): the hook has already written the file, so just paste it.
    if FileExist(OutFile) {
        StopRecClock()
        ClaudeSubmittedItself()
        return
    }
    elapsed := (A_TickCount - RecStartTick) // 1000
    if MicInUse() {
        MicSeen := true
    } else if MicSeen {
        ; The microphone went off without a file: either Claude Code is still
        ; transcribing (file follows shortly) or it gave up ("No speech detected").
        StopRecClock()
        ClaudeStoppedItself()
        return
    } else if (elapsed >= 5) {
        StopRecClock()
        global Recording := false
        LogEvent("mic never came on within 5 s")
        SetIndicator("No mic", "E05050", 3000)
        return
    }
    left := RecLimitSec - elapsed
    if (left <= RecForceStopAt) {
        StopRecClock()
        LogEvent("countdown reached " left " s, forcing stop")
        FinishDictation()
        return
    }
    ; green while recording, red for the last RecWarnSec seconds and past zero
    a := Abs(left)
    SetIndicator("● REC " (left < 0 ? "-" : "") (a // 60) ":" Format("{:02}", Mod(a, 60)), (left <= RecWarnSec) ? "FF4040" : "60C060")
}

; ---- Claude Code window -------------------------------------------

; Starts Claude Code in a classic console (conhost) and remembers its window.
; Environment variables set here are inherited by the child process.
; conhost accepts posted keys whether the window is visible, minimized or hidden;
; Windows Terminal does not, which is why it is not used here.
StartClaudeWindow() {
    global DictHwnd
    if (ConfigDir != "")
        EnvSet "CLAUDE_CONFIG_DIR", ConfigDir
    ; /voice needs a claude.ai login; make sure no API key overrides it.
    EnvSet "ANTHROPIC_API_KEY", ""
    EnvSet "ANTHROPIC_AUTH_TOKEN", ""
    EnvSet "CLAUDE_CODE_OAUTH_TOKEN", ""

    ; The new window is the ConsoleWindowClass window that was not there before.
    before := WinGetList("ahk_class ConsoleWindowClass")
    Run 'conhost.exe "' ClaudeExe '" --settings "' Settings '"', A_ScriptDir
    DictHwnd := 0
    Loop 150 {
        for h in WinGetList("ahk_class ConsoleWindowClass") {
            isOld := false
            for b in before
                if (b = h)
                    isOld := true
            if !isOld {
                DictHwnd := h
                break
            }
        }
        if DictHwnd
            break
        Sleep 100
    }
    if !DictHwnd
        return false

    Sleep 5000   ; let Claude Code draw its prompt
    ApplyWindowMode(WindowMode)
    LogEvent("Claude Code started, console hwnd " DictHwnd ", config " (ConfigDir != "" ? ConfigDir : "default") ", window " WindowMode)
    return true
}

ClaudeWindowAlive() {
    return DictHwnd && WinExist("ahk_id " DictHwnd)
}

CloseClaudeWindow(*) {
    if ClaudeWindowAlive() {
        WinShow "ahk_id " DictHwnd
        WinClose "ahk_id " DictHwnd
    }
}

; Posts keys into the Claude Code console without touching the focus.
SendToClaude(keys) {
    if !ClaudeWindowAlive()
        return false
    ControlSend keys, , "ahk_id " DictHwnd
    return true
}

; ---- event log ----------------------------------------------------

; Same file the hook writes to; script lines are tagged [ahk].
LogEvent(msg) {
    try FileAppend FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " [ahk] " msg "`n", LogFile, "UTF-8"
}

; ---- dictation ----------------------------------------------------

ToggleDictation() {
    global Recording, TargetHwnd
    if !Ready
        return      ; still starting Claude Code
    if !Recording {
        try TargetHwnd := WinGetID("A")
        catch
            TargetHwnd := 0
        try FileDelete OutFile
        if !ClaudeWindowAlive() && !StartClaudeWindow() {
            LogEvent("start failed: no Claude Code window")
            SetIndicator("No Claude", "E05050", 3000)
            return
        }
        SendToClaude("{Space}")
        Recording := true
        StartRecClock()
        LogEvent("recording started, target window " TargetHwnd " (" TargetTitle() ")")
    } else {
        LogEvent("stop requested by hotkey")
        FinishDictation()
    }
}

TargetTitle() {
    try return WinGetTitle("ahk_id " TargetHwnd)
    return ""
}

; Second press (or the countdown reaching zero): stop, wait for the hook, paste.
FinishDictation() {
    global Recording
    Recording := false
    StopRecClock()
    SetIndicator("… process", "E0B050")
    if !ClaudeWindowAlive() {
        LogEvent("stop failed: Claude Code window is gone")
        SetIndicator("No Claude", "E05050", 3000)
        return
    }
    ; Only stop the recording if it is still running. If Claude Code already
    ; stopped by itself, a Space on an empty prompt would start a new recording.
    if MicInUse()
        SendToClaude("{Space}")
    else
        LogEvent("mic already off, Space not sent")
    ; Claude Code auto-submits transcripts of 3+ words. Shorter ones stay
    ; in the input, so if nothing arrives we press Enter once and wait again.
    text := WaitForText(6000)
    if (text = "") {
        LogEvent("no text after 6 s, sending Enter")
        SendToClaude("{Enter}")
        text := WaitForText(6000)
    }
    DeliverText(text, "No text", 3000)
}

; The microphone went off on its own and no file has arrived yet.
ClaudeStoppedItself() {
    global Recording
    Recording := false
    LogEvent("mic went off by itself")
    SetIndicator("… process", "E0B050")
    DeliverText(WaitForText(2500), "No speech", 2000)
}

; Claude Code ended the recording and submitted without our second Space.
ClaudeSubmittedItself() {
    global Recording
    Recording := false
    LogEvent("Claude Code submitted by itself")
    SetIndicator("… process", "E0B050")
    DeliverText(WaitForText(2000), "No text", 3000)
}

; Pastes the text if there is any, otherwise shows the given error state.
DeliverText(text, errorLabel, errorMs) {
    if (text = "") {
        LogEvent("nothing to paste: " errorLabel)
        SetIndicator(errorLabel, "E05050", errorMs)
        return
    }
    PasteText(text)
    LogEvent("pasted " StrLen(text) " chars into " TargetHwnd " (" TargetTitle() ")")
    SetIndicator("✓ pasted", "60C060", 1500)
}

; Escape inside Claude Code aborts the recording: nothing is submitted,
; the hook does not run. Verified by hand on 2.1.257.
CancelDictation() {
    global Recording
    Recording := false
    StopRecClock()
    SendToClaude("{Escape}")
    LogEvent("cancelled by Escape")
    SetIndicator("✕ ESC", "E0A040", 1500)
}

WaitForText(timeoutMs) {
    start := A_TickCount
    while (A_TickCount - start < timeoutMs) {
        if FileExist(OutFile) {
            Sleep 50
            text := FileRead(OutFile, "UTF-8")
            try FileDelete OutFile
            return Trim(text, " `t`r`n")
        }
        Sleep 100
    }
    return ""
}

PasteText(text) {
    global TargetHwnd
    saved := ClipboardAll()
    A_Clipboard := text
    if !ClipWait(1)
        return
    if (TargetHwnd && WinExist("ahk_id " TargetHwnd)) {
        WinActivate "ahk_id " TargetHwnd
        WinWaitActive("ahk_id " TargetHwnd, , 2)
    }
    Send "^v"
    Sleep 500
    A_Clipboard := saved       ; restore whatever the user had in the clipboard
}

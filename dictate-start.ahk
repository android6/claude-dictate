#Requires AutoHotkey v2.0
#SingleInstance Off

; ------------------------------------------------------------------
; THE file to run. Picks the Claude profile, then starts dictate-core.ahk.
;
; A profile is a Claude config directory (CLAUDE_CONFIG_DIR) holding a
; .credentials.json. "default" means Claude Code's own ~\.claude.
;
;   first run  -> dictate.ini is created from dictate.example.ini and a folder
;                 dialog asks for the profile to dictate with (Cancel = default);
;                 its parent folder is remembered as [profiles] dir, so sibling
;                 profiles show up in the core's tray menu
;   argument   -> a config dir or "default" (the tray menu uses this to switch
;                 profiles and to reload)
;   otherwise  -> [profiles] last, i.e. the profile used last time, else default
; ------------------------------------------------------------------

Ini      := A_ScriptDir "\dictate.ini"
Dictate  := A_ScriptDir "\dictate-core.ahk"
FirstRun := !FileExist(Ini)

; On the first run the core keeps the Claude Code console visible, because
; Claude Code asks about trusting the folder (and maybe about logging in).
StartCore(configDir) {
    Run '"' A_AhkPath '" "' Dictate '" "' configDir '"' (FirstRun ? " firstrun" : "")
    ExitApp
}

if FirstRun {
    FileCopy A_ScriptDir "\dictate.example.ini", Ini
    chosen := DirSelect("*" EnvGet("USERPROFILE"), 2,
        "claude-dictate: select the folder of the Claude profile to dictate with"
        . " (it contains .credentials.json).`nCancel = use the default profile.")
    if (chosen != "" && !FileExist(chosen "\.credentials.json")) {
        MsgBox "No .credentials.json in " chosen "`nUsing the default profile instead.", "claude-dictate", "Iconi"
        chosen := ""
    }
    if (chosen != "") {
        SplitPath chosen, , &parent
        IniWrite parent, Ini, "profiles", "dir"
        IniWrite chosen, Ini, "profiles", "last"
        StartCore(chosen)
    }
    StartCore("default")
}

; Explicit argument from the tray menu.
if (A_Args.Length >= 1) {
    if (A_Args[1] != "default")
        IniWrite A_Args[1], Ini, "profiles", "last"
    StartCore(A_Args[1])
}

; The profile used last time, else default.
last := IniRead(Ini, "profiles", "last", "")
StartCore((last != "" && DirExist(last)) ? last : "default")

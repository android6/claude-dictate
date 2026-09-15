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

StartCore(configDir) {
    Run '"' A_AhkPath '" "' Dictate '" "' configDir '"'
    ExitApp
}

if FirstRun {
    ; The tree opens with Claude Code's own ~\.claude preselected: OK on it = the
    ; default profile, OK on another profile folder = that one, Cancel = do not start
    ; (nothing is created, the question comes back next time).
    defaultDir := EnvGet("USERPROFILE") "\.claude"
    chosen := DirSelect("*" defaultDir, 2,
        "Select the Claude profile folder.`n"
        . "Preselected .claude = default profile.`n"
        . "Can be changed later in the tray menu.")
    if (chosen = "")
        ExitApp
    if (chosen != defaultDir && !FileExist(chosen "\.credentials.json")) {
        MsgBox "This is not a Claude profile folder (no .credentials.json):`n" chosen "`n`nRun dictate-start.ahk again and pick a profile folder.", "claude-dictate", "Iconx"
        ExitApp
    }
    FileCopy A_ScriptDir "\dictate.example.ini", Ini
    if (chosen = defaultDir)
        StartCore("default")
    SplitPath chosen, , &parent
    IniWrite parent, Ini, "profiles", "dir"
    IniWrite chosen, Ini, "profiles", "last"
    StartCore(chosen)
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

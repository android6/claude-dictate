#Requires AutoHotkey v2.0
#SingleInstance Off

; ------------------------------------------------------------------
; THE file to run. Picks the Claude profile, then starts dictate-core.ahk.
;   [profiles] dir empty in dictate.ini  -> core with Claude's default config
;   an explicit argument (config dir or "default"; the core's tray menu uses
;   it to switch profiles and to reload)    -> that one
;   [profiles] last=... (written here on every start)  -> that one
;   otherwise -> the first profile found in [profiles] dir=... (a subfolder
;   with .credentials.json); switch from the core's tray menu
; ------------------------------------------------------------------

Ini         := A_ScriptDir "\dictate.ini"
FirstRun    := !FileExist(Ini)
if FirstRun                              ; first run: start from the example
    FileCopy A_ScriptDir "\dictate.example.ini", Ini
ProfilesDir := IniRead(Ini, "profiles", "dir", "")
Dictate     := A_ScriptDir "\dictate-core.ahk"

; On the first run the core keeps the Claude Code console visible, because
; Claude Code asks about trusting the folder (and maybe about logging in).
StartCore(configDir) {
    Run '"' A_AhkPath '" "' Dictate '" "' configDir '"' (FirstRun ? " firstrun" : "")
    ExitApp
}

; No profiles configured: plain Claude Code with its default config.
if (ProfilesDir = "")
    StartCore("default")
if !DirExist(ProfilesDir) {
    MsgBox "[profiles] dir in dictate.ini does not exist: " ProfilesDir, "claude-dictate", "Iconx"
    ExitApp
}

; Optional argument: a config dir, or "default", chosen from the core's tray menu.
configDir := ""
if (A_Args.Length >= 1) {
    if (A_Args[1] = "default")
        StartCore("default")
    configDir := A_Args[1]
}

; 1. the profile used last time
if (configDir = "") {
    last := IniRead(Ini, "profiles", "last", "")
    if (last != "" && DirExist(last))
        configDir := last
}
; 2. the first logged-in profile found (switch any time from the tray menu)
if (configDir = "") {
    Loop Files ProfilesDir "\*", "D"
        if (configDir = "" && FileExist(A_LoopFileFullPath "\.credentials.json"))
            configDir := A_LoopFileFullPath
}
if (configDir = "") {
    MsgBox "No logged-in Claude profiles found in " ProfilesDir, "claude-dictate", "Iconx"
    ExitApp
}

if !DirExist(configDir) {
    MsgBox "Profile directory not found: " configDir, "claude-dictate", "Iconx"
    ExitApp
}

IniWrite configDir, Ini, "profiles", "last"
StartCore(configDir)

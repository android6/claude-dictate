#Requires AutoHotkey v2.0
#SingleInstance Off

; ------------------------------------------------------------------
; Profile add-on for claude-dictate.
;
; THE file to run. Picks the Claude profile, then starts dictate-core.ahk.
;   [profiles] dir empty in dictate.ini  -> core with Claude's default config
;   [profiles] current=... names a live profile ([OpenChamber] configDir=<path>
;   pid=<owner process id>; today the OpenChamber launcher writes it) -> that one
;   [profiles] last=... (written here on every start)             -> that one
;   otherwise -> the first profile found in [profiles] dir=... (a subfolder
;   with .credentials.json); switch from the core's tray menu
;   An explicit argument (config dir or "default", used by the core's tray
;   menu to switch profiles) wins over all of the above.
; ------------------------------------------------------------------

Ini         := A_ScriptDir "\dictate.ini"
if !FileExist(Ini)                       ; first run: start from the example
    FileCopy A_ScriptDir "\dictate.example.ini", Ini
ProfilesDir := IniRead(Ini, "profiles", "dir", "")
CurrentIni  := IniRead(Ini, "profiles", "current", "")
Dictate     := A_ScriptDir "\dictate-core.ahk"

; No profiles configured: plain Claude Code with its default config.
if (ProfilesDir = "") {
    Run '"' A_AhkPath '" "' Dictate '" default'
    ExitApp
}
if !DirExist(ProfilesDir) {
    MsgBox "[profiles] dir in dictate.ini does not exist: " ProfilesDir, "claude-dictate", "Iconx"
    ExitApp
}

; Optional argument: a config dir, or "default", chosen from the core's tray menu.
configDir := ""
if (A_Args.Length >= 1) {
    if (A_Args[1] = "default") {
        Run '"' A_AhkPath '" "' Dictate '" default'
        ExitApp
    }
    configDir := A_Args[1]
}

; 1. the profile the running OpenChamber uses
if (configDir = "" && CurrentIni != "" && FileExist(CurrentIni)) {
    pid := IniRead(CurrentIni, "OpenChamber", "pid", "0")
    dir := IniRead(CurrentIni, "OpenChamber", "configDir", "")
    if (dir != "" && ProcessExist(Integer(pid)))
        configDir := dir
}
; 2. the profile used last time
if (configDir = "") {
    last := IniRead(Ini, "profiles", "last", "")
    if (last != "" && DirExist(last))
        configDir := last
}
; 3. the first logged-in profile found (switch any time from the tray menu)
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
Run '"' A_AhkPath '" "' Dictate '" "' configDir '"'

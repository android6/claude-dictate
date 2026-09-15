# claude-dictate

English · [Русский](README.ru.md)

System-wide voice dictation for Windows, powered by Claude Code's speech recognition.
Press Ctrl+Space in any application, speak, press again, and the text is pasted where
the cursor was. Claude Code only acts as a "dictaphone": a hook intercepts the dictated
text, the model never sees it, no tokens are spent. Transcription itself is free and
does not count toward subscription limits.

A small AutoHotkey utility, no build, no dependencies.

## Requirements

- Windows 10/11.
- [AutoHotkey v2](https://www.autohotkey.com/).
- [Claude Code](https://code.claude.com/) 2.1.116 or newer (tap-mode dictation),
  `claude.exe` in PATH. Signed in with a claude.ai account on a Pro/Max/Team/Enterprise
  plan; dictation is not available with an API key.
- A microphone that desktop apps are allowed to use (Windows privacy settings).

## Getting started

1. Copy the folder anywhere.
2. Double-click `dictate-start.ahk`. On the first run it asks for the folder of the Claude
   profile to dictate with; press Cancel to use the default one. Then a console with
   Claude Code opens, a small `○ ready` indicator appears in a screen corner, a green
   "H" icon in the tray.
3. The first time, Claude Code asks in that console whether to trust this folder:
   answer Yes. It will not ask again. From the second start on, the console opens
   minimized (see `windowMode` in `dictate.ini`).

Exit: right-click the indicator or the tray icon, `Exit`. The Claude Code console
closes together with the script.

## Usage

| Key | Action |
|---|---|
| Ctrl+Space | start recording |
| Ctrl+Space again | stop and paste the text into the window you started in |
| Escape while recording | cancel, paste nothing |

Outside of a recording the script does not touch Escape. The clipboard is restored after pasting.

Claude Code stops a recording by itself after 15 seconds of silence and after two minutes;
in both cases the text is pasted automatically. A completely silent recording gives `No speech`.

The indicator can be dragged with the mouse; the position is remembered. Right-click on it
or on the tray icon opens the menu: profiles (check mark on the current one, click to switch),
console window mode (hidden, minimized, visible), `Autostart` (check mark = shortcut
`dictate-start.ahk.lnk` in `shell:startup`), `Reload`, `Exit`.

| Indicator | Meaning |
|---|---|
| `○ ready` | ready |
| `● REC 1:53` | recording, countdown to two minutes, last 10 seconds in red |
| `… process` | recording stopped, waiting for the text |
| `✓ pasted` | pasted |
| `✕ ESC` | cancelled |
| `No speech` / `No text` / `No mic` / `No Claude` | error, see `dictate.log` |

## Settings

Everything is in `dictate.ini`, every key has a comment: hotkeys (AutoHotkey notation,
e.g. `^Space`, `^!d`, `#v`), path to `claude.exe`, window mode, indicator position and
opacity, countdown limits, profiles. On first run the file is created
from `dictate.example.ini`. After editing, `Reload` from the menu.

Recognition language: `dictate-settings.json`, key `language` (default `ru`; see the
[supported languages](https://code.claude.com/docs/en/voice-dictation)).

## Files

| File | Role |
|---|---|
| `dictate-start.ahk` | **run this one**: picks the profile and starts the core |
| `dictate-core.ahk` | the core: hotkey, Claude Code window, indicator, pasting. Does not run on its own |
| `dictate.ini` | settings; created from `dictate.example.ini`, not committed to git |
| `dictate-settings.json` | Claude Code settings for the dictation instance: language, tap mode, hook |
| `hook-grab.ps1` | the hook: intercepts the prompt, writes it to `dictate-out.txt`, blocks submission |
| `dictate.log` | log: hook lines with the recognized text and `[ahk]` lines from the script |

## How the profile is chosen

A profile is a Claude Code config directory (`CLAUDE_CONFIG_DIR`) with its own login,
recognizable by a `.credentials.json` inside. `default` is Claude Code's own `~\.claude`.

**One account, the usual case.** Press Cancel in the first-run dialog. The launcher starts
the core with `default`, the core leaves `CLAUDE_CONFIG_DIR` alone, Claude Code uses
`~\.claude`. The menu shows `Profile: default`.

**Several accounts.** Pick the profile folder in the first-run dialog. It becomes `last`
in `dictate.ini`, its parent folder becomes `dir`, and every sibling folder with a
`.credentials.json` shows up in the tray menu. With `dir` empty the parent is your user
folder, which covers the usual `~\.claude-work`, `~\.claude-personal` layout.

On every start the launcher takes the first that applies:

1. Command-line argument: a config directory or `default`. This is how the core restarts
   itself when you switch profiles from the menu or press `Reload`.
2. The `last` key: the profile used last time. Written automatically.
3. `default`.

## How it works

1. `dictate-core.ahk` runs `claude --settings dictate-settings.json` in a classic console
   (not Windows Terminal, which ignores keys posted to its window) and posts keys into it
   with `ControlSend`, without taking the focus.
2. `dictate-settings.json` enables tap-mode dictation and installs a `UserPromptSubmit` hook.
   The file is passed only to this instance; global Claude Code settings are untouched.
3. `hook-grab.ps1` receives the submitted prompt, writes it to `dictate-out.txt` and exits
   with code 2: the prompt is blocked, the model never sees it.
4. The script waits for the file, pastes the text via the clipboard and restores the old clipboard.
5. The real microphone state is read from the Windows registry
   (`CapabilityAccessManager\ConsentStore\microphone`); otherwise an empty recording
   cannot be told apart from a running one.

## Limitations

- Recognition quality is set by Anthropic's server and cannot be influenced. Russian mixed
  with English terms is recognized poorly. Claude Code has no custom vocabulary.
- Windows only. On macOS the hook scheme works the same, but AutoHotkey has to be replaced
  by Hammerspoon and posting keys to a window by tmux.
- At most two minutes per recording, a Claude Code limit.

# Mindfulness Prompt Bat

A Windows .bat file (batch-to-PowerShell hybrid) that serves as a combined mindfulness reminder and Pomodoro-style work timer. Double-clickable, runs from console with popup reminders.

**GitHub:** https://github.com/LocusScienceApps/Mindfulness_Prompt_Bat

## Key Architecture
- Single `.bat` file using `<# : ... #>` hybrid pattern to invoke PowerShell via `-Command` (not `-File`, which requires `.ps1` extension on Windows PowerShell 5.1)
- Non-modal WinForms popups (`$form.Show()` + `DoEvents()`) so the main timing loop can replace them when new events fire
- Absolute-time scheduling (all events computed from start time, no chained sleeps)
- Script-scope variables for popup state to avoid PowerShell closure issues
- No literal Unicode characters in source files — construct at runtime with `[char]0x2014` etc. (PowerShell 5.1 reads .ps1/.bat as ANSI by default, corrupting multi-byte UTF-8)

## Important Gotchas
- **File encoding:** Never put literal em-dashes or other non-ASCII in source. Use `$emDash = [char]0x2014` and string interpolation. Test .ps1 files fail silently with garbled variable names if encoding is wrong.
- **Batch hybrid:** Must use `-Command` with `Get-Content`/`scriptblock::Create`, NOT `-File` (which requires .ps1 extension in PS 5.1).
- **Timer closures:** Use `$script:` scope variables, not `GetNewClosure()`, for WinForms timer tick handlers.
- **Popup close prevention:** Use `$script:forceClose` flag to distinguish user X-click (blocked during countdown) from programmatic close (always allowed).
- **`$env:BAT_DIR`**: Batch header passes `%~dp0` to PowerShell via environment variable so the JSON settings file is always saved in the same folder as the .bat file.

## Current Features (as of 2026-02-13)
- **3-mode selection at startup:** Pomodoro only (P), Mindfulness only (R), or Both (B)
- **Mode-specific flows:** Each mode only shows/asks about relevant settings
  - P: work, break, sessions/set, long break, sets, sound (6 questions)
  - R: prompt text, interval, dismiss delay, sound (4 questions)
  - B: all 9 questions
- **Presets system (slots 0-9):** Save named presets with S at summary screen, load by pressing number at startup. Presets store the mode.
- **Settings management (M at startup):** Edit defaults (D), manage presets (P: rename/delete), factory reset (R)
- **Persistent settings:** `MindfulPrompter-settings.json` in same folder as .bat (created on first save, not at startup). In `.gitignore`.
- **Session-complete popup:** Larger window (500x300) with detailed stats, auto-dismiss after 60 seconds
- **Mindfulness-only mode:** Separate simple timer loop, runs indefinitely until window closed
- **Pomodoro-only mode:** Transition popups without mindfulness text, short 3s dismiss, no mid-work prompts
- **Terminology:** "sets" not "rounds", "sessions" not "pomodoros", "prompt" not "reminder", "break" not "short break"

## Session History

### Session 1 — 2026-02-12
- Built initial version, then v2 with rounds, quick-start, session-complete
- Fixed: batch hybrid, Unicode encoding, timer closures, popup close-prevention
- Passed automated timing tests

### Session 2 — 2026-02-13
- Backported UX redesign (A-F notes) from web app: new terminology, reordered prompts, defaults display, rewritten prompt text
- Added 3 major features: presets/templates, settings management menu, improved session-complete popup with auto-dismiss
- Added 3-mode startup selection (P/R/B) with mode-specific customize flows
- Added mindfulness-only timer (separate simple loop, no Pomodoro structure)
- Made Pomodoro-only popups clean (no mindfulness text, shorter dismiss)
- Fixed customize question ordering: sets before long break; long break only asked if sets > 1
- Reworded all customize prompts: parenthesized defaults, clearer instructions, removed "during work" from prompt interval
- Dismiss delay wording: "How long should mindfulness prompts stay on the screen before you can dismiss them?"
- Pomodoro-only dismiss delay = 0 (immediately closeable, stays until dismissed or replaced)
- Added prompt count limit for mindfulness-only mode (unlimited by default, or set a number)
- Long break hidden from defaults/summary displays when sets = 1
- Committed and pushed to GitHub

**Current state:**
- All features built; user testing in progress
- Question wording and ordering updated per user feedback

**Next session priorities:**
1. User testing feedback — fix any bugs found
2. Commit and push latest changes (mode selection, all recent work)
3. Any polish from testing

**Future features:**
- Shared sessions (multiple people get the same prompts together over the network) — likely requires the Electron/web wrapper app, not feasible in batch file alone

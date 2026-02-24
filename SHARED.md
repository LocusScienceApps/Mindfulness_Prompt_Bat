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

## Current Features (as of 2026-02-24)
- **Two-level flow:** Choose mode (M/P/B), then mode-specific menu with Enter/P/C/D/V/B options
- **Mode-specific settings:** Completely separate defaults and presets for each mode
  - **Mindfulness (M)**: 15min default interval (divides into 60min), must validate to 60min divisors
  - **Pomodoro (P)**: 25min work, 0sec dismiss delay (immediately closeable)
  - **Both (B)**: 25min work, 12.5min prompts (divides into work session)
- **Mode-specific presets (slots 1-5 per mode):** P1-P5, M1-M5, B1-B5 (15 total)
  - Load with number (e.g., "1"), view details with number+V (e.g., "1V")
  - Auto-generated names based on differences from defaults
  - Shows available vs occupied slots when saving
- **No auto-display of settings:** Press V anywhere to view current/default settings
- **Save options after customize:** Enter (start), P (save preset), D (save defaults with confirmation), V (view), B (back)
- **Settings storage:** `MindfulPrompter-settings.json` with defaultsP/defaultsM/defaultsB and mode-prefixed preset keys
- **Session-complete popup:** Larger window (500x300) with detailed stats, auto-dismiss after 60 seconds
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

### Session 3 — 2026-02-24
- **MAJOR REWRITE:** Complete redesign of settings architecture and UI flow based on user testing feedback
- Implemented mode-specific defaults (defaultsP/M/B) and presets (P1-P5, M1-M5, B1-B5)
- Changed M mode default from 12.5min to 15min (divides evenly into 60min clock cycle)
- Added validation: M mode intervals must divide evenly into 60 minutes
- New two-level flow: choose mode first, then mode-specific menu
- Removed all auto-display of settings — press V to view everywhere
- Changed shortcut letters: M=Mindfulness (was R), removed global Settings option
- Preset selection: number to load, number+V to view details (e.g., "1V")
- Save options after customize: Enter/P(reset)/D(efault)/V(iew)/B(ack)
- Auto-generated preset names based on differences from defaults
- Fixed preset save bug using direct property assignment instead of Add-Member
- Updated all timer loops to use M instead of R
- Committed and pushed to GitHub

**Current state:**
- Major rewrite complete and committed
- All new features implemented and ready for testing
- Settings structure completely changed (old settings files will need migration or reset)

**Next session priorities:**
1. **USER TESTING** — Test all flows end-to-end
2. Fix any bugs discovered during testing
3. Consider adding Back navigation during customize questions (currently only available after customize completes)

**Known limitations:**
- No Back navigation during customize questions (would require state-machine rewrite)
- Old settings files (from sessions 1-2) won't work with new structure — users will need to recreate presets/defaults

**Future features:**
- Back navigation during customize flow (significant refactor)
- Preset management UI (rename/delete existing presets)
- Shared sessions (network feature - requires Electron/web app)

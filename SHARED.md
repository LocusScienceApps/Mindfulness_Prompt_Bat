# Mindfulness Prompt Bat

A Windows .bat file (batch-to-PowerShell hybrid) that serves as a combined mindfulness reminder and Pomodoro-style work timer. Double-clickable, runs from console with popup reminders.

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

## Session — 2026-02-12
**What was done:**
- Built initial version with 6 prompts, flat pomodoro+break cycle
- Fixed batch-to-PowerShell hybrid (switched from `-File` to `-Command`)
- Fixed Unicode em-dash for PowerShell 5.1 compatibility
- Fixed timer closures using script-scope variables
- Improved divisor suggestions (clean decimals only)
- Added popup close-prevention during countdown
- Added v2: rounds structure, quick-start, scaled defaults, session-complete
  - Quick-start (Enter) vs full customization (S) with 9 prompts
  - Short break default = work/5, long break default = 4x short (20min with defaults)
  - Standard Pomodoro: long break replaces last short break in a round
  - Session auto-ends after configured number of rounds
  - Console shows round/pom progress
- Passed automated timing tests:
  - v1: 9 events across 2 flat cycles, all within 0.1s
  - v2: 18 events across 2 rounds (short breaks, long break, round transition, session complete), all within 0.1s
- User tested manually — everything working

**Current state:**
- Fully working v2 with rounds, quick-start, and session-complete
- Pushed to GitHub: https://github.com/LocusScienceApps/Mindfulness_Prompt_Bat

**Next steps for AI:**

### Feature 1: Favorites / Templates System
- Let user save up to 10 preset configurations (keys 0-9) with custom names
- Each preset stores answers to all 9 prompts
- Startup screen shows: Enter = default, S = customize, 0-9 = saved presets
- Display as: `0 — Wednesday pomodoro`, `1 — Focus @ Locus`, etc.
- Need persistent storage — likely a companion `.json` or `.ini` file alongside the .bat

### Feature 2: Settings Management
- **(a) Edit defaults:** Change what "Enter for defaults" uses (the quick-start values)
- **(b) Factory reset:** Revert to original hardcoded defaults (25min work, 5min break, etc.)
- **(c) Manage presets:** Add, edit, rename, delete saved quick-start templates
- Consider: settings menu accessible from the startup screen (e.g., press M for manage)

### Feature 3: Improved Session-Complete Popup
- Currently just prints text to console — should be a full popup like other events
- Include: mindfulness prompt text + summary of what was completed (rounds, pomodoros, total time)
- Same dismiss-delay countdown as other popups (e.g., 15 seconds before OK is enabled)
- After the countdown, user can close it manually OR it auto-closes after 1 minute
- This is the only popup with auto-close behavior (1 minute timeout after countdown finishes)

**Open questions:**
- Storage format for presets/settings: .json (easy to parse in PowerShell) vs .ini (simpler)?
- Where to store the settings file: same directory as the .bat? User's AppData?

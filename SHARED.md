# Mindfulness Prompt Bat

A Windows .bat file (batch-to-PowerShell hybrid) that serves as a combined mindfulness reminder and Pomodoro-style work timer. Double-clickable, runs from console with popup reminders.

## Key Architecture
- Single `.bat` file using `<# : ... #>` hybrid pattern to invoke PowerShell via `-Command` (not `-File`, which requires `.ps1` extension on Windows PowerShell 5.1)
- Non-modal WinForms popups (`$form.Show()` + `DoEvents()`) so the main timing loop can replace them when new events fire
- Absolute-time scheduling (all events computed from start time, no chained sleeps)
- Script-scope variables for popup state to avoid PowerShell closure issues

## Session — 2025-02-12
**What was done:**
- Built initial version with 6 prompts, flat pomodoro+break cycle
- Fixed batch-to-PowerShell hybrid (switched from `-File` to `-Command`)
- Fixed Unicode em-dash for PowerShell 5.1 compatibility
- Fixed timer closures using script-scope variables
- Improved divisor suggestions (clean decimals only)
- Added popup close-prevention during countdown
- Passed automated timing test (9 events across 2 cycles, all within 0.1s)
- User tested manually — prompts and popups working

**Current state:**
- Working flat cycle (pomodoro → short break → repeat forever)
- About to implement: rounds structure, long breaks, quick-start, session-complete, scaled defaults

**Next steps for AI:**
- Implement round/set structure (4 poms per round, long break between rounds)
- Add quick-start option (Enter for all defaults)
- Scale default short break (work/5), default long break (4× short), default rounds = 1
- Update popups and console display for round awareness
- Add session-complete behavior (finite rounds)

**Open questions:**
- None currently

# Mindfulness Reminder + Pomodoro Timer — Build Spec

**Goal:** Build a Windows `.bat` file (using the batch-to-PowerShell hybrid trick so it's double-clickable) that serves as a combined mindfulness reminder and pomodoro-style work timer. The file extension must be `.bat`. When double-clicked, it should open a console window and run entirely from there plus popup windows.

---

## STARTUP: Six sequential prompts

Each prompt displays its default value and clear instructions. Pressing Enter accepts the default. The prompts appear one at a time, each after the previous one is answered.

### Prompt 1 — Reminder text:
```
1. What reminder do you want today?
   Press Enter to use the default: "Are you doing what you should be doing?"
   Or type your own and press Enter:
```
Default: `Are you doing what you should be doing?`

### Prompt 2 — Work session length:
```
2. How long are your work sessions ("pomodoros"), in minutes?
   Press Enter for the default (25 minutes), or type a number and press Enter:
```
Default: `25`

### Prompt 3 — Reminder interval (with validation):
```
3. How often do you want a mindfulness reminder during work, in minutes?
   This must fit a whole number of times into your [X]-minute work session.
   Press Enter for the default ([Y] minutes), or type a number and press Enter:
```
Where `[X]` is whatever the user set in Prompt 2, and `[Y]` is the default, calculated as: half the work session length. So if the work session is 25 minutes, the default is 12.5. If the work session is 24 minutes, the default is 12. If the work session is 7 minutes, the default is 3.5.

**Validation rule:** `work_session_minutes / reminder_interval_minutes` must produce a whole number (integer) with no remainder. If the user enters a value that fails this check, show:
```
   That doesn't fit a whole number of times into [X] minutes.
   Some options that work: [list of reasonable divisors]
   Try again:
```
The list of reasonable divisors should include all values that divide into the work session length a whole number of times, filtered to only show values >= 1 minute, sorted from largest to smallest, and capped at about 8-10 suggestions so it doesn't become overwhelming. Include decimal values where relevant (e.g., 4.8 for a 24-minute session).

### Prompt 4 — Break length:
```
4. How long are your breaks between work sessions, in minutes?
   Press Enter for the default (5 minutes), or type a number and press Enter:
```
Default: `5`

### Prompt 5 — Dismiss delay:
```
5. How many seconds should the reminder stay on screen before you can dismiss it?
   This gives you time to actually reflect on the prompt.
   Press Enter for the default (15 seconds), or type a number and press Enter:
```
Default: `15`

### Prompt 6 — Sound:
```
6. Play a sound when reminders appear?
   Press Enter for the default (yes), or type N and press Enter for no sound:
```
Default: `yes`. Accept `y`, `yes`, `n`, `no` (case-insensitive), and Enter for default.

---

## AFTER PROMPTS: Summary and start

Show a summary of all settings:
```
==========================================
  YOUR SETTINGS:
  Reminder:      "Are you doing what you should be doing?"
  Work:          25 min
  Remind every:  12.5 min
  Break:         5 min
  Dismiss delay: 15 sec
  Sound:         On
==========================================

You're all set. Press Enter when you're ready to begin.
```

When the user presses Enter, record this moment as the **absolute start time**. ALL subsequent event scheduling is calculated from this start time. Nothing that happens during the session (popup display time, dismiss time, user delays) should ever shift the schedule.

---

## CORE TIMING LOGIC — CRITICAL

All events are scheduled as absolute offsets from the start time. The script should use a main loop that checks elapsed time against the schedule, NOT chained `Start-Sleep` calls.

**The schedule is a repeating cycle.** One full cycle = work session + break. Within each cycle:
- Mindfulness reminders fire at each reminder interval during the work phase only.
- The last reminder of the work phase coincides with the start of the break.
- The end of the break coincides with the start of the next work phase.

Example with defaults (start at 9:00:00, 12.5 min reminder, 25 min work, 5 min break):

- 9:00:00 — Session begins (Pomodoro #1, work phase)
- 9:12:30 — **Mid-session mindfulness popup**
- 9:25:00 — **Combined mindfulness + break popup** (Break #1 begins)
- 9:30:00 — **Combined mindfulness + work-starting popup** (Pomodoro #2 begins)
- 9:42:30 — Mid-session mindfulness popup
- 9:55:00 — **Combined mindfulness + break popup** (Break #2 begins)
- 10:00:00 — **Combined mindfulness + work-starting popup** (Pomodoro #3 begins)
- ...continues until the user closes the console window or presses Ctrl+C.

---

## POPUP REPLACEMENT LOGIC — CRITICAL

**New popups replace old ones.** If a popup is still open when the next scheduled event fires, the script must:
1. Programmatically close the current popup.
2. Immediately show the new popup.

This means the user only ever sees ONE popup at a time, and it's always the most current one. If the user walks away for hours, they come back to a single popup reflecting the current state of the schedule — not a backlog of old popups.

**Implementation requirement:** The popup cannot be a simple blocking modal. The script needs to run the popup on a separate thread or use a timer-based approach so the main loop can continue checking the schedule and close/replace the popup when needed. One approach: run the popup form non-modally (`$form.Show()` instead of `$form.ShowDialog()`) and use `[System.Windows.Forms.Application]::DoEvents()` in the main loop to keep the form responsive while the loop continues checking the schedule. When a new event fires, call `$form.Close()` on the existing form before showing the new one.

---

## POPUP WINDOWS — THREE VARIANTS, ONE MECHANISM

All popups use the same custom Windows Form (NOT a simple MessageBox). All popups share these behaviors:
- **TopMost** — always on top of other windows, centered on screen.
- **Cannot be closed for N seconds** (the user's configured dismiss delay, default 15). The OK button is disabled and grayed out, showing a countdown like `Wait (12s)...`. After the countdown, the button enables and shows `OK`.
- **If sound is enabled**, play a system notification sound when the popup appears.
- **The popup window should not be resizable or minimizable.** It should have a fixed size appropriate for the text content.
- **The popup blocks user interaction with other windows** as much as reasonably possible (TopMost + focus stealing), but does NOT literally lock the OS. If the user Alt+Tabs away, the popup remains TopMost.

The three variants differ only in their text content:

### Variant 1 — Mid-session mindfulness popup:
- Title bar: `Mindfulness Check`
- Body: The user's custom reminder text (e.g., "Are you doing what you should be doing?")

### Variant 2 — Combined mindfulness + break popup (end of work session):
- Title bar: `Mindfulness Check — Break Time`
- Body:
```
[User's custom reminder text]

Pomodoro #[N] complete! Take a [X]-minute break.
```

### Variant 3 — Combined mindfulness + work-starting popup (end of break):
- Title bar: `Mindfulness Check — Back to Work`
- Body:
```
[User's custom reminder text]

Break #[N] is over! Pomodoro #[N+1] is starting now. ([X]-minute work session)
```

---

## CONSOLE DISPLAY — LIVE STATUS

After the user presses Enter to begin, the console should show a continuously updating status display that refreshes every second:

**During work phase:**
```
Mindfulness Prompter is running
Next reminder in: 4:32
Next break in: 17:02
[Pomodoro #1 — Work]
```

**During break phase:**
```
Mindfulness Prompter is running
Break #1 ends in: 3:15
[Break #1]
```

Use cursor repositioning (`[Console]::SetCursorPosition()`) to update these lines in place rather than scrolling.

Above the live status area, maintain a scrolling event log that records events as they happen:
```
9:00 AM — Pomodoro #1 started
9:12 AM — Mindfulness check
9:25 AM — Break #1 started (5 min)
9:30 AM — Pomodoro #2 started
```

---

## IMPLEMENTATION NOTES

- The file must be a `.bat` file that uses the batch-to-PowerShell hybrid pattern (batch header that re-invokes itself via `powershell -ExecutionPolicy Bypass -NoProfile -File "%~f0"`).
- Use `Add-Type -AssemblyName System.Windows.Forms` and `System.Drawing` for custom popup windows.
- For the countdown timer on the OK button, use a `System.Windows.Forms.Timer` inside the form.
- For the system sound, use `[System.Media.SystemSounds]::Exclamation.Play()`.
- The popup replacement logic is the most complex part. One approach: run the popup form non-modally (`$form.Show()` instead of `$form.ShowDialog()`) and use `[System.Windows.Forms.Application]::DoEvents()` in the main loop to keep the form responsive while the loop continues checking the schedule. When a new event fires, call `$form.Close()` on the existing form before showing the new one.
- The main loop should sleep in short increments (e.g., 200-500 ms) and compare `(Get-Date) - $startTime` against the schedule to decide when events fire.
- The app runs until the user closes the console window or presses Ctrl+C. It does not run in the background after that.
- **Test with short intervals** (e.g., 5-second reminders, 15-second work, 5-second break) to verify: (a) timing doesn't drift, (b) popups replace correctly when the user is away, (c) the dismiss countdown works, (d) the console display updates smoothly, (e) the divisibility validation catches bad inputs and shows helpful alternatives.

<# :
@echo off
powershell -ExecutionPolicy Bypass -NoProfile -Command "& ([scriptblock]::Create((Get-Content -LiteralPath '%~f0' -Raw)))"
echo.
echo Press any key to close this window...
pause >nul
exit /b
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$emDash = [char]0x2014

# ============================================================
# UTILITY FUNCTIONS
# ============================================================
function Get-Divisors($total) {
    $divisors = @()
    $maxN = [math]::Floor($total)
    for ($n = 1; $n -le $maxN; $n++) {
        $d = $total / $n
        if ($d -lt 1) { continue }
        $dRounded = [math]::Round($d, 2)
        $check = $total / $dRounded
        if ([math]::Abs($check - [math]::Round($check)) -lt 0.001) {
            $already = $false
            foreach ($existing in $divisors) {
                if ([math]::Abs($existing - $dRounded) -lt 0.001) { $already = $true; break }
            }
            if (-not $already) { $divisors += $dRounded }
        }
    }
    $divisors = $divisors | Sort-Object -Descending
    if ($divisors.Count -gt 10) { $divisors = $divisors[0..9] }
    return $divisors
}

function Format-Num($val) {
    if ($val -eq [math]::Floor($val)) { return [string][int]$val }
    $rounded = [math]::Round($val, 2)
    if ($rounded -eq [math]::Floor($rounded)) { return [string][int]$rounded }
    return ([string]$rounded).TrimEnd('0').TrimEnd('.')
}

function Format-Duration($totalMinutes) {
    if ($totalMinutes -lt 1) {
        $secs = [math]::Round($totalMinutes * 60)
        return "${secs}s"
    }
    $hours = [math]::Floor($totalMinutes / 60)
    $mins = [math]::Round($totalMinutes % 60)
    if ($hours -gt 0 -and $mins -gt 0) { return "${hours}h ${mins}m" }
    if ($hours -gt 0) { return "${hours}h" }
    return "${mins}m"
}

function Round-ToSecond($minutes) {
    return [math]::Round($minutes * 60) / 60
}

# ============================================================
# QUICK START OR CUSTOMIZE
# ============================================================
Write-Host ""
Write-Host "=== Mindfulness Prompter ==="
Write-Host ""
Write-Host "Press Enter to start with default settings, or S to customize:"
$quickChoice = Read-Host " "

if ([string]::IsNullOrWhiteSpace($quickChoice)) {
    # Quick start with all defaults
    $reminderText = "Are you doing what you should be doing?"
    $workMinutes = [double]25
    $reminderMinutes = [double]12.5
    $shortBreakMinutes = [double]5        # 25 / 5
    $pomsPerRound = 4
    $longBreakMinutes = [double]20        # 4 * shortBreak
    $totalRounds = 1
    $dismissSeconds = 15
    $playSound = $true
} else {
    # ========================================================
    # PROMPT 1 — Reminder text
    # ========================================================
    Write-Host ""
    Write-Host "1. What reminder do you want today?"
    Write-Host "   Press Enter to use the default: `"Are you doing what you should be doing?`""
    Write-Host "   Or type your own and press Enter:"
    $inp = Read-Host "  "
    if ([string]::IsNullOrWhiteSpace($inp)) {
        $reminderText = "Are you doing what you should be doing?"
    } else {
        $reminderText = $inp.Trim()
    }

    # ========================================================
    # PROMPT 2 — Pomodoro length
    # ========================================================
    Write-Host ""
    Write-Host "2. How long are your pomodoros (work sessions), in minutes?"
    Write-Host "   Press Enter for the default (25 minutes), or type a number and press Enter:"
    while ($true) {
        $inp = Read-Host "  "
        if ([string]::IsNullOrWhiteSpace($inp)) {
            $workMinutes = [double]25
            break
        }
        $parsed = [double]0
        if ([double]::TryParse($inp, [ref]$parsed) -and $parsed -gt 0) {
            $workMinutes = $parsed
            break
        }
        Write-Host "   Please enter a positive number."
    }

    # ========================================================
    # PROMPT 3 — Reminder interval (with validation)
    # ========================================================
    $defaultReminder = $workMinutes / 2
    $defaultReminderDisplay = Format-Num $defaultReminder
    $workDisplayPrompt = Format-Num $workMinutes
    Write-Host ""
    Write-Host "3. How often do you want a mindfulness reminder during work, in minutes?"
    Write-Host "   This must fit a whole number of times into your $workDisplayPrompt-minute pomodoro."
    Write-Host "   Press Enter for the default ($defaultReminderDisplay minutes), or type a number and press Enter:"
    while ($true) {
        $inp = Read-Host "  "
        if ([string]::IsNullOrWhiteSpace($inp)) {
            $reminderMinutes = $defaultReminder
            break
        }
        $parsed = [double]0
        if ([double]::TryParse($inp, [ref]$parsed) -and $parsed -gt 0) {
            $ratio = $workMinutes / $parsed
            if ([math]::Abs($ratio - [math]::Round($ratio)) -lt 0.0001) {
                $reminderMinutes = $parsed
                break
            } else {
                $divs = Get-Divisors $workMinutes
                $divList = ($divs | ForEach-Object { Format-Num $_ }) -join ", "
                Write-Host "   That doesn't fit a whole number of times into $workDisplayPrompt minutes."
                Write-Host "   Some options that work: $divList"
                Write-Host "   Try again:"
            }
        } else {
            Write-Host "   Please enter a positive number."
        }
    }

    # ========================================================
    # PROMPT 4 — Short break length (scaled default)
    # ========================================================
    $defaultShort = Round-ToSecond ($workMinutes / 5)
    $defaultShortDisplay = Format-Num $defaultShort
    Write-Host ""
    Write-Host "4. How long are short breaks between pomodoros, in minutes?"
    Write-Host "   Press Enter for the default ($defaultShortDisplay minutes), or type a number and press Enter:"
    while ($true) {
        $inp = Read-Host "  "
        if ([string]::IsNullOrWhiteSpace($inp)) {
            $shortBreakMinutes = $defaultShort
            break
        }
        $parsed = [double]0
        if ([double]::TryParse($inp, [ref]$parsed) -and $parsed -gt 0) {
            $shortBreakMinutes = $parsed
            break
        }
        Write-Host "   Please enter a positive number."
    }

    # ========================================================
    # PROMPT 5 — Pomodoros per round
    # ========================================================
    Write-Host ""
    Write-Host "5. How many pomodoros in each round (before a long break)?"
    Write-Host "   Press Enter for the default (4), or type a number and press Enter:"
    while ($true) {
        $inp = Read-Host "  "
        if ([string]::IsNullOrWhiteSpace($inp)) {
            $pomsPerRound = 4
            break
        }
        $parsed = 0
        if ([int]::TryParse($inp, [ref]$parsed) -and $parsed -gt 0) {
            $pomsPerRound = $parsed
            break
        }
        Write-Host "   Please enter a positive whole number."
    }

    # ========================================================
    # PROMPT 6 — Long break length
    # ========================================================
    $defaultLong = Round-ToSecond (4 * $shortBreakMinutes)
    $defaultLongDisplay = Format-Num $defaultLong
    Write-Host ""
    Write-Host "6. How long should the long break between rounds be, in minutes?"
    Write-Host "   Press Enter for the default ($defaultLongDisplay minutes), or type a number and press Enter:"
    while ($true) {
        $inp = Read-Host "  "
        if ([string]::IsNullOrWhiteSpace($inp)) {
            $longBreakMinutes = $defaultLong
            break
        }
        $parsed = [double]0
        if ([double]::TryParse($inp, [ref]$parsed) -and $parsed -gt 0) {
            $longBreakMinutes = $parsed
            break
        }
        Write-Host "   Please enter a positive number."
    }

    # ========================================================
    # PROMPT 7 — Number of rounds
    # ========================================================
    Write-Host ""
    Write-Host "7. How many rounds before the session ends?"
    Write-Host "   Press Enter for the default (1 round), type a number, or type 0 to run until stopped:"
    while ($true) {
        $inp = Read-Host "  "
        if ([string]::IsNullOrWhiteSpace($inp)) {
            $totalRounds = 1
            break
        }
        $parsed = 0
        if ([int]::TryParse($inp, [ref]$parsed) -and $parsed -ge 0) {
            $totalRounds = $parsed
            break
        }
        Write-Host "   Please enter 0 (unlimited) or a positive whole number."
    }

    # ========================================================
    # PROMPT 8 — Dismiss delay
    # ========================================================
    Write-Host ""
    Write-Host "8. How many seconds should reminders stay on screen before you can dismiss them?"
    Write-Host "   This gives you time to actually reflect on the prompt."
    Write-Host "   Press Enter for the default (15 seconds), or type a number and press Enter:"
    while ($true) {
        $inp = Read-Host "  "
        if ([string]::IsNullOrWhiteSpace($inp)) {
            $dismissSeconds = 15
            break
        }
        $parsed = 0
        if ([int]::TryParse($inp, [ref]$parsed) -and $parsed -gt 0) {
            $dismissSeconds = $parsed
            break
        }
        Write-Host "   Please enter a positive whole number."
    }

    # ========================================================
    # PROMPT 9 — Sound
    # ========================================================
    Write-Host ""
    Write-Host "9. Play a sound when reminders appear?"
    Write-Host "   Press Enter for the default (yes), or type N and press Enter for no sound:"
    while ($true) {
        $inp = Read-Host "  "
        if ([string]::IsNullOrWhiteSpace($inp) -or $inp.Trim() -match '^(y|yes)$') {
            $playSound = $true
            break
        }
        if ($inp.Trim() -match '^(n|no)$') {
            $playSound = $false
            break
        }
        Write-Host "   Please enter Y or N."
    }
}

# ============================================================
# SUMMARY
# ============================================================
$soundText = if ($playSound) { "On" } else { "Off" }
$workDisplay = Format-Num $workMinutes
$reminderDisplay = Format-Num $reminderMinutes
$shortBreakDisplay = Format-Num $shortBreakMinutes
$longBreakDisplay = Format-Num $longBreakMinutes
$roundsDisplay = if ($totalRounds -eq 0) { "Unlimited" } else { [string]$totalRounds }

# Calculate total session time
$roundWorkMin = $pomsPerRound * $workMinutes + ($pomsPerRound - 1) * $shortBreakMinutes
$roundWithLongMin = $roundWorkMin + $longBreakMinutes
if ($totalRounds -eq 0) {
    $totalTimeDisplay = "Runs until stopped"
} elseif ($totalRounds -eq 1) {
    $totalTimeDisplay = Format-Duration $roundWorkMin
} else {
    $totalMin = ($totalRounds - 1) * $roundWithLongMin + $roundWorkMin
    $totalTimeDisplay = Format-Duration $totalMin
}

Write-Host ""
Write-Host "=========================================="
Write-Host "  YOUR SETTINGS:"
Write-Host "  Reminder:        `"$reminderText`""
Write-Host "  Pomodoro:        $workDisplay min"
Write-Host "  Remind every:    $reminderDisplay min"
Write-Host "  Short break:     $shortBreakDisplay min"
Write-Host "  Pomodoros/round: $pomsPerRound"
Write-Host "  Long break:      $longBreakDisplay min"
Write-Host "  Rounds:          $roundsDisplay"
Write-Host "  Dismiss delay:   $dismissSeconds sec"
Write-Host "  Sound:           $soundText"
Write-Host "  ---"
Write-Host "  Total session:   $totalTimeDisplay"
Write-Host "=========================================="
Write-Host ""
Write-Host "You're all set. Press Enter when you're ready to begin."
Read-Host | Out-Null

# ============================================================
# CONVERT TO SECONDS AND COMPUTE TIMING
# ============================================================
$workSec = [math]::Round($workMinutes * 60)
$shortBreakSec = [math]::Round($shortBreakMinutes * 60)
$longBreakSec = [math]::Round($longBreakMinutes * 60)
$reminderSec = $reminderMinutes * 60   # no rounding — must divide evenly into workSec
$miniCycleSec = $workSec + $shortBreakSec
$roundSec = ($pomsPerRound - 1) * $miniCycleSec + $workSec + $longBreakSec
$lastRoundSec = ($pomsPerRound - 1) * $miniCycleSec + $workSec
$remindersPerWork = [int][math]::Round($workSec / $reminderSec)

# ============================================================
# POPUP STATE AND FUNCTIONS
# ============================================================
$script:currentForm = $null
$script:popupButton = $null
$script:popupTimer = $null
$script:dismissCountdown = 0
$script:forceClose = $false

function Show-Popup {
    param(
        [string]$Title,
        [string]$Body,
        [int]$DismissDelay,
        [bool]$Sound
    )
    Close-Popup
    if ($Sound) { [System.Media.SystemSounds]::Exclamation.Play() }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Width = 450
    $form.Height = 240
    $form.ShowInTaskbar = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Body
    $label.AutoSize = $false
    $label.Width = 410
    $label.Height = 130
    $label.Location = New-Object System.Drawing.Point(15, 15)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $label.TextAlign = "MiddleCenter"
    $form.Controls.Add($label)

    $button = New-Object System.Windows.Forms.Button
    $button.Width = 120
    $button.Height = 35
    $button.Location = New-Object System.Drawing.Point(160, 155)
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $button.Enabled = $false
    $button.Text = "Wait (${DismissDelay}s)..."
    $form.Controls.Add($button)
    $form.AcceptButton = $button

    $script:popupButton = $button
    $script:dismissCountdown = $DismissDelay

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({
        $script:dismissCountdown = $script:dismissCountdown - 1
        if ($script:dismissCountdown -le 0) {
            $script:popupTimer.Stop()
            $script:popupButton.Enabled = $true
            $script:popupButton.Text = "OK"
            $script:popupButton.Focus()
        } else {
            $script:popupButton.Text = "Wait ($($script:dismissCountdown)s)..."
        }
    })
    $timer.Start()
    $script:popupTimer = $timer

    $button.Add_Click({
        $script:popupTimer.Stop()
        $script:forceClose = $true
        $script:currentForm.Close()
    })

    $form.Add_FormClosing({
        if (-not $script:forceClose -and $script:dismissCountdown -gt 0) {
            $_.Cancel = $true
        } else {
            if ($script:popupTimer -ne $null) { $script:popupTimer.Stop() }
        }
    })

    $script:currentForm = $form
    $script:forceClose = $false
    $form.Show()
    $form.Activate()
    $form.BringToFront()
}

function Close-Popup {
    if ($script:currentForm -ne $null -and -not $script:currentForm.IsDisposed) {
        if ($script:popupTimer -ne $null) { $script:popupTimer.Stop() }
        $script:forceClose = $true
        $script:currentForm.Close()
        $script:currentForm.Dispose()
        $script:currentForm = $null
        $script:forceClose = $false
    }
}

# ============================================================
# DISPLAY FUNCTIONS
# ============================================================
$script:logLines = @()
$script:statusAreaTop = -1

function Write-Log($msg) {
    $ts = (Get-Date).ToString("h:mm:ss tt")
    $script:logLines += "$ts $emDash $msg"
    Refresh-Display
}

function Refresh-Display {
    [Console]::Clear()
    foreach ($line in $script:logLines) {
        Write-Host $line
    }
    Write-Host ""
    $script:statusAreaTop = [Console]::CursorTop
}

function Update-Status {
    param([string[]]$Lines)
    if ($script:statusAreaTop -lt 0) { return }
    try { $width = [Console]::WindowWidth } catch { $width = 80 }
    [Console]::SetCursorPosition(0, $script:statusAreaTop)
    foreach ($line in $Lines) {
        Write-Host ($line.PadRight($width - 1))
    }
    Write-Host ("".PadRight($width - 1))
}

# ============================================================
# MAIN LOOP
# ============================================================
$startTime = Get-Date
$lastEventKey = ""
$sessionComplete = $false

$roundsLabel = if ($totalRounds -eq 0) { "" } else { "/$totalRounds" }

Write-Log "Pomodoro #1 started (Round 1$roundsLabel, Pom 1/$pomsPerRound)"
Refresh-Display

while (-not $sessionComplete) {
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.Application]::DoEvents()

    $now = Get-Date
    $elapsed = ($now - $startTime).TotalSeconds

    # --- Determine round and offset within round ---
    if ($totalRounds -eq 0) {
        # Infinite mode: every round has a long break
        $roundIndex = [math]::Floor($elapsed / $roundSec)
        $roundOffset = $elapsed - ($roundIndex * $roundSec)
        $isLastRound = $false
    } else {
        # Finite mode: last round has no long break
        $allButLastSec = ($totalRounds - 1) * $roundSec

        # Check for session complete
        if ($elapsed -ge $allButLastSec + $lastRoundSec) {
            $sessionComplete = $true
            $totalPoms = $totalRounds * $pomsPerRound
            $actualMin = $elapsed / 60
            Close-Popup
            $bodyText = "$reminderText`r`n`r`nAll $totalRounds round(s) done! $totalPoms pomodoros in $(Format-Duration $actualMin).`r`nGreat work!"
            Show-Popup -Title "Session Complete!" -Body $bodyText -DismissDelay $dismissSeconds -Sound $playSound
            Write-Log "Session complete! $totalPoms pomodoros in $(Format-Duration $actualMin)."
            Refresh-Display
            # Wait for user to dismiss the popup
            while ($script:currentForm -ne $null -and -not $script:currentForm.IsDisposed) {
                Start-Sleep -Milliseconds 200
                [System.Windows.Forms.Application]::DoEvents()
            }
            continue
        }

        if ($elapsed -lt $allButLastSec) {
            $roundIndex = [math]::Floor($elapsed / $roundSec)
            $roundOffset = $elapsed - ($roundIndex * $roundSec)
        } else {
            $roundIndex = $totalRounds - 1
            $roundOffset = $elapsed - $allButLastSec
        }
        $isLastRound = ($roundIndex -eq $totalRounds - 1)
    }

    $roundNum = $roundIndex + 1

    # --- Determine position within round ---
    # A round: (N-1) mini-cycles [work+short] + last pom [work + long break]
    $firstPartSec = ($pomsPerRound - 1) * $miniCycleSec

    if ($roundOffset -lt $firstPartSec) {
        # In one of the first (N-1) pom slots (work + short break)
        $pomInRound = [math]::Floor($roundOffset / $miniCycleSec)
        $miniOffset = $roundOffset - ($pomInRound * $miniCycleSec)
        if ($miniOffset -lt $workSec) {
            $phase = "work"
            $workPhaseOffset = $miniOffset
        } else {
            $phase = "short_break"
            $breakPhaseOffset = $miniOffset - $workSec
        }
    } else {
        # In the last pom slot of the round
        $pomInRound = $pomsPerRound - 1
        $lastPomOffset = $roundOffset - $firstPartSec
        if ($lastPomOffset -lt $workSec) {
            $phase = "work"
            $workPhaseOffset = $lastPomOffset
        } else {
            # Long break (only reached if not the last round — handled by session-complete check above)
            $phase = "long_break"
            $breakPhaseOffset = $lastPomOffset - $workSec
        }
    }

    $pomInRoundNum = $pomInRound + 1
    $globalPom = $roundIndex * $pomsPerRound + $pomInRoundNum
    $statusLines = @()

    # --- WORK PHASE ---
    if ($phase -eq "work") {
        $reminderIndex = [math]::Floor($workPhaseOffset / $reminderSec)
        $eventKey = "r${roundIndex}_p${pomInRound}_w${reminderIndex}"

        if ($eventKey -ne $lastEventKey) {
            $lastEventKey = $eventKey

            if ($reminderIndex -eq 0) {
                if ($roundIndex -eq 0 -and $pomInRound -eq 0) {
                    # Very first pomodoro — already logged at startup
                }
                elseif ($pomInRound -eq 0) {
                    # First pom of a new round (came from long break)
                    Close-Popup
                    $bodyText = "$reminderText`r`n`r`nRound $roundIndex complete! Round $roundNum starting.`r`nPomodoro #$globalPom begins. ($workDisplay-min work session)"
                    Show-Popup -Title "Mindfulness Check $emDash New Round" -Body $bodyText -DismissDelay $dismissSeconds -Sound $playSound
                    Write-Log "Pomodoro #$globalPom started (Round $roundNum$roundsLabel, Pom $pomInRoundNum/$pomsPerRound)"
                    Refresh-Display
                }
                else {
                    # Came from a short break
                    Close-Popup
                    $bodyText = "$reminderText`r`n`r`nBreak over! Pomodoro #$globalPom starting. ($workDisplay-min work session)"
                    Show-Popup -Title "Mindfulness Check $emDash Back to Work" -Body $bodyText -DismissDelay $dismissSeconds -Sound $playSound
                    Write-Log "Pomodoro #$globalPom started (Round $roundNum$roundsLabel, Pom $pomInRoundNum/$pomsPerRound)"
                    Refresh-Display
                }
            }
            elseif ($reminderIndex -gt 0 -and $reminderIndex -lt $remindersPerWork) {
                Close-Popup
                Show-Popup -Title "Mindfulness Check" -Body $reminderText -DismissDelay $dismissSeconds -Sound $playSound
                Write-Log "Mindfulness check"
                Refresh-Display
            }
        }

        # Status countdowns
        $nextReminderAt = ([math]::Floor($workPhaseOffset / $reminderSec) + 1) * $reminderSec
        if ($nextReminderAt -gt $workSec) { $nextReminderAt = $workSec }
        $secsToReminder = [math]::Max(0, $nextReminderAt - $workPhaseOffset)
        $secsToBreak = [math]::Max(0, $workSec - $workPhaseOffset)

        $remMin = [math]::Floor($secsToReminder / 60)
        $remSec = [int]($secsToReminder % 60)
        $brkMin = [math]::Floor($secsToBreak / 60)
        $brkSec = [int]($secsToBreak % 60)

        # Label for what kind of break is next
        if ($pomInRound -lt $pomsPerRound - 1) {
            $nextBreakLabel = ""
        } elseif ($isLastRound) {
            $nextBreakLabel = " (session ends)"
        } else {
            $nextBreakLabel = " (long break)"
        }

        $statusLines = @(
            "Mindfulness Prompter is running",
            "Next reminder in: ${remMin}:$($remSec.ToString('00'))",
            "Next break in: ${brkMin}:$($brkSec.ToString('00'))$nextBreakLabel",
            "[Pomodoro #$globalPom $emDash Round $roundNum$roundsLabel, Pom $pomInRoundNum/$pomsPerRound $emDash Work]"
        )
    }
    # --- SHORT BREAK ---
    elseif ($phase -eq "short_break") {
        $eventKey = "r${roundIndex}_p${pomInRound}_sbreak"
        if ($eventKey -ne $lastEventKey) {
            $lastEventKey = $eventKey
            Close-Popup
            $bodyText = "$reminderText`r`n`r`nPomodoro #$globalPom complete! Take a $shortBreakDisplay-min short break."
            Show-Popup -Title "Mindfulness Check $emDash Short Break" -Body $bodyText -DismissDelay $dismissSeconds -Sound $playSound
            Write-Log "Short break ($shortBreakDisplay min) $emDash after Pom $pomInRoundNum/$pomsPerRound"
            Refresh-Display
        }

        $secsLeft = [math]::Max(0, $shortBreakSec - $breakPhaseOffset)
        $m = [math]::Floor($secsLeft / 60)
        $s = [int]($secsLeft % 60)

        $statusLines = @(
            "Mindfulness Prompter is running",
            "Short break ends in: ${m}:$($s.ToString('00'))",
            "[Short Break $emDash after Pomodoro #$globalPom]",
            "Round $roundNum$roundsLabel, Pom $pomInRoundNum/$pomsPerRound complete"
        )
    }
    # --- LONG BREAK ---
    elseif ($phase -eq "long_break") {
        $eventKey = "r${roundIndex}_lbreak"
        if ($eventKey -ne $lastEventKey) {
            $lastEventKey = $eventKey
            Close-Popup
            $bodyText = "$reminderText`r`n`r`nRound $roundNum complete! Take a $longBreakDisplay-min long break."
            Show-Popup -Title "Mindfulness Check $emDash Long Break" -Body $bodyText -DismissDelay $dismissSeconds -Sound $playSound
            Write-Log "Long break ($longBreakDisplay min) $emDash Round $roundNum$roundsLabel complete!"
            Refresh-Display
        }

        $secsLeft = [math]::Max(0, $longBreakSec - $breakPhaseOffset)
        $m = [math]::Floor($secsLeft / 60)
        $s = [int]($secsLeft % 60)

        $statusLines = @(
            "Mindfulness Prompter is running",
            "Long break ends in: ${m}:$($s.ToString('00'))",
            "[Long Break $emDash Round $roundNum$roundsLabel complete]"
        )
    }

    Update-Status $statusLines
}

Write-Host ""
Write-Host "Session ended. Well done!"

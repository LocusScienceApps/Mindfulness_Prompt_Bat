<# :
@echo off
powershell -ExecutionPolicy Bypass -NoProfile -Command "& ([scriptblock]::Create((Get-Content -LiteralPath '%~f0' -Raw)))"
pause
exit /b
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$emDash = [char]0x2014

# ============================================================
# PROMPT 1 — Reminder text
# ============================================================
Write-Host ""
Write-Host "1. What reminder do you want today?"
Write-Host "   Press Enter to use the default: `"Are you doing what you should be doing?`""
Write-Host "   Or type your own and press Enter:"
$input1 = Read-Host "  "
if ([string]::IsNullOrWhiteSpace($input1)) {
    $reminderText = "Are you doing what you should be doing?"
} else {
    $reminderText = $input1.Trim()
}

# ============================================================
# PROMPT 2 — Work session length
# ============================================================
Write-Host ""
Write-Host "2. How long are your work sessions (`"pomodoros`"), in minutes?"
Write-Host "   Press Enter for the default (25 minutes), or type a number and press Enter:"
while ($true) {
    $input2 = Read-Host "  "
    if ([string]::IsNullOrWhiteSpace($input2)) {
        $workMinutes = [double]25
        break
    }
    $parsed = [double]0
    if ([double]::TryParse($input2, [ref]$parsed) -and $parsed -gt 0) {
        $workMinutes = $parsed
        break
    }
    Write-Host "   Please enter a positive number."
}

# ============================================================
# PROMPT 3 — Reminder interval (with divisibility validation)
# ============================================================
function Get-Divisors($total) {
    $divisors = @()
    $maxN = [math]::Floor($total)
    for ($n = 1; $n -le $maxN; $n++) {
        $d = $total / $n
        if ($d -lt 1) { continue }
        # Round to 2 decimal places and verify it still divides evenly
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
    # Remove trailing zeros from decimal
    return ([string]$val).TrimEnd('0').TrimEnd('.')
}

$defaultReminder = $workMinutes / 2
$defaultReminderDisplay = Format-Num $defaultReminder
$workDisplayPrompt = Format-Num $workMinutes
Write-Host ""
Write-Host "3. How often do you want a mindfulness reminder during work, in minutes?"
Write-Host "   This must fit a whole number of times into your $workDisplayPrompt-minute work session."
Write-Host "   Press Enter for the default ($defaultReminderDisplay minutes), or type a number and press Enter:"
while ($true) {
    $input3 = Read-Host "  "
    if ([string]::IsNullOrWhiteSpace($input3)) {
        $reminderMinutes = $defaultReminder
        break
    }
    $parsed = [double]0
    if ([double]::TryParse($input3, [ref]$parsed) -and $parsed -gt 0) {
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

# ============================================================
# PROMPT 4 — Break length
# ============================================================
Write-Host ""
Write-Host "4. How long are your breaks between work sessions, in minutes?"
Write-Host "   Press Enter for the default (5 minutes), or type a number and press Enter:"
while ($true) {
    $input4 = Read-Host "  "
    if ([string]::IsNullOrWhiteSpace($input4)) {
        $breakMinutes = [double]5
        break
    }
    $parsed = [double]0
    if ([double]::TryParse($input4, [ref]$parsed) -and $parsed -gt 0) {
        $breakMinutes = $parsed
        break
    }
    Write-Host "   Please enter a positive number."
}

# ============================================================
# PROMPT 5 — Dismiss delay
# ============================================================
Write-Host ""
Write-Host "5. How many seconds should the reminder stay on screen before you can dismiss it?"
Write-Host "   This gives you time to actually reflect on the prompt."
Write-Host "   Press Enter for the default (15 seconds), or type a number and press Enter:"
while ($true) {
    $input5 = Read-Host "  "
    if ([string]::IsNullOrWhiteSpace($input5)) {
        $dismissSeconds = 15
        break
    }
    $parsed = 0
    if ([int]::TryParse($input5, [ref]$parsed) -and $parsed -gt 0) {
        $dismissSeconds = $parsed
        break
    }
    Write-Host "   Please enter a positive whole number."
}

# ============================================================
# PROMPT 6 — Sound
# ============================================================
Write-Host ""
Write-Host "6. Play a sound when reminders appear?"
Write-Host "   Press Enter for the default (yes), or type N and press Enter for no sound:"
while ($true) {
    $input6 = Read-Host "  "
    if ([string]::IsNullOrWhiteSpace($input6) -or $input6.Trim() -match '^(y|yes)$') {
        $playSound = $true
        break
    }
    if ($input6.Trim() -match '^(n|no)$') {
        $playSound = $false
        break
    }
    Write-Host "   Please enter Y or N."
}

# ============================================================
# SUMMARY
# ============================================================
$soundText = if ($playSound) { "On" } else { "Off" }
$reminderDisplay = Format-Num $reminderMinutes
$workDisplay = Format-Num $workMinutes
$breakDisplay = Format-Num $breakMinutes

Write-Host ""
Write-Host "=========================================="
Write-Host "  YOUR SETTINGS:"
Write-Host "  Reminder:      `"$reminderText`""
Write-Host "  Work:          $workDisplay min"
Write-Host "  Remind every:  $reminderDisplay min"
Write-Host "  Break:         $breakDisplay min"
Write-Host "  Dismiss delay: $dismissSeconds sec"
Write-Host "  Sound:         $soundText"
Write-Host "=========================================="
Write-Host ""
Write-Host "You're all set. Press Enter when you're ready to begin."
Read-Host | Out-Null

# ============================================================
# CONVERT TO SECONDS FOR TIMING
# ============================================================
$workSec = $workMinutes * 60
$breakSec = $breakMinutes * 60
$reminderSec = $reminderMinutes * 60
$cycleSec = $workSec + $breakSec

# ============================================================
# POPUP STATE
# ============================================================
$script:currentForm = $null
$script:popupButton = $null
$script:popupTimer = $null
$script:dismissCountdown = 0
$script:forceClose = $false

# ============================================================
# POPUP FUNCTIONS
# ============================================================
function Show-Popup {
    param(
        [string]$Title,
        [string]$Body,
        [int]$DismissDelay,
        [bool]$Sound
    )

    Close-Popup

    if ($Sound) {
        [System.Media.SystemSounds]::Exclamation.Play()
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = $Title
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.Width = 420
    $form.Height = 220
    $form.ShowInTaskbar = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Body
    $label.AutoSize = $false
    $label.Width = 380
    $label.Height = 110
    $label.Location = New-Object System.Drawing.Point(15, 15)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $label.TextAlign = "MiddleCenter"
    $form.Controls.Add($label)

    $button = New-Object System.Windows.Forms.Button
    $button.Width = 120
    $button.Height = 35
    $button.Location = New-Object System.Drawing.Point(145, 135)
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $button.Enabled = $false
    $button.Text = "Wait (${DismissDelay}s)..."
    $form.Controls.Add($button)
    $form.AcceptButton = $button

    $script:popupButton = $button
    $script:dismissCountdown = $DismissDelay

    # Countdown timer using script-scope variables for reliable access
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

    # Prevent user from closing during countdown; allow programmatic close
    $form.Add_FormClosing({
        if (-not $script:forceClose -and $script:dismissCountdown -gt 0) {
            $_.Cancel = $true
        } else {
            $script:popupTimer.Stop()
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
# EVENT LOG + LIVE STATUS DISPLAY
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
    try {
        $width = [Console]::WindowWidth
    } catch {
        $width = 80
    }
    [Console]::SetCursorPosition(0, $script:statusAreaTop)
    foreach ($line in $Lines) {
        $padded = $line.PadRight($width - 1)
        Write-Host $padded
    }
    $blank = "".PadRight($width - 1)
    Write-Host $blank
}

# ============================================================
# MAIN LOOP
# ============================================================
$startTime = Get-Date
$lastEventKey = ""

Write-Log "Pomodoro #1 started"
Refresh-Display

$remindersPerWork = [int][math]::Round($workSec / $reminderSec)

while ($true) {
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.Application]::DoEvents()

    $now = Get-Date
    $elapsed = ($now - $startTime).TotalSeconds

    # Where are we in the cycle?
    $cycleIndex = [math]::Floor($elapsed / $cycleSec)
    $cycleOffset = $elapsed - ($cycleIndex * $cycleSec)

    $currentPom = $cycleIndex + 1
    $inWork = $cycleOffset -lt $workSec
    $statusLines = @()

    if ($inWork) {
        $reminderIndex = [math]::Floor($cycleOffset / $reminderSec)
        $eventKey = "c${cycleIndex}_r${reminderIndex}"

        if ($eventKey -ne $lastEventKey) {
            $lastEventKey = $eventKey

            if ($reminderIndex -eq 0 -and $cycleIndex -gt 0) {
                # End of break -> new work session
                $brkNum = $cycleIndex
                Close-Popup
                $bodyText = "$reminderText`r`n`r`nBreak #$brkNum is over! Pomodoro #$currentPom is starting now. ($workDisplay-minute work session)"
                Show-Popup -Title "Mindfulness Check $emDash Back to Work" -Body $bodyText -DismissDelay $dismissSeconds -Sound $playSound
                Write-Log "Pomodoro #$currentPom started"
                Refresh-Display
            }
            elseif ($reminderIndex -gt 0 -and $reminderIndex -lt $remindersPerWork) {
                # Mid-session mindfulness reminder
                Close-Popup
                Show-Popup -Title "Mindfulness Check" -Body $reminderText -DismissDelay $dismissSeconds -Sound $playSound
                Write-Log "Mindfulness check"
                Refresh-Display
            }
        }

        # Calculate countdown timers for status display
        $nextReminderAt = ([math]::Floor($cycleOffset / $reminderSec) + 1) * $reminderSec
        if ($nextReminderAt -gt $workSec) { $nextReminderAt = $workSec }
        $secsToReminder = [math]::Max(0, $nextReminderAt - $cycleOffset)
        $secsToBreak = [math]::Max(0, $workSec - $cycleOffset)

        $remMin = [math]::Floor($secsToReminder / 60)
        $remSec = [int]($secsToReminder % 60)
        $brkMin = [math]::Floor($secsToBreak / 60)
        $brkSec = [int]($secsToBreak % 60)

        $statusLines = @(
            "Mindfulness Prompter is running",
            "Next reminder in: ${remMin}:$($remSec.ToString('00'))",
            "Next break in: ${brkMin}:$($brkSec.ToString('00'))",
            "[Pomodoro #$currentPom $emDash Work]"
        )
    }
    else {
        # Break phase
        $breakElapsed = $cycleOffset - $workSec
        $currentBreakNum = $cycleIndex + 1

        $eventKey = "c${cycleIndex}_break"
        if ($eventKey -ne $lastEventKey) {
            $lastEventKey = $eventKey
            Close-Popup
            $bodyText = "$reminderText`r`n`r`nPomodoro #$currentPom complete! Take a $breakDisplay-minute break."
            Show-Popup -Title "Mindfulness Check $emDash Break Time" -Body $bodyText -DismissDelay $dismissSeconds -Sound $playSound
            Write-Log "Break #$currentBreakNum started ($breakDisplay min)"
            Refresh-Display
        }

        $secsToWork = [math]::Max(0, $breakSec - $breakElapsed)
        $wMin = [math]::Floor($secsToWork / 60)
        $wSec = [int]($secsToWork % 60)

        $statusLines = @(
            "Mindfulness Prompter is running",
            "Break #$currentBreakNum ends in: ${wMin}:$($wSec.ToString('00'))",
            "[Break #$currentBreakNum]"
        )
    }

    Update-Status $statusLines
}

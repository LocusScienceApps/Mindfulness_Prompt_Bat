<# :
@echo off
powershell -ExecutionPolicy Bypass -NoProfile -Command "$env:BAT_DIR='%~dp0'; & ([scriptblock]::Create((Get-Content -LiteralPath '%~f0' -Raw)))"
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
# HARDCODED DEFAULTS (factory values) - separate for each mode
# ============================================================
$script:FACTORY_DEFAULTS_P = @{
    reminderText = ""
    workMinutes = [double]25
    reminderMinutes = [double]25
    shortBreakMinutes = [double]5
    pomsPerRound = 4
    longBreakMinutes = [double]20
    totalRounds = 1
    dismissSeconds = 0
    playSound = $true
}

$script:FACTORY_DEFAULTS_M = @{
    reminderText = "Are you doing what you should be doing?"
    workMinutes = [double]0
    reminderMinutes = [double]15
    shortBreakMinutes = [double]0
    pomsPerRound = 0
    longBreakMinutes = [double]0
    totalRounds = 0
    dismissSeconds = 15
    playSound = $true
}

$script:FACTORY_DEFAULTS_B = @{
    reminderText = "Are you doing what you should be doing?"
    workMinutes = [double]25
    reminderMinutes = [double]12.5
    shortBreakMinutes = [double]5
    pomsPerRound = 4
    longBreakMinutes = [double]20
    totalRounds = 1
    dismissSeconds = 15
    playSound = $true
}

# ============================================================
# SETTINGS I/O
# ============================================================
$script:settingsPath = Join-Path $env:BAT_DIR "MindfulPrompter-settings.json"

function Load-Settings {
    if (-not (Test-Path $script:settingsPath)) { return $null }
    try {
        $json = Get-Content $script:settingsPath -Raw | ConvertFrom-Json
        return $json
    } catch {
        return $null
    }
}

function Save-Settings($settingsObj) {
    $settingsObj | ConvertTo-Json -Depth 4 | Set-Content $script:settingsPath -Encoding UTF8
}

function Get-Defaults {
    param($mode = 'B')

    # Determine which factory defaults to use
    $factory = switch ($mode) {
        'P' { $script:FACTORY_DEFAULTS_P }
        'M' { $script:FACTORY_DEFAULTS_M }
        default { $script:FACTORY_DEFAULTS_B }
    }

    $settings = Load-Settings
    $defaultsKey = "defaults$mode"
    if ($settings -ne $null -and $settings.PSObject.Properties[$defaultsKey] -ne $null) {
        $d = $settings.$defaultsKey
        return @{
            reminderText = if ($d.PSObject.Properties['reminderText'] -ne $null) { $d.reminderText } else { $factory.reminderText }
            workMinutes = [double]$(if ($d.workMinutes) { $d.workMinutes } else { $factory.workMinutes })
            reminderMinutes = [double]$(if ($d.reminderMinutes) { $d.reminderMinutes } else { $factory.reminderMinutes })
            shortBreakMinutes = [double]$(if ($d.shortBreakMinutes) { $d.shortBreakMinutes } else { $factory.shortBreakMinutes })
            pomsPerRound = [int]$(if ($d.pomsPerRound) { $d.pomsPerRound } else { $factory.pomsPerRound })
            longBreakMinutes = [double]$(if ($d.longBreakMinutes) { $d.longBreakMinutes } else { $factory.longBreakMinutes })
            totalRounds = [int]$(if ($d.PSObject.Properties['totalRounds'] -ne $null) { $d.totalRounds } else { $factory.totalRounds })
            dismissSeconds = [int]$(if ($d.PSObject.Properties['dismissSeconds'] -ne $null) { $d.dismissSeconds } else { $factory.dismissSeconds })
            playSound = if ($d.PSObject.Properties['playSound'] -ne $null) { [bool]$d.playSound } else { $factory.playSound }
        }
    }
    return $factory.Clone()
}

function Get-Presets {
    $settings = Load-Settings
    if ($settings -ne $null -and $settings.presets -ne $null) {
        return $settings.presets
    }
    return $null
}

function Get-PresetsForMode {
    param($mode)

    $allPresets = Get-Presets
    if ($allPresets -eq $null) { return $null }

    $modePresets = [pscustomobject]@{}
    foreach ($prop in $allPresets.PSObject.Properties) {
        if ($prop.Name -match "^$mode\d+$") {
            $modePresets | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value
        }
    }

    if ($modePresets.PSObject.Properties.Count -eq 0) { return $null }
    return $modePresets
}

function Apply-Settings($s) {
    $script:reminderText = $s.reminderText
    $script:workMinutes = [double]$s.workMinutes
    $script:reminderMinutes = [double]$s.reminderMinutes
    $script:shortBreakMinutes = [double]$s.shortBreakMinutes
    $script:pomsPerRound = [int]$s.pomsPerRound
    $script:longBreakMinutes = [double]$s.longBreakMinutes
    $script:totalRounds = [int]$s.totalRounds
    $script:dismissSeconds = [int]$s.dismissSeconds
    $script:playSound = [bool]$s.playSound
}

function Get-CurrentSettingsObject {
    return @{
        mode = $script:mode
        reminderText = $reminderText
        workMinutes = $workMinutes
        reminderMinutes = $reminderMinutes
        shortBreakMinutes = $shortBreakMinutes
        pomsPerRound = $pomsPerRound
        longBreakMinutes = $longBreakMinutes
        totalRounds = $totalRounds
        dismissSeconds = $dismissSeconds
        playSound = $playSound
    }
}

function Format-PresetLine($key, $preset) {
    # Extract slot number from key (e.g., "P1" -> "1", "M3" -> "3")
    $slotNum = $key -replace '^[PMB]', ''

    $pMode = if ($preset.mode) { $preset.mode } else { 'B' }
    if ($pMode -eq 'P') {
        $w = Format-Num $preset.workMinutes
        $b = Format-Num $preset.shortBreakMinutes
        $s = $preset.pomsPerRound
        return "  $slotNum $emDash $($preset.name) (${w}m work, ${b}m break, $s sessions)"
    }
    elseif ($pMode -eq 'M') {
        $r = Format-Num $preset.reminderMinutes
        return "  $slotNum $emDash $($preset.name) (every ${r}m)"
    }
    else {
        $w = Format-Num $preset.workMinutes
        $r = Format-Num $preset.reminderMinutes
        $b = Format-Num $preset.shortBreakMinutes
        $s = $preset.pomsPerRound
        return "  $slotNum $emDash $($preset.name) (${w}m work, every ${r}m, ${b}m break, $s sessions)"
    }
}

function Show-SettingsSummary($s) {
    $soundText = if ($s.playSound) { "On" } else { "Off" }
    $setsDisplay = if ($s.totalRounds -eq 0) { "Unlimited" } else { [string]$s.totalRounds }
    Write-Host "  Prompt:          `"$($s.reminderText)`""
    Write-Host "  Work session:    $(Format-Num $s.workMinutes) min"
    Write-Host "  Prompt every:    $(Format-Num $s.reminderMinutes) min"
    Write-Host "  Break:           $(Format-Num $s.shortBreakMinutes) min"
    Write-Host "  Sessions/set:    $($s.pomsPerRound)"
    if ($s.totalRounds -ne 1) {
        Write-Host "  Long break:      $(Format-Num $s.longBreakMinutes) min"
    }
    Write-Host "  Sets:            $setsDisplay"
    Write-Host "  Dismiss delay:   $($s.dismissSeconds) sec"
    Write-Host "  Sound:           $soundText"
}

# ============================================================
# CUSTOMIZE FLOW (mode-aware)
# ============================================================
function Run-CustomizeFlow {
    param($defaults, $flowMode = 'B')

    # Start with all defaults — only modify the ones we ask about
    $result = @{
        reminderText = $defaults.reminderText
        workMinutes = [double]$defaults.workMinutes
        reminderMinutes = [double]$defaults.reminderMinutes
        shortBreakMinutes = [double]$defaults.shortBreakMinutes
        pomsPerRound = [int]$defaults.pomsPerRound
        longBreakMinutes = [double]$defaults.longBreakMinutes
        totalRounds = [int]$defaults.totalRounds
        dismissSeconds = [int]$defaults.dismissSeconds
        playSound = [bool]$defaults.playSound
    }

    $qNum = 1

    # --- Pomodoro questions (modes P and B) ---
    if ($flowMode -ne 'M') {
        # Work session length
        Write-Host ""
        Write-Host "$qNum. How long is each work session?"
        Write-Host "   Press Enter for the default ($(Format-Num $defaults.workMinutes) minutes),"
        Write-Host "   or type a different number of minutes:"
        $wm = $null
        while ($wm -eq $null) {
            $inp = Read-Host "  "
            if ([string]::IsNullOrWhiteSpace($inp)) { $wm = [double]$defaults.workMinutes; break }
            $parsed = [double]0
            if ([double]::TryParse($inp, [ref]$parsed) -and $parsed -gt 0) { $wm = $parsed; break }
            Write-Host "   Please enter a positive number."
        }
        $result.workMinutes = $wm
        $qNum++

        # Break length
        $defShort = Round-ToSecond ($wm / 5)
        Write-Host ""
        Write-Host "$qNum. How long are breaks between sessions?"
        Write-Host "   Press Enter for the default ($(Format-Num $defShort) minutes),"
        Write-Host "   or type a different number of minutes:"
        $sbm = $null
        while ($sbm -eq $null) {
            $inp = Read-Host "  "
            if ([string]::IsNullOrWhiteSpace($inp)) { $sbm = $defShort; break }
            $parsed = [double]0
            if ([double]::TryParse($inp, [ref]$parsed) -and $parsed -gt 0) { $sbm = $parsed; break }
            Write-Host "   Please enter a positive number."
        }
        $result.shortBreakMinutes = $sbm
        $qNum++

        # Sessions per set
        Write-Host ""
        Write-Host "$qNum. How many sessions in each set?"
        Write-Host "   Press Enter for the default ($($defaults.pomsPerRound)),"
        Write-Host "   or type a different number:"
        $ppr = $null
        while ($ppr -eq $null) {
            $inp = Read-Host "  "
            if ([string]::IsNullOrWhiteSpace($inp)) { $ppr = [int]$defaults.pomsPerRound; break }
            $parsed = 0
            if ([int]::TryParse($inp, [ref]$parsed) -and $parsed -gt 0) { $ppr = $parsed; break }
            Write-Host "   Please enter a positive whole number."
        }
        $result.pomsPerRound = $ppr
        $qNum++

        # More than one set?
        $defMultiple = ($defaults.totalRounds -ne 1)
        $defMultiLabel = if ($defMultiple) { "yes" } else { "no" }
        Write-Host ""
        Write-Host "$qNum. Would you like to do more than one set?"
        Write-Host "   Press Enter for $defMultiLabel, or type Y/N:"
        $wantMultiple = $null
        while ($wantMultiple -eq $null) {
            $inp = Read-Host "  "
            if ([string]::IsNullOrWhiteSpace($inp)) { $wantMultiple = $defMultiple; break }
            if ($inp.Trim() -match '^(y|yes)$') { $wantMultiple = $true; break }
            if ($inp.Trim() -match '^(n|no)$') { $wantMultiple = $false; break }
            Write-Host "   Please enter Y or N."
        }
        $qNum++

        if ($wantMultiple) {
            # How many sets?
            Write-Host ""
            Write-Host "$qNum. How many sets?"
            Write-Host "   Type a number, or 0 for unlimited:"
            $tr = $null
            while ($tr -eq $null) {
                $inp = Read-Host "  "
                if ([string]::IsNullOrWhiteSpace($inp)) { Write-Host "   Please enter a number."; continue }
                $parsed = 0
                if ([int]::TryParse($inp, [ref]$parsed) -and $parsed -ge 0 -and $parsed -ne 1) { $tr = $parsed; break }
                if ($parsed -eq 1) { Write-Host "   That's just one set. Type a number greater than 1, or 0 for unlimited."; continue }
                Write-Host "   Please enter 0 (unlimited) or a number greater than 1."
            }
            $result.totalRounds = $tr
            $qNum++
        } else {
            $result.totalRounds = 1
        }

        # Long break — only ask if more than 1 set
        if ($wantMultiple) {
            $defLong = Round-ToSecond (4 * $sbm)
            Write-Host ""
            Write-Host "$qNum. How long is the long break between sets?"
            Write-Host "   Press Enter for the default ($(Format-Num $defLong) minutes),"
            Write-Host "   or type a different number of minutes:"
            $lbm = $null
            while ($lbm -eq $null) {
                $inp = Read-Host "  "
                if ([string]::IsNullOrWhiteSpace($inp)) { $lbm = $defLong; break }
                $parsed = [double]0
                if ([double]::TryParse($inp, [ref]$parsed) -and $parsed -gt 0) { $lbm = $parsed; break }
                Write-Host "   Please enter a positive number."
            }
            $result.longBreakMinutes = $lbm
            $qNum++
        }
    }

    # --- Mindfulness questions (modes R and B) ---
    if ($flowMode -ne 'P') {
        # Prompt text
        Write-Host ""
        Write-Host "$qNum. What's your mindfulness prompt?"
        Write-Host "   Press Enter for: `"$($defaults.reminderText)`""
        Write-Host "   Or type your own:"
        $inp = Read-Host "  "
        $result.reminderText = if ([string]::IsNullOrWhiteSpace($inp)) { $defaults.reminderText } else { $inp.Trim() }
        $qNum++

        # Prompt interval
        if ($flowMode -eq 'B') {
            # Must fit evenly into work session
            $wm = $result.workMinutes
            $defReminder = $wm / 2
            $wmDisplay = Format-Num $wm
            Write-Host ""
            Write-Host "$qNum. How often should the prompt appear?"
            Write-Host "   Must fit evenly into your $wmDisplay-minute work session."
            Write-Host "   Press Enter for the default ($(Format-Num $defReminder) minutes),"
            Write-Host "   or type a different number of minutes:"
            $rm = $null
            while ($rm -eq $null) {
                $inp = Read-Host "  "
                if ([string]::IsNullOrWhiteSpace($inp)) { $rm = $defReminder; break }
                $parsed = [double]0
                if ([double]::TryParse($inp, [ref]$parsed) -and $parsed -gt 0) {
                    $ratio = $wm / $parsed
                    if ([math]::Abs($ratio - [math]::Round($ratio)) -lt 0.0001) { $rm = $parsed; break }
                    else {
                        $divs = Get-Divisors $wm
                        $divList = ($divs | ForEach-Object { Format-Num $_ }) -join ", "
                        Write-Host "   That doesn't fit evenly into $wmDisplay minutes."
                        Write-Host "   Options that work: $divList"
                        Write-Host "   Try again:"
                    }
                } else { Write-Host "   Please enter a positive number." }
            }
            $result.reminderMinutes = $rm
        }
        else {
            # Mindfulness only — must divide evenly into 60 minutes
            $defReminder = $defaults.reminderMinutes
            Write-Host ""
            Write-Host "$qNum. How often should the prompt appear?"
            Write-Host "   Must divide evenly into 60 minutes."
            Write-Host "   Press Enter for the default ($(Format-Num $defReminder) minutes),"
            Write-Host "   or type a different number of minutes:"
            $rm = $null
            while ($rm -eq $null) {
                $inp = Read-Host "  "
                if ([string]::IsNullOrWhiteSpace($inp)) { $rm = [double]$defReminder; break }
                $parsed = [double]0
                if ([double]::TryParse($inp, [ref]$parsed) -and $parsed -gt 0) {
                    $ratio = 60 / $parsed
                    if ([math]::Abs($ratio - [math]::Round($ratio)) -lt 0.0001) { $rm = $parsed; break }
                    else {
                        $divs = Get-Divisors 60
                        $divList = ($divs | ForEach-Object { Format-Num $_ }) -join ", "
                        Write-Host "   That doesn't divide evenly into 60 minutes."
                        Write-Host "   Try 7.5, 15, or 30 minutes (or any value that divides evenly into 60)."
                        Write-Host "   All valid options: $divList"
                        Write-Host "   Try again:"
                    }
                } else { Write-Host "   Please enter a positive number." }
            }
            $result.reminderMinutes = $rm
        }
        $qNum++

        # Dismiss delay
        Write-Host ""
        Write-Host "$qNum. How long should mindfulness prompts stay on the screen"
        Write-Host "   before you can dismiss them?"
        Write-Host "   Press Enter for the default ($($defaults.dismissSeconds) seconds),"
        Write-Host "   or type a different number of seconds:"
        $ds = $null
        while ($ds -eq $null) {
            $inp = Read-Host "  "
            if ([string]::IsNullOrWhiteSpace($inp)) { $ds = [int]$defaults.dismissSeconds; break }
            $parsed = 0
            if ([int]::TryParse($inp, [ref]$parsed) -and $parsed -ge 0) { $ds = $parsed; break }
            Write-Host "   Please enter 0 or a positive whole number."
        }
        $result.dismissSeconds = $ds
        $qNum++
    }

    # --- Mindfulness-only: number of prompts ---
    if ($flowMode -eq 'M') {
        Write-Host ""
        Write-Host "$qNum. How many prompts before the session ends?"
        Write-Host "   Press Enter for unlimited,"
        Write-Host "   or type a number:"
        $np = $null
        while ($np -eq $null) {
            $inp = Read-Host "  "
            if ([string]::IsNullOrWhiteSpace($inp)) { $np = 0; break }
            $parsed = 0
            if ([int]::TryParse($inp, [ref]$parsed) -and $parsed -ge 0) { $np = $parsed; break }
            Write-Host "   Please enter 0 (unlimited) or a positive whole number."
        }
        $result.totalRounds = $np
        $qNum++
    }

    # --- Sound (all modes) ---
    Write-Host ""
    Write-Host "$qNum. Play a sound when prompts appear?"
    $defSoundLabel = if ($defaults.playSound) { "yes" } else { "no" }
    Write-Host "   Press Enter for the default ($defSoundLabel), or type Y/N:"
    $ps = $null
    while ($ps -eq $null) {
        $inp = Read-Host "  "
        if ([string]::IsNullOrWhiteSpace($inp)) { $ps = [bool]$defaults.playSound; break }
        if ($inp.Trim() -match '^(y|yes)$') { $ps = $true; break }
        if ($inp.Trim() -match '^(n|no)$') { $ps = $false; break }
        Write-Host "   Please enter Y or N."
    }
    $result.playSound = $ps

    # For Pomodoro-only, set non-relevant fields to sensible values
    if ($flowMode -eq 'P') {
        $result.reminderMinutes = $result.workMinutes  # no mid-work prompts
        $result.dismissSeconds = 0  # popups immediately closeable
    }

    return $result
}

# ============================================================
# SETTINGS MANAGEMENT MENU
# ============================================================
function Show-ManagementMenu {
    while ($true) {
        Write-Host ""
        Write-Host "=== Settings Management ==="
        Write-Host ""
        Write-Host "  D $emDash Edit default settings"
        Write-Host "  P $emDash Manage saved presets"
        Write-Host "  R $emDash Factory reset (restore original defaults)"
        Write-Host "  B $emDash Back to main screen"
        Write-Host ""
        Write-Host "Choose an option:"
        $choice = Read-Host " "

        if ($choice -match '^[Dd]$') {
            Write-Host ""
            Write-Host "--- Edit Default Settings ---"
            Write-Host "Walk through each setting. Press Enter to keep the current default."
            $currentDefaults = Get-Defaults
            $newDefaults = Run-CustomizeFlow $currentDefaults 'B'
            $settings = Load-Settings
            if ($settings -eq $null) { $settings = [pscustomobject]@{ defaults = $null; presets = $null } }
            $settings.defaults = $newDefaults
            Save-Settings $settings
            Write-Host ""
            Write-Host "Defaults saved!"
            Start-Sleep -Seconds 1
            return
        }
        elseif ($choice -match '^[Pp]$') {
            Show-PresetManagement
        }
        elseif ($choice -match '^[Rr]$') {
            Write-Host ""
            Write-Host "This will reset your default settings to the originals"
            Write-Host "(25-min work, 5-min break, etc.)"
            Write-Host "Your saved presets will NOT be deleted."
            Write-Host ""
            Write-Host "Are you sure? (Y/N):"
            $confirm = Read-Host " "
            if ($confirm -match '^[Yy]') {
                $settings = Load-Settings
                if ($settings -ne $null) {
                    $settings.defaults = $null
                    Save-Settings $settings
                }
                Write-Host "Defaults reset to factory values!"
                Start-Sleep -Seconds 1
                return
            }
        }
        elseif ($choice -match '^[Bb]$') {
            return
        }
    }
}

function Show-PresetManagement {
    while ($true) {
        $presets = Get-Presets
        Write-Host ""
        Write-Host "=== Manage Presets ==="
        Write-Host ""
        $hasAny = $false
        if ($presets -ne $null) {
            foreach ($prop in $presets.PSObject.Properties) {
                $hasAny = $true
                Write-Host (Format-PresetLine $prop.Name $prop.Value)
            }
        }
        if (-not $hasAny) {
            Write-Host "  (no saved presets)"
        }
        Write-Host ""
        Write-Host "  R $emDash Rename a preset"
        Write-Host "  D $emDash Delete a preset"
        Write-Host "  B $emDash Back"
        Write-Host ""
        Write-Host "Choose an option:"
        $choice = Read-Host " "

        if ($choice -match '^[Rr]$' -and $hasAny) {
            Write-Host "Which preset number to rename?"
            $slot = Read-Host " "
            if ($presets.PSObject.Properties[$slot] -ne $null) {
                Write-Host "New name for preset $slot (currently `"$($presets.$slot.name)`"):"
                $newName = Read-Host " "
                if (-not [string]::IsNullOrWhiteSpace($newName)) {
                    $presets.$slot.name = $newName.Trim()
                    $settings = Load-Settings
                    $settings.presets = $presets
                    Save-Settings $settings
                    Write-Host "Renamed!"
                }
            } else { Write-Host "No preset in slot $slot." }
        }
        elseif ($choice -match '^[Dd]$' -and $hasAny) {
            Write-Host "Which preset number to delete?"
            $slot = Read-Host " "
            if ($presets.PSObject.Properties[$slot] -ne $null) {
                Write-Host "Delete preset $slot (`"$($presets.$slot.name)`")? (Y/N):"
                $confirm = Read-Host " "
                if ($confirm -match '^[Yy]') {
                    $presets.PSObject.Properties.Remove($slot)
                    $settings = Load-Settings
                    $settings.presets = $presets
                    Save-Settings $settings
                    Write-Host "Deleted!"
                }
            } else { Write-Host "No preset in slot $slot." }
        }
        elseif ($choice -match '^[Bb]$') {
            return
        }
    }
}

# ============================================================
# SAVE-AS-PRESET FLOW
# ============================================================
function Save-AsPresetNew($settingsObj, $mode, $defaults) {
    $modePresets = Get-PresetsForMode $mode

    # Find available and occupied slots
    $occupiedSlots = @()
    $availableSlots = @(1,2,3,4,5)

    if ($modePresets -ne $null) {
        foreach ($prop in $modePresets.PSObject.Properties) {
            $slotNum = $prop.Name -replace '^[PMB]', ''
            $occupiedSlots += [int]$slotNum
            $availableSlots = $availableSlots | Where-Object { $_ -ne [int]$slotNum }
        }
    }

    Write-Host ""
    Write-Host "=== Save as Preset ($(Get-ModeName $mode)) ==="
    Write-Host ""

    if ($availableSlots.Count -gt 0) {
        Write-Host "Available slots: $($availableSlots -join ', ')"
        Write-Host ""
    }

    if ($occupiedSlots.Count -gt 0) {
        Write-Host "Occupied slots:"
        $sortedOccupied = $occupiedSlots | Sort-Object
        foreach ($num in $sortedOccupied) {
            $presetKey = "$mode$num"
            $preset = $modePresets.$presetKey
            Write-Host "  $num $emDash $($preset.name)"
        }
        Write-Host ""
    }

    $firstAvailable = if ($availableSlots.Count -gt 0) { $availableSlots[0] } else { 1 }
    Write-Host "Which slot (1-5)? Press Enter to select the first available slot ($firstAvailable):"
    $slot = $null
    while ($slot -eq $null) {
        $inp = Read-Host " "
        if ([string]::IsNullOrWhiteSpace($inp)) { $slot = [string]$firstAvailable; break }
        if ($inp -match '^[1-5]$') { $slot = $inp; break }
        Write-Host "  Please enter a number from 1 to 5."
    }

    # Check if slot is occupied
    $presetKey = "$mode$slot"
    if ($occupiedSlots -contains [int]$slot) {
        $existingName = $modePresets.$presetKey.name
        Write-Host "Slot $slot is occupied by `"$existingName`". Overwrite? (Y/N):"
        $confirm = Read-Host " "
        if ($confirm -notmatch '^[Yy]$') {
            Write-Host "Cancelled."
            return $false
        }
    }

    # Generate suggested name
    $suggestedName = Generate-PresetName $settingsObj $defaults $mode

    Write-Host "Suggested name: `"$suggestedName`""
    Write-Host "Press Enter to use this name, or type your own:"
    $nameInp = Read-Host " "
    $presetName = if ([string]::IsNullOrWhiteSpace($nameInp)) { $suggestedName } else { $nameInp.Trim() }

    $presetData = @{
        name = $presetName
        mode = $mode
        reminderText = $settingsObj.reminderText
        workMinutes = $settingsObj.workMinutes
        reminderMinutes = $settingsObj.reminderMinutes
        shortBreakMinutes = $settingsObj.shortBreakMinutes
        pomsPerRound = $settingsObj.pomsPerRound
        longBreakMinutes = $settingsObj.longBreakMinutes
        totalRounds = $settingsObj.totalRounds
        dismissSeconds = $settingsObj.dismissSeconds
        playSound = $settingsObj.playSound
    }

    $settings = Load-Settings
    if ($settings -eq $null) { $settings = [pscustomobject]@{ presets = [pscustomobject]@{} } }
    if ($settings.presets -eq $null) { $settings.presets = [pscustomobject]@{} }

    # Use direct property assignment instead of Add-Member (fixes the bug)
    $settings.presets.$presetKey = $presetData

    Save-Settings $settings
    Write-Host "Saved as `"$presetName`" in slot $slot!"
    return $true
}

function Save-AsPreset($settingsObj) {
    $presets = Get-Presets
    Write-Host ""
    Write-Host "Save as preset (slot 0-9)."
    if ($presets -ne $null) {
        $taken = @()
        foreach ($prop in $presets.PSObject.Properties) { $taken += $prop.Name }
        if ($taken.Count -gt 0) {
            Write-Host "  Slots in use: $($taken -join ', ')"
        }
    }
    Write-Host "Which slot (0-9)?"
    $slot = $null
    while ($slot -eq $null) {
        $inp = Read-Host " "
        if ($inp -match '^[0-9]$') { $slot = $inp }
        else { Write-Host "  Please enter a single digit 0-9." }
    }

    # Check if slot is taken
    if ($presets -ne $null -and $presets.PSObject.Properties[$slot] -ne $null) {
        Write-Host "Slot $slot is `"$($presets.$slot.name)`". Overwrite? (Y/N):"
        $confirm = Read-Host " "
        if ($confirm -notmatch '^[Yy]') {
            Write-Host "Cancelled."
            return
        }
    }

    Write-Host "Name for this preset (or Enter for `"Preset $slot`"):"
    $nameInp = Read-Host " "
    $presetName = if ([string]::IsNullOrWhiteSpace($nameInp)) { "Preset $slot" } else { $nameInp.Trim() }

    $presetData = @{
        name = $presetName
        mode = $settingsObj.mode
        reminderText = $settingsObj.reminderText
        workMinutes = $settingsObj.workMinutes
        reminderMinutes = $settingsObj.reminderMinutes
        shortBreakMinutes = $settingsObj.shortBreakMinutes
        pomsPerRound = $settingsObj.pomsPerRound
        longBreakMinutes = $settingsObj.longBreakMinutes
        totalRounds = $settingsObj.totalRounds
        dismissSeconds = $settingsObj.dismissSeconds
        playSound = $settingsObj.playSound
    }

    $settings = Load-Settings
    if ($settings -eq $null) { $settings = [pscustomobject]@{ defaults = $null; presets = [pscustomobject]@{} } }
    if ($settings.presets -eq $null) { $settings.presets = [pscustomobject]@{} }
    $settings.presets | Add-Member -NotePropertyName $slot -NotePropertyValue $presetData -Force
    Save-Settings $settings
    Write-Host "Saved as `"$presetName`" in slot $slot!"
}

# ============================================================
# HELPER FUNCTIONS FOR NEW UI FLOW
# ============================================================

function Get-ModeName($mode) {
    switch ($mode) {
        'P' { return "Pomodoro Sessions" }
        'M' { return "Mindfulness Sessions" }
        'B' { return "Pomodoro + Mindfulness Sessions" }
        default { return "Unknown Mode" }
    }
}

function Show-ViewSettings($settingsObj, $mode) {
    $soundText = if ($settingsObj.playSound) { "On" } else { "Off" }
    Write-Host ""
    Write-Host "=== Current Settings ==="
    Write-Host ""

    if ($mode -eq 'P') {
        $workDisplay = Format-Num $settingsObj.workMinutes
        $shortBreakDisplay = Format-Num $settingsObj.shortBreakMinutes
        $longBreakDisplay = Format-Num $settingsObj.longBreakMinutes
        $setsDisplay = if ($settingsObj.totalRounds -eq 0) { "Unlimited" } else { [string]$settingsObj.totalRounds }

        Write-Host "  Work session:    $workDisplay min"
        Write-Host "  Break:           $shortBreakDisplay min"
        Write-Host "  Sessions/set:    $($settingsObj.pomsPerRound)"
        if ($settingsObj.totalRounds -ne 1) {
            Write-Host "  Long break:      $longBreakDisplay min"
        }
        Write-Host "  Sets:            $setsDisplay"
        Write-Host "  Sound:           $soundText"
    }
    elseif ($mode -eq 'M') {
        $reminderDisplay = Format-Num $settingsObj.reminderMinutes
        $promptsDisplay = if ($settingsObj.totalRounds -eq 0) { "Unlimited" } else { "$($settingsObj.totalRounds)" }

        Write-Host "  Prompt:          `"$($settingsObj.reminderText)`""
        Write-Host "  Prompt every:    $reminderDisplay min"
        Write-Host "  Dismiss delay:   $($settingsObj.dismissSeconds) sec"
        Write-Host "  Prompts:         $promptsDisplay"
        Write-Host "  Sound:           $soundText"
    }
    else {
        Show-SettingsSummary $settingsObj
    }

    Write-Host ""
    Write-Host "Press Enter to continue..."
    Read-Host | Out-Null
}

function Show-PresetSelection($mode) {
    $modePresets = Get-PresetsForMode $mode

    if ($modePresets -eq $null -or $modePresets.PSObject.Properties.Count -eq 0) {
        Write-Host ""
        Write-Host "No saved presets for this mode yet."
        Start-Sleep -Seconds 1
        return $null
    }

    while ($true) {
        Write-Host ""
        Write-Host "=== Saved Presets ($(Get-ModeName $mode)) ==="
        Write-Host ""

        # Show presets sorted by slot number
        $presetList = @()
        foreach ($prop in $modePresets.PSObject.Properties) {
            $presetList += $prop
        }
        $presetList = $presetList | Sort-Object { $_.Name -replace '^\D+', '' -as [int] }

        foreach ($prop in $presetList) {
            Write-Host (Format-PresetLine $prop.Name $prop.Value)
        }

        Write-Host ""
        Write-Host "  Enter the preset number (1-5) and press Enter to load and start a saved preset"
        Write-Host "  Enter the preset number followed by V to view preset details (1V, 2V, etc.)"
        Write-Host "  B $emDash Back"
        Write-Host ""
        Write-Host "Choose an option:"
        $choice = Read-Host " "

        if ($choice -match '^[Bb]$') {
            return $null
        }
        elseif ($choice -match '^([1-5])[Vv]$') {
            # View details
            $slotNum = $Matches[1]
            $presetKey = "$mode$slotNum"
            if ($modePresets.PSObject.Properties[$presetKey] -ne $null) {
                $preset = $modePresets.$presetKey
                $presetSettings = @{
                    reminderText = $preset.reminderText
                    workMinutes = [double]$preset.workMinutes
                    reminderMinutes = [double]$preset.reminderMinutes
                    shortBreakMinutes = [double]$preset.shortBreakMinutes
                    pomsPerRound = [int]$preset.pomsPerRound
                    longBreakMinutes = [double]$preset.longBreakMinutes
                    totalRounds = [int]$preset.totalRounds
                    dismissSeconds = [int]$preset.dismissSeconds
                    playSound = [bool]$preset.playSound
                }
                Show-ViewSettings $presetSettings $mode
            } else {
                Write-Host "  No preset in slot $slotNum."
                Start-Sleep -Seconds 1
            }
        }
        elseif ($choice -match '^[1-5]$') {
            # Load preset
            $slotNum = $choice
            $presetKey = "$mode$slotNum"
            if ($modePresets.PSObject.Properties[$presetKey] -ne $null) {
                $preset = $modePresets.$presetKey
                Write-Host ""
                Write-Host "Loaded preset: `"$($preset.name)`""
                Start-Sleep -Seconds 1
                return @{
                    reminderText = $preset.reminderText
                    workMinutes = [double]$preset.workMinutes
                    reminderMinutes = [double]$preset.reminderMinutes
                    shortBreakMinutes = [double]$preset.shortBreakMinutes
                    pomsPerRound = [int]$preset.pomsPerRound
                    longBreakMinutes = [double]$preset.longBreakMinutes
                    totalRounds = [int]$preset.totalRounds
                    dismissSeconds = [int]$preset.dismissSeconds
                    playSound = [bool]$preset.playSound
                }
            } else {
                Write-Host "  No preset in slot $slotNum."
                Start-Sleep -Seconds 1
            }
        }
        else {
            Write-Host "  Invalid choice."
            Start-Sleep -Seconds 1
        }
    }
}

function Generate-PresetName($settingsObj, $defaults, $mode) {
    $diffs = @()

    if ($mode -eq 'P') {
        if ($settingsObj.workMinutes -ne $defaults.workMinutes) {
            $diffs += "$(Format-Num $settingsObj.workMinutes)m work"
        }
        if ($settingsObj.shortBreakMinutes -ne $defaults.shortBreakMinutes) {
            $diffs += "$(Format-Num $settingsObj.shortBreakMinutes)m break"
        }
        if ($settingsObj.pomsPerRound -ne $defaults.pomsPerRound) {
            $diffs += "$($settingsObj.pomsPerRound) sessions"
        }
        if ($settingsObj.totalRounds -ne $defaults.totalRounds) {
            if ($settingsObj.totalRounds -eq 0) {
                $diffs += "unlimited sets"
            } else {
                $diffs += "$($settingsObj.totalRounds) sets"
            }
        }
        if ($settingsObj.totalRounds -gt 1 -and $settingsObj.longBreakMinutes -ne $defaults.longBreakMinutes) {
            $diffs += "$(Format-Num $settingsObj.longBreakMinutes)m long break"
        }
    }
    elseif ($mode -eq 'M') {
        if ($settingsObj.reminderText -ne $defaults.reminderText) {
            $diffs += "custom prompt"
        }
        if ($settingsObj.reminderMinutes -ne $defaults.reminderMinutes) {
            $diffs += "every $(Format-Num $settingsObj.reminderMinutes)m"
        }
        if ($settingsObj.dismissSeconds -ne $defaults.dismissSeconds) {
            $diffs += "$($settingsObj.dismissSeconds)s delay"
        }
        if ($settingsObj.totalRounds -ne $defaults.totalRounds) {
            if ($settingsObj.totalRounds -eq 0) {
                $diffs += "unlimited"
            } else {
                $diffs += "$($settingsObj.totalRounds) prompts"
            }
        }
    }
    else {
        if ($settingsObj.reminderText -ne $defaults.reminderText) {
            $diffs += "custom prompt"
        }
        if ($settingsObj.workMinutes -ne $defaults.workMinutes) {
            $diffs += "$(Format-Num $settingsObj.workMinutes)m work"
        }
        if ($settingsObj.reminderMinutes -ne $defaults.reminderMinutes) {
            $diffs += "every $(Format-Num $settingsObj.reminderMinutes)m"
        }
        if ($settingsObj.shortBreakMinutes -ne $defaults.shortBreakMinutes) {
            $diffs += "$(Format-Num $settingsObj.shortBreakMinutes)m break"
        }
        if ($settingsObj.pomsPerRound -ne $defaults.pomsPerRound) {
            $diffs += "$($settingsObj.pomsPerRound) sessions"
        }
    }

    if ($diffs.Count -eq 0) {
        return "Custom preset"
    }

    # Join first 3 differences to keep name reasonable length
    $nameparts = $diffs[0..[math]::Min(2, $diffs.Count - 1)]
    return ($nameparts -join ", ")
}

# ============================================================
# STARTUP SCREEN
# ============================================================
$script:mode = 'B'
$startupDone = $false

# Main startup loop
while (-not $startupDone) {
    Write-Host ""
    Write-Host "=== MindfulPrompter ==="
    Write-Host ""
    Write-Host "  Choose your session type:"
    Write-Host "    P $emDash Pomodoro sessions"
    Write-Host "    M $emDash Mindfulness sessions"
    Write-Host "    B $emDash Both (Pomodoro + mindfulness)"
    Write-Host ""
    Write-Host "Choose an option:"
    $modeChoice = Read-Host " "

    if ($modeChoice -match '^[PpMmBb]$') {
        $script:mode = $modeChoice.ToUpper()
        if ($script:mode -eq 'R') { $script:mode = 'M' }  # Legacy compatibility

        $defaults = Get-Defaults $script:mode
        $currentSettings = $defaults.Clone()

        # Mode-specific menu loop
        $modeMenuDone = $false
        while (-not $modeMenuDone) {
            Write-Host ""
            Write-Host "=== $(Get-ModeName $script:mode) ==="
            Write-Host ""
            Write-Host "Press V to view current settings"
            Write-Host ""
            Write-Host "  Enter $emDash Start with current settings"
            Write-Host "  P $emDash Load a preset"
            Write-Host "  C $emDash Customize for this session only"
            Write-Host "  D $emDash Edit default settings"
            Write-Host "  B $emDash Back to mode selection"
            Write-Host ""
            Write-Host "Choose an option:"
            $menuChoice = Read-Host " "

            if ($menuChoice -match '^[Vv]$') {
                Show-ViewSettings $currentSettings $script:mode
            }
            elseif ([string]::IsNullOrWhiteSpace($menuChoice)) {
                # Start with current settings
                Apply-Settings $currentSettings
                $startupDone = $true
                $modeMenuDone = $true
            }
            elseif ($menuChoice -match '^[Pp]$') {
                # Load a preset
                $presetResult = Show-PresetSelection $script:mode
                if ($presetResult -ne $null) {
                    $currentSettings = $presetResult
                    Apply-Settings $currentSettings
                    $startupDone = $true
                    $modeMenuDone = $true
                }
            }
            elseif ($menuChoice -match '^[Cc]$') {
                # Customize for this session
                $customResult = Run-CustomizeFlow $currentSettings $script:mode
                if ($customResult -ne $null) {
                    # Show save options
                    $saveMenuDone = $false
                    while (-not $saveMenuDone) {
                        Write-Host ""
                        Write-Host "Settings customized."
                        Write-Host ""
                        Write-Host "Press V to view customized settings"
                        Write-Host ""
                        Write-Host "  Enter $emDash Start with these settings"
                        Write-Host "  P $emDash Save as a preset"
                        Write-Host "  D $emDash Save as new defaults"
                        Write-Host "  B $emDash Back (discard changes)"
                        Write-Host ""
                        Write-Host "Choose an option:"
                        $saveChoice = Read-Host " "

                        if ($saveChoice -match '^[Vv]$') {
                            Show-ViewSettings $customResult $script:mode
                        }
                        elseif ([string]::IsNullOrWhiteSpace($saveChoice)) {
                            $currentSettings = $customResult
                            Apply-Settings $currentSettings
                            $startupDone = $true
                            $modeMenuDone = $true
                            $saveMenuDone = $true
                        }
                        elseif ($saveChoice -match '^[Pp]$') {
                            # Save as preset
                            $presetSaved = Save-AsPresetNew $customResult $script:mode $defaults
                            if ($presetSaved) {
                                Write-Host ""
                                Write-Host "Press Enter to start with these settings, or B to go back to menu."
                                $postSave = Read-Host " "
                                if ([string]::IsNullOrWhiteSpace($postSave)) {
                                    $currentSettings = $customResult
                                    Apply-Settings $currentSettings
                                    $startupDone = $true
                                    $modeMenuDone = $true
                                    $saveMenuDone = $true
                                } else {
                                    $saveMenuDone = $true
                                }
                            }
                        }
                        elseif ($saveChoice -match '^[Dd]$') {
                            # Save as defaults
                            Write-Host ""
                            Write-Host "Are you sure you want to change the default settings for $(Get-ModeName $script:mode)? (Y/N):"
                            $confirm = Read-Host " "
                            if ($confirm -match '^[Yy]$') {
                                $settings = Load-Settings
                                if ($settings -eq $null) { $settings = [pscustomobject]@{} }
                                $defaultsKey = "defaults$($script:mode)"
                                $settings | Add-Member -NotePropertyName $defaultsKey -NotePropertyValue $customResult -Force
                                Save-Settings $settings
                                Write-Host "Defaults updated!"
                                $defaults = Get-Defaults $script:mode
                                $currentSettings = $customResult
                                Start-Sleep -Seconds 1
                                Write-Host ""
                                Write-Host "Press Enter to start with these settings, or B to go back to menu."
                                $postSave = Read-Host " "
                                if ([string]::IsNullOrWhiteSpace($postSave)) {
                                    Apply-Settings $currentSettings
                                    $startupDone = $true
                                    $modeMenuDone = $true
                                    $saveMenuDone = $true
                                } else {
                                    $saveMenuDone = $true
                                }
                            }
                        }
                        elseif ($saveChoice -match '^[Bb]$') {
                            $saveMenuDone = $true
                        }
                        else {
                            Write-Host "  Invalid choice."
                        }
                    }
                }
            }
            elseif ($menuChoice -match '^[Dd]$') {
                # Edit defaults
                $newDefaults = Run-CustomizeFlow $defaults $script:mode
                if ($newDefaults -ne $null) {
                    Write-Host ""
                    Write-Host "Save these as new defaults for $(Get-ModeName $script:mode)? (Y/N):"
                    $confirm = Read-Host " "
                    if ($confirm -match '^[Yy]$') {
                        $settings = Load-Settings
                        if ($settings -eq $null) { $settings = [pscustomobject]@{} }
                        $defaultsKey = "defaults$($script:mode)"
                        $settings | Add-Member -NotePropertyName $defaultsKey -NotePropertyValue $newDefaults -Force
                        Save-Settings $settings
                        Write-Host "Defaults updated!"
                        $defaults = Get-Defaults $script:mode
                        $currentSettings = $defaults.Clone()
                        Start-Sleep -Seconds 1
                    }
                }
            }
            elseif ($menuChoice -match '^[Bb]$') {
                $modeMenuDone = $true
            }
            else {
                Write-Host "  Invalid choice."
            }
        }
    }
    else {
        Write-Host "  Invalid choice. Please try again."
    }
}

# ============================================================
# POPUP STATE AND FUNCTIONS
# ============================================================
$script:currentForm = $null
$script:popupButton = $null
$script:popupTimer = $null
$script:dismissCountdown = 0
$script:autoDismissCountdown = 0
$script:forceClose = $false

function Show-Popup {
    param(
        [string]$Title,
        [string]$Body,
        [int]$DismissDelay,
        [bool]$Sound,
        [int]$AutoDismiss = 0,
        [int]$Width = 450,
        [int]$Height = 240
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
    $form.Width = $Width
    $form.Height = $Height
    $form.ShowInTaskbar = $true

    $labelHeight = $Height - 110
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Body
    $label.AutoSize = $false
    $label.Width = $Width - 40
    $label.Height = $labelHeight
    $label.Location = New-Object System.Drawing.Point(15, 15)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $label.TextAlign = "MiddleCenter"
    $form.Controls.Add($label)

    $btnY = $Height - 85
    $btnX = [int](($Width - 160) / 2)
    $button = New-Object System.Windows.Forms.Button
    $button.Width = 160
    $button.Height = 35
    $button.Location = New-Object System.Drawing.Point($btnX, $btnY)
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 10)

    if ($DismissDelay -le 0) {
        $button.Enabled = $true
        $button.Text = "OK"
    } else {
        $button.Enabled = $false
        $button.Text = "Wait (${DismissDelay}s)..."
    }
    $form.Controls.Add($button)
    $form.AcceptButton = $button

    $script:popupButton = $button
    $script:dismissCountdown = $DismissDelay
    $script:autoDismissCountdown = $AutoDismiss

    if ($DismissDelay -gt 0 -or $AutoDismiss -gt 0) {
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1000
        $timer.Add_Tick({
            if ($script:dismissCountdown -gt 0) {
                $script:dismissCountdown = $script:dismissCountdown - 1
                if ($script:dismissCountdown -le 0) {
                    $script:popupButton.Enabled = $true
                    if ($script:autoDismissCountdown -gt 0) {
                        $script:popupButton.Text = "OK (auto-close in $($script:autoDismissCountdown)s)"
                    } else {
                        $script:popupTimer.Stop()
                        $script:popupButton.Text = "OK"
                    }
                    $script:popupButton.Focus()
                } else {
                    $script:popupButton.Text = "Wait ($($script:dismissCountdown)s)..."
                }
            }
            elseif ($script:autoDismissCountdown -gt 0) {
                $script:autoDismissCountdown = $script:autoDismissCountdown - 1
                if ($script:autoDismissCountdown -le 0) {
                    $script:popupTimer.Stop()
                    $script:forceClose = $true
                    $script:currentForm.Close()
                } else {
                    $script:popupButton.Text = "OK (auto-close in $($script:autoDismissCountdown)s)"
                }
            }
        })
        $timer.Start()
        $script:popupTimer = $timer
    } else {
        $script:popupTimer = $null
    }

    $button.Add_Click({
        if ($script:popupTimer -ne $null) { $script:popupTimer.Stop() }
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
# MINDFULNESS-ONLY TIMER (mode M)
# ============================================================
if ($script:mode -eq 'M') {
    $startTime = Get-Date
    $lastPromptIndex = 0
    $mReminderSec = $reminderMinutes * 60
    $mSessionDone = $false

    $promptLimitLabel = if ($totalRounds -gt 0) { " ($totalRounds prompts)" } else { "" }
    Write-Log "Mindfulness session started $emDash prompt every $(Format-Num $reminderMinutes) min$promptLimitLabel"
    Refresh-Display

    while (-not $mSessionDone) {
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.Application]::DoEvents()

        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        $currentPromptIndex = [math]::Floor($elapsed / $mReminderSec)

        if ($currentPromptIndex -gt $lastPromptIndex) {
            $lastPromptIndex = $currentPromptIndex
            Close-Popup
            Show-Popup -Title "Mindfulness Check" -Body $reminderText -DismissDelay $dismissSeconds -Sound $playSound
            $countLabel = if ($totalRounds -gt 0) { " ($lastPromptIndex/$totalRounds)" } else { "" }
            Write-Log "Mindfulness prompt$countLabel"
            Refresh-Display

            # Check if we've reached the prompt limit
            if ($totalRounds -gt 0 -and $lastPromptIndex -ge $totalRounds) {
                # Wait for the last prompt popup to be dismissed
                while ($script:currentForm -ne $null -and -not $script:currentForm.IsDisposed) {
                    Start-Sleep -Milliseconds 200
                    [System.Windows.Forms.Application]::DoEvents()
                }
                # Show session complete popup
                $actualMin = $elapsed / 60
                $hr = [char]0x2500
                $ruler = ([string]$hr) * 30
                $bodyText = "$reminderText`r`n`r`n$ruler`r`nPrompts completed: $totalRounds`r`nTotal elapsed: $(Format-Duration $actualMin)`r`n`r`nGreat work!"
                Show-Popup -Title "Session Complete!" -Body $bodyText -DismissDelay $dismissSeconds -Sound $playSound -AutoDismiss 60 -Width 500 -Height 300
                Write-Log "Session complete! $totalRounds prompts in $(Format-Duration $actualMin)."
                Refresh-Display
                while ($script:currentForm -ne $null -and -not $script:currentForm.IsDisposed) {
                    Start-Sleep -Milliseconds 200
                    [System.Windows.Forms.Application]::DoEvents()
                }
                $mSessionDone = $true
                continue
            }
        }

        if (-not $mSessionDone) {
            $nextPromptAt = ($lastPromptIndex + 1) * $mReminderSec
            $secsToPrompt = [math]::Max(0, $nextPromptAt - $elapsed)
            $m = [math]::Floor($secsToPrompt / 60)
            $s = [int]($secsToPrompt % 60)
            $eM = [math]::Floor($elapsed / 60)
            $eS = [int]($elapsed % 60)

            $countLine = if ($totalRounds -gt 0) { " ($lastPromptIndex/$totalRounds)" } else { "" }
            $endLine = if ($totalRounds -gt 0) { "Session ends after $totalRounds prompts" } else { "Close this window to end" }

            Update-Status @(
                "Mindfulness session running$countLine",
                "Next prompt in: ${m}:$($s.ToString('00'))",
                "Elapsed: ${eM}:$($eS.ToString('00'))",
                $endLine
            )
        }
    }

    Write-Host ""
    Write-Host "Session ended. Well done!"
    exit
}

# ============================================================
# POMODORO TIMER (modes P and B)
# ============================================================
$workSec = [math]::Round($workMinutes * 60)
$shortBreakSec = [math]::Round($shortBreakMinutes * 60)
$longBreakSec = [math]::Round($longBreakMinutes * 60)
$reminderSec = $reminderMinutes * 60
$miniCycleSec = $workSec + $shortBreakSec
$roundSec = ($pomsPerRound - 1) * $miniCycleSec + $workSec + $longBreakSec
$lastRoundSec = ($pomsPerRound - 1) * $miniCycleSec + $workSec
$remindersPerWork = [int][math]::Round($workSec / $reminderSec)

$workDisplay = Format-Num $workMinutes
$shortBreakDisplay = Format-Num $shortBreakMinutes
$longBreakDisplay = Format-Num $longBreakMinutes

$startTime = Get-Date
$lastEventKey = ""
$sessionComplete = $false

$setsLabel = if ($totalRounds -eq 0) { "" } else { "/$totalRounds" }

Write-Log "Session 1 started (Set 1$setsLabel, Session 1/$pomsPerRound)"
Refresh-Display

while (-not $sessionComplete) {
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.Application]::DoEvents()

    $now = Get-Date
    $elapsed = ($now - $startTime).TotalSeconds

    # --- Determine round and offset within round ---
    if ($totalRounds -eq 0) {
        $roundIndex = [math]::Floor($elapsed / $roundSec)
        $roundOffset = $elapsed - ($roundIndex * $roundSec)
        $isLastRound = $false
    } else {
        $allButLastSec = ($totalRounds - 1) * $roundSec

        if ($elapsed -ge $allButLastSec + $lastRoundSec) {
            $sessionComplete = $true
            $totalPoms = $totalRounds * $pomsPerRound
            $actualMin = $elapsed / 60
            $workOnlyMin = $totalPoms * $workMinutes
            Close-Popup

            $hr = [char]0x2500
            $ruler = ([string]$hr) * 30
            $setsText = if ($totalRounds -eq 1) { "1 set" } else { "$totalRounds sets" }

            if ($script:mode -eq 'B') {
                $bodyText = "$reminderText`r`n`r`n$ruler`r`nSessions completed: $totalPoms ($setsText)`r`nTotal work time: $(Format-Duration $workOnlyMin)`r`nTotal elapsed: $(Format-Duration $actualMin)`r`n`r`nGreat work!"
            } else {
                $bodyText = "$ruler`r`nSessions completed: $totalPoms ($setsText)`r`nTotal work time: $(Format-Duration $workOnlyMin)`r`nTotal elapsed: $(Format-Duration $actualMin)`r`n`r`nGreat work!"
            }

            Show-Popup -Title "Session Complete!" -Body $bodyText -DismissDelay $dismissSeconds -Sound $playSound -AutoDismiss 60 -Width 500 -Height 300
            Write-Log "Session complete! $totalPoms sessions in $(Format-Duration $actualMin)."
            Refresh-Display
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
    $firstPartSec = ($pomsPerRound - 1) * $miniCycleSec

    if ($roundOffset -lt $firstPartSec) {
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
        $pomInRound = $pomsPerRound - 1
        $lastPomOffset = $roundOffset - $firstPartSec
        if ($lastPomOffset -lt $workSec) {
            $phase = "work"
            $workPhaseOffset = $lastPomOffset
        } else {
            $phase = "long_break"
            $breakPhaseOffset = $lastPomOffset - $workSec
        }
    }

    $pomInRoundNum = $pomInRound + 1
    $globalPom = $roundIndex * $pomsPerRound + $pomInRoundNum
    $statusLines = @()

    # Prefix for popup body: include mindfulness prompt only in mode B
    $promptLine = if ($script:mode -eq 'B') { "$reminderText`r`n`r`n" } else { "" }

    # --- WORK PHASE ---
    if ($phase -eq "work") {
        $reminderIndex = [math]::Floor($workPhaseOffset / $reminderSec)
        $eventKey = "r${roundIndex}_p${pomInRound}_w${reminderIndex}"

        if ($eventKey -ne $lastEventKey) {
            $lastEventKey = $eventKey

            if ($reminderIndex -eq 0) {
                if ($roundIndex -eq 0 -and $pomInRound -eq 0) {
                    # Very first session — already logged at startup
                }
                elseif ($pomInRound -eq 0) {
                    Close-Popup
                    $bodyText = "${promptLine}Set $roundIndex complete! Set $roundNum starting.`r`nSession $globalPom begins. ($workDisplay-min work session)"
                    $popTitle = if ($script:mode -eq 'B') { "Mindfulness Check $emDash New Set" } else { "New Set" }
                    Show-Popup -Title $popTitle -Body $bodyText -DismissDelay $dismissSeconds -Sound $playSound
                    Write-Log "Session $globalPom started (Set $roundNum$setsLabel, Session $pomInRoundNum/$pomsPerRound)"
                    Refresh-Display
                }
                else {
                    Close-Popup
                    $bodyText = "${promptLine}Break over! Session $globalPom starting. ($workDisplay-min work session)"
                    $popTitle = if ($script:mode -eq 'B') { "Mindfulness Check $emDash Back to Work" } else { "Back to Work" }
                    Show-Popup -Title $popTitle -Body $bodyText -DismissDelay $dismissSeconds -Sound $playSound
                    Write-Log "Session $globalPom started (Set $roundNum$setsLabel, Session $pomInRoundNum/$pomsPerRound)"
                    Refresh-Display
                }
            }
            elseif ($reminderIndex -gt 0 -and $reminderIndex -lt $remindersPerWork) {
                # Mid-work mindfulness prompt (only fires in mode B)
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

        $brkMin = [math]::Floor($secsToBreak / 60)
        $brkSec = [int]($secsToBreak % 60)

        if ($pomInRound -lt $pomsPerRound - 1) {
            $nextBreakLabel = ""
        } elseif ($isLastRound) {
            $nextBreakLabel = " (session ends)"
        } else {
            $nextBreakLabel = " (long break)"
        }

        $statusLines = @(
            "MindfulPrompter is running",
            "Next break in: ${brkMin}:$($brkSec.ToString('00'))$nextBreakLabel",
            "[Session $globalPom $emDash Set $roundNum$setsLabel, Session $pomInRoundNum/$pomsPerRound $emDash Work]"
        )

        # Show "next prompt" line only in mode B
        if ($script:mode -eq 'B') {
            $remMin = [math]::Floor($secsToReminder / 60)
            $remSec = [int]($secsToReminder % 60)
            $statusLines = @(
                "MindfulPrompter is running",
                "Next prompt in: ${remMin}:$($remSec.ToString('00'))",
                "Next break in: ${brkMin}:$($brkSec.ToString('00'))$nextBreakLabel",
                "[Session $globalPom $emDash Set $roundNum$setsLabel, Session $pomInRoundNum/$pomsPerRound $emDash Work]"
            )
        }
    }
    # --- SHORT BREAK ---
    elseif ($phase -eq "short_break") {
        $eventKey = "r${roundIndex}_p${pomInRound}_sbreak"
        if ($eventKey -ne $lastEventKey) {
            $lastEventKey = $eventKey
            Close-Popup
            $bodyText = "${promptLine}Session $globalPom complete! Take a $shortBreakDisplay-min break."
            $popTitle = if ($script:mode -eq 'B') { "Mindfulness Check $emDash Break" } else { "Break Time" }
            Show-Popup -Title $popTitle -Body $bodyText -DismissDelay $dismissSeconds -Sound $playSound
            Write-Log "Break ($shortBreakDisplay min) $emDash after Session $pomInRoundNum/$pomsPerRound"
            Refresh-Display
        }

        $secsLeft = [math]::Max(0, $shortBreakSec - $breakPhaseOffset)
        $m = [math]::Floor($secsLeft / 60)
        $s = [int]($secsLeft % 60)

        $statusLines = @(
            "MindfulPrompter is running",
            "Break ends in: ${m}:$($s.ToString('00'))",
            "[Break $emDash after Session $globalPom]",
            "Set $roundNum$setsLabel, Session $pomInRoundNum/$pomsPerRound complete"
        )
    }
    # --- LONG BREAK ---
    elseif ($phase -eq "long_break") {
        $eventKey = "r${roundIndex}_lbreak"
        if ($eventKey -ne $lastEventKey) {
            $lastEventKey = $eventKey
            Close-Popup
            $bodyText = "${promptLine}Set $roundNum complete! Take a $longBreakDisplay-min long break."
            $popTitle = if ($script:mode -eq 'B') { "Mindfulness Check $emDash Long Break" } else { "Long Break" }
            Show-Popup -Title $popTitle -Body $bodyText -DismissDelay $dismissSeconds -Sound $playSound
            Write-Log "Long break ($longBreakDisplay min) $emDash Set $roundNum$setsLabel complete!"
            Refresh-Display
        }

        $secsLeft = [math]::Max(0, $longBreakSec - $breakPhaseOffset)
        $m = [math]::Floor($secsLeft / 60)
        $s = [int]($secsLeft % 60)

        $statusLines = @(
            "MindfulPrompter is running",
            "Long break ends in: ${m}:$($s.ToString('00'))",
            "[Long Break $emDash Set $roundNum$setsLabel complete]"
        )
    }

    Update-Status $statusLines
}

Write-Host ""
Write-Host "Session ended. Well done!"

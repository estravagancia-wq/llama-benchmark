# llama.cpp Performance Monitor - TTFT (idle ping) + TPS degradation (n_decoded delta)
# Hardware: AMD RX 9070 XT (16GB) + Ryzen 7 9800X3D + 64GB DDR5

$serverUrl = "http://127.0.0.1:8080"
$slotsUrl = "$serverUrl/slots"

$stop = $false
$host.UI.RawUI.WindowTitle = ">> llama.cpp Monitor (TTFT + TPS Degradation)"

# TTFT history
$tfttHistory = @()

# TPS degradation history: list of {timestamp, n_decoded}
$tpsHistory = @{}

# Previous n_decoded values
$prevNDecoded = @{}

# Session tracking
$sessionStartTime = Get-Date

$rocmSmi = Get-Command rocm-smi -ErrorAction SilentlyContinue
$hasAmdRZR = Get-Command amdrzr -ErrorAction SilentlyContinue -InformationAction SilentlyContinue
$gpuTool = if ($hasAmdRZR) { 'amdrzr' } elseif ($rocmSmi) { 'rocm-smi' } else { $null }

Write-Host ""
Write-Host "=======================================================" -ForegroundColor DarkCyan
Write-Host "  llama.cpp Monitor" -ForegroundColor Cyan
Write-Host "  RX 9070 XT (16GB) | 9800X3D | 64GB DDR5" -ForegroundColor DarkGray
Write-Host "  Server: $serverUrl" -ForegroundColor DarkGray
if ($gpuTool) {
    Write-Host "  [GPU: $gpuTool OK]" -ForegroundColor DarkGreen
} else {
    Write-Host "  [GPU: rocm-smi NO disponible]" -ForegroundColor Yellow
}
Write-Host "  Ctrl+C para detener y guardar log" -ForegroundColor DarkGray
Write-Host ""

# Set up Ctrl+C handler to save log before exiting
$script:stopRequested = $false

# Trap to handle Ctrl+C and enable graceful exit with logging
trap {
    Write-Host "`n[INFO] Capturando Ctrl+C..." -ForegroundColor Yellow
    $script:stopRequested = $true
}

# Header
Write-Host "  Time" -NoNewline -ForegroundColor DarkGray
Write-Host "  " -NoNewline
Write-Host "TTFT" -NoNewline -ForegroundColor DarkCyan
Write-Host " " -NoNewline
Write-Host "TPS" -NoNewline -ForegroundColor DarkCyan
Write-Host " " -NoNewline
Write-Host "Tokens" -NoNewline -ForegroundColor DarkCyan
Write-Host " " -NoNewline
Write-Host "CPU%" -NoNewline -ForegroundColor DarkCyan
Write-Host " RAM(GB)" -NoNewline -ForegroundColor DarkCyan
Write-Host " " -NoNewline
Write-Host "Slots" -NoNewline -ForegroundColor DarkCyan
Write-Host " " -NoNewline
Write-Host "Chart" -NoNewline -ForegroundColor DarkCyan
Write-Host "" -ForegroundColor DarkCyan

function Get-SlotData {
    try {
        $slots = Invoke-RestMethod -Uri $slotsUrl -TimeoutSec 3 -Method Get
        if ($slots -is [array]) { return $slots }
        return @($slots)
    } catch { return $null }
}

function Measure-TTFT {
    $url = "$serverUrl/v1/chat/completions"
    $body = @{
        messages = @( @{ role = "user"; content = "ok" } )
        max_tokens = 2
        stream = $true
        temperature = 0.7
    } | ConvertTo-Json

    $ttft = 0
    try {
        $httpReq = [System.Net.HttpWebRequest]::Create($url)
        $httpReq.Method = "POST"
        $httpReq.ContentType = "application/json"
        $httpReq.Timeout = 5000
        $httpReq.KeepAlive = $false

        $writer = New-Object System.IO.StreamWriter($httpReq.GetRequestStream())
        $writer.Write($body)
        $writer.Close()

        $ttftStart = [System.DateTime]::Now
        $firstByteFound = $false

        try {
            $response = [System.Net.HttpWebResponse]$httpReq.GetResponse()
            $ttftMs = [math]::Round(([System.DateTime]::Now - $ttftStart).TotalMilliseconds, 1)
            
            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $line = $reader.ReadLine()
            if ($null -eq $line) { $line = $reader.ReadLine() }
            $reader.Close()
            $response.Close()

            if ($line -match 'data:\s*"') {
                $ttft = $ttftMs
            } elseif ($line -match 'data:\s*\[') {
                $ttft = $ttftMs
            } else {
                $ttft = $ttftMs
            }
        } catch {
            # timeout or error - can't measure
        }
    } catch {
        # connection error - can't measure
    }

    return $ttft
}

function Get-GpuVram {
    $vram = 0
    if (-not $gpuTool) { return $vram }
    try {
        if ($gpuTool -eq 'rocm-smi') {
            $gpuData = & rocm-smi --showmeminfo vram 2>&1 | Out-String
            if ($gpuData -match 'Total:\s*(\d+)\s+MiB' -and $gpuData -match 'Free:\s*(\d+)\s+MiB') {
                $total = [int]$Matches[1]
                $free = [int]$Matches[2]
                $vram = $total - $free
            }
        }
    } catch { $vram = 0 }
    return $vram
}

function Format-Chart($tpsValues) {
    if ($tpsValues.Count -lt 2) { return " " }
    
    $max = ($tpsValues | Measure-Object -Maximum).Maximum
    if ($max -le 0 -or [double]::IsNaN($max) -or [double]::IsInfinity($max)) { return " " }
    if ([double]::IsNaN($tpsValues[0])) { return " " }
    
    $chartWidth = 15
    $chart = ""
    
    for ($i = 0; $i -lt $tpsValues.Count; $i++) {
        $val = $tpsValues[$i]
        if ([double]::IsNaN($val) -or [double]::IsInfinity($val)) { continue }
        if ($val -le 0) { continue }
        $height = [math]::Round(($val / $max) * $chartWidth)
        $height = [math]::Max(1, [math]::Min([int]$height, $chartWidth))
        $chart += "." * $height
        if ($i -lt ($tpsValues.Count - 1)) {
            $chart += " "
        }
    }
    
    return $chart
}

function Save-SessionLog {
    # Create logs directory if it doesn't exist
    $logDir = Join-Path $PSScriptRoot "logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $logFile = Join-Path $logDir "llama_monitor_$timestamp.json"
    
    # Prepare session data for logging
    $sessionData = @{
        SessionInfo = @{
            StartTime = $sessionStartTime.ToString()
            EndTime = (Get-Date).ToString()
            ServerUrl = $serverUrl
            TotalDurationSeconds = ((Get-Date) - $sessionStartTime).TotalSeconds
        }
        HardwareInfo = @{
            GPUTool = $gpuTool
            # Note: VRAM, CPU, RAM info would need to be captured at start/end
        }
        TTFT_History = $tfttHistory
        TPS_History_Slots = @{}
        Summary = @{}
        CpuUsage = $null
        RamUsedGB = $null
    }
    
    # Capture current CPU and RAM at save time
    try {
        $cpuProcs = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
        $sessionData.HardwareInfo.CpuUsage = if ($cpuProcs) { [math]::Round(($cpuProcs | Measure-Object -Property LoadPercentage -Average).Average, 1) } else { $null }
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $sessionData.HardwareInfo.RamUsedGB = if ($os) { [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1) } else { $null }
    } catch { $sessionData.HardwareInfo.CpuUsage = $null; $sessionData.HardwareInfo.RamUsedGB = $null }
    
    # Convert TPS history to a more readable format
    foreach ($key in $tpsHistory.Keys) {
        $slotId = $key.Substring(6)  # Remove "slot_" prefix
        $sessionData.TPS_History_Slots[$slotId] = $tpsHistory[$key]
    }
    
    # Summary statistics
    $sessionData.Summary = @{
        TTFT_Count = $tfttHistory.Count
        TTFT_Average = if ($tfttHistory.Count -gt 0) { [math]::Round(($tfttHistory | Measure-Object -Average).Average, 2) } else { 0 }
        TTFT_Min = if ($tfttHistory.Count -gt 0) { [math]::Round(($tfttHistory | Measure-Object -Minimum).Minimum, 2) } else { 0 }
        TTFT_Max = if ($tfttHistory.Count -gt 0) { [math]::Round(($tfttHistory | Measure-Object -Maximum).Maximum, 2) } else { 0 }
    }
    
    # Save as JSON
    try {
        $sessionData | ConvertTo-Json -Depth 4 | Out-File -FilePath $logFile -Encoding UTF8
        Write-Host "`n[LOG] Session data saved to: $logFile" -ForegroundColor DarkGreen
        return $true
    } catch {
        Write-Host "`n[ERROR] Failed to save log: $_" -ForegroundColor Red
        return $false
    }
}

# Main loop - poll every second
$slotStartTime = @{}
$lastPollTime = @{}

while (-not $script:stopRequested) {
    Start-Sleep 5
    if ($script:stopRequested) { break }
    $time = Get-Date -Format 'HH:mm:ss'
    $now = [System.DateTime]::Now

    $slots = Get-SlotData
    if ($null -eq $slots) { continue }

    $activeCount = 0
    $idleCount = 0
    $vram = Get-GpuVram
    $cpuProcs = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
    $cpuTotal = if ($cpuProcs) { [math]::Round(($cpuProcs | Measure-Object -Property LoadPercentage -Average).Average, 1) } else { 0 }
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $ramUsed = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)

  # Check if all slots are idle (for TTFT measurement)
    $allIdle = $true
    foreach ($slot in $slots) {
        if ($slot.id -ne -1 -and $slot.is_processing) {
            $allIdle = $false
            break
        }
    }

    # Measure TTFT only if all idle (don't count as active)
    $ttftMs = $null
    if ($allIdle -and $activeCount -eq 0) {
        $ttftMs = Measure-TTFT
        if ($null -ne $ttftMs -and $ttftMs -gt 0) {
            $tfttHistory += $ttftMs
            if ($tfttHistory.Count -gt 50) { $tfttHistory = $tfttHistory[-20..-1] }
        }
        # If no real request, show idle
        $idleCpuColor = if ($cpuTotal -gt 80) { 'Red' } elseif ($cpuTotal -gt 50) { 'Yellow' } else { 'Cyan' }
        # Count slots before display
        $idleSlotCount = 0
        foreach ($slot in $slots) {
            if ($slot.id -eq -1) { $idleSlotCount++ }
        }
        $activeSlotCount = $slots.Count - $idleSlotCount
        Write-Host "$time " -NoNewline -ForegroundColor DarkGray
        if ($null -ne $ttftMs -and $ttftMs -gt 0) {
            $ttftColor = if ($ttftMs -lt 100) { 'Green' } elseif ($ttftMs -lt 500) { 'Yellow' } else { 'Red' }
            Write-Host "$([math]::Round($ttftMs))ms " -NoNewline -ForegroundColor $ttftColor
        } else {
            Write-Host " --  " -NoNewline -ForegroundColor Gray
        }
        Write-Host "idle " -NoNewline -ForegroundColor Gray
        Write-Host " -- " -NoNewline -ForegroundColor Gray
        Write-Host " " -NoNewline
        Write-Host "${cpuTotal}% " -NoNewline -ForegroundColor $idleCpuColor
        Write-Host "${ramUsed}GB " -NoNewline -ForegroundColor Green
        Write-Host " " -NoNewline
        Write-Host "$activeSlotCount/$idleSlotCount " -NoNewline -ForegroundColor Yellow
        Write-Host "   " -ForegroundColor Gray
        Write-Host ""
        continue
    }

    # Track TPS degradation via n_decoded delta
    $tpsValues = @()
    $totalContext = 0
    
    foreach ($slot in $slots) {
        $slotId = $slot.id
        if ($slotId -eq -1) {
            $idleCount++
            continue
        }
        
        $activeCount++
        $nDecoded = if ($null -ne $slot.next_token -and $slot.next_token.Count -gt 0) {
            $slot.next_token[0].n_decoded
        } else { 0 }
        
        $totalContext += $nDecoded
        
        # Calculate TPS from delta
        $tps = 0
        if ($lastPollTime.ContainsKey($slotId) -and $prevNDecoded.ContainsKey($slotId)) {
            $elapsed = ($now - $lastPollTime[$slotId]).TotalSeconds
            $delta = $nDecoded - $prevNDecoded[$slotId]
            if ($elapsed -gt 0 -and $delta -ge 0) {
                $tps = [math]::Round($delta / $elapsed, 1)
            }
        }
        
        # Track TPS history per slot for mini chart
        $tpsKey = "slot_$slotId"
        if (-not $tpsHistory.ContainsKey($tpsKey)) {
            $tpsHistory[$tpsKey] = @()
        }
        $tpsHistory[$tpsKey] += $tps
        if ($tpsHistory[$tpsKey].Count -gt 30) { $tpsHistory[$tpsKey] = $tpsHistory[$tpsKey][-20..-1] }
        
        $tpsValues += $tps
        $lastPollTime[$slotId] = $now
        $prevNDecoded[$slotId] = $nDecoded
        
        if ($nDecoded -gt 0) {
            $slotStartTime[$slotId] = $now
        }
    }

    # Calculate average TPS
    $avgTps = if ($tpsValues.Count -gt 0) {
        [math]::Round(($tpsValues | Measure-Object -Average).Average, 1)
    } else { 0 }

    # Color for TPS
    $tpsColor = if ($avgTps -lt 20) { 'Red' } elseif ($avgTps -lt 40) { 'Yellow' } else { 'Green' }

    # Get mini chart from last TPS values
    $miniChart = ""
    if ($activeCount -gt 0) {
        # Use the first active slot's TPS history
        $firstActiveSlot = $slots | Where-Object { $_.id -ne -1 } | Select-Object -First 1
        if ($null -ne $firstActiveSlot) {
            $chartKey = "slot_$($firstActiveSlot.id)"
            if ($tpsHistory.ContainsKey($chartKey)) {
                $miniChart = Format-Chart $tpsHistory[$chartKey]
            }
        }
    }

    # Format output
    Write-Host "$time " -NoNewline -ForegroundColor DarkGray
    
    # TTFT
    if ($activeCount -eq 0) {
        if ($null -ne $ttftMs -and $ttftMs -gt 0) {
            $ttftColor = if ($ttftMs -lt 100) { 'Green' } elseif ($ttftMs -lt 500) { 'Yellow' } else { 'Red' }
            Write-Host "$([math]::Round($ttftMs))ms " -NoNewline -ForegroundColor $ttftColor
        } else {
            Write-Host " --  " -NoNewline -ForegroundColor Gray
        }
    } else {
        Write-Host " --  " -NoNewline -ForegroundColor Gray
    }
    
    Write-Host " " -NoNewline
    
    # TPS
    if ($activeCount -eq 0) {
        Write-Host "idle " -NoNewline -ForegroundColor Gray
        Write-Host " " -NoNewline
    } else {
        Write-Host "$avgTps " -NoNewline -ForegroundColor $tpsColor
        Write-Host " " -NoNewline
    }
    
    # Context (n_decoded = tokens en VRAM)
    if ($activeCount -eq 0) {
        Write-Host "-- " -NoNewline -ForegroundColor Gray
        Write-Host " " -NoNewline
    } else {
        Write-Host "$totalContext " -NoNewline -ForegroundColor DarkGray
        Write-Host "tok" -NoNewline -ForegroundColor Gray
        Write-Host " " -NoNewline
    }
    
    # CPU + RAM
    $cpuColor = if ($cpuTotal -gt 80) { 'Red' } elseif ($cpuTotal -gt 50) { 'Yellow' } else { 'Cyan' }
    Write-Host "$cpuTotal% " -NoNewline -ForegroundColor $cpuColor
    Write-Host "${ramUsed}GB " -NoNewline -ForegroundColor Green
    Write-Host " " -NoNewline
    
    # Slots
    Write-Host "$activeCount/$idleCount " -NoNewline -ForegroundColor Yellow
    Write-Host " " -NoNewline
    
    # Mini chart
    if ($activeCount -eq 0) {
        Write-Host "   " -ForegroundColor Gray
    } else {
        Write-Host "$miniChart" -ForegroundColor $tpsColor
    }
    Write-Host ""
}

# Save log before exiting
if ($script:stopRequested) {
    Save-SessionLog
}

# Cleanup: unregister event if registered
try {
    Get-Job -Name "CancelKeyHandler" -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue
    Get-Job -Name "CancelKeyHandler" -ErrorAction SilentlyContinue | Remove-Job -ErrorAction SilentlyContinue
} catch {}

Write-Host "`n[OK] Monitor detenido." -ForegroundColor DarkGray

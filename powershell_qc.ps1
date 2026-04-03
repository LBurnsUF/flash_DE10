# Author: Logan Burns
# Description: A basic programming tool used to flash devices in bulk with a safe test program (unused pins tristated inputs)

Add-Type -AssemblyName System.Windows.Forms

function Show-Info($message, $title = "Info") {
    [System.Windows.Forms.MessageBox]::Show(
        $message,
        $title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Show-YesNo($message, $title = "Confirm") {
    return [System.Windows.Forms.MessageBox]::Show(
        $message,
        $title,
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
}

function Show-RetryCancel($message, $title = "Confirm") {
    return [System.Windows.Forms.MessageBox]::Show(
        $message,
        $title,
        [System.Windows.Forms.MessageBoxButtons]::RetryCancel,
        [System.Windows.Forms.MessageBoxIcon]::Exclamation
    )
}


function Show-OkCancel($message, $title = "Confirm") {
    return [System.Windows.Forms.MessageBox]::Show(
        $message,
        $title,
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
}

function Get-JtagCables {
    param([string]$QuartusPgmPath)

    $output = & $QuartusPgmPath --list 2>$null

    $cables = @()
    foreach ($line in $output) {
        if ($line -match "^\s*(\d+)\)\s+(.+?)\s*$") {
            $cables += [pscustomobject]@{
                Index = [int]$Matches[1]
                Name  = $Matches[2]
            }
        }
    }
    return $cables
}

function Ensure-JtagdRunning {
    param([string]$QuartusBinDir)

    $jtagd = Join-Path $QuartusBinDir "jtagd.exe"
    if (-not (Test-Path $jtagd)) { return }

    $already = Get-Process -Name "jtagd" -ErrorAction SilentlyContinue
    if ($already) { return }

    Start-Process -FilePath $jtagd -WorkingDirectory $QuartusBinDir -WindowStyle Hidden | Out-Null
    Start-Sleep -Milliseconds 600
}

function Program-AllDevicesParallel {
    param(
        [string]$QuartusPgmPath,
        [string]$QuartusBinDir,
        [string]$PofFilePath,
        [pscustomobject[]]$Cables = $null,
        [int]$MaxAttempts = 3
    )

    if (-not $Cables -or $Cables.Count -eq 0) {
        $Cables = Get-JtagCables $QuartusPgmPath
    }

    if (-not $Cables -or $Cables.Count -eq 0) {
        Show-Info "No JTAG programmers detected." "Error"
        return @()
    }

    Ensure-JtagdRunning -QuartusBinDir $QuartusBinDir

    $logDir = Join-Path (Get-Location) "logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null

    $jobs = @()

    foreach ($c in $Cables) {

        $safeName = ($c.Name -replace '[\\/:*?"<>|\[\] ]','_')
        $logPath  = Join-Path $logDir ("cable_{0}_{1}.log" -f $c.Index, $safeName)

        $jobs += Start-Job -ScriptBlock {
            param($pgm, $binDir, $pof, $cableName, $cableIndex, $logPath, $maxAttempts)

            $code = 999
            $attemptUsed = 0

            try {
                $ld = Split-Path -Parent $logPath
                New-Item -ItemType Directory -Path $ld -Force | Out-Null

                Set-Location $binDir

                Start-Sleep -Milliseconds (150 + (Get-Random -Minimum 0 -Maximum 250))

                for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                    $attemptUsed = $attempt

                    ("[{0}] Cable {1} ({2}) attempt {3}/{4}" -f (Get-Date), $cableIndex, $cableName, $attempt, $maxAttempts) |
                        Out-File -FilePath $logPath -Append -Encoding Default

                    $output = & $pgm -m jtag -c $cableName -o ("pvb;{0}" -f $pof) 2>&1
                    $code = $LASTEXITCODE

                    $output | Out-File -FilePath $logPath -Append -Encoding Default

                    if ($code -eq 0) {
                        ("[{0}] SUCCESS" -f (Get-Date)) | Out-File -FilePath $logPath -Append -Encoding Default
                        break
                    }

                    ("[{0}] FAIL exitcode={1}" -f (Get-Date), $code) | Out-File -FilePath $logPath -Append -Encoding Default

                    if ($attempt -lt $maxAttempts) {
                        $delayMs = 500 * $attempt + (Get-Random -Minimum 0 -Maximum 400)
                        Start-Sleep -Milliseconds $delayMs
                    }
                }
            }
            catch {
                $code = 999
                ("[{0}] JOB EXCEPTION:`r`n{1}" -f (Get-Date), ($_ | Out-String)) |
                    Out-File -FilePath $logPath -Append -Encoding Default
            }

            [pscustomobject]@{
                CableIndex   = $cableIndex
                CableName    = $cableName
                ExitCode     = $code
                AttemptsUsed = $attemptUsed
                Success      = ($code -eq 0)
                Log          = $logPath
            }
        } -ArgumentList $QuartusPgmPath, $QuartusBinDir, $PofFilePath, $c.Name, $c.Index, $logPath, $MaxAttempts
    }

    Wait-Job $jobs | Out-Null
    $results = $jobs | Receive-Job
    Remove-Job $jobs

    return $results | Sort-Object CableIndex
}

function Restart-Jtagd {
    param([string]$QuartusBinDir)

    $jtagd = Join-Path $QuartusBinDir "jtagd.exe"
    if (-not (Test-Path $jtagd)) { return }

    Get-Process -Name "jtagd" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    Start-Process -FilePath $jtagd -WorkingDirectory $QuartusBinDir -WindowStyle Hidden | Out-Null
    Start-Sleep -Milliseconds 800
}

function Get-JtagCablesFresh {
    param(
        [string]$QuartusPgmPath,
        [string]$QuartusBinDir
    )

    Restart-Jtagd -QuartusBinDir $QuartusBinDir

    return Get-JtagCables -QuartusPgmPath $QuartusPgmPath
}

$quartusRootDir = [System.Environment]::GetEnvironmentVariable("QUARTUS_ROOTDIR", [System.EnvironmentVariableTarget]::Machine)
if (-not $quartusRootDir) {
    Show-Info "The environment variable QUARTUS_ROOTDIR is not set." "Error"
    exit 1
}

$quartusBin = Join-Path -Path $quartusRootDir -ChildPath "bin"
if (-not (Test-Path $quartusBin)) {
    $quartusBin = Join-Path -Path $quartusRootDir -ChildPath "bin64"
    if (-not (Test-Path $quartusBin)) {
        Show-Info "Neither 'bin' nor 'bin64' directory was found under QUARTUS_ROOTDIR." "Error"
        exit 1
    }
}

$quartusPgm = Join-Path $quartusBin "quartus_pgm.exe"
if (-not (Test-Path $quartusPgm)) {
    Show-Info "quartus_pgm.exe was not found under $quartusBin" "Error"
    exit 1
}

$pofItem = Get-ChildItem -Path $PSScriptRoot -Filter "safe.pof" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $pofItem) {
    Show-Info "Could not find 'safe.pof' next to the script: $PSScriptRoot" "Error"
    exit 1
}

$pofFullPath = (Resolve-Path $pofItem.FullName).Path

Show-Info "Connect all DE10s you want to flash (one per USB-Blaster), then click OK." "Awaiting DE10s"

$continue = $true
$logDir = Join-Path (Get-Location) "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

while ($continue) {

    $start = Show-YesNo "Ready to flash all connected programmers with safe.pof?" "Flash Batch"
    if ($start -ne [System.Windows.Forms.DialogResult]::Yes) {
        break
    }

    $cables = Get-JtagCablesFresh -QuartusPgmPath $quartusPgm -QuartusBinDir $quartusBin
    $results = Program-AllDevicesParallel `
    -QuartusPgmPath $quartusPgm `
    -QuartusBinDir  $quartusBin `
    -PofFilePath    $pofFullPath `
    -Cables         $cables `
    -MaxAttempts    3

    $passed = @($results | Where-Object { $_.ExitCode -eq 0 })
    $failed = @($results | Where-Object { $_.ExitCode -ne 0 })

    if ($results.Count -eq 0) {
        $next = Show-OkCancel "No programmers detected. Connect devices and click OK to retry, or Cancel to quit." "Awaiting DE10s"
        if ($next -ne [System.Windows.Forms.DialogResult]::OK) { $continue = $false }
        continue
    }

    $passedNames = $passed | ForEach-Object { "$($_.CableIndex): $($_.CableName)" }
    $failedNames = $failed | ForEach-Object { "$($_.CableIndex): $($_.CableName)" }

    $summary = "Batch complete.`n`n" +
           "Success: $($passed.Count) cable(s)" +
           ($(if ($passedNames.Count) { "`n  " + ($passedNames -join ", ") } else { "" })) +
           "`n`nFailures: $($failed.Count) cable(s)" +
           ($(if ($failedNames.Count) { "`n  " + ($failedNames -join ", ") } else { "" }))
    
    if ($failed.Count -gt 0) {
        $errText = ($failed | ForEach-Object {
        $tail = @()
        if (Test-Path $_.Log) {
            $tail = Get-Content $_.Log -Tail 30 -ErrorAction SilentlyContinue
        }
        $snippet = if ($tail.Count -gt 0) { ($tail -join "`r`n") } else { "(no log output captured)" }

        "Cable $($_.CableIndex): $($_.CableName)`r`nExitCode: $($_.ExitCode)`r`n--- Last log lines ---`r`n$snippet`r`n"
    }) -join "`r`n========================`r`n"

    Show-Info $errText "Quartus Error Details"
    }

    if ($failed.Count -eq 0) {
        Show-Info ($summary + "`n`nProgramming done. Sort boards by status (working/broken).") "Done"
    } 
    else {
        $retry = Show-RetryCancel ($summary + "`n`nRetry FAILED cables?") "Programming Failed"
        if ($retry -eq [System.Windows.Forms.DialogResult]::Retry) {
            while ($true) {
                 $cablesFresh = Get-JtagCablesFresh -QuartusPgmPath $quartusPgm -QuartusBinDir $quartusBin

                 $failedNamesOnly = @($failed | Select-Object -ExpandProperty CableName)
                 $failedCableObjs = @($cablesFresh | Where-Object { $_.Name -in $failedNamesOnly })

                 if ($failedCableObjs.Count -eq 0) { break }

                 $cables = $cablesFresh

                 $failedNames = $failed | ForEach-Object { "$($_.CableIndex): $($_.CableName)" }
                 $retrySummary = "Retry complete.`n`nStill failing: $($failed.Count)`n  " + ($failedNames -join ", ")

                 $errText = ($failed | ForEach-Object {
                     $tail = @()
                     if (Test-Path $_.Log) { $tail = Get-Content $_.Log -Tail 30 -ErrorAction SilentlyContinue }
                     $snippet = if ($tail.Count -gt 0) { ($tail -join "`r`n") } else { "(no log output captured)" }
                     "Cable $($_.CableIndex): $($_.CableName)`r`nExitCode: $($_.ExitCode)`r`n--- Last log lines ---`r`n$snippet`r`n"
                 }) -join "`r`n========================`r`n"

                 Show-Info $errText "Quartus Error Details (Retry)"

                 $again = Show-RetryCancel ($retrySummary + "`n`nRetry again?") "Still Failing"
                 if ($again -ne [System.Windows.Forms.DialogResult]::Retry) { break }
        }
    }
}

    $next = Show-OkCancel "Disconnect finished boards, connect the next set, and click OK when ready.`nCancel to quit." "Next Batch"
    if ($next -ne [System.Windows.Forms.DialogResult]::OK) {
        $continue = $false
    }
}
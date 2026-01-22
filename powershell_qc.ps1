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

$pofPath = Get-ChildItem -Path (Get-Location) -Filter "safe.pof" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not (Test-Path $pofPath)) {
    Show-Info "Could not find 'safe.pof' in: $(Get-Location) or any subdirectories." "Error"
    exit 1
}

function Program-DeviceSafePof {
    param(
        [string]$QuartusPgmPath,
        [string]$PofFilePath
    )
	
    $retrypath = $false
    while ($true) {

	if(!$retrypath) {
            $start = Show-YesNo "Ready to flash this DE10-Lite with safe.pof?" "Flash DE10"
        
            if ($start -eq [System.Windows.Forms.DialogResult]::No) {
                return $false
            }
        }

        # Run Quartus Programmer
        & $QuartusPgmPath -m jtag -c 1 -o "pvb;$PofFilePath" *> $null
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            Show-Info "Programming done. If working, Place the DE10 in the section corresponding to its status (working/broken)." "Done"
            return $true
        }

        $retry = Show-RetryCancel "Programming failed (exit code: $exitCode).`nRetry?" "Programming Failed"
	if ($retry -eq [System.Windows.Forms.DialogResult]::Retry) {
            $retrypath = $true
        }

        if ($retry -ne [System.Windows.Forms.DialogResult]::Retry) {
            return $false
        }
    }
}

Show-Info "Connect the first DE10 before proceeding" "Awaiting DE10"

$continue = $true

while ($continue) {

    # Flash device
    [void](Program-DeviceSafePof -QuartusPgmPath $quartusPgm -PofFilePath $pofPath)

    $next = Show-OkCancel "Connect the next device and click OK when ready." "Awaiting DE10"
    switch ($next) {
        ([System.Windows.Forms.DialogResult]::OK)     { }
        ([System.Windows.Forms.DialogResult]::Cancel) { $continue = $false }
        default { $continue = $false }
    }
}

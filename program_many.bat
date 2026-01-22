@echo off
setlocal

REM Ensure QUARTUS_ROOTDIR exists
if "%QUARTUS_ROOTDIR%"=="" (
  echo ERROR: QUARTUS_ROOTDIR is not set.
  echo Set it or open the Quartus shell, then re-run.
  pause
  exit /b 1
)

REM Launch the PowerShell flasher
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\powershell_qc.ps1

endlocal

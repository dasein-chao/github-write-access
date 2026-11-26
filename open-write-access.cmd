@echo off
setlocal enabledelayedexpansion
title GitHub Write Access

set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"

echo.
echo ============================================================
echo   GitHub Write Access
echo ============================================================
echo.

set "GIT="
for /f "delims=" %%i in ('where git 2^>nul') do if not defined GIT set "GIT=%%i"
if not defined GIT goto :nogit

set "BASH="
for /f "delims=" %%i in ('where bash 2^>nul') do if not defined BASH set "BASH=%%i"
if not defined BASH (
  for %%i in ("!GIT!") do set "GITDIR=%%~dpi"
  if exist "!GITDIR!..\..\usr\bin\bash.exe" set "BASH=!GITDIR!..\..\usr\bin\bash.exe"
  if not defined BASH if exist "!GITDIR!..\..\bin\bash.exe" set "BASH=!GITDIR!..\..\bin\bash.exe"
)
if not defined BASH goto :nobash

echo git : !GIT!
echo bash: !BASH!
echo.

"!BASH!" "!HERE!\setup.sh"
if errorlevel 1 (
  echo.
  echo Setup stopped early. Read the message above - it says what to do next.
  goto :end
)

echo.
echo ------------------------------------------------------------
set "REPO="
set /p REPO=Repo to test with a real push (owner/name, Enter to skip): 
if "!REPO!"=="" goto :end
echo.
"!BASH!" "!HERE!\verify.sh" --repo "!REPO!"
goto :end

:nogit
echo [x] git not found in PATH.
echo     Install Git for Windows, then reopen this file.
goto :end

:nobash
echo [x] git was found but bash was not.
echo     Expected next to git: ..\..\usr\bin\bash.exe
echo     Reinstall Git for Windows including the Unix tools.
goto :end

:end
echo.
pause

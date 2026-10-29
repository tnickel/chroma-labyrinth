@echo off
setlocal

rem Prefer an explicitly configured engine; local settings never enter Git.
if defined GODOT_EXE goto validate_engine
if exist "%~dp0start.local.bat" call "%~dp0start.local.bat"
if defined GODOT_EXE goto validate_engine

rem A portable Godot executable can live next to this launcher.
for %%N in (godot.exe godot4.exe Godot_v4.7.2-stable_win64_console.exe Godot_v4.7.2-stable_win64.exe) do (
  if exist "%~dp0%%N" (
    set "GODOT_EXE=%~dp0%%N"
    goto validate_engine
  )
)
rem Otherwise use Godot from PATH.
for %%N in (godot.exe godot4.exe Godot_v4.7.2-stable_win64_console.exe Godot_v4.7.2-stable_win64.exe) do (
  for /f "delims=" %%P in ('where %%N 2^>nul') do (
    set "GODOT_EXE=%%P"
    goto validate_engine
  )
)

echo Godot wurde nicht gefunden. Empfohlen: Godot 4.7.2 mit Forward+.
echo Setze GODOT_EXE auf den vollstaendigen Pfad zur Godot-EXE,
echo lege die EXE neben start.bat ab oder fuege Godot zu PATH hinzu.
echo Alternativ project.godot im Godot-Editor oeffnen. Details: README.md.
pause
exit /b 1

:validate_engine
if exist "%GODOT_EXE%" goto launch
echo Die konfigurierte Godot-EXE wurde nicht gefunden: "%GODOT_EXE%"
pause
exit /b 1

:launch
echo Bereite Projekt und 3D-Modelle vor ...
"%GODOT_EXE%" --headless --path "%~dp0." --import
if errorlevel 1 (
  echo Der Import ist fehlgeschlagen. Siehe Fehlermeldung oben.
  pause
  exit /b 1
)
"%GODOT_EXE%" --path "%~dp0." %*
set "CHROMA_EXIT=%ERRORLEVEL%"
if not "%CHROMA_EXIT%"=="0" (
  echo Godot konnte nicht gestartet werden. Siehe Fehlermeldung oben.
  pause
)
exit /b %CHROMA_EXIT%

@echo off
rem Start socket-lab on Windows:   .\lab.cmd [lab|strace|step|step_strace]
rem
rem This only starts lab.ps1, which does the work. -ExecutionPolicy Bypass
rem is needed because Windows does not run downloaded .ps1 scripts by default.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lab.ps1" %*
exit /b %ERRORLEVEL%

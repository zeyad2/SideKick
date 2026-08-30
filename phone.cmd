@echo off
setlocal

cd /d "%~dp0"

if not exist "C:\src\flutter\bin\flutter.bat" (
  echo Flutter was not found at C:\src\flutter\bin\flutter.bat
  exit /b 1
)

if not exist ".env" (
  echo SideKick's .env file was not found in %CD%
  exit /b 1
)

"C:\src\flutter\bin\flutter.bat" run -d AX3C025606000388 --dart-define-from-file=.env
exit /b %ERRORLEVEL%

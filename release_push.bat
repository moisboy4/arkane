@echo off
REM Wrapper to run release_push.py with system Python
cd /d "%~dp0"
python release_push.py %*

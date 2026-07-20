@echo off
chcp 65001 > nul
:: Python script run wrapper
set SCRIPT_PATH=%USERPROFILE%\scripts\notion\notion_auto_sync.py
python "%SCRIPT_PATH%"

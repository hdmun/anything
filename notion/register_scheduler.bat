@echo off
chcp 65001 > nul
echo ==========================================================
echo  Notion 스크랩 자동 정리 스케줄러 등록 도구
echo ==========================================================
echo.
echo [안내] 이 도구는 매일 1회(오전 9시) 스크랩을 자동 분류하는 백그라운드 작업을
echo        Windows 작업 스케줄러에 등록합니다.
echo        등록에 실패할 경우, 이 파일을 '마우스 우클릭 -> 관리자 권한으로 실행'해 주세요.
echo.

set TASK_NAME=NotionScrapAutoSync
set ACTION_PATH=%USERPROFILE%\scripts\notion\run_notion_sync.bat

:: 기존 등록된 동일 명칭의 태스크 제거 (안전성 확보)
schtasks /delete /tn "%TASK_NAME%" /f >nul 2>&1

:: 매일 1회(daily), 오전 9시(09:00)에 실행되도록 스케줄러 등록
schtasks /create /tn "%TASK_NAME%" /tr "\"%ACTION_PATH%\"" /sc daily /st 09:00 /f

if %errorlevel% equ 0 (
    echo.
    echo ----------------------------------------------------------
    echo [성공] 작업 스케줄러 등록 완료!
    echo        매일 오전 9시에 백그라운드에서 스크랩이 자동으로 정돈됩니다.
    echo        로그 확인: C:\Users\hdmun\agent\logs\sync_YYYYMMDD_HHMMSS.log
    echo.
    echo *참고* 실행 시각을 변경하고 싶다면 Windows 제어판의 '작업 스케줄러'를 열어
    echo        'NotionScrapAutoSync' 작업의 트리거(시간)를 자유롭게 변경하십시오.
    echo ----------------------------------------------------------
) else (
    echo.
    echo ----------------------------------------------------------
    echo [오류] 스케줄러 등록 실패. 
    echo        관리자 권한(우클릭 -> 관리자 권한으로 실행)이 필요할 수 있습니다.
    echo ----------------------------------------------------------
)
echo.
pause

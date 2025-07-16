@echo off
echo ========================================
echo Whisper 語音轉文字工具
echo ========================================
echo.

REM 檢查虛擬環境是否存在
if not exist "venv" (
    echo [錯誤] 未找到虛擬環境！
    echo 請先執行 install.bat 進行安裝
    pause
    exit /b 1
)

echo [1/2] 啟動虛擬環境...
call venv\Scripts\activate.bat

echo.
echo [2/2] 啟動應用程式...
echo.
echo 應用程式將在瀏覽器中開啟
echo 網址: http://localhost:8501
echo.
echo 按 Ctrl+C 可以停止應用程式
echo ========================================
echo.

streamlit run whisper_app.py

pause

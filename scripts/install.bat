@echo off
echo ========================================
echo Whisper 語音轉文字工具 - 安裝程式
echo ========================================
echo.

REM 檢查 Python 是否已安裝
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [錯誤] 未偵測到 Python！
    echo 請先安裝 Python 3.8 或更高版本
    echo 下載地址: https://www.python.org/downloads/
    pause
    exit /b 1
)

echo [1/4] 檢查 Python 版本...
python --version

echo.
echo [2/4] 建立虛擬環境...
python -m venv venv

echo.
echo [3/4] 啟動虛擬環境...
call venv\Scripts\activate.bat

echo.
echo [4/4] 安裝必要套件...
python -m pip install --upgrade pip
pip install -r requirements.txt

echo.
echo ========================================
echo 安裝完成！
echo.
echo 執行 "啟動.bat" 來啟動應用程式
echo ========================================
pause

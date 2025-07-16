#!/bin/bash

echo "========================================"
echo "Whisper 語音轉文字工具"
echo "========================================"
echo

# 進入專案根目錄
cd "$(dirname "$0")/.."

# 檢查虛擬環境是否存在
if [ ! -d "venv" ]; then
    echo "[錯誤] 未找到虛擬環境！"
    echo "請先執行 ./scripts/install.sh 進行安裝"
    exit 1
fi

# 檢查 ffmpeg 是否已安裝
if ! command -v ffmpeg &> /dev/null; then
    echo "[錯誤] 未偵測到 ffmpeg！"
    echo ""
    echo "請先安裝 ffmpeg："
    echo "執行: brew install ffmpeg"
    echo ""
    echo "安裝完成後再執行此腳本"
    exit 1
fi

echo "[1/3] 檢查 ffmpeg..."
ffmpeg -version | head -n 1

echo
echo "[2/3] 啟動虛擬環境..."
source venv/bin/activate

# 檢查 streamlit 是否已安裝
if ! command -v streamlit &> /dev/null; then
    echo "[錯誤] Streamlit 未安裝！"
    echo "請先執行 ./scripts/install.sh 進行安裝"
    exit 1
fi

echo
echo "[3/3] 啟動應用程式..."
echo
echo "應用程式將在瀏覽器中開啟"
echo "網址: http://localhost:8501"
echo
echo "按 Ctrl+C 可以停止應用程式"
echo "========================================"
echo

streamlit run whisper_app.py

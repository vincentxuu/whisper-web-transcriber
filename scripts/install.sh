#!/bin/bash

echo "========================================"
echo "Whisper 語音轉文字工具 - 安裝程式"
echo "========================================"
echo

# 進入專案根目錄
cd "$(dirname "$0")/.."

# 檢查 Python 是否已安裝
if ! command -v python3 &> /dev/null; then
    echo "[錯誤] 未偵測到 Python3！"
    echo "請先安裝 Python 3.8 或更高版本"
    echo "macOS: brew install python3"
    echo "Ubuntu/Debian: sudo apt-get install python3"
    echo "CentOS/RHEL: sudo yum install python3"
    exit 1
fi

# 檢查 ffmpeg 是否已安裝
if ! command -v ffmpeg &> /dev/null; then
    echo "[警告] 未偵測到 ffmpeg！"
    echo "Whisper 需要 ffmpeg 來處理音頻檔案"
    echo ""
    echo "請安裝 ffmpeg："
    echo "macOS: brew install ffmpeg"
    echo "Ubuntu/Debian: sudo apt-get install ffmpeg"
    echo "CentOS/RHEL: sudo yum install ffmpeg"
    echo ""
    read -p "是否繼續安裝？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "[1/5] 檢查 Python 版本..."
python3 --version

if command -v ffmpeg &> /dev/null; then
    echo "[2/5] 檢查 ffmpeg 版本..."
    ffmpeg -version | head -n 1
fi

echo
echo "[3/5] 建立虛擬環境..."
python3 -m venv venv

echo
echo "[4/5] 啟動虛擬環境..."
source venv/bin/activate

echo
echo "[5/5] 安裝必要套件..."
python -m pip install --upgrade pip
pip install -r requirements.txt

echo
echo "========================================"
echo "安裝完成！"
echo

if ! command -v ffmpeg &> /dev/null; then
    echo "[重要] 請記得安裝 ffmpeg 才能正常使用！"
    echo "執行: brew install ffmpeg"
    echo
fi

echo "執行 './scripts/start.sh' 來啟動應用程式"
echo "========================================"

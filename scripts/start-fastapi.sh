#!/bin/bash

echo "========================================"
echo "Whisper 語音轉文字工具 - FastAPI 版本"
echo "========================================"
echo

# 進入專案根目錄
cd "$(dirname "$0")/.."

# 檢查基本需求
echo "[1/6] 檢查系統需求..."

# 檢查 Python
if ! command -v python3 &> /dev/null; then
    echo "[錯誤] 未偵測到 Python3！"
    echo "請先安裝 Python 3.8 或更高版本"
    exit 1
fi

# 檢查 Python 版本
PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
MIN_VERSION="3.8"
if [ "$(printf '%s\n' "$MIN_VERSION" "$PYTHON_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]; then
    echo "[錯誤] Python 版本 $PYTHON_VERSION 過低，需要 3.8 或更高版本"
    exit 1
fi

echo "✅ Python 版本: $PYTHON_VERSION"

# 檢查並安裝 ffmpeg
echo "[2/6] 檢查 ffmpeg..."
if ! command -v ffmpeg &> /dev/null; then
    echo "[警告] 未偵測到 ffmpeg！正在嘗試自動安裝..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            echo "使用 Homebrew 安裝 ffmpeg..."
            brew install ffmpeg
        else
            echo "[錯誤] 請先安裝 Homebrew 或手動安裝 ffmpeg"
            echo "安裝 Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get &> /dev/null; then
            echo "使用 apt 安裝 ffmpeg..."
            sudo apt-get update && sudo apt-get install -y ffmpeg
        elif command -v yum &> /dev/null; then
            echo "使用 yum 安裝 ffmpeg..."
            sudo yum install -y ffmpeg
        else
            echo "[錯誤] 無法自動安裝 ffmpeg，請手動安裝"
            exit 1
        fi
    fi
else
    echo "✅ ffmpeg 已安裝"
fi

# 創建必要目錄
echo "[3/6] 檢查專案結構..."
mkdir -p uploads results logs

if [ ! -d "backend" ] || [ ! -d "frontend" ]; then
    echo "[錯誤] 未找到完整的專案結構 (backend/frontend)！"
    echo "請確保您在正確的專案目錄中執行此腳本"
    exit 1
fi

echo "✅ 專案結構完整"

# 檢查並創建虛擬環境
echo "[4/6] 檢查 Python 虛擬環境..."
if [ ! -d "venv" ]; then
    echo "正在創建虛擬環境..."
    python3 -m venv venv
    echo "✅ 虛擬環境創建完成"
else
    echo "✅ 虛擬環境已存在"
fi

# 啟動虛擬環境
echo "[5/6] 啟動虛擬環境並檢查依賴..."
source venv/bin/activate

# 升級 pip
python -m pip install --upgrade pip > /dev/null 2>&1

# 檢查並安裝依賴
NEED_INSTALL=false

if ! python -c "import fastapi, uvicorn" &> /dev/null; then
    echo "⚠️  FastAPI/uvicorn 未安裝，正在安裝..."
    NEED_INSTALL=true
fi

if ! python -c "import whisper" &> /dev/null; then
    echo "⚠️  OpenAI Whisper 未安裝，正在安裝..."
    NEED_INSTALL=true
fi

if $NEED_INSTALL; then
    echo "正在安裝 Python 依賴..."
    pip install -r backend/requirements.txt
    echo "✅ 依賴安裝完成"
else
    echo "✅ 所有依賴已安裝"
fi

echo
echo "[6/6] 啟動 FastAPI 應用程式..."
echo
echo "========================================"
echo "🚀 FastAPI 應用程式啟動中..."
echo ""
echo "🌐 主要介面: http://localhost:8000"
echo "📚 API 文檔: http://localhost:8000/docs"
echo "📖 ReDoc 文檔: http://localhost:8000/redoc"
echo ""
echo "💡 提示："
echo "- 可以直接使用網頁介面進行語音轉文字"
echo "- 也可以通過 API 端點進行程式化調用"
echo "- 首次使用會自動下載 Whisper 模型"
echo ""
echo "按 Ctrl+C 可以停止應用程式"
echo "========================================"
echo

# 切換到 backend 目錄
cd backend

# 設置環境變數
export UPLOAD_DIR="../uploads"
export RESULT_DIR="../results"
export LOG_LEVEL="info"

# 使用陷阱處理中斷信號
trap 'echo -e "\n正在停止服務..."; kill $UVICORN_PID 2>/dev/null; exit 0' INT

# 啟動 FastAPI 應用
echo "🔄 正在啟動服務..."

# 使用 uvicorn 啟動應用
uvicorn app:app \
    --host 0.0.0.0 \
    --port 8000 \
    --reload \
    --log-level info \
    --access-log &

UVICORN_PID=$!

# 等待服務啟動
sleep 3

# 檢查服務是否成功啟動
if kill -0 $UVICORN_PID 2>/dev/null; then
    echo "✅ FastAPI 服務啟動成功！"
    echo ""
    echo "🎉 準備就緒！請在瀏覽器中訪問："
    echo "   http://localhost:8000"
    echo ""
    
    # 嘗試自動開啟瀏覽器（macOS）
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "🔓 嘗試自動開啟瀏覽器..."
        sleep 2
        open http://localhost:8000 2>/dev/null || echo "請手動開啟瀏覽器訪問 http://localhost:8000"
    fi
    
    # 等待進程結束
    wait $UVICORN_PID
else
    echo "❌ FastAPI 服務啟動失敗！"
    echo ""
    echo "可能的原因："
    echo "1. 端口 8000 已被佔用"
    echo "2. 依賴缺失或版本不相容"
    echo "3. 權限問題"
    echo ""
    echo "請檢查錯誤信息並重試"
    exit 1
fi
#!/bin/bash

echo "========================================"
echo "Whisper 語音轉文字工具 - FastAPI 版本"
echo "========================================"
echo

# 進入專案根目錄
cd "$(dirname "$0")/.."

# 檢查虛擬環境是否存在
if [ ! -d "venv" ]; then
    echo "[錯誤] 未找到虛擬環境！"
    echo "請先執行 ./scripts/install-fastapi.sh 進行安裝"
    exit 1
fi

# 檢查 backend 目錄是否存在
if [ ! -d "backend" ]; then
    echo "[錯誤] 未找到 backend 目錄！"
    echo "請先執行 ./scripts/install-fastapi.sh 進行安裝"
    exit 1
fi

# 檢查 frontend 目錄是否存在
if [ ! -d "frontend" ]; then
    echo "[錯誤] 未找到 frontend 目錄！"
    echo "請先執行 ./scripts/install-fastapi.sh 進行安裝"
    exit 1
fi

# 檢查 ffmpeg 是否已安裝
if ! command -v ffmpeg &> /dev/null; then
    echo "[錯誤] 未偵測到 ffmpeg！"
    echo ""
    echo "請先安裝 ffmpeg："
    echo "macOS: brew install ffmpeg"
    echo "Ubuntu/Debian: sudo apt-get install ffmpeg"
    echo "CentOS/RHEL: sudo yum install ffmpeg"
    echo ""
    echo "安裝完成後再執行此腳本"
    exit 1
fi

echo "[1/4] 檢查 ffmpeg..."
ffmpeg -version | head -n 1

echo
echo "[2/4] 啟動虛擬環境..."
source venv/bin/activate

# 檢查 FastAPI 相關套件是否已安裝
echo "[3/4] 檢查依賴..."
if ! python -c "import fastapi, uvicorn" &> /dev/null; then
    echo "[錯誤] FastAPI 或 uvicorn 未安裝！"
    echo "請先執行 ./scripts/install-fastapi.sh 進行安裝"
    exit 1
fi

# 檢查 Whisper 是否已安裝
if ! python -c "import whisper" &> /dev/null; then
    echo "[錯誤] OpenAI Whisper 未安裝！"
    echo "請先執行 ./scripts/install-fastapi.sh 進行安裝"
    exit 1
fi

echo "✅ 所有依賴檢查通過"

echo
echo "[4/4] 啟動 FastAPI 應用程式..."
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
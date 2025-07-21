#!/bin/bash

echo "========================================"
echo "Whisper 語音轉文字工具 - FastAPI 版本安裝程式"
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

# 檢查 Python 版本
echo "[1/8] 檢查 Python 版本..."
PYTHON_VERSION=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
MIN_VERSION="3.8"

if [ "$(printf '%s\n' "$MIN_VERSION" "$PYTHON_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]; then
    echo "[錯誤] Python 版本 $PYTHON_VERSION 過低，需要 3.8 或更高版本"
    exit 1
fi

echo "✅ Python 版本: $PYTHON_VERSION"

# 檢查 ffmpeg 是否已安裝
echo "[2/8] 檢查 ffmpeg..."
if ! command -v ffmpeg &> /dev/null; then
    echo "[警告] 未偵測到 ffmpeg！"
    echo "Whisper 需要 ffmpeg 來處理音頻檔案"
    echo ""
    echo "嘗試自動安裝 ffmpeg..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            echo "使用 Homebrew 安裝 ffmpeg..."
            brew install ffmpeg
        else
            echo "[錯誤] 請先安裝 Homebrew 或手動安裝 ffmpeg"
            echo "安裝 Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
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

# 備份原始檔案（如果需要）
echo "[3/8] 備份原始檔案..."
if [ -f "whisper_app.py" ]; then
    if [ ! -f "whisper_app_streamlit_backup.py" ]; then
        cp whisper_app.py whisper_app_streamlit_backup.py
        echo "✅ 已備份原始 Streamlit 應用為 whisper_app_streamlit_backup.py"
    fi
fi

# 創建專案結構
echo "[4/8] 創建 FastAPI 專案結構..."
mkdir -p backend/{models,api,utils,config}
mkdir -p frontend/{css,js,assets}
mkdir -p uploads results logs

echo "✅ 目錄結構已創建"

# 建立虛擬環境
echo "[5/8] 建立虛擬環境..."
if [ -d "venv" ]; then
    echo "虛擬環境已存在，跳過創建"
else
    python3 -m venv venv
fi

echo "[6/8] 啟動虛擬環境..."
source venv/bin/activate

# 升級 pip
echo "升級 pip..."
python -m pip install --upgrade pip

# 創建 FastAPI requirements.txt
echo "[7/8] 創建 FastAPI 依賴清單..."
cat > backend/requirements.txt << 'EOF'
fastapi>=0.104.0
uvicorn[standard]>=0.24.0
aiofiles>=23.0.0
python-multipart>=0.0.6
openai-whisper
torch>=2.0.0
torchaudio>=2.0.0
numba>=0.59.0
numpy>=1.26.0
transformers>=4.19.0
ffmpeg-python==0.2.0
python-dotenv>=1.0.0
EOF

# 安裝 FastAPI 依賴
echo "安裝 FastAPI 依賴..."
pip install -r backend/requirements.txt

# 創建 FastAPI 應用檔案
echo "[8/8] 創建 FastAPI 應用檔案..."

# 創建主應用
cat > backend/app.py << 'EOF'
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import os
import uuid
import logging
from models.whisper_service import WhisperService
from utils.file_handler import FileHandler

# 設置日誌
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Whisper 語音轉文字 API",
    description="使用 OpenAI Whisper 進行語音轉文字的 API 服務",
    version="1.0.0"
)

# CORS 設定
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 靜態檔案服務 (前端)
app.mount("/", StaticFiles(directory="../frontend", html=True), name="frontend")

# 服務實例
whisper_service = WhisperService()
file_handler = FileHandler()

# Pydantic 模型
class TranscribeRequest(BaseModel):
    file_id: str
    model_size: str = "base"
    language: str = "auto"
    include_timestamps: bool = False

class HealthResponse(BaseModel):
    status: str
    service: str

class ModelInfo(BaseModel):
    id: str
    name: str
    size: str

class ModelsResponse(BaseModel):
    models: list[ModelInfo]

class UploadResponse(BaseModel):
    file_id: str
    filename: str
    size: int
    estimated_time: float

class TranscribeResponse(BaseModel):
    success: bool
    result: dict
    processing_time: float
    word_count: int
    char_count: int

@app.get("/api/health", response_model=HealthResponse)
async def health_check():
    """健康檢查端點"""
    return HealthResponse(status="healthy", service="whisper-transcriber")

@app.get("/api/models", response_model=ModelsResponse)
async def get_available_models():
    """獲取可用的 Whisper 模型列表"""
    models = [
        ModelInfo(id="tiny", name="Tiny - 最快速", size="39 MB"),
        ModelInfo(id="base", name="Base - 平衡（推薦）", size="74 MB"),
        ModelInfo(id="small", name="Small - 較準確", size="244 MB"),
        ModelInfo(id="medium", name="Medium - 很準確", size="769 MB"),
        ModelInfo(id="large", name="Large - 最準確", size="1550 MB")
    ]
    return ModelsResponse(models=models)

@app.post("/api/upload", response_model=UploadResponse)
async def upload_file(file: UploadFile = File(...)):
    """上傳音頻檔案"""
    
    # 檢查檔案類型
    allowed_extensions = {'.mp3', '.wav', '.m4a', '.flac', '.mp4', '.avi', '.mov', '.mkv', '.webm'}
    file_extension = os.path.splitext(file.filename)[1].lower()
    
    if file_extension not in allowed_extensions:
        raise HTTPException(
            status_code=400, 
            detail=f"不支援的檔案格式: {file_extension}. 支援格式: {', '.join(allowed_extensions)}"
        )
    
    # 檢查檔案大小 (限制 500MB)
    file_content = await file.read()
    if len(file_content) > 500 * 1024 * 1024:  # 500MB
        raise HTTPException(status_code=400, detail="檔案大小超過 500MB 限制")
    
    try:
        # 儲存檔案並返回檔案 ID
        file_id = await file_handler.save_upload(file, file_content)
        file_info = await file_handler.get_file_info(file_id)
        
        return UploadResponse(
            file_id=file_id,
            filename=file_info["filename"],
            size=file_info["size"],
            estimated_time=file_info["estimated_processing_time"]
        )
        
    except Exception as e:
        logger.error(f"檔案上傳失敗: {e}")
        raise HTTPException(status_code=500, detail=f"檔案上傳失敗: {str(e)}")

@app.post("/api/transcribe", response_model=TranscribeResponse)
async def transcribe_audio(request: TranscribeRequest):
    """執行語音轉文字"""
    
    # 驗證檔案是否存在
    if not await file_handler.file_exists(request.file_id):
        raise HTTPException(status_code=404, detail="檔案不存在")
    
    # 驗證模型大小
    valid_models = {"tiny", "base", "small", "medium", "large"}
    if request.model_size not in valid_models:
        raise HTTPException(status_code=400, detail=f"無效的模型大小: {request.model_size}")
    
    # 驗證語言代碼
    valid_languages = {"auto", "zh", "en", "ja", "ko"}
    if request.language not in valid_languages:
        raise HTTPException(status_code=400, detail=f"無效的語言代碼: {request.language}")
    
    try:
        result = await whisper_service.transcribe(
            file_id=request.file_id,
            model_size=request.model_size,
            language=request.language,
            include_timestamps=request.include_timestamps
        )
        
        return TranscribeResponse(
            success=True,
            result=result,
            processing_time=result["processing_time"],
            word_count=len(result["text"].split()),
            char_count=len(result["text"])
        )
        
    except Exception as e:
        logger.error(f"轉換失敗: {e}")
        raise HTTPException(status_code=500, detail=f"轉換失敗: {str(e)}")

@app.get("/api/download/{file_id}")
async def download_result(file_id: str):
    """下載轉換結果檔案"""
    
    try:
        file_path = await file_handler.get_result_file(file_id)
        
        if not os.path.exists(file_path):
            raise HTTPException(status_code=404, detail="結果檔案不存在")
        
        return FileResponse(
            path=file_path,
            filename=f"transcript_{file_id}.txt",
            media_type="text/plain"
        )
        
    except Exception as e:
        logger.error(f"下載失敗: {e}")
        raise HTTPException(status_code=500, detail=f"下載失敗: {str(e)}")

@app.on_event("startup")
async def startup_event():
    """應用啟動時的初始化"""
    logger.info("Whisper 語音轉文字服務啟動中...")
    # 預載入 base 模型（可選）
    try:
        logger.info("預載入 base 模型...")
        await whisper_service.load_model("base")
        logger.info("✅ Base 模型預載入完成")
    except Exception as e:
        logger.warning(f"模型預載入失敗: {e}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        log_level="info"
    )
EOF

# 創建 Whisper 服務
cat > backend/models/__init__.py << 'EOF'
# Models package
EOF

cat > backend/models/whisper_service.py << 'EOF'
import whisper
import asyncio
import time
import os
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import logging

logger = logging.getLogger(__name__)

class WhisperService:
    def __init__(self):
        self.loaded_models = {}
        self.executor = ThreadPoolExecutor(max_workers=2)
    
    async def load_model(self, model_size: str):
        """異步載入 Whisper 模型"""
        if model_size not in self.loaded_models:
            logger.info(f"載入 {model_size} 模型...")
            
            loop = asyncio.get_event_loop()
            model = await loop.run_in_executor(
                self.executor, 
                whisper.load_model, 
                model_size
            )
            
            self.loaded_models[model_size] = model
            logger.info(f"{model_size} 模型載入完成")
        
        return self.loaded_models[model_size]
    
    async def transcribe(self, file_id: str, model_size: str, language: str, include_timestamps: bool):
        """異步執行語音轉文字"""
        
        model = await self.load_model(model_size)
        file_path = self._get_file_path(file_id)
        
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"檔案不存在: {file_path}")
        
        logger.info(f"開始轉換檔案: {file_id}, 模型: {model_size}, 語言: {language}")
        
        start_time = time.time()
        
        language_param = None if language == "auto" else language
        transcribe_options = {
            "language": language_param,
            "task": "transcribe",
            "fp16": False,
        }
        
        loop = asyncio.get_event_loop()
        result = await loop.run_in_executor(
            self.executor,
            lambda: model.transcribe(file_path, **transcribe_options)
        )
        
        processing_time = time.time() - start_time
        logger.info(f"轉換完成，耗時: {processing_time:.2f}秒")
        
        formatted_result = {
            "text": result["text"].strip(),
            "processing_time": processing_time,
            "language": result.get("language", "unknown")
        }
        
        if include_timestamps and 'segments' in result:
            formatted_result["segments"] = [
                {
                    "start": self._format_timestamp(segment["start"]),
                    "end": self._format_timestamp(segment["end"]),
                    "text": segment["text"].strip()
                }
                for segment in result["segments"]
                if segment["text"].strip()
            ]
        
        return formatted_result
    
    def _format_timestamp(self, seconds: float) -> str:
        """格式化時間戳記為 MM:SS 格式"""
        minutes = int(seconds // 60)
        seconds = int(seconds % 60)
        return f"{minutes:02d}:{seconds:02d}"
    
    def _get_file_path(self, file_id: str) -> str:
        """獲取檔案路徑"""
        upload_dir = os.getenv("UPLOAD_DIR", "../uploads")
        return os.path.join(upload_dir, file_id)
    
    def __del__(self):
        """清理資源"""
        if hasattr(self, 'executor'):
            self.executor.shutdown(wait=True)
EOF

# 創建檔案處理工具
cat > backend/utils/__init__.py << 'EOF'
# Utils package
EOF

cat > backend/utils/file_handler.py << 'EOF'
import os
import uuid
import aiofiles
from pathlib import Path
from typing import Optional, Dict
import logging
from fastapi import UploadFile

logger = logging.getLogger(__name__)

class FileHandler:
    def __init__(self):
        self.upload_dir = os.getenv("UPLOAD_DIR", "../uploads")
        self.result_dir = os.getenv("RESULT_DIR", "../results")
        self.max_file_size = int(os.getenv("MAX_FILE_SIZE", 500 * 1024 * 1024))
        
        os.makedirs(self.upload_dir, exist_ok=True)
        os.makedirs(self.result_dir, exist_ok=True)
    
    async def save_upload(self, file: UploadFile, file_content: bytes) -> str:
        """保存上傳的檔案"""
        
        file_id = str(uuid.uuid4())
        file_extension = Path(file.filename).suffix
        stored_filename = f"{file_id}{file_extension}"
        file_path = os.path.join(self.upload_dir, stored_filename)
        
        async with aiofiles.open(file_path, 'wb') as f:
            await f.write(file_content)
        
        metadata = {
            "original_filename": file.filename,
            "stored_filename": stored_filename,
            "file_size": len(file_content),
            "file_extension": file_extension,
        }
        
        await self._save_metadata(file_id, metadata)
        
        logger.info(f"檔案已保存: {file.filename} -> {file_id}")
        return file_id
    
    async def get_file_info(self, file_id: str) -> Dict:
        """獲取檔案資訊"""
        metadata = await self._load_metadata(file_id)
        
        if not metadata:
            raise FileNotFoundError(f"檔案不存在: {file_id}")
        
        file_size_mb = metadata["file_size"] / (1024 * 1024)
        estimated_time = max(0.5, file_size_mb / 10)
        
        return {
            "filename": metadata["original_filename"],
            "size": metadata["file_size"],
            "estimated_processing_time": round(estimated_time, 1)
        }
    
    async def file_exists(self, file_id: str) -> bool:
        """檢查檔案是否存在"""
        metadata = await self._load_metadata(file_id)
        if not metadata:
            return False
        
        file_path = os.path.join(self.upload_dir, metadata["stored_filename"])
        return os.path.exists(file_path)
    
    async def get_result_file(self, file_id: str) -> str:
        """獲取結果檔案路徑"""
        result_filename = f"{file_id}_text.txt"
        result_path = os.path.join(self.result_dir, result_filename)
        
        if not os.path.exists(result_path):
            raise FileNotFoundError(f"結果檔案不存在: {result_filename}")
        
        return result_path
    
    async def _save_metadata(self, file_id: str, metadata: Dict):
        """保存檔案元資料"""
        import json
        
        metadata_path = os.path.join(self.upload_dir, f"{file_id}_metadata.json")
        async with aiofiles.open(metadata_path, 'w', encoding='utf-8') as f:
            await f.write(json.dumps(metadata, ensure_ascii=False, indent=2))
    
    async def _load_metadata(self, file_id: str) -> Optional[Dict]:
        """載入檔案元資料"""
        import json
        
        metadata_path = os.path.join(self.upload_dir, f"{file_id}_metadata.json")
        
        try:
            async with aiofiles.open(metadata_path, 'r', encoding='utf-8') as f:
                content = await f.read()
                return json.loads(content)
        except (FileNotFoundError, json.JSONDecodeError):
            return None
EOF

# 創建前端檔案
echo "創建前端檔案..."

# 從轉換文件複製前端程式碼（這裡創建一個簡化版本）
cat > frontend/index.html << 'EOF'
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🎤 語音轉文字工具 - FastAPI 版本</title>
    <link rel="stylesheet" href="css/main.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🎤</text></svg>">
</head>
<body>
    <div class="container">
        <header class="header">
            <h1>🎤 語音轉文字工具</h1>
            <p class="subtitle">FastAPI 版本 - 使用 OpenAI Whisper 技術，精準轉換您的音頻內容</p>
        </header>

        <main class="main-content">
            <!-- 檔案上傳區 -->
            <section class="upload-section">
                <h2>📁 選擇檔案</h2>
                <div class="upload-area" id="uploadArea">
                    <div class="upload-icon">📁</div>
                    <p>點擊選擇或拖拉檔案到這裡</p>
                    <input type="file" id="fileInput" accept=".mp3,.wav,.m4a,.flac,.mp4,.avi,.mov,.mkv,.webm" hidden>
                    <small>支援 MP3, WAV, M4A, FLAC, MP4, AVI, MOV, MKV 等格式</small>
                </div>
                
                <div class="file-info" id="fileInfo" style="display: none;">
                    <div class="info-item">
                        <strong>檔案名稱:</strong> <span id="fileName"></span>
                    </div>
                    <div class="info-item">
                        <strong>檔案大小:</strong> <span id="fileSize"></span>
                    </div>
                    <div class="info-item">
                        <strong>預估處理時間:</strong> <span id="estimatedTime"></span>
                    </div>
                </div>
            </section>

            <!-- 設定選項 -->
            <section class="settings-section" id="settingsSection" style="display: none;">
                <h2>⚙️ 轉換設定</h2>
                <div class="settings-grid">
                    <div class="setting-item">
                        <label for="modelSelect">選擇 AI 模型</label>
                        <select id="modelSelect">
                            <option value="tiny">Tiny - 最快速</option>
                            <option value="base" selected>Base - 平衡（推薦）</option>
                            <option value="small">Small - 較準確</option>
                            <option value="medium">Medium - 很準確</option>
                            <option value="large">Large - 最準確</option>
                        </select>
                    </div>
                    
                    <div class="setting-item">
                        <label for="languageSelect">選擇語言</label>
                        <select id="languageSelect">
                            <option value="auto">自動偵測</option>
                            <option value="zh">中文</option>
                            <option value="en">英文</option>
                            <option value="ja">日文</option>
                            <option value="ko">韓文</option>
                        </select>
                    </div>
                    
                    <div class="setting-item">
                        <label>
                            <input type="checkbox" id="timestampCheck"> 包含時間戳記
                        </label>
                    </div>
                </div>
                
                <button class="transcribe-btn" id="transcribeBtn">🚀 開始轉換</button>
            </section>

            <!-- 進度區域 -->
            <section class="progress-section" id="progressSection" style="display: none;">
                <h2>🔄 處理進度</h2>
                <div class="progress-container">
                    <div class="progress-bar">
                        <div class="progress-fill" id="progressFill"></div>
                    </div>
                    <div class="progress-text" id="progressText">準備中...</div>
                </div>
            </section>

            <!-- 結果區域 -->
            <section class="results-section" id="resultsSection" style="display: none;">
                <h2>📝 轉換結果</h2>
                
                <!-- 統計資料 -->
                <div class="stats-grid">
                    <div class="stat-item">
                        <div class="stat-number" id="wordCount">0</div>
                        <div class="stat-label">字數</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-number" id="charCount">0</div>
                        <div class="stat-label">字元數</div>
                    </div>
                    <div class="stat-item">
                        <div class="stat-number" id="processingTime">0s</div>
                        <div class="stat-label">處理時間</div>
                    </div>
                </div>

                <!-- 轉換內容 -->
                <div class="result-content">
                    <textarea id="resultText" rows="10" readonly placeholder="轉換結果將在這裡顯示..."></textarea>
                    <button class="download-btn" id="downloadTextBtn">📥 下載文字檔</button>
                </div>
            </section>
        </main>

        <!-- 說明區域 -->
        <footer class="info-section">
            <details>
                <summary>ℹ️ 關於此工具 (FastAPI 版本)</summary>
                <div class="info-content">
                    <p>此工具使用 FastAPI + OpenAI Whisper 進行語音轉文字。</p>
                    
                    <h4>FastAPI 版本特點：</h4>
                    <ul>
                        <li>異步處理，更高效能</li>
                        <li>自動 API 文檔生成</li>
                        <li>前後端分離架構</li>
                        <li>支援 RESTful API</li>
                    </ul>
                    
                    <h4>功能特點：</h4>
                    <ul>
                        <li>支援多種音頻和視頻格式</li>
                        <li>提供多種模型選擇</li>
                        <li>支援多語言識別</li>
                        <li>可選時間戳記輸出</li>
                    </ul>
                    
                    <h4>API 文檔：</h4>
                    <ul>
                        <li><a href="/docs" target="_blank">Swagger UI - 互動式 API 文檔</a></li>
                        <li><a href="/redoc" target="_blank">ReDoc - 美觀的 API 文檔</a></li>
                    </ul>
                </div>
            </details>
        </footer>
    </div>

    <script src="js/app.js"></script>
</body>
</html>
EOF

# 創建簡化的 CSS
cat > frontend/css/main.css << 'EOF'
/* 基礎設置 */
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', sans-serif;
    line-height: 1.6;
    color: #262730;
    background-color: #f8f9fa;
}

.container {
    max-width: 1000px;
    margin: 0 auto;
    padding: 20px;
}

/* 標題區域 */
.header {
    text-align: center;
    margin-bottom: 30px;
}

.header h1 {
    font-size: 2.5rem;
    color: #1f1f23;
    margin-bottom: 10px;
}

.subtitle {
    font-size: 1.1rem;
    color: #6c757d;
    margin-bottom: 20px;
}

/* 區塊樣式 */
section {
    background: white;
    border-radius: 10px;
    padding: 20px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    margin-bottom: 20px;
}

section h2 {
    font-size: 1.3rem;
    margin-bottom: 15px;
    color: #1f1f23;
}

/* 檔案上傳區域 */
.upload-area {
    border: 2px dashed #dee2e6;
    border-radius: 8px;
    padding: 40px 20px;
    text-align: center;
    transition: all 0.3s ease;
    cursor: pointer;
}

.upload-area:hover {
    border-color: #007bff;
    background-color: #f8f9ff;
}

.upload-icon {
    font-size: 3rem;
    margin-bottom: 10px;
}

.upload-area p {
    font-size: 1.1rem;
    margin-bottom: 10px;
    color: #495057;
}

.upload-area small {
    color: #6c757d;
}

/* 檔案資訊 */
.file-info {
    background: #f8f9fa;
    border-radius: 8px;
    padding: 15px;
    margin-top: 15px;
}

.info-item {
    margin-bottom: 8px;
}

/* 設定區域 */
.settings-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 15px;
    margin-bottom: 20px;
}

.setting-item label {
    display: block;
    margin-bottom: 5px;
    font-weight: 500;
}

.setting-item select,
.setting-item input {
    width: 100%;
    padding: 8px 12px;
    border: 1px solid #dee2e6;
    border-radius: 5px;
    font-size: 0.9rem;
}

.setting-item input[type="checkbox"] {
    width: auto;
    margin-right: 8px;
}

/* 按鈕樣式 */
.transcribe-btn {
    width: 100%;
    padding: 12px 24px;
    background: linear-gradient(135deg, #007bff, #0056b3);
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 1.1rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s ease;
}

.transcribe-btn:hover {
    background: linear-gradient(135deg, #0056b3, #004085);
    transform: translateY(-2px);
}

.transcribe-btn:disabled {
    background: #6c757d;
    cursor: not-allowed;
    transform: none;
}

.download-btn {
    padding: 8px 16px;
    background: #28a745;
    color: white;
    border: none;
    border-radius: 5px;
    font-size: 0.9rem;
    cursor: pointer;
    margin-top: 10px;
}

.download-btn:hover {
    background: #218838;
}

/* 進度條 */
.progress-container {
    margin: 20px 0;
}

.progress-bar {
    width: 100%;
    height: 10px;
    background: #e9ecef;
    border-radius: 5px;
    overflow: hidden;
}

.progress-fill {
    height: 100%;
    background: linear-gradient(90deg, #007bff, #28a745);
    border-radius: 5px;
    transition: width 0.3s ease;
    width: 0%;
}

.progress-text {
    text-align: center;
    margin-top: 10px;
    font-weight: 500;
}

/* 統計區域 */
.stats-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 15px;
    margin-bottom: 20px;
}

.stat-item {
    text-align: center;
    padding: 15px;
    background: #f8f9fa;
    border-radius: 8px;
}

.stat-number {
    font-size: 1.5rem;
    font-weight: bold;
    color: #007bff;
}

.stat-label {
    font-size: 0.9rem;
    color: #6c757d;
    margin-top: 5px;
}

/* 結果文字區域 */
#resultText {
    width: 100%;
    border: 1px solid #dee2e6;
    border-radius: 5px;
    padding: 15px;
    font-family: monospace;
    resize: vertical;
}

/* 說明區域 */
.info-section {
    margin-top: 30px;
}

.info-section details {
    background: white;
    border-radius: 10px;
    padding: 15px;
    box-shadow: 0 2px 5px rgba(0,0,0,0.1);
}

.info-section summary {
    cursor: pointer;
    font-weight: 600;
    margin-bottom: 10px;
}

.info-content h4 {
    margin: 15px 0 8px 0;
    color: #495057;
}

.info-content ul {
    margin-left: 20px;
}

.info-content li {
    margin-bottom: 5px;
}

.info-content a {
    color: #007bff;
    text-decoration: none;
}

.info-content a:hover {
    text-decoration: underline;
}

/* 響應式設計 */
@media (max-width: 768px) {
    .container {
        padding: 10px;
    }
    
    .header h1 {
        font-size: 2rem;
    }
    
    .settings-grid {
        grid-template-columns: 1fr;
    }
    
    .stats-grid {
        grid-template-columns: 1fr;
    }
}
EOF

# 創建簡化的 JavaScript
cat > frontend/js/app.js << 'EOF'
class WhisperApp {
    constructor() {
        this.apiBase = '/api';  // 使用相對路徑
        this.currentFileId = null;
        
        this.initializeElements();
        this.bindEvents();
        this.loadInitialData();
    }
    
    initializeElements() {
        this.elements = {
            uploadArea: document.getElementById('uploadArea'),
            fileInput: document.getElementById('fileInput'),
            fileInfo: document.getElementById('fileInfo'),
            fileName: document.getElementById('fileName'),
            fileSize: document.getElementById('fileSize'),
            estimatedTime: document.getElementById('estimatedTime'),
            settingsSection: document.getElementById('settingsSection'),
            transcribeBtn: document.getElementById('transcribeBtn'),
            progressSection: document.getElementById('progressSection'),
            progressFill: document.getElementById('progressFill'),
            progressText: document.getElementById('progressText'),
            resultsSection: document.getElementById('resultsSection'),
            resultText: document.getElementById('resultText'),
            downloadTextBtn: document.getElementById('downloadTextBtn'),
            wordCount: document.getElementById('wordCount'),
            charCount: document.getElementById('charCount'),
            processingTime: document.getElementById('processingTime')
        };
    }
    
    bindEvents() {
        // 檔案上傳事件
        this.elements.uploadArea.addEventListener('click', () => {
            this.elements.fileInput.click();
        });
        
        this.elements.fileInput.addEventListener('change', (e) => {
            this.handleFileSelect(e.target.files[0]);
        });
        
        // 拖拉上傳
        this.elements.uploadArea.addEventListener('dragover', (e) => {
            e.preventDefault();
            this.elements.uploadArea.style.borderColor = '#007bff';
        });
        
        this.elements.uploadArea.addEventListener('dragleave', () => {
            this.elements.uploadArea.style.borderColor = '#dee2e6';
        });
        
        this.elements.uploadArea.addEventListener('drop', (e) => {
            e.preventDefault();
            this.elements.uploadArea.style.borderColor = '#dee2e6';
            this.handleFileSelect(e.dataTransfer.files[0]);
        });
        
        // 轉換按鈕
        this.elements.transcribeBtn.addEventListener('click', () => {
            this.startTranscription();
        });
        
        // 下載按鈕
        this.elements.downloadTextBtn.addEventListener('click', () => {
            this.downloadResult();
        });
    }
    
    async loadInitialData() {
        try {
            const response = await fetch(`${this.apiBase}/models`);
            const data = await response.json();
            this.updateModelOptions(data.models);
        } catch (error) {
            console.error('Failed to load models:', error);
        }
    }
    
    updateModelOptions(models) {
        const select = document.getElementById('modelSelect');
        select.innerHTML = '';
        
        models.forEach(model => {
            const option = document.createElement('option');
            option.value = model.id;
            option.textContent = model.name;
            if (model.id === 'base') option.selected = true;
            select.appendChild(option);
        });
    }
    
    async handleFileSelect(file) {
        if (!file) return;
        
        // 顯示檔案資訊
        this.elements.fileName.textContent = file.name;
        this.elements.fileSize.textContent = `${(file.size / 1024 / 1024).toFixed(1)} MB`;
        this.elements.estimatedTime.textContent = `${Math.max(0.5, file.size / 1024 / 1024 / 10).toFixed(1)} 分鐘`;
        
        this.elements.fileInfo.style.display = 'block';
        this.elements.settingsSection.style.display = 'block';
        
        // 上傳檔案
        try {
            this.elements.transcribeBtn.disabled = true;
            this.elements.transcribeBtn.textContent = '上傳中...';
            
            const formData = new FormData();
            formData.append('file', file);
            
            const response = await fetch(`${this.apiBase}/upload`, {
                method: 'POST',
                body: formData
            });
            
            const data = await response.json();
            
            if (response.ok) {
                this.currentFileId = data.file_id;
                this.elements.transcribeBtn.disabled = false;
                this.elements.transcribeBtn.textContent = '🚀 開始轉換';
            } else {
                throw new Error(data.detail);
            }
        } catch (error) {
            alert(`上傳失敗: ${error.message}`);
            this.elements.transcribeBtn.disabled = false;
            this.elements.transcribeBtn.textContent = '🚀 開始轉換';
        }
    }
    
    async startTranscription() {
        if (!this.currentFileId) return;
        
        const modelSize = document.getElementById('modelSelect').value;
        const language = document.getElementById('languageSelect').value;
        const includeTimestamps = document.getElementById('timestampCheck').checked;
        
        try {
            // 顯示進度
            this.elements.progressSection.style.display = 'block';
            this.elements.transcribeBtn.disabled = true;
            this.updateProgress(10, '正在載入模型...');
            
            this.updateProgress(30, '正在處理音頻...');
            
            // 開始轉換
            const response = await fetch(`${this.apiBase}/transcribe`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    file_id: this.currentFileId,
                    model_size: modelSize,
                    language: language,
                    include_timestamps: includeTimestamps
                })
            });
            
            const data = await response.json();
            
            if (response.ok) {
                this.updateProgress(100, '轉換完成！');
                this.displayResults(data.result);
                
                // 更新統計
                this.elements.wordCount.textContent = data.word_count;
                this.elements.charCount.textContent = data.char_count;
                this.elements.processingTime.textContent = `${data.processing_time.toFixed(1)}s`;
            } else {
                throw new Error(data.detail);
            }
        } catch (error) {
            alert(`轉換失敗: ${error.message}`);
        } finally {
            this.elements.transcribeBtn.disabled = false;
            setTimeout(() => {
                this.elements.progressSection.style.display = 'none';
            }, 2000);
        }
    }
    
    updateProgress(percentage, text) {
        this.elements.progressFill.style.width = `${percentage}%`;
        this.elements.progressText.textContent = text;
    }
    
    displayResults(result) {
        this.elements.resultText.value = result.text;
        this.elements.resultsSection.style.display = 'block';
        this.currentResult = result;
    }
    
    downloadResult() {
        if (!this.currentResult) return;
        
        const content = this.currentResult.text;
        const blob = new Blob([content], { type: 'text/plain' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'transcript.txt';
        a.click();
        URL.revokeObjectURL(url);
    }
}

// 啟動應用
document.addEventListener('DOMContentLoaded', () => {
    new WhisperApp();
});
EOF

echo ""
echo "========================================"
echo "FastAPI 版本安裝完成！"
echo "========================================"
echo ""
echo "專案結構："
echo "├── backend/          # FastAPI 後端"
echo "├── frontend/         # HTML/CSS/JS 前端"
echo "├── uploads/          # 上傳檔案目錄"
echo "├── results/          # 結果檔案目錄"
echo "├── logs/             # 日誌目錄"
echo "└── venv/             # Python 虛擬環境"
echo ""
echo "下一步："
echo "1. 執行 './scripts/start-fastapi.sh' 啟動 FastAPI 應用"
echo "2. 瀏覽器訪問 http://localhost:8000"
echo "3. 查看 API 文檔: http://localhost:8000/docs"
echo ""
echo "備註："
echo "- 原始 Streamlit 版本已備份為 whisper_app_streamlit_backup.py"
echo "- 原始腳本 (install.sh, start.sh) 仍可用於 Streamlit 版本"
echo "- FastAPI 版本使用新的腳本 (install-fastapi.sh, start-fastapi.sh)"
echo "========================================"
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import os
import uuid
import logging
from .models.whisper_service import WhisperService
from .utils.file_handler import FileHandler

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

@app.post("/api/transcribe")
async def transcribe_audio(request: TranscribeRequest):
    """啟動語音轉文字處理（異步）"""
    
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
        # 啟動背景任務
        import asyncio
        asyncio.create_task(whisper_service.transcribe(
            file_id=request.file_id,
            model_size=request.model_size,
            language=request.language,
            include_timestamps=request.include_timestamps
        ))
        
        # 立即返回成功響應
        return JSONResponse(content={
            "success": True,
            "message": "轉換已開始",
            "file_id": request.file_id
        })
        
    except Exception as e:
        logger.error(f"啟動轉換失敗: {e}")
        raise HTTPException(status_code=500, detail=f"啟動轉換失敗: {str(e)}")

@app.get("/api/status/{file_id}")
async def get_processing_status(file_id: str):
    """獲取處理狀態（用於輪詢）"""
    
    try:
        status = await file_handler.get_processing_status(file_id)
        return JSONResponse(content=status)
        
    except Exception as e:
        logger.error(f"獲取狀態失敗: {e}")
        raise HTTPException(status_code=500, detail=f"獲取狀態失敗: {str(e)}")

@app.get("/api/result/{file_id}")
async def get_result(file_id: str):
    """獲取轉換結果內容"""
    
    try:
        # 檢查狀態
        status = await file_handler.get_processing_status(file_id)
        
        if status["status"] != "completed":
            raise HTTPException(status_code=400, detail="轉換尚未完成")
        
        # 嘗試讀取結果檔案
        result_path = os.path.join(file_handler.result_dir, f"{file_id}_text.txt")
        if os.path.exists(result_path):
            with open(result_path, 'r', encoding='utf-8') as f:
                text_content = f.read()
                
            return JSONResponse(content={
                "result": {
                    "text": text_content,
                    "processing_time": status.get("processing_time", 0)
                },
                "word_count": len([c for c in text_content if c.strip() and not c.isspace()]),
                "char_count": len(text_content),
                "processing_time": status.get("processing_time", 0)
            })
        else:
            raise HTTPException(status_code=404, detail="結果檔案不存在")
        
    except Exception as e:
        logger.error(f"獲取結果失敗: {e}")
        raise HTTPException(status_code=500, detail=f"獲取結果失敗: {str(e)}")

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

# 靜態檔案服務 (前端) - 必須放在所有 API 路由之後
# 使用絕對路徑來避免路徑問題
import os
frontend_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "frontend")
app.mount("/", StaticFiles(directory=frontend_path, html=True), name="frontend")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        log_level="info"
    )

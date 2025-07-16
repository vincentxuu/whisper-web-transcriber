import streamlit as st
import whisper
import tempfile
import os
import time
from pathlib import Path
import traceback

# 設定頁面配置
st.set_page_config(
    page_title="語音轉文字工具",
    page_icon="🎤",
    layout="wide"
)

# ===== 所有函數定義 =====

@st.cache_resource
def load_whisper_model(model_size):
    """載入並快取 Whisper 模型"""
    try:
        model = whisper.load_model(model_size)
        return model
    except Exception as e:
        st.error(f"模型載入失敗: {str(e)}")
        if "Connection" in str(e) or "URLError" in str(e):
            st.warning("網路連線問題，請檢查網路後重試")
        return None

def estimate_processing_time(file_size_mb):
    """估算處理時間（分鐘）"""
    # 簡單估算：每 10MB 約 1 分鐘
    return max(0.5, file_size_mb / 10)

def format_time(seconds):
    """格式化時間"""
    if seconds < 60:
        return f"{int(seconds)}秒"
    else:
        minutes = int(seconds / 60)
        seconds = int(seconds % 60)
        return f"{minutes}分{seconds}秒"

def format_timestamp(seconds):
    """格式化時間戳記為 MM:SS"""
    minutes = int(seconds // 60)
    seconds = int(seconds % 60)
    return f"{minutes:02d}:{seconds:02d}"

def process_audio(uploaded_file, model_size, language, include_timestamps):
    """處理音頻檔案"""
    # 顯示進度
    progress_bar = st.progress(0)
    status_text = st.empty()
    
    try:
        # 步驟1: 儲存檔案
        status_text.text("正在儲存檔案...")
        progress_bar.progress(10)
        
        with tempfile.NamedTemporaryFile(delete=False, suffix=Path(uploaded_file.name).suffix) as tmp_file:
            tmp_file.write(uploaded_file.getvalue())
            tmp_file_path = tmp_file.name
        
        # 步驟2: 載入模型
        status_text.text(f"正在載入 {model_size} 模型...")
        progress_bar.progress(30)
        
        # 檢查是否需要重新載入模型
        if (st.session_state.loaded_model is None or 
            st.session_state.loaded_model_size != model_size):
            
            with st.spinner(f"首次載入 {model_size} 模型，請稍候..."):
                model = load_whisper_model(model_size)
                
            if model is not None:
                st.session_state.loaded_model = model
                st.session_state.loaded_model_size = model_size
                st.session_state.model_loaded = True
            else:
                st.error("模型載入失敗")
                return
        else:
            model = st.session_state.loaded_model
        
        # 步驟3: 轉換音頻
        status_text.text("正在進行語音識別...")
        progress_bar.progress(60)
        
        start_time = time.time()
        
        # 執行轉換
        language_param = None if language == "auto" else language
        result = model.transcribe(tmp_file_path, language=language_param)
        
        # 步驟4: 完成
        processing_time = time.time() - start_time
        progress_bar.progress(100)
        status_text.text(f"轉換完成！耗時 {format_time(processing_time)}")
        
        # 更新統計
        st.session_state.processing_count += 1
        
        # 清理暫存檔案
        os.remove(tmp_file_path)
        
        # 顯示結果
        st.success("✅ 轉換成功完成！")
        
        # 結果區域
        st.header("📝 轉換結果")
        
        # 顯示統計
        col_stat1, col_stat2, col_stat3 = st.columns(3)
        with col_stat1:
            st.metric("字數", len(result['text'].split()))
        with col_stat2:
            st.metric("字元數", len(result['text']))
        with col_stat3:
            st.metric("處理時間", format_time(processing_time))
        
        # 顯示轉換內容
        if include_timestamps and 'segments' in result:
            # 時間戳記模式
            st.subheader("含時間戳記的內容")
            
            timestamp_text = ""
            for segment in result['segments']:
                start_time = format_timestamp(segment['start'])
                end_time = format_timestamp(segment['end'])
                text_line = f"[{start_time} - {end_time}] {segment['text']}\n"
                timestamp_text += text_line
                st.text(text_line.strip())
            
            # 下載按鈕
            st.download_button(
                label="📥 下載時間戳記文字檔",
                data=timestamp_text,
                file_name=f"{Path(uploaded_file.name).stem}_timestamps.txt",
                mime="text/plain"
            )
        else:
            # 純文字模式
            st.subheader("轉換內容")
            st.text_area(
                "轉換結果",
                result['text'],
                height=300
            )
            
            # 下載按鈕
            st.download_button(
                label="📥 下載文字檔",
                data=result['text'],
                file_name=f"{Path(uploaded_file.name).stem}_transcript.txt",
                mime="text/plain"
            )
        
    except Exception as e:
        progress_bar.empty()
        status_text.empty()
        st.error(f"處理時發生錯誤: {str(e)}")
        
        # 顯示詳細錯誤
        with st.expander("查看詳細錯誤"):
            st.code(traceback.format_exc())
        
        # 清理暫存檔案
        if 'tmp_file_path' in locals() and os.path.exists(tmp_file_path):
            os.remove(tmp_file_path)

# ===== 主程式 UI =====

# 初始化 session state
if 'model_loaded' not in st.session_state:
    st.session_state.model_loaded = False
    st.session_state.loaded_model_size = None
    st.session_state.loaded_model = None
    st.session_state.processing_count = 0

# 標題
st.title("🎤 語音轉文字工具")
st.markdown("使用 OpenAI Whisper 技術，精準轉換您的音頻內容")

# 創建兩欄布局
col1, col2 = st.columns([3, 1])

with col1:
    # 主要功能區
    st.header("📁 選擇檔案")
    
    uploaded_file = st.file_uploader(
        "上傳音頻或視頻檔案",
        type=['mp3', 'wav', 'm4a', 'flac', 'mp4', 'avi', 'mov', 'mkv', 'webm'],
        help="支援 MP3, WAV, M4A, FLAC, MP4, AVI, MOV, MKV 等格式"
    )
    
    if uploaded_file is not None:
        # 顯示檔案資訊
        file_size_mb = uploaded_file.size / 1024 / 1024
        
        # 檔案資訊
        st.info(f"""
        📄 **檔案名稱:** {uploaded_file.name}  
        💾 **檔案大小:** {file_size_mb:.1f} MB  
        ⏱️ **預估處理時間:** {estimate_processing_time(file_size_mb):.1f} 分鐘
        """)
        
        # 設定選項
        st.header("⚙️ 轉換設定")
        
        col_setting1, col_setting2, col_setting3 = st.columns(3)
        
        with col_setting1:
            model_size = st.selectbox(
                "選擇 AI 模型",
                ["tiny", "base", "small", "medium", "large"],
                index=1,
                format_func=lambda x: {
                    "tiny": "Tiny - 最快速",
                    "base": "Base - 平衡（推薦）",
                    "small": "Small - 較準確",
                    "medium": "Medium - 很準確",
                    "large": "Large - 最準確"
                }[x]
            )
        
        with col_setting2:
            language = st.selectbox(
                "選擇語言",
                ["auto", "zh", "en", "ja", "ko"],
                format_func=lambda x: {
                    "auto": "自動偵測",
                    "zh": "中文",
                    "en": "英文",
                    "ja": "日文",
                    "ko": "韓文"
                }[x]
            )
        
        with col_setting3:
            include_timestamps = st.checkbox("包含時間戳記", value=False)
        
        # 轉換按鈕
        if st.button("🚀 開始轉換", type="primary", use_container_width=True):
            process_audio(uploaded_file, model_size, language, include_timestamps)

with col2:
    # 側邊資訊
    st.header("📊 狀態")
    
    # 模型狀態
    if st.session_state.model_loaded:
        st.success(f"✅ {st.session_state.loaded_model_size.upper()} 模型已載入")
    else:
        st.info("💤 等待載入模型")
    
    # 處理統計
    st.metric("已處理檔案", f"{st.session_state.processing_count} 個")
    
    # 使用提示
    st.header("💡 使用提示")
    
    st.markdown("""
    **選擇模型：**
    - 🚀 Tiny: 最快，適合測試
    - ⚡ Base: 速度與品質平衡
    - 🎯 Large: 最準確，較慢
    
    **最佳實踐：**
    - 音質越好，結果越準確
    - 中文內容選擇「中文」
    - 混合語言選「自動偵測」
    
    **支援格式：**
    - 音頻: MP3, WAV, M4A
    - 視頻: MP4, MOV, AVI
    """)

# 簡單說明
with st.expander("ℹ️ 關於此工具"):
    st.markdown("""
    此工具使用 OpenAI 的 Whisper 模型進行語音轉文字。
    
    **功能特點：**
    - 支援多種音頻和視頻格式
    - 提供多種模型選擇
    - 支援多語言識別
    - 可選時間戳記輸出
    
    **注意事項：**
    - 首次使用需要下載模型
    - 大檔案處理時間較長
    - 請確保網路連線穩定
    """)

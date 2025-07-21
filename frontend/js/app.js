class WhisperApp {
    constructor() {
        this.apiBase = '/api';  // 使用相對路徑
        this.currentFileId = null;
        this.pollingInterval = null;
        
        // 進度條動畫配置
        this.progressConfig = {
            currentProgress: 0,
            targetProgress: 0,
            animationInterval: null,
            simulationInterval: null,
            startTime: null
        };
        
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
            progressPercentage: document.getElementById('progressPercentage'),
            progressTime: document.getElementById('progressTime'),
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
            this.updateProgress(0, '準備開始轉換...');
            
            // 開始轉換（非阻塞）
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
            
            if (response.ok) {
                // 重置進度配置
                this.progressConfig.currentProgress = 0;
                this.progressConfig.targetProgress = 0;
                this.progressConfig.startTime = Date.now();
                
                // 開始輪詢狀態
                this.startPolling();
                
                // 開始進度模擬
                this.startProgressSimulation();
            } else {
                const data = await response.json();
                throw new Error(data.detail);
            }
        } catch (error) {
            alert(`轉換失敗: ${error.message}`);
            this.elements.transcribeBtn.disabled = false;
            this.elements.progressSection.style.display = 'none';
        }
    }
    
    startPolling() {
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
        }
        
        // 立即檢查一次
        this.checkProcessingStatus();
        
        // 開始輪詢 - 使用固定間隔，不再動態調整
        this.pollingInterval = setInterval(() => {
            this.checkProcessingStatus();
        }, 2000); // 2秒間隔
    }
    
    async checkProcessingStatus() {
        if (!this.currentFileId) return;
        
        try {
            console.log(`檢查狀態: ${this.currentFileId}`);
            const response = await fetch(`${this.apiBase}/status/${this.currentFileId}`);
            
            if (response.ok) {
                const status = await response.json();
                console.log('收到狀態更新:', status);
                this.handleStatusUpdate(status);
            } else {
                console.error('狀態檢查失敗:', response.status, response.statusText);
                const errorData = await response.text();
                console.error('錯誤詳情:', errorData);
            }
        } catch (error) {
            console.error('輪詢錯誤:', error);
        }
    }
    
    handleStatusUpdate(status) {
        // 確保進度值是數字
        const progress = parseInt(status.progress) || 0;
        const stage = status.stage || '處理中...';
        
        console.log(`更新進度條: ${progress}% - ${stage}`);
        
        // 更新進度條和文字
        this.updateProgress(progress, stage);
        
        // 儲存處理時間到狀態中
        if (status.processing_time) {
            this.processingTime = status.processing_time;
        }
        
        // 處理完成或錯誤狀態
        if (status.status === 'completed') {
            this.onProcessingComplete(status);
        } else if (status.status === 'error') {
            this.onProcessingError(status);
        }
    }
    
    
    async onProcessingComplete(status) {
        // 停止輪詢和進度模擬
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
            this.pollingInterval = null;
        }
        this.stopProgressSimulation();
        
        // 更新進度為100%
        this.updateProgress(100, '轉換完成！');
        
        try {
            // 獲取轉換結果 - 需要添加專門的結果獲取API
            const response = await fetch(`${this.apiBase}/result/${this.currentFileId}`);
            
            if (response.ok) {
                const data = await response.json();
                this.displayResults(data.result);
                
                // 更新統計
                this.elements.wordCount.textContent = data.word_count || 0;
                this.elements.charCount.textContent = data.char_count || 0;
                this.elements.processingTime.textContent = `${(data.processing_time || this.processingTime || 0).toFixed(1)}s`;
            } else {
                // 如果結果API不存在，顯示基本信息
                this.displayBasicResult(status);
            }
        } catch (error) {
            console.error('獲取結果失敗:', error);
            // 顯示基本信息
            this.displayBasicResult(status);
        }
        
        // 重置UI
        this.elements.transcribeBtn.disabled = false;
        setTimeout(() => {
            this.elements.progressSection.style.display = 'none';
        }, 3000);
    }
    
    displayBasicResult(status) {
        // 顯示基本完成信息
        this.elements.resultText.value = '轉換完成！請查看下載的文件。';
        this.elements.resultsSection.style.display = 'block';
        
        // 基本統計
        this.elements.wordCount.textContent = '完成';
        this.elements.charCount.textContent = '完成';
        this.elements.processingTime.textContent = `${(status.processing_time || this.processingTime || 0).toFixed(1)}s`;
    }
    
    onProcessingError(status) {
        // 停止輪詢和進度模擬
        if (this.pollingInterval) {
            clearInterval(this.pollingInterval);
            this.pollingInterval = null;
        }
        this.stopProgressSimulation();
        
        // 顯示錯誤
        this.updateProgress(0, '處理失敗');
        alert(`轉換失敗: ${status.message}`);
        
        // 重置UI
        this.elements.transcribeBtn.disabled = false;
        this.elements.progressSection.style.display = 'none';
    }
    
    updateProgress(percentage, text) {
        console.log(`設置進度條: ${percentage}% - ${text}`);
        this.elements.progressText.textContent = text;
        
        // 更新百分比顯示
        this.elements.progressPercentage.textContent = `${percentage}%`;
        
        // 更新已進行時間
        if (this.progressConfig.startTime) {
            const elapsed = Math.floor((Date.now() - this.progressConfig.startTime) / 1000);
            const minutes = Math.floor(elapsed / 60);
            const seconds = elapsed % 60;
            this.elements.progressTime.textContent = `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
        }
        
        // 設置目標進度，啟動平滑動畫
        this.animateProgressTo(percentage);
        
        // 確保進度條有視覺反饋
        if (percentage > 0) {
            this.elements.progressFill.style.minWidth = '10px';
        }
    }
    
    animateProgressTo(targetPercentage) {
        // 停止之前的動畫
        if (this.progressConfig.animationInterval) {
            clearInterval(this.progressConfig.animationInterval);
        }
        
        this.progressConfig.targetProgress = targetPercentage;
        
        // 如果目標進度與當前進度相同，直接返回
        if (Math.abs(this.progressConfig.currentProgress - targetPercentage) < 0.5) {
            return;
        }
        
        // 開始平滑動畫
        this.progressConfig.animationInterval = setInterval(() => {
            const current = this.progressConfig.currentProgress;
            const target = this.progressConfig.targetProgress;
            const diff = target - current;
            
            if (Math.abs(diff) < 0.5) {
                // 動畫完成
                this.progressConfig.currentProgress = target;
                this.elements.progressFill.style.width = `${target}%`;
                clearInterval(this.progressConfig.animationInterval);
                this.progressConfig.animationInterval = null;
                return;
            }
            
            // 計算下一步進度（緩動效果）
            // 根據進度階段調整動畫速度
            let animationSpeed = 0.1;
            if (this.progressConfig.targetProgress <= 20) {
                animationSpeed = 0.3; // 初始階段：較快動畫
            } else if (this.progressConfig.targetProgress >= 20 && this.progressConfig.targetProgress < 95) {
                animationSpeed = 0.05; // 主要處理階段：較慢動畫
            } else {
                animationSpeed = 0.2; // 完成階段：較快動畫
            }
            
            const step = diff * animationSpeed;
            this.progressConfig.currentProgress += step;
            this.elements.progressFill.style.width = `${this.progressConfig.currentProgress}%`;
        }, 100); // 100ms間隔，讓動畫更穩定
    }
    
    startProgressSimulation() {
        // 在實際進度更新之間模擬微小的進度增長
        if (this.progressConfig.simulationInterval) {
            clearInterval(this.progressConfig.simulationInterval);
        }
        
        this.progressConfig.simulationInterval = setInterval(() => {
            // 根據不同階段調整模擬速度
            let shouldSimulate = false;
            let increaseRate = 0;
            
            if (this.progressConfig.targetProgress >= 5 && this.progressConfig.targetProgress < 20) {
                // 初始階段：較快的模擬（模型載入很快）
                shouldSimulate = true;
                increaseRate = Math.random() * 0.5 + 0.3; // 0.3-0.8%
            } else if (this.progressConfig.targetProgress >= 20 && this.progressConfig.targetProgress < 95) {
                // 主要處理階段：較慢的模擬（轉換需要時間）
                shouldSimulate = true;
                increaseRate = Math.random() * 0.15 + 0.05; // 0.05-0.2%
            }
            
            if (shouldSimulate) {
                const maxAllowedProgress = this.progressConfig.targetProgress + 2; // 不能超過目標進度太多
                
                if (this.progressConfig.currentProgress < maxAllowedProgress) {
                    this.progressConfig.currentProgress += increaseRate;
                    this.elements.progressFill.style.width = `${this.progressConfig.currentProgress}%`;
                }
            }
        }, 800); // 每800ms微調一次，讓進度更穩定
    }
    
    stopProgressSimulation() {
        if (this.progressConfig.simulationInterval) {
            clearInterval(this.progressConfig.simulationInterval);
            this.progressConfig.simulationInterval = null;
        }
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

import Foundation
import AVFoundation
import UIKit

// 音频类型枚举
enum AudioType: String, CaseIterable {
    case humanVoice = "human_voice"      // 人声
    case music = "music"                 // 音乐
    case nature = "nature"               // 自然环境音
    case mechanical = "mechanical"        // 机械声
    case conversation = "conversation"    // 对话
    case singing = "singing"             // 歌声
    case noise = "noise"                 // 噪音
    case unknown = "unknown"             // 未知
    
    var displayName: String {
        switch self {
        case .humanVoice: return "人声"
        case .music: return "音乐"
        case .nature: return "自然音"
        case .mechanical: return "机械音"
        case .conversation: return "对话"
        case .singing: return "歌声"
        case .noise: return "噪音"
        case .unknown: return "未知"
        }
    }
    
    var icon: String {
        switch self {
        case .humanVoice: return "person.wave.2"
        case .music: return "music.note"
        case .nature: return "leaf"
        case .mechanical: return "gearshape"
        case .conversation: return "bubble.left.and.bubble.right"
        case .singing: return "music.mic"
        case .noise: return "waveform"
        case .unknown: return "questionmark"
        }
    }
    
    var color: UIColor {
        switch self {
        case .humanVoice: return .systemBlue
        case .music: return .systemPurple
        case .nature: return .systemGreen
        case .mechanical: return .systemOrange
        case .conversation: return .systemTeal
        case .singing: return .systemPink
        case .noise: return .systemRed
        case .unknown: return .systemGray
        }
    }
}

// Step Realtime API WebSocket客户端
class StepRealtimeManager: NSObject, ObservableObject {
    
    // API配置
    private let apiKey = "8FyDGELcpTdfh1JNOoePkfXzCtExQHL8DSdEX9UYfl4dCsE77R4WIUOIJqanw0Cl"
    private let wsURL = "wss://api.stepfun.com/v1/realtime"
    
    // WebSocket连接
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    
    // 连接管理和重连
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private var maxReconnectAttempts = 5
    private var reconnectInterval: TimeInterval = 2.0
    private var pingTimer: Timer?
    private var connectionHealthTimer: Timer?
    private var isManualDisconnect = false
    
    // 连接稳定性管理
    private var lastConnectionFailure: Date?
    private var consecutiveFailures = 0
    private var circuitBreakerOpen = false
    private var circuitBreakerTimeout: TimeInterval = 60.0
    
    // 音频处理
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode!
    
    // 状态管理
    @Published var isConnected = false
    @Published var isRecording = false
    @Published var currentTranscription = ""
    @Published var currentSummary = ""
    @Published var audioType: AudioType = .unknown
    @Published var conversationHistory: [ConversationItem] = []
    @Published var connectionStatus: ConnectionStatus = .disconnected
    
    // 连接状态枚举
    enum ConnectionStatus: String, CaseIterable {
        case disconnected = "已断开"
        case connecting = "连接中"
        case connected = "已连接"
        case reconnecting = "重连中"
        case failed = "连接失败"
    }
    
    // 实时处理状态
    @Published var processingStartTime: Date?
    @Published var isProcessing = false
    
    // 回调
    var onTranscriptionUpdate: ((String) -> Void)?
    var onSummaryGenerated: ((String, AudioType) -> Void)?
    var onAudioTypeDetected: ((AudioType) -> Void)?
    
    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        inputNode = audioEngine.inputNode
    }
    
    // MARK: - WebSocket连接管理
    
    // Real content analysis using WebSocket for immediate audio processing
    func analyzeAudioWithHTTP(audioURL: String, duration: Int) async throws -> (summary: String, transcription: String, audioType: AudioType) {
        print("🎯 使用WebSocket实时分析音频内容...")
        print("🔗 音频URL: \(audioURL)")
        print("⏱️ 音频时长: \(duration)秒")
        
        return try await withCheckedThrowingContinuation { continuation in
            // Start analysis with actual audio content
            Task {
                do {
                    let result = try await processAudioViaWebSocket(audioURL: audioURL, duration: duration)
                    print("✅ WebSocket分析成功: \(result.summary)")
                    continuation.resume(returning: result)
                } catch {
                    // Fallback to smart summary if WebSocket fails
                    print("❌ WebSocket分析失败，使用智能摘要: \(error)")
                    print("🔍 失败详情: \(error.localizedDescription)")
                    let fallback = await generateFallbackSummary(duration: duration)
                    print("🔄 使用fallback摘要: \(fallback.summary)")
                    continuation.resume(returning: fallback)
                }
            }
        }
    }
    
    // Process audio through WebSocket for real content analysis
    private func processAudioViaWebSocket(audioURL: String, duration: Int) async throws -> (summary: String, transcription: String, audioType: AudioType) {
        // Download audio data and convert to PCM16 if needed
        guard let url = URL(string: audioURL) else {
            throw NSError(domain: "StepRealtimeManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio URL"])
        }
        
        let (audioData, _) = try await URLSession.shared.data(from: url)
        let pcmData = try convertAudioToPCM16(audioData: audioData)
        
        // Connect to WebSocket and process audio
        return try await processAudioData(pcmData: pcmData, duration: duration)
    }
    
    // Convert audio data to PCM16 format
    private func convertAudioToPCM16(audioData: Data) throws -> Data {
        // Check if this is a WAV file by looking for WAV header
        if audioData.count > 44 && audioData.starts(with: Data("RIFF".utf8)) {
            // Skip WAV header (44 bytes) and return raw PCM data
            let headerSize = 44
            if audioData.count > headerSize {
                return audioData.dropFirst(headerSize)
            }
        }
        
        // If it's not a WAV file or too small, return as-is
        // (assume it's already raw PCM16 data)
        return audioData
    }
    
    // Process PCM16 audio data through WebSocket
    private func processAudioData(pcmData: Data, duration: Int) async throws -> (summary: String, transcription: String, audioType: AudioType) {
        // Clear previous analysis transcription
        currentAnalysisTranscription = ""
        // Try different connection approaches to handle -1011 errors
        let connectionMethods = [
            ("Standard", { self.createAnalysisWebSocket() }),
            ("Minimal Headers", { self.createMinimalAnalysisWebSocket() }),
            ("HTTP Upgrade", { self.createHTTPUpgradeWebSocket() })
        ]
        
        var analysisConnection: URLSessionWebSocketTask?
        
        for (methodName, createConnection) in connectionMethods {
            print("🔄 Trying connection method: \(methodName)")
            
            analysisConnection = createConnection()
            
            // Wait for connection to establish
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            
            if analysisConnection?.state == .running {
                print("✅ 分析连接成功，使用方法: \(methodName)")
                break
            } else {
                print("❌ 方法 \(methodName) 连接失败，状态: \(analysisConnection?.state.rawValue ?? -1)")
                analysisConnection?.cancel()
                analysisConnection = nil
                
                // Wait before trying next method
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
        
        // If all methods failed, use fallback
        guard let validConnection = analysisConnection, validConnection.state == .running else {
            print("❌ 所有连接方法均失败，使用fallback")
            let fallback = await generateFallbackSummary(duration: duration)
            return fallback
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            var hasReturned = false
            
            // Set up analysis completion handler
            self.analysisCompletionHandler = { summary, transcription, audioType in
                if !hasReturned {
                    hasReturned = true
                    continuation.resume(returning: (summary, transcription, audioType))
                }
            }
            
            // Send audio data for analysis
            Task {
                await sendAudioForAnalysis(pcmData: pcmData, connection: validConnection)
            }
            
            // Timeout after 30 seconds
            Task {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                if !hasReturned {
                    hasReturned = true
                    print("⏰ WebSocket分析超时，使用fallback摘要")
                    let fallback = await generateFallbackSummary(duration: duration)
                    print("🔄 超时fallback摘要: \(fallback.summary)")
                    continuation.resume(returning: fallback)
                }
            }
        }
    }
    
    // Analysis completion handler
    private var analysisCompletionHandler: ((String, String, AudioType) -> Void)?
    
    // Store WebSocket transcription for current analysis
    private var currentAnalysisTranscription: String = ""
    
    // Send audio data for analysis
    private func sendAudioForAnalysis(pcmData: Data, connection: URLSessionWebSocketTask) async {
        // Send session configuration for analysis
        let sessionConfig: [String: Any] = [
            "event_id": UUID().uuidString,
            "type": "session.update",
            "session": [
                "model": "step-audio-2-mini",
                "modalities": ["text", "audio"],
                "instructions": """
                分析音频，只输出：
                emoji:summary

                规则：
                1. emoji只能1个
                2. summary限5-8个字
                3. 不要加任何标记或符号
                4. 唱歌优先识别为🎵
                5. 不要输出<|EOT|>或其他结束标记
                
                示例：
                🎵:军歌嘹亮
                😊:开心聊天
                🌧️:雨声环境
                """,
                "voice": "qingchunshaonv",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "turn_detection": NSNull()
            ]
        ]
        
        await sendAnalysisMessage(sessionConfig, to: connection)
        
        // Send audio data in chunks
        let chunkSize = 4096
        let base64Audio = pcmData.base64EncodedString()
        
        for i in stride(from: 0, to: base64Audio.count, by: chunkSize) {
            let endIndex = min(i + chunkSize, base64Audio.count)
            let chunk = String(base64Audio[base64Audio.index(base64Audio.startIndex, offsetBy: i)..<base64Audio.index(base64Audio.startIndex, offsetBy: endIndex)])
            
            let audioMessage: [String: Any] = [
                "event_id": UUID().uuidString,
                "type": "input_audio_buffer.append",
                "audio": chunk
            ]
            
            await sendAnalysisMessage(audioMessage, to: connection)
        }
        
        // Commit audio buffer for processing
        let commitMessage: [String: Any] = [
            "event_id": UUID().uuidString,
            "type": "input_audio_buffer.commit"
        ]
        
        await sendAnalysisMessage(commitMessage, to: connection)
        
        // Request response
        let responseMessage: [String: Any] = [
            "event_id": UUID().uuidString,
            "type": "response.create"
        ]
        
        await sendAnalysisMessage(responseMessage, to: connection)
    }
    
    // Create analysis WebSocket connection with improved stability
    private func createAnalysisWebSocket() -> URLSessionWebSocketTask {
        // Model parameter is REQUIRED in URL for Step API
        let urlWithModel = "\(wsURL)?model=step-audio-2-mini"
        guard let url = URL(string: urlWithModel) else {
            fatalError("Invalid WebSocket URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0  // Shorter timeout for faster failure detection
        
        // Use minimal headers to avoid handshake conflicts
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
        
        // Add required Step API headers
        request.setValue("step-audio-2-mini", forHTTPHeaderField: "X-Model")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("🔗 Connecting to WebSocket: \(urlWithModel)")
        print("🔑 Authorization: Bearer \(String(apiKey.prefix(10)))...")
        print("📋 Model: step-audio-2-mini")
        
        let task = urlSession.webSocketTask(with: request)
        
        task.resume()
        
        // Monitor connection state
        Task {
            for attempt in 1...10 { // Check for 5 seconds
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds each
                
                switch task.state {
                case .running:
                    print("✅ Analysis WebSocket connected successfully")
                    // Start ping timer only after successful connection
                    self.startPingTimer(for: task)
                    return
                case .completed, .canceling:
                    print("❌ Analysis WebSocket connection failed: state \(task.state.rawValue)")
                    return
                default:
                    if attempt == 10 {
                        print("⏰ Analysis WebSocket connection timeout")
                    }
                }
            }
        }
        
        // Set up message receiving
        receiveAnalysisMessageWithRetry(from: task)
        
        return task
    }
    
    // Alternative connection methods for handling -1011 errors
    private func createMinimalAnalysisWebSocket() -> URLSessionWebSocketTask {
        let urlWithModel = "\(wsURL)?model=step-audio-2-mini"
        guard let url = URL(string: urlWithModel) else {
            fatalError("Invalid WebSocket URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0
        
        // Only essential WebSocket headers
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        
        print("🔗 Minimal WebSocket connection to: \(urlWithModel)")
        
        let task = urlSession.webSocketTask(with: request)
        task.resume()
        receiveAnalysisMessageWithRetry(from: task)
        
        return task
    }
    
    private func createHTTPUpgradeWebSocket() -> URLSessionWebSocketTask {
        // Try with query parameters in URL
        let urlWithParams = "\(wsURL)?model=step-audio-2-mini&format=json"
        guard let url = URL(string: urlWithParams) else {
            fatalError("Invalid WebSocket URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0
        
        // Standard HTTP to WebSocket upgrade headers
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
        request.setValue("*", forHTTPHeaderField: "Sec-WebSocket-Extensions")
        
        print("🔗 HTTP Upgrade WebSocket connection to: \(urlWithParams)")
        
        let task = urlSession.webSocketTask(with: request)
        task.resume()
        receiveAnalysisMessageWithRetry(from: task)
        
        return task
    }
    
    // Keep connection alive with periodic pings
    private func startPingTimer(for task: URLSessionWebSocketTask) {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self, weak task] _ in
            guard let task = task, task.state == .running else { 
                self?.handleConnectionFailure()
                return 
            }
            
            task.sendPing { [weak self] error in
                if let error = error {
                    print("❌ Ping failed: \(error)")
                    self?.handleConnectionFailure()
                } else {
                    print("🏓 Ping successful")
                }
            }
        }
    }
    
    // Send message to analysis WebSocket with retry logic
    private func sendAnalysisMessage(_ message: [String: Any], to connection: URLSessionWebSocketTask, retryCount: Int = 0) async {
        // Check connection state first
        guard connection.state == .running else {
            print("❌ 分析WebSocket连接状态异常: \(connection.state.rawValue)")
            if retryCount < 2 {
                // Wait and retry
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await sendAnalysisMessage(message, to: connection, retryCount: retryCount + 1)
            }
            return
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("❌ 分析消息序列化失败")
            return
        }
        
        let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
        
        do {
            try await connection.send(wsMessage)
            
            // Log success for non-audio messages
            if let type = message["type"] as? String, type != "input_audio_buffer.append" {
                print("✅ 分析消息发送成功: \(type)")
            }
        } catch {
            print("❌ 发送分析消息失败: \(error)")
            
            // Handle specific error types
            if let urlError = error as? URLError {
                switch urlError.code {
                case .networkConnectionLost, .timedOut:
                    print("🌐 网络连接问题，将重试")
                    if retryCount < 2 {
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                        await sendAnalysisMessage(message, to: connection, retryCount: retryCount + 1)
                    }
                default:
                    print("🔍 URLError details: \(urlError.localizedDescription)")
                }
            }
        }
    }
    
    // Receive messages from analysis WebSocket with retry
    private func receiveAnalysisMessageWithRetry(from connection: URLSessionWebSocketTask) {
        connection.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleAnalysisEvent(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleAnalysisEvent(text)
                    }
                @unknown default:
                    break
                }
                
                // Continue receiving
                self?.receiveAnalysisMessageWithRetry(from: connection)
                
            case .failure(let error):
                print("❌ 分析消息接收失败: \(error)")
                print("🔍 连接状态: \(connection.state.rawValue)")
                
                // Don't retry if connection is cancelled
                if connection.state != .canceling && connection.state != .completed {
                    // Retry after a short delay
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        print("🔄 重试接收消息...")
                        self?.receiveAnalysisMessageWithRetry(from: connection)
                    }
                }
            }
        }
    }
    
    // Legacy function for backward compatibility
    private func receiveAnalysisMessage(from connection: URLSessionWebSocketTask) {
        receiveAnalysisMessageWithRetry(from: connection)
    }
    
    // Handle analysis WebSocket events
    private func handleAnalysisEvent(_ jsonString: String) {
        print("📥 分析事件: \(jsonString)")
        
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        
        switch type {
        case "conversation.item.input_audio_transcription.completed":
            // Got transcription
            if let transcript = json["transcript"] as? String {
                DispatchQueue.main.async {
                    self.currentTranscription = transcript
                    // Store for current analysis
                    self.currentAnalysisTranscription = transcript
                    // 🔧 CRITICAL FIX: Also trigger callback in HTTP analysis path
                    self.onTranscriptionUpdate?(transcript)
                }
                print("📝 转录完成: \(transcript)")
                print("🔧 存储分析转录: \(transcript)")
                print("🔧 触发转录回调: onTranscriptionUpdate")
            }
            
        case "response.audio_transcript.done":
            // Got AI analysis response - WAIT for transcription before completing
            if let transcript = json["transcript"] as? String {
                // Clean EOT marker immediately
                let cleanTranscript = transcript
                    .replacingOccurrences(of: "<|EOT|>", with: "")
                    .replacingOccurrences(of: "<|eot|>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                print("🤖 AI完整响应: \(cleanTranscript)")
                let (summary, audioType) = parseAIResponse(cleanTranscript)
                
                print("✅ AI分析完成: 总结=\(summary), 类型=\(audioType.displayName)")
                print("🔍 当前分析转录: '\(currentAnalysisTranscription)'")
                
                // 🔧 CRITICAL FIX: Wait for transcription if not yet received  
                if currentAnalysisTranscription.isEmpty {
                    print("⏰ AI完成但转录未收到，延迟3秒等待转录...")
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                        let finalTranscription = self.currentAnalysisTranscription.isEmpty ? cleanTranscript : self.currentAnalysisTranscription
                        print("🔧 延迟完成，使用转录: '\(finalTranscription)'")
                        self.analysisCompletionHandler?(summary, finalTranscription, audioType)
                    }
                } else {
                    // Transcription already received, complete immediately
                    print("🔧 立即完成，使用转录: '\(currentAnalysisTranscription)'")
                    analysisCompletionHandler?(summary, currentAnalysisTranscription, audioType)
                }
            }
            
        case "response.content_part.done":
            // Alternative completion signal - WAIT for transcription before completing
            if let part = json["part"] as? [String: Any],
               let transcript = part["transcript"] as? String {
                // Clean EOT marker immediately
                let cleanTranscript = transcript
                    .replacingOccurrences(of: "<|EOT|>", with: "")
                    .replacingOccurrences(of: "<|eot|>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                print("🤖 AI内容完成: \(cleanTranscript)")
                print("🤖 AI原始回复: \(transcript)")
                let (summary, audioType) = parseAIResponse(cleanTranscript)
                
                print("✅ AI分析完成: 总结=\(summary), 类型=\(audioType.displayName)")
                print("🔍 当前分析转录: '\(currentAnalysisTranscription)'")
                
                // 🔧 CRITICAL FIX: Wait for transcription if not yet received
                if currentAnalysisTranscription.isEmpty {
                    print("⏰ AI完成但转录未收到，延迟3秒等待转录...")
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
                        let finalTranscription = self.currentAnalysisTranscription.isEmpty ? cleanTranscript : self.currentAnalysisTranscription
                        print("🔧 延迟完成，使用转录: '\(finalTranscription)'")
                        self.analysisCompletionHandler?(summary, finalTranscription, audioType)
                    }
                } else {
                    // Transcription already received, complete immediately
                    print("🔧 立即完成，使用转录: '\(currentAnalysisTranscription)'")
                    analysisCompletionHandler?(summary, currentAnalysisTranscription, audioType)
                }
            }
            
        default:
            break
        }
    }
    
    // Fallback summary generation
    private func generateFallbackSummary(duration: Int) async -> (summary: String, transcription: String, audioType: AudioType) {
        print("🔄 生成fallback智能摘要...")
        
        // 基于时长和时间的智能推测 - 使用emoji:summary格式
        let summary = generateSmartSummaryWithEmoji(duration: duration)
        let transcription = "音频内容记录 (\(duration)秒)"
        let audioType = inferAudioTypeFromDuration(duration: duration)
        
        print("🔄 Fallback结果: \(summary) | 类型: \(audioType.displayName)")
        return (summary, transcription, audioType)
    }
    
    // Generate emoji-based smart summary for fallback
    private func generateSmartSummaryWithEmoji(duration: Int) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay = getTimeOfDay(hour: hour)
        let durationCategory = getDurationCategory(duration: duration)
        
        // 基于时间和时长的智能emoji选择
        let emojiSummaries = [
            "🎵:\(timeOfDay)歌声",      // 可能是唱歌
            "💬:\(timeOfDay)对话",      // 可能是对话
            "📝:\(durationCategory)录音", // 一般录音
            "🎤:\(timeOfDay)语音",      // 语音内容
            "📞:\(timeOfDay)通话",      // 可能是通话
            "🏢:\(timeOfDay)会议",      // 工作会议
            "😊:\(timeOfDay)聊天",      // 轻松聊天
        ]
        
        return emojiSummaries.randomElement() ?? "📝:\(durationCategory)录音"
    }
    
    // Generate context-aware summary
    private func generateSmartSummary(duration: Int) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay = getTimeOfDay(hour: hour)
        let durationCategory = getDurationCategory(duration: duration)
        
        let summaries = [
            "\(timeOfDay)\(durationCategory)",
            "录音内容",
            "\(timeOfDay)记录",
            "语音备忘",
            "\(durationCategory)音频",
            "个人录音",
            "重要内容",
            "语音笔记"
        ]
        
        return summaries.randomElement() ?? "录音"
    }
    
    private func getTimeOfDay(hour: Int) -> String {
        switch hour {
        case 6..<9: return "晨间"
        case 9..<12: return "上午"
        case 12..<14: return "午间" 
        case 14..<18: return "下午"
        case 18..<22: return "晚间"
        default: return "夜间"
        }
    }
    
    private func getDurationCategory(duration: Int) -> String {
        switch duration {
        case 0..<30: return "简短"
        case 30..<180: return "常规"
        case 180..<600: return "详细"
        default: return "长篇"
        }
    }
    
    private func inferAudioTypeFromDuration(duration: Int) -> AudioType {
        switch duration {
        case 0..<15: return .humanVoice
        case 15..<60: return .conversation
        case 60..<300: return .humanVoice
        default: return .conversation
        }
    }
    
    // Original HTTP analysis (currently disabled due to model unavailability)
    private func analyzeAudioWithStepAPI(audioURL: String, duration: Int) async throws -> (summary: String, transcription: String, audioType: AudioType) {
        print("🎯 使用Step API分析音频...")
        
        guard let url = URL(string: "https://api.stepfun.com/v1/chat/completions") else {
            throw NSError(domain: "StepAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        请基于音频时长(\(duration)秒)生成智能总结。
        
        回复格式：
        转录：音频内容记录
        总结：[5-8字智能总结]
        类型：human_voice
        """
        
        let requestBody: [String: Any] = [
            "model": "step-1v-8k",
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": 100,
            "temperature": 0.7
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Step Audio API响应码: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    // Log response body for debugging
                    if let responseString = String(data: data, encoding: .utf8) {
                        print("📥 Error response: \(responseString)")
                    }
                    throw NSError(domain: "StepAudio", code: httpResponse.statusCode,
                                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"])
                }
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            if let choices = json?["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                
                print("🤖 AI原始回复: \(content)")
                
                // Parse the structured response
                let result = parseMultimodalResponse(content)
                print("✅ 多模态分析完成: 总结=\(result.summary), 类型=\(result.audioType.displayName)")
                return (result.summary, result.transcription, result.audioType)
            }
            
            // Fallback if parsing fails
            return ("音频分析", "转录失败", .humanVoice)
            
        } catch {
            print("❌ Step Audio API调用失败: \(error)")
            throw error
        }
    }
    
    // Parse multimodal response
    private func parseMultimodalResponse(_ content: String) -> (summary: String, transcription: String, audioType: AudioType) {
        var transcription = "转录失败"
        var summary = "音频分析"
        var audioType = AudioType.humanVoice
        
        let lines = content.components(separatedBy: "\n")
        
        for line in lines {
            if line.contains("转录：") {
                transcription = line.replacingOccurrences(of: "转录：", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.contains("总结：") {
                summary = line.replacingOccurrences(of: "总结：", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if line.contains("类型：") {
                let typeString = line.replacingOccurrences(of: "类型：", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                audioType = AudioType(rawValue: typeString) ?? .humanVoice
            }
        }
        
        return (summary, transcription, audioType)
    }
    
    func connect() {
        isManualDisconnect = false
        attemptConnection()
    }
    
    private func attemptConnection() {
        // Prevent multiple connection attempts
        if connectionStatus == .connecting || connectionStatus == .connected {
            print("⚠️ WebSocket already connecting or connected")
            return
        }
        
        // Check circuit breaker
        if circuitBreakerOpen {
            if let lastFailure = lastConnectionFailure,
               Date().timeIntervalSince(lastFailure) < circuitBreakerTimeout {
                print("⚡ Circuit breaker open, skipping connection attempt")
                scheduleReconnect()
                return
            } else {
                print("⚡ Circuit breaker timeout elapsed, attempting connection")
                circuitBreakerOpen = false
                consecutiveFailures = 0
            }
        }
        
        updateConnectionStatus(.connecting)
        
        // Model parameter is REQUIRED in URL for Step API
        let urlWithModel = "\(wsURL)?model=step-audio-2-mini"
        guard let url = URL(string: urlWithModel) else {
            print("❌ Invalid WebSocket URL: \(urlWithModel)")
            updateConnectionStatus(.failed)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30.0  // Shorter timeout for faster failure detection
        
        // Use minimal standard WebSocket headers
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")
        
        // Add Step API specific headers
        request.setValue("step-audio-2-mini", forHTTPHeaderField: "X-Model")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        print("🔌 Attempting to connect to: \(urlWithModel) (Attempt: \(reconnectAttempts + 1))")
        print("🔑 Using API key: \(apiKey.prefix(10))...")
        print("📋 Model: step-audio-2-mini")
        
        // Cleanup previous connection
        cleanupConnection()
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // Start receiving messages
        receiveMessage()
        
        // Start connection health monitoring
        startConnectionHealthMonitoring()
        
        // Set connection timeout
        Task {
            try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds timeout
            if connectionStatus == .connecting {
                print("❌ Connection timeout after 10s")
                handleConnectionFailure()
            }
        }
    }
    
    // 连接状态更新
    private func updateConnectionStatus(_ status: ConnectionStatus) {
        DispatchQueue.main.async {
            self.connectionStatus = status
            self.isConnected = (status == .connected)
            print("🔄 Connection status: \(status.rawValue)")
        }
    }
    
    // 连接健康监控
    private func startConnectionHealthMonitoring() {
        connectionHealthTimer?.invalidate()
        connectionHealthTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.checkConnectionHealth()
        }
    }
    
    // 检查连接健康状态
    private func checkConnectionHealth() {
        guard let task = webSocketTask else { return }
        
        if task.state != .running {
            print("⚠️ WebSocket connection unhealthy, state: \(task.state.rawValue)")
            handleConnectionFailure()
        } else {
            // Send ping to verify connection is truly alive
            task.sendPing { [weak self] error in
                if let error = error {
                    print("❌ Health check ping failed: \(error)")
                    self?.handleConnectionFailure()
                } else {
                    print("✅ Connection health check passed")
                }
            }
        }
    }
    
    // 处理连接失败
    private func handleConnectionFailure() {
        guard !isManualDisconnect else { return }
        
        print("❌ Handling connection failure")
        cleanupConnection()
        
        // Update failure tracking
        lastConnectionFailure = Date()
        consecutiveFailures += 1
        
        // Open circuit breaker after too many consecutive failures
        if consecutiveFailures >= 3 {
            print("⚡ Opening circuit breaker after \(consecutiveFailures) consecutive failures")
            circuitBreakerOpen = true
        }
        
        if reconnectAttempts < maxReconnectAttempts {
            scheduleReconnect()
        } else {
            print("❌ Max reconnect attempts reached")
            updateConnectionStatus(.failed)
            resetReconnectAttempts()
            
            // Extended delay before allowing new connection attempts
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                print("🔄 Resetting connection failure state")
                consecutiveFailures = 0
                circuitBreakerOpen = false
            }
        }
    }
    
    // 安排重连
    private func scheduleReconnect() {
        reconnectAttempts += 1
        updateConnectionStatus(.reconnecting)
        
        let delay = min(reconnectInterval * Double(reconnectAttempts), 30.0) // Max 30 seconds
        print("🔄 Scheduling reconnect in \(delay) seconds (attempt \(reconnectAttempts))")
        
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.attemptConnection()
        }
    }
    
    // 重置重连尝试计数
    private func resetReconnectAttempts() {
        reconnectAttempts = 0
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    // 清理连接资源
    private func cleanupConnection() {
        pingTimer?.invalidate()
        pingTimer = nil
        
        webSocketTask?.cancel()
        webSocketTask = nil
    }
    
    private func reconnectWithDelay() async {
        handleConnectionFailure()
    }
    
    private func testAPIConnection() async {
        print("🔍 Testing API connectivity...")
        
        guard let testURL = URL(string: "https://api.stepfun.com/v1/chat/completions") else { return }
        
        var request = URLRequest(url: testURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let testBody: [String: Any] = [
            "model": "step-1v-8k",
            "messages": [["role": "user", "content": "test"]],
            "max_tokens": 10
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: testBody)
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🔍 API Test Response Code: \(httpResponse.statusCode)")
                if httpResponse.statusCode == 401 {
                    print("❌ API Key 认证失败 - 可能是无效的API Key")
                } else if httpResponse.statusCode == 200 {
                    print("✅ API Key 认证成功")
                }
            }
        } catch {
            print("❌ API连接测试失败: \(error)")
        }
    }
    
    func disconnect() {
        print("🔌 Manual disconnect requested")
        isManualDisconnect = true
        
        // Stop all timers
        reconnectTimer?.invalidate()
        pingTimer?.invalidate()
        connectionHealthTimer?.invalidate()
        
        // Cancel WebSocket connection
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        
        // Update status
        updateConnectionStatus(.disconnected)
        
        // Stop recording if active
        stopRecording()
        
        // Reset reconnect attempts
        resetReconnectAttempts()
    }
    
    // MARK: - Session配置
    
    private func configureSession() async {
        let sessionConfig: [String: Any] = [
            "event_id": UUID().uuidString,
            "type": "session.update",
            "session": [
                "model": "step-audio-2-mini", 
                "modalities": ["text", "audio"],
                "instructions": """
                分析音频，只输出：
                emoji:summary

                规则：
                1. emoji只能1个
                2. summary限5-8个字
                3. 不要加任何标记或符号
                4. 唱歌优先识别为🎵
                5. 不要输出<|EOT|>或其他结束标记
                
                示例：
                🎵:军歌嘹亮
                😊:开心聊天
                🌧️:雨声环境
                """,
                "voice": "qingchunshaonv",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "turn_detection": NSNull()
            ]
        ]
        
        await sendMessage(sessionConfig)
    }
    
    // MARK: - 消息发送与接收
    
    private func sendMessage(_ message: [String: Any], retryCount: Int = 0) async {
        guard let webSocketTask = webSocketTask else {
            print("❌ WebSocket未连接，无法发送消息")
            if !isManualDisconnect && connectionStatus != .connecting {
                handleConnectionFailure()
            }
            return
        }
        
        // Check if WebSocket is in a valid state
        guard webSocketTask.state == .running else {
            print("❌ WebSocket状态无效: \(webSocketTask.state.rawValue)")
            if !isManualDisconnect {
                handleConnectionFailure()
            }
            return
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("❌ 消息序列化失败")
            return
        }
        
        // Debug: 打印发送的消息
        if let type = message["type"] as? String, type != "input_audio_buffer.append" {
            print("📤 发送消息: \(type)")
            if retryCount > 0 {
                print("📤 重试发送 (第\(retryCount + 1)次)")
            }
        }
        
        let wsMessage = URLSessionWebSocketTask.Message.string(jsonString)
        
        do {
            try await webSocketTask.send(wsMessage)
        } catch {
            print("❌ 发送消息失败: \(error)")
            
            // Check if we should retry
            if retryCount < 3 && !isManualDisconnect {
                print("🔄 将在1秒后重试发送消息")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await sendMessage(message, retryCount: retryCount + 1)
            } else {
                // Max retries reached or connection issues
                if !isManualDisconnect {
                    print("❌ 消息发送失败，触发重连")
                    handleConnectionFailure()
                }
            }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleServerEvent(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleServerEvent(text)
                    }
                @unknown default:
                    break
                }
                
                // 继续接收下一条消息
                self?.receiveMessage()
                
            case .failure(let error):
                print("❌ 接收消息失败: \(error)")
                
                // Check if this is a connection issue that warrants reconnection
                if let urlError = error as? URLError {
                    switch urlError.code {
                    case .networkConnectionLost, .timedOut, .notConnectedToInternet:
                        print("🌐 Network error while receiving, will attempt reconnect")
                        self?.handleConnectionFailure()
                        return
                    default:
                        break
                    }
                }
                
                // For other errors, also attempt reconnection if not manually disconnected
                if let strongSelf = self, !strongSelf.isManualDisconnect {
                    print("🔄 Receive error, attempting reconnect")
                    strongSelf.handleConnectionFailure()
                }
            }
        }
    }
    
    private func handleServerEvent(_ jsonString: String) {
        print("📥 收到服务器消息: \(jsonString)")
        
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { 
            print("❌ 无法解析服务器消息")
            return 
        }
        
        DispatchQueue.main.async { [weak self] in
            switch type {
            case "session.created":
                self?.isConnected = true
                print("✅ Session已创建")
                
            case "session.updated":
                self?.isConnected = true  
                print("✅ Session已更新")
                
            case "input_audio_buffer.speech_started":
                // VAD检测到说话开始
                print("🎤 检测到音频输入开始")
                self?.isProcessing = true
                self?.processingStartTime = Date()
                
            case "input_audio_buffer.speech_stopped":
                // VAD检测到说话结束
                print("🔇 检测到说话结束")
                
            case "conversation.item.input_audio_transcription.completed":
                // 用户音频转录完成
                if let transcript = json["transcript"] as? String {
                    self?.currentTranscription = transcript
                    self?.onTranscriptionUpdate?(transcript)
                    
                    // 触发智能分析和总结
                    self?.requestSmartAnalysis(for: transcript)
                }
                
            case "response.audio_transcript.delta":
                // AI回复的文字流（分析结果）
                if let delta = json["delta"] as? String {
                    self?.currentSummary += delta
                }
                
            case "response.audio_transcript.done":
                // AI回复完成
                if let transcript = json["transcript"] as? String {
                    // Clean EOT marker immediately
                    let cleanTranscript = transcript
                        .replacingOccurrences(of: "<|EOT|>", with: "")
                        .replacingOccurrences(of: "<|eot|>", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    print("🎤 实时录音AI回复: \(cleanTranscript)")
                    let (summary, detectedType) = self?.parseAIResponse(cleanTranscript) ?? ("", .unknown)
                    
                    print("🎤 实时分析结果: 总结=\(summary), 类型=\(detectedType.displayName)")
                    
                    self?.currentSummary = summary
                    self?.audioType = detectedType
                    self?.isProcessing = false
                    
                    // 计算处理时间
                    let processingTime = Date().timeIntervalSince(self?.processingStartTime ?? Date())
                    print("⏱️ 处理耗时: \(String(format: "%.1f", processingTime))秒")
                    
                    self?.onSummaryGenerated?(summary, detectedType)
                    self?.onAudioTypeDetected?(detectedType)
                    
                    // 保存到历史
                    let item = ConversationItem(
                        transcription: self?.currentTranscription ?? "",
                        summary: summary,
                        timestamp: Date(),
                        audioType: detectedType.rawValue
                    )
                    self?.conversationHistory.append(item)
                }
                
            case "error":
                if let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("❌ 服务器错误: \(message)")
                }
                
            default:
                break
            }
        }
    }
    
    // MARK: - 音频录制与发送
    
    func startRecording() {
        guard !isRecording else { return }
        
        setupAudioSession()
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
            isRecording = true
            print("🎤 开始录音")
        } catch {
            print("❌ 启动录音失败: \(error)")
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        do {
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
            
            // Reset audio session
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("❌ 停止录音时音频会话重置失败: \(error)")
        }
        
        isRecording = false
        
        // 提交音频缓冲区
        Task {
            await commitAudioBuffer()
        }
        
        print("🛑 停止录音")
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            print("❌ 音频会话设置失败: \(error)")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // 转换为PCM16格式
        guard let pcm16Data = convertToPCM16(buffer: buffer) else { return }
        
        // Base64编码
        let base64Audio = pcm16Data.base64EncodedString()
        
        // 发送到服务器
        Task {
            let message: [String: Any] = [
                "event_id": UUID().uuidString,
                "type": "input_audio_buffer.append",
                "audio": base64Audio
            ]
            await sendMessage(message)
        }
    }
    
    private func convertToPCM16(buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else {
            // 如果不是int16格式，需要转换
            return convertFloatToPCM16(buffer: buffer)
        }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        var data = Data()
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                let sample = channelData[channel][frame]
                data.append(contentsOf: withUnsafeBytes(of: sample) { Array($0) })
            }
        }
        
        return data
    }
    
    private func convertFloatToPCM16(buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData else { return nil }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        var data = Data()
        for frame in 0..<frameLength {
            for channel in 0..<channelCount {
                let floatSample = channelData[channel][frame]
                let int16Sample = Int16(max(-32768, min(32767, floatSample * 32768)))
                data.append(contentsOf: withUnsafeBytes(of: int16Sample) { Array($0) })
            }
        }
        
        return data
    }
    
    private func commitAudioBuffer() async {
        let message: [String: Any] = [
            "event_id": UUID().uuidString,
            "type": "input_audio_buffer.commit"
        ]
        await sendMessage(message)
    }
    
    // MARK: - 智能分析功能
    
    private func requestSmartAnalysis(for text: String) {
        Task {
            // 如果是环境音或无转录内容，直接通过VAD处理
            if text.isEmpty || text.count < 3 {
                await requestEnvironmentAnalysis()
                return
            }
            
            // 有内容则进行智能分析
            let message: [String: Any] = [
                "event_id": UUID().uuidString,
                "type": "conversation.item.create", 
                "item": [
                    "id": UUID().uuidString,
                    "type": "message",
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": "请根据以下音频转录内容生成简洁的摘要，要求：1)准确反映核心内容，2)不超过8个字，3)避免使用emoji或无关装饰文字，4)直接提取关键信息。转录内容：\(text)"
                        ]
                    ]
                ]
            ]
            await sendMessage(message)
            
            // 触发推理
            let responseMessage: [String: Any] = [
                "event_id": UUID().uuidString,
                "type": "response.create"
            ]
            await sendMessage(responseMessage)
        }
    }
    
    private func requestEnvironmentAnalysis() async {
        let message: [String: Any] = [
            "event_id": UUID().uuidString,
            "type": "conversation.item.create",
            "item": [
                "id": UUID().uuidString,
                "type": "message", 
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": "刚才检测到环境音频，请识别声音类型"
                    ]
                ]
            ]
        ]
        await sendMessage(message)
        
        let responseMessage: [String: Any] = [
            "event_id": UUID().uuidString,
            "type": "response.create"
        ]
        await sendMessage(responseMessage)
    }
    
    // 检测字符串是否包含emoji
    private func containsEmoji(_ string: String) -> Bool {
        return string.unicodeScalars.contains { scalar in
            scalar.properties.isEmoji
        }
    }
    
    private func parseAIResponse(_ response: String) -> (String, AudioType) {
        print("🤖 AI原始回复: \(response)")
        print("🔍 响应长度: \(response.count) 字符")
        
        // Clean up common artifacts and trailing garbage
        var cleanResponse = response
            .replacingOccurrences(of: "<|EOT|>", with: "")
            .replacingOccurrences(of: "<|eot|>", with: "")
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\n\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove everything after common end markers
        if let range = cleanResponse.range(of: "→") {
            // Keep everything including the arrow but remove anything after the next word
            let afterArrow = String(cleanResponse[range.upperBound...])
            if let spaceIndex = afterArrow.firstIndex(of: " ") {
                cleanResponse = String(cleanResponse[..<range.upperBound]) + String(afterArrow[..<spaceIndex])
            }
        }
        
        // Parse emoji:summary format
        if cleanResponse.contains(":") {
            print("📋 检测到emoji:summary格式")
            
            // Handle "emoji:" prefix if present
            if cleanResponse.lowercased().hasPrefix("emoji:") {
                cleanResponse = String(cleanResponse.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Find first colon to split emoji and summary
            if let colonIndex = cleanResponse.firstIndex(of: ":") {
                let emojiPart = String(cleanResponse[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                var summaryPart = String(cleanResponse[cleanResponse.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Clean summary - remove any trailing garbage after 8 characters
                if summaryPart.count > 8 {
                    // Keep only first 8 characters for summary
                    let endIndex = summaryPart.index(summaryPart.startIndex, offsetBy: 8)
                    summaryPart = String(summaryPart[..<endIndex])
                }
                
                // Validate emoji (should be 1-2 characters max)
                if emojiPart.count <= 2 && containsEmoji(emojiPart) && !summaryPart.isEmpty {
                    let fullContent = "\(emojiPart):\(summaryPart)"
                    print("📋 解析emoji:summary内容: \(fullContent)")
                    
                    // Determine audio type from emoji and content
                    let audioType = inferAudioTypeFromEmojiContent(emoji: emojiPart, content: summaryPart)
                    
                    return (fullContent, audioType)
                }
            }
            
            // 也检查其他emoji格式（向后兼容）
            let lines = cleanResponse.components(separatedBy: "\n")
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // 检查是否包含emoji和冒号
                if trimmedLine.contains(":") && trimmedLine.count > 2 {
                    // 尝试分割emoji和summary
                    let parts = trimmedLine.components(separatedBy: ":")
                    if parts.count >= 2 {
                        let emojiPart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        let summaryPart = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // 验证第一部分是否包含emoji（更宽松的检查）
                        if emojiPart.count <= 4 && !summaryPart.isEmpty && containsEmoji(emojiPart) {
                            let fullContent = "\(emojiPart):\(summaryPart)"
                            print("📋 解析emoji:summary内容: \(fullContent)")
                            
                            // 根据emoji和内容确定音频类型
                            let audioType = inferAudioTypeFromEmojiContent(emoji: emojiPart, content: summaryPart)
                            
                            return (fullContent, audioType)
                        }
                    }
                }
            }
            
            print("⚠️ emoji:summary格式中未找到有效内容，继续其他格式解析")
        }
        
        // 解析旧的状态格式（向后兼容）
        if response.contains("状态：") || response.contains("状态:") {
            print("📋 检测到旧状态格式")
            
            // 提取状态行内容
            let lines = response.components(separatedBy: "\n")
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if trimmedLine.contains("状态：") || trimmedLine.contains("状态:") {
                    let statusContent = trimmedLine.replacingOccurrences(of: "状态：", with: "")
                        .replacingOccurrences(of: "状态:", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    print("📋 解析旧状态内容: \(statusContent)")
                    
                    // 根据状态内容确定音频类型
                    let audioType = inferAudioTypeFromStatus(statusContent)
                    
                    // 直接使用状态内容作为总结
                    return (statusContent, audioType)
                }
            }
            
            print("⚠️ 旧状态格式中未找到状态行，继续其他格式解析")
        }
        
        // 解析旧的结构化输出格式  
        if response.contains("人声内容:") {
            print("📋 检测到结构化人声内容格式")
            // 人声内容解析
            var summary = "语音内容"
            var expressionType = ""
            var emotion = ""
            var characteristics = ""
            
            let lines = response.components(separatedBy: "\n")
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if trimmedLine.contains("总结：") {
                    summary = trimmedLine.replacingOccurrences(of: "- 总结：", with: "")
                        .replacingOccurrences(of: "总结：", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else if trimmedLine.contains("表达：") {
                    expressionType = trimmedLine.replacingOccurrences(of: "- 表达：", with: "")
                        .replacingOccurrences(of: "表达：", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else if trimmedLine.contains("情感：") {
                    emotion = trimmedLine.replacingOccurrences(of: "- 情感：", with: "")
                        .replacingOccurrences(of: "情感：", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else if trimmedLine.contains("特征：") {
                    characteristics = trimmedLine.replacingOccurrences(of: "- 特征：", with: "")
                        .replacingOccurrences(of: "特征：", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
            // 根据表达方式确定音频类型
            let audioType = inferAudioTypeFromExpression(expressionType, emotion: emotion)
            
            // 构建增强的总结，包含副语言信息
            let enhancedSummary = buildEnhancedSummary(
                summary: summary,
                expression: expressionType, 
                emotion: emotion,
                characteristics: characteristics
            )
            
            print("🎯 副语言信息解析 - 方式:\(expressionType) 情感:\(emotion) 特征:\(characteristics)")
            return (enhancedSummary, audioType)
            
        } else if response.contains("环境音:") {
            // 环境音解析
            var soundType = "环境声"
            var characteristics = ""
            
            let lines = response.components(separatedBy: "\n")
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if trimmedLine.contains("声音：") {
                    soundType = trimmedLine.replacingOccurrences(of: "- 声音：", with: "")
                        .replacingOccurrences(of: "声音：", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else if trimmedLine.contains("特征：") {
                    characteristics = trimmedLine.replacingOccurrences(of: "- 特征：", with: "")
                        .replacingOccurrences(of: "特征：", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
            let audioType = classifyEnvironmentSound(soundType)
            let enhancedSoundDescription = characteristics.isEmpty ? soundType : "\(soundType)(\(characteristics))"
            
            return (enhancedSoundDescription, audioType)
            
        } else if response.contains("总结:") || response.contains("总结：") {
            // 兼容旧格式
            let summary = response.replacingOccurrences(of: "总结:", with: "")
                .replacingOccurrences(of: "总结：", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let audioType = inferAudioType(from: response)
            return (summary, audioType)
            
        } else if response.contains("声音:") || response.contains("声音：") {
            // 兼容旧格式
            let soundType = response.replacingOccurrences(of: "声音:", with: "")
                .replacingOccurrences(of: "声音：", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let audioType = classifyEnvironmentSound(soundType)
            return (soundType, audioType)
            
        } else {
            // 通用处理：提取关键信息作为总结
            print("📋 使用通用解析格式")
            let cleanResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 🔧 改进：更智能的音频类型判断
            let lowercasedResponse = response.lowercased()
            var audioType = AudioType.humanVoice
            
            // 只有当AI明确说这是唱歌或音乐时才判断为音乐
            // 避免因为提到"音乐"这个词就误判
            if (lowercasedResponse.hasPrefix("唱") || lowercasedResponse.hasPrefix("歌") ||
                lowercasedResponse.hasPrefix("音乐") || lowercasedResponse.hasPrefix("🎵") ||
                lowercasedResponse.hasPrefix("🎶") || lowercasedResponse.hasPrefix("🎤")) {
                audioType = .singing
                print("🎵 检测到音乐/歌唱内容")
            } else if lowercasedResponse.contains("唱") && lowercasedResponse.count < 10 {
                // 短回复中包含"唱"字，可能是音乐
                audioType = .singing
                print("🎵 短回复检测到唱歌关键词")
            } else {
                // 默认为人声，除非有明确的其他类型标记
                audioType = .humanVoice
                print("🗣️ 默认判断为人声内容")
            }
            
            let summary = extractSummaryFromResponse(cleanResponse)
            print("📋 通用解析结果: 总结=\(summary), 类型=\(audioType.displayName)")
            return (summary, audioType)
        }
    }
    
    // Extract meaningful summary from AI response
    private func extractSummaryFromResponse(_ response: String) -> String {
        // If response starts with emoji, keep entire response up to EOT marker
        if response.unicodeScalars.first?.properties.isEmoji == true {
            // Remove EOT marker and clean up
            let cleaned = response.replacingOccurrences(of: "<|EOT|>", with: "")
                                 .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned
        }
        
        // Look for key content patterns
        if response.contains("男性") || response.contains("女性") {
            if response.contains("说话") || response.contains("对话") {
                return "人声对话"
            } else {
                return "人声内容"
            }
        }
        
        if response.contains("音乐") || response.contains("歌曲") {
            return "音乐内容"
        }
        
        if response.contains("噪音") || response.contains("杂音") {
            return "环境噪音"
        }
        
        // For responses with + symbols (like "威笑+那个+句子"), keep the full content
        if response.contains("+") {
            let cleaned = response.replacingOccurrences(of: "<|EOT|>", with: "")
                                 .trimmingCharacters(in: .whitespacesAndNewlines)
            // Return up to first 20 characters to preserve meaning
            return String(cleaned.prefix(20))
        }
        
        // Extract first meaningful phrase
        let words = response.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        for word in words {
            if word.count >= 2 && word.count <= 12 {
                return word
            }
        }
        
        // Fallback - keep more content
        return String(response.prefix(12))
    }
    
    // 根据emoji和内容推断音频类型
    private func inferAudioTypeFromEmojiContent(emoji: String, content: String) -> AudioType {
        let contentLower = content.lowercased()
        
        // 基于emoji优先判断
        switch emoji {
        case "🎵":
            return .singing
        case "🏢", "📞":
            return .conversation  
        case "📢":
            return .humanVoice
        case "📚", "📖":
            return .humanVoice
        case "🤫":
            return .humanVoice
        case "🌧️", "🌪️":
            return .nature
        case "😊", "😠", "😡", "🤧", "😤", "😮", "😯", "😲", "😱", "🤔", "😎", "🥺", "😭", "🤭", "🙄":
            return .conversation
        case "🎤", "🎙️":
            return .humanVoice
        case "🌊", "🌨️", "❄️", "☀️":
            return .nature
        case "🔧", "⚙️", "🚗", "✈️":
            return .mechanical
        default:
            break
        }
        
        // 基于内容关键词判断
        if contentLower.contains("唱") || contentLower.contains("歌") {
            return .singing
        } else if contentLower.contains("会议") || contentLower.contains("对话") || contentLower.contains("聊天") {
            return .conversation
        } else if contentLower.contains("演讲") || contentLower.contains("发言") || contentLower.contains("朗读") {
            return .humanVoice
        } else if contentLower.contains("雨") || contentLower.contains("风") || contentLower.contains("雷") {
            return .nature
        } else if contentLower.contains("音乐") || contentLower.contains("乐器") {
            return .music
        } else {
            return .humanVoice // 默认人声
        }
    }
    
    // 根据状态内容推断音频类型
    private func inferAudioTypeFromStatus(_ statusContent: String) -> AudioType {
        let lowercased = statusContent.lowercased()
        
        // 通过emoji和关键词智能识别
        if statusContent.contains("🎵") || lowercased.contains("唱") || lowercased.contains("歌") {
            return .singing
        } else if statusContent.contains("📢") || lowercased.contains("演讲") || lowercased.contains("发言") {
            return .humanVoice
        } else if statusContent.contains("📖") || lowercased.contains("朗读") || lowercased.contains("朗诵") {
            return .humanVoice
        } else if statusContent.contains("🤫") || lowercased.contains("耳语") || lowercased.contains("私语") {
            return .humanVoice
        } else if lowercased.contains("会议") || lowercased.contains("对话") || lowercased.contains("交谈") {
            return .conversation
        } else if lowercased.contains("雨声") || lowercased.contains("风声") || lowercased.contains("雷声") ||
                  lowercased.contains("海浪") || lowercased.contains("流水") || lowercased.contains("鸟") {
            return .nature
        } else if lowercased.contains("音乐") || lowercased.contains("乐器") {
            return .music
        } else if lowercased.contains("机器") || lowercased.contains("设备") || lowercased.contains("引擎") {
            return .mechanical
        } else if lowercased.contains("噪") || lowercased.contains("杂") {
            return .noise
        } else {
            return .humanVoice // 默认人声
        }
    }
    
    // 根据表达方式和情感推断音频类型
    private func inferAudioTypeFromExpression(_ expression: String, emotion: String) -> AudioType {
        let expressionLower = expression.lowercased()
        
        if expressionLower.contains("唱歌") || expressionLower.contains("歌唱") || expressionLower.contains("吟唱") {
            return .singing
        } else if expressionLower.contains("对话") || expressionLower.contains("交谈") || expressionLower.contains("聊天") {
            return .conversation
        } else if expressionLower.contains("演讲") || expressionLower.contains("朗读") || expressionLower.contains("朗诵") {
            return .humanVoice
        } else if expressionLower.contains("呼喊") || expressionLower.contains("叫喊") {
            return .humanVoice
        } else if expressionLower.contains("耳语") || expressionLower.contains("窃窃私语") {
            return .humanVoice
        } else {
            return .humanVoice
        }
    }
    
    // 构建增强的总结，包含副语言信息
    private func buildEnhancedSummary(summary: String, expression: String, emotion: String, characteristics: String) -> String {
        var enhancedSummary = summary
        
        // 移除emoji前缀，保持摘要简洁
        // 特殊表达方式的信息已经在分类中体现，不需要额外标识
        
        // 移除情感emoji，保持文本简洁
        
        return enhancedSummary
    }
    
    private func inferAudioType(from content: String) -> AudioType {
        let lowercased = content.lowercased()
        
        if lowercased.contains("对话") || lowercased.contains("交谈") {
            return .conversation
        } else if lowercased.contains("歌") || lowercased.contains("唱") {
            return .singing
        } else if lowercased.contains("音乐") {
            return .music
        } else if lowercased.contains("机器") || lowercased.contains("设备") {
            return .mechanical
        } else if lowercased.contains("自然") || lowercased.contains("风") || lowercased.contains("雨") {
            return .nature
        } else if lowercased.contains("噪音") || lowercased.contains("吵") {
            return .noise
        } else {
            return .humanVoice
        }
    }
    
    private func classifyEnvironmentSound(_ soundDescription: String) -> AudioType {
        let lowercased = soundDescription.lowercased()
        
        // 音乐类
        if lowercased.contains("音乐") || lowercased.contains("歌") || lowercased.contains("乐器") || lowercased.contains("钢琴") || lowercased.contains("吉他") {
            return .music
        }
        
        // 自然环境类 - 智能识别各种自然声音
        else if lowercased.contains("风") || lowercased.contains("雨") || lowercased.contains("雪") || lowercased.contains("雷") ||
                lowercased.contains("海浪") || lowercased.contains("流水") || lowercased.contains("溪水") || lowercased.contains("瀑布") ||
                lowercased.contains("鸟") || lowercased.contains("虫") || lowercased.contains("蛙") || lowercased.contains("动物") ||
                lowercased.contains("树叶") || lowercased.contains("自然") || lowercased.contains("森林") || lowercased.contains("海洋") {
            return .nature
        }
        
        // 机械设备类
        else if lowercased.contains("机") || lowercased.contains("电") || lowercased.contains("车") || lowercased.contains("引擎") ||
                lowercased.contains("设备") || lowercased.contains("工具") || lowercased.contains("马达") || lowercased.contains("空调") {
            return .mechanical
        }
        
        // 噪音杂音类
        else if lowercased.contains("噪") || lowercased.contains("杂") || lowercased.contains("嘈") || lowercased.contains("吵") {
            return .noise
        }
        
        // 默认分类 - 让模型的智能识别结果决定
        else {
            // 根据描述内容智能推断
            if soundDescription.count > 2 {
                return .unknown // 保持为unknown，让UI显示原始描述
            } else {
                return .noise
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension StepRealtimeManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket连接已建立")
        
        updateConnectionStatus(.connected)
        resetReconnectAttempts()
        
        // Reset failure tracking on successful connection
        consecutiveFailures = 0
        circuitBreakerOpen = false
        lastConnectionFailure = nil
        
        // Start ping timer for this connection
        startPingTimer(for: webSocketTask)
        
        // Send session configuration immediately after connection
        Task {
            await configureSession()
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "No reason provided"
        print("🔌 WebSocket连接已关闭 - Code: \(closeCode.rawValue), Reason: \(reasonString)")
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.isProcessing = false
            self.currentTranscription = ""
            self.currentSummary = ""
        }
        
        // Handle disconnection based on close code
        if !isManualDisconnect {
            if closeCode == .normalClosure {
                print("📝 Normal WebSocket closure")
                updateConnectionStatus(.disconnected)
            } else {
                print("⚠️ Unexpected WebSocket closure, attempting reconnect")
                handleConnectionFailure()
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("❌ WebSocket任务完成时出错: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                print("❌ URL错误代码: \(urlError.code.rawValue)")
                print("❌ 错误详情: \(urlError.localizedDescription)")
                
                // Handle specific error codes
                switch urlError.code {
                case .networkConnectionLost, .timedOut, .notConnectedToInternet:
                    print("🌐 Network connectivity issue, will retry")
                    if !isManualDisconnect {
                        handleConnectionFailure()
                    }
                default:
                    break
                }
            }
        }
    }
}

// MARK: - 数据模型

struct ConversationItem: Identifiable {
    let id = UUID()
    let transcription: String
    let summary: String
    let timestamp: Date
    let audioType: String
    
    init(transcription: String, summary: String, timestamp: Date = Date(), audioType: String = "unknown") {
        self.transcription = transcription
        self.summary = summary
        self.timestamp = timestamp
        self.audioType = audioType
    }
}
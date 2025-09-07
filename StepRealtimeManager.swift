import Foundation
import AVFoundation

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
    
    func connect() {
        guard let url = URL(string: wsURL) else { return }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        webSocketTask = urlSession.webSocketTask(with: request)
        webSocketTask?.resume()
        
        // 开始接收消息
        receiveMessage()
        
        // 发送session配置
        Task {
            await configureSession()
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        stopRecording()
    }
    
    // MARK: - Session配置
    
    private func configureSession() async {
        let sessionConfig: [String: Any] = [
            "event_id": UUID().uuidString,
            "type": "session.update",
            "session": [
                "modalities": ["text", "audio"],
                "instructions": """
                你是专业的实时音频分析助手。任务：
                
                **音频分类**：
                1. 人声内容 - 对话、独白、歌声等
                2. 环境音 - 音乐、自然声、机械声、噪音等
                
                **处理规则**：
                - 检测到人声：转录内容 + 5-10字总结
                - 检测到环境音：识别声音类型 + 5字描述
                - 混合声音：优先识别主要声源
                
                **输出格式**：
                人声: "总结: [内容]"
                环境音: "声音: [类型]"
                
                **响应要求**：
                - 5-10秒内完成分析
                - 保持简洁准确
                - 中文回复
                
                请使用默认女声与用户交流
                """,
                "voice": "qingchunshaonv",
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.3,  // 降低阈值，对环境音更敏感
                    "prefix_padding_ms": 200,
                    "silence_duration_ms": 1000  // 增加静默时间，给环境音更多检测时间
                ]
            ]
        ]
        
        await sendMessage(sessionConfig)
    }
    
    // MARK: - 消息发送与接收
    
    private func sendMessage(_ message: [String: Any]) async {
        guard let webSocketTask = webSocketTask,
              let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        
        do {
            try await webSocketTask.send(message)
        } catch {
            print("❌ 发送消息失败: \(error)")
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
                self?.isConnected = false
            }
        }
    }
    
    private func handleServerEvent(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        
        DispatchQueue.main.async { [weak self] in
            switch type {
            case "session.created", "session.updated":
                self?.isConnected = true
                print("✅ Session已建立")
                
            case "input_audio_buffer.speech_started":
                // VAD检测到说话开始
                print("🎤 检测到音频输入开始")
                self?.isProcessing = true
                self?.processingStartTime = Date()
                
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
                    let (summary, detectedType) = self?.parseAIResponse(transcript) ?? ("", .unknown)
                    
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
                
            case "input_audio_buffer.speech_started":
                // VAD检测到说话开始
                print("🎤 检测到说话开始")
                
            case "input_audio_buffer.speech_stopped":
                // VAD检测到说话结束
                print("🔇 检测到说话结束")
                
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
        
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
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
                            "text": "分析这段音频内容：\(text)"
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
    
    private func parseAIResponse(_ response: String) -> (String, AudioType) {
        print("🤖 AI原始回复: \(response)")
        
        // 解析回复格式
        if response.contains("总结:") {
            // 人声内容
            let summary = response.replacingOccurrences(of: "总结:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 根据内容推断具体类型
            let audioType = inferAudioType(from: response)
            return (summary, audioType)
            
        } else if response.contains("声音:") {
            // 环境音
            let soundType = response.replacingOccurrences(of: "声音:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            let audioType = classifyEnvironmentSound(soundType)
            return (soundType, audioType)
            
        } else {
            // 通用处理：直接截取前10个字作为总结
            let summary = String(response.prefix(10))
            let audioType = inferAudioType(from: response)
            return (summary, audioType)
        }
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
        
        if lowercased.contains("音乐") || lowercased.contains("歌") {
            return .music
        } else if lowercased.contains("自然") || lowercased.contains("风") || lowercased.contains("雨") || lowercased.contains("鸟") {
            return .nature
        } else if lowercased.contains("机") || lowercased.contains("电") || lowercased.contains("车") {
            return .mechanical
        } else if lowercased.contains("噪") || lowercased.contains("杂") {
            return .noise
        } else {
            return .unknown
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension StepRealtimeManager: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket连接已建立")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("🔌 WebSocket连接已关闭")
        isConnected = false
    }
}

// MARK: - 数据模型

struct ConversationItem: Identifiable {
    let id = UUID()
    let transcription: String
    let summary: String
    let timestamp: Date
    let audioType: String = "unknown"
}
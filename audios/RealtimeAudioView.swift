import SwiftUI
import AVFoundation

struct RealtimeAudioView: View {
    @StateObject private var realtimeManager = StepRealtimeManager()
    @State private var isRecording = false
    @State private var showingHistory = false
    @State private var currentWaveformLevel: CGFloat = 0
    @State private var isPreviewMode = false
    
    init() {
        // 检查Preview环境
        #if DEBUG
        _isPreviewMode = State(initialValue: ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1")
        #endif
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                // 连接状态
                HStack {
                    Circle()
                        .fill(realtimeManager.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(realtimeManager.isConnected ? "已连接" : "未连接")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    
                    Spacer()
                    
                    Button(action: {
                        showingHistory.toggle()
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // 实时转录显示
                VStack(spacing: 20) {
                    if !realtimeManager.currentTranscription.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("实时转录")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            
                            Text(realtimeManager.currentTranscription)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                        }
                    }
                    
                    // AI总结显示
                    if !realtimeManager.currentSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AI总结")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            
                            Text(realtimeManager.currentSummary)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .cornerRadius(16)
                                .shadow(color: .blue.opacity(0.3), radius: 10)
                        }
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // 录音按钮
                VStack(spacing: 20) {
                    // 音频波形可视化
                    if isRecording {
                        HStack(spacing: 2) {
                            ForEach(0..<20, id: \.self) { _ in
                                Capsule()
                                    .fill(Color.white.opacity(0.8))
                                    .frame(width: 3, height: CGFloat.random(in: 10...40))
                                    .animation(
                                        .easeInOut(duration: 0.3)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double.random(in: 0...0.3)),
                                        value: isRecording
                                    )
                            }
                        }
                        .frame(height: 40)
                    }
                    
                    Button(action: toggleRecording) {
                        ZStack {
                            // 外圈动画
                            if isRecording {
                                Circle()
                                    .stroke(Color.red.opacity(0.3), lineWidth: 2)
                                    .scaleEffect(isRecording ? 1.5 : 1)
                                    .opacity(isRecording ? 0 : 1)
                                    .animation(
                                        .easeOut(duration: 1)
                                        .repeatForever(autoreverses: false),
                                        value: isRecording
                                    )
                            }
                            
                            Circle()
                                .fill(isRecording ? Color.red : Color.white)
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 30))
                                .foregroundColor(isRecording ? .white : .black)
                        }
                    }
                    .scaleEffect(isRecording ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: isRecording)
                    
                    Text(isRecording ? "正在录音..." : "点击开始录音")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.bottom, 50)
            }
            
            // 历史记录抽屉
            if showingHistory {
                HistoryDrawer(
                    isShowing: $showingHistory,
                    history: realtimeManager.conversationHistory
                )
                .transition(.move(edge: .bottom))
                .zIndex(100)
            }
        }
        .onAppear {
            if !isPreviewMode {
                realtimeManager.connect()
            } else {
                // Preview模式：模拟连接状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    realtimeManager.isConnected = true
                }
            }
            setupCallbacks()
        }
        .onDisappear {
            if !isPreviewMode {
                realtimeManager.disconnect()
            }
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            if isPreviewMode {
                // Preview模式：模拟停止录音
                realtimeManager.currentTranscription = ""
                realtimeManager.currentSummary = ""
            } else {
                realtimeManager.stopRecording()
            }
            isRecording = false
        } else {
            if isPreviewMode {
                // Preview模式：模拟开始录音和处理流程
                simulatePreviewRecording()
            } else {
                realtimeManager.startRecording()
            }
            isRecording = true
        }
    }
    
    private func simulatePreviewRecording() {
        // 模拟转录阶段
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.isRecording {
                self.realtimeManager.currentTranscription = "这是预览模式的测试转录内容"
            }
        }
        
        // 模拟AI总结阶段
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.isRecording {
                self.realtimeManager.currentSummary = "预览测试"
                // 模拟添加到历史记录
                let previewItem = ConversationItem(
                    transcription: self.realtimeManager.currentTranscription,
                    summary: "预览测试",
                    audioType: "human_voice"
                )
                self.realtimeManager.conversationHistory.append(previewItem)
            }
        }
    }
    
    private func setupCallbacks() {
        realtimeManager.onTranscriptionUpdate = { (transcription: String) in
            // 可以添加振动反馈
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        }
        
        realtimeManager.onSummaryGenerated = { (summary: String, audioType: AudioType) in
            // 总结生成时的反馈
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        }
    }
}

// 历史记录抽屉视图
struct HistoryDrawer: View {
    @Binding var isShowing: Bool
    let history: [ConversationItem]
    
    var body: some View {
        VStack(spacing: 0) {
            // 拖动指示器
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 8)
            
            HStack {
                Text("历史记录")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    isShowing = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding()
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(history.reversed()) { item in
                        HistoryCard(item: item)
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Color.black.opacity(0.95)
                .ignoresSafeArea()
        )
        .cornerRadius(20, corners: [.topLeft, .topRight])
    }
}

// 历史记录卡片
struct HistoryCard: View {
    let item: ConversationItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatTime(item.timestamp))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                CategoryBadge(type: item.audioType)
            }
            
            // 总结
            Text(item.summary)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            // 原文
            Text(item.transcription)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// 分类标签
struct CategoryBadge: View {
    let type: String
    
    var categoryInfo: (text: String, color: Color) {
        switch type {
        case "daily_life":
            return ("生活", .green)
        case "work_meeting":
            return ("工作", .blue)
        case "learning_notes":
            return ("学习", .purple)
        case "personal_thoughts":
            return ("想法", .orange)
        default:
            return ("其他", .gray)
        }
    }
    
    var body: some View {
        Text(categoryInfo.text)
            .font(.caption2)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(categoryInfo.color.opacity(0.3))
            .cornerRadius(4)
    }
}

// 圆角扩展
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

#Preview {
    RealtimeAudioView()
}
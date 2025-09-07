import SwiftUI

struct SmartGridView: View {
    @State private var audioRecordings: [AudioRecording] = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                SmartGridLayout(recordings: audioRecordings)
                    .padding(16)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("智能录音布局")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu("添加") {
                        Button("30秒内 (1×1)") { addRecording(duration: 25) }
                        Button("30秒-2分钟 (2×1)") { addRecording(duration: 90) }
                        Button("2分钟以上 (2×2)") { addRecording(duration: 180) }
                        Button("随机添加") { addRandomRecording() }
                    }
                }
            }
        }
        .onAppear {
            setupTestData()
        }
    }
    
    private func setupTestData() {
        audioRecordings = [
            AudioRecording(duration: 25, title: "快速备忘", timestamp: Date()),
            AudioRecording(duration: 20, title: "提醒", timestamp: Date().addingTimeInterval(-300)),
            AudioRecording(duration: 90, title: "会议要点记录", timestamp: Date().addingTimeInterval(-600)),
            AudioRecording(duration: 180, title: "详细项目讨论和未来规划", timestamp: Date().addingTimeInterval(-900)),
            AudioRecording(duration: 150, title: "用户访谈完整记录", timestamp: Date().addingTimeInterval(-1200)),
            AudioRecording(duration: 30, title: "想法", timestamp: Date().addingTimeInterval(-1500)),
            AudioRecording(duration: 45, title: "学习笔记", timestamp: Date().addingTimeInterval(-1800))
        ]
    }
    
    private func addRecording(duration: Int) {
        let titles = ["新录音", "会议记录", "学习笔记", "想法记录", "待办事项"]
        let newRecording = AudioRecording(
            duration: duration,
            title: titles.randomElement() ?? "录音",
            timestamp: Date()
        )
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            audioRecordings.insert(newRecording, at: 0)
        }
    }
    
    private func addRandomRecording() {
        let durations = [20, 45, 90, 30, 150, 75, 200]
        addRecording(duration: durations.randomElement() ?? 30)
    }
}

// MARK: - 智能网格布局
struct SmartGridLayout: View {
    let recordings: [AudioRecording]
    let gridWidth: CGFloat = UIScreen.main.bounds.width - 32 // 减去 padding
    let spacing: CGFloat = 8
    
    var body: some View {
        VStack(spacing: spacing) {
            ForEach(arrangeInRows(), id: \.id) { row in
                HStack(spacing: spacing) {
                    ForEach(row.recordings, id: \.id) { recording in
                        EnhancedAudioCard(recording: recording)
                            .frame(
                                width: cellWidth(for: recording, in: row),
                                height: cellHeight(for: recording)
                            )
                    }
                    
                    // 填充剩余空间
                    if row.needsSpacer {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
    
    // 将录音安排到行中
    private func arrangeInRows() -> [GridRow] {
        var rows: [GridRow] = []
        var currentRow: [AudioRecording] = []
        var currentRowWidth: CGFloat = 0
        
        for recording in recordings {
            let recordingWidth = requiredWidth(for: recording)
            
            // 检查当前行是否还能放下这个录音
            if currentRowWidth + recordingWidth <= gridWidth - spacing || currentRow.isEmpty {
                currentRow.append(recording)
                currentRowWidth += recordingWidth
                
                // 如果录音是 2×1 或 2×2，占满整行
                if recording.gridSize.columns == 2 {
                    rows.append(GridRow(recordings: currentRow))
                    currentRow = []
                    currentRowWidth = 0
                }
            } else {
                // 当前行放不下，开始新行
                if !currentRow.isEmpty {
                    rows.append(GridRow(recordings: currentRow))
                }
                currentRow = [recording]
                currentRowWidth = recordingWidth
                
                // 如果录音是 2×1 或 2×2，占满整行
                if recording.gridSize.columns == 2 {
                    rows.append(GridRow(recordings: currentRow))
                    currentRow = []
                    currentRowWidth = 0
                }
            }
        }
        
        // 添加最后一行
        if !currentRow.isEmpty {
            rows.append(GridRow(recordings: currentRow))
        }
        
        return rows
    }
    
    // 计算录音所需的宽度
    private func requiredWidth(for recording: AudioRecording) -> CGFloat {
        switch recording.gridSize.columns {
        case 1:
            return (gridWidth - spacing) / 2 // 1×1 占用一半宽度
        case 2:
            return gridWidth // 2×1 和 2×2 占用全宽
        default:
            return (gridWidth - spacing) / 2
        }
    }
    
    // 计算单元格宽度
    private func cellWidth(for recording: AudioRecording, in row: GridRow) -> CGFloat {
        if row.recordings.count == 1 && recording.gridSize.columns == 2 {
            return gridWidth // 单独占一行的大卡片
        } else if row.recordings.count == 2 && recording.gridSize.columns == 1 {
            return (gridWidth - spacing) / 2 // 两个小卡片并排
        } else {
            return requiredWidth(for: recording)
        }
    }
    
    // 计算单元格高度
    private func cellHeight(for recording: AudioRecording) -> CGFloat {
        switch recording.cardSize {
        case .small: return 120
        case .medium: return 120
        case .large: return 250
        }
    }
}

// MARK: - 网格行数据结构
struct GridRow {
    let id = UUID()
    let recordings: [AudioRecording]
    
    var needsSpacer: Bool {
        // 如果行中只有一个元素且不是全宽，需要 Spacer
        return recordings.count == 1 && recordings.first?.gridSize.columns == 1
    }
    
    var totalColumns: Int {
        recordings.reduce(0) { $0 + $1.gridSize.columns }
    }
}

// MARK: - 带动画效果的优化版卡片
struct EnhancedAudioCard: View {
    let recording: AudioRecording
    @State private var isPressed = false
    @State private var showDetails = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 头部
            cardHeader
            
            Spacer(minLength: 4)
            
            // 主要内容
            cardContent
            
            Spacer(minLength: 4)
            
            // 底部
            cardFooter
        }
        .padding(cardPadding)
        .background(cardBackground)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onTapGesture {
            handleTap()
        }
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
        .contextMenu {
            contextMenuItems
        }
    }
    
    // MARK: - 卡片组件
    private var cardHeader: some View {
        HStack {
            // 状态指示器
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 4)
                        .scaleEffect(recording.isProcessing ? 1.5 : 0)
                        .opacity(recording.isProcessing ? 0 : 1)
                        .animation(.easeInOut(duration: 1).repeatForever(), value: recording.isProcessing)
                )
            
            Spacer()
            
            // 时长标签
            Text(recording.durationText)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.1))
                .clipShape(Capsule())
                .foregroundColor(.secondary)
        }
    }
    
    private var cardContent: some View {
        VStack(spacing: contentSpacing) {
            // 波形图
            waveformView
            
            // 标题
            Text(recording.title)
                .font(titleFont)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(titleLineLimit)
                .foregroundColor(.primary)
        }
    }
    
    private var cardFooter: some View {
        VStack(spacing: 4) {
            if recording.hasAIAnalysis {
                aiAnalysisIndicator
            }
            
            Text(recording.timestamp, style: .time)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var waveformView: some View {
        HStack(spacing: 2) {
            ForEach(0..<waveformBars, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.black)
                    .frame(width: 3, height: waveformHeight(for: index))
                    .animation(
                        .easeInOut(duration: 0.5)
                        .delay(Double(index) * 0.1),
                        value: recording.isProcessing
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var aiAnalysisIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "brain.head.profile")
                .font(.caption2)
                .foregroundColor(.green)
            Text("已分析")
                .font(.caption2)
                .foregroundColor(.green)
        }
    }
    
    private var contextMenuItems: some View {
        Group {
            Button("播放") {
                // 播放录音
            }
            
            Button("分析内容") {
                // 开始 AI 分析
            }
            
            Divider()
            
            Button("删除", role: .destructive) {
                // 删除录音
            }
        }
    }
    
    // MARK: - 计算属性
    private var cardPadding: CGFloat {
        switch recording.cardSize {
        case .small: return 12
        case .medium: return 16
        case .large: return 20
        }
    }
    
    private var contentSpacing: CGFloat {
        switch recording.cardSize {
        case .small: return 6
        case .medium: return 8
        case .large: return 12
        }
    }
    
    private var waveformBars: Int {
        switch recording.cardSize {
        case .small: return 8
        case .medium: return 15
        case .large: return 20
        }
    }
    
    private var titleFont: Font {
        switch recording.cardSize {
        case .small: return .caption
        case .medium: return .subheadline
        case .large: return .headline
        }
    }
    
    private var titleLineLimit: Int {
        switch recording.cardSize {
        case .small: return 2
        case .medium: return 2
        case .large: return 4
        }
    }
    
    private var statusColor: Color {
        if recording.isProcessing {
            return .yellow
        } else if recording.hasAIAnalysis {
            return .green
        } else {
            return .black
        }
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(UIColor.secondarySystemGroupedBackground))
            .shadow(
                color: Color.black.opacity(0.1),
                radius: isPressed ? 4 : 8,
                x: 0,
                y: isPressed ? 2 : 4
            )
    }
    
    private func waveformHeight(for index: Int) -> CGFloat {
        let baseHeights: [CGFloat] = [12, 20, 16, 24, 18, 14, 22, 10, 26, 15, 19, 13, 21, 17, 23, 11, 25, 14, 20, 16]
        let height = baseHeights[index % baseHeights.count]
        
        if recording.isProcessing {
            // 处理中时波形动画
            return height * (0.5 + 0.5 * sin(Double(index) * 0.5 + Date().timeIntervalSince1970 * 2))
        } else {
            return height
        }
    }
    
    private func handleTap() {
        // 处理点击事件
        print("点击了录音: \(recording.title)")
        
        // 这里可以添加导航到详情页面的逻辑
        withAnimation {
            showDetails = true
        }
    }
}

#Preview {
    SmartGridView()
}
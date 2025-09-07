import SwiftUI
import AVFoundation
import UIKit

struct AudioDetailView: View {
    let recording: AudioRecording
    @Binding var isPresented: Bool
    @State private var transcription: String = ""
    @State private var summary: String = ""
    @State private var isTranscribing: Bool = false
    @State private var isPlaying: Bool = false
    @State private var playbackProgress: Double = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playbackTimer: Timer?
    
    // Animation states
    @State private var showContent = false
    @State private var dragOffset: CGSize = .zero
    
    // AI Analysis states
    @StateObject private var realtimeManager = StepRealtimeManager()
    @State private var hasLoadedData = false
    @State private var audioDelegate: AudioPlayerDelegate?
    
    // Share functionality
    @State private var showShareOptions = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var selectedShareType: ShareType = .combined
    
    enum ShareType: String, CaseIterable {
        case summary = "摘要"
        case audio = "音频"
        case combined = "摘要+音频"
        
        var icon: String {
            switch self {
            case .summary: return "doc.text"
            case .audio: return "waveform"  
            case .combined: return "square.and.arrow.up"
            }
        }
        
        var description: String {
            switch self {
            case .summary: return "仅分享文本内容"
            case .audio: return "仅分享音频文件"
            case .combined: return "完整分享"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Background - full screen
            Color.white
                .ignoresSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header with drag indicator
                VStack(spacing: 12) {
                    // Drag indicator
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 8)
                    
                    // Back button and title
                    HStack {
                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isPresented = false
                            }
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.black)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.05))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        Text("点点滴滴")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                        
                        Spacer()
                        
                        // Placeholder for symmetry
                        Color.clear
                            .frame(width: 40, height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)  // Add extra top padding for status bar
                }
                .padding(.bottom, 30)  // Increase bottom padding
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Audio Player Card
                        VStack(spacing: 16) {
                            // Waveform visualization placeholder
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.03))
                                    .frame(height: 80)
                                
                                HStack(spacing: 2) {
                                    ForEach(0..<40) { i in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.black.opacity(isPlaying ? 0.8 : 0.2))
                                            .frame(width: 3, height: CGFloat.random(in: 10...60))
                                            .animation(
                                                isPlaying ?
                                                    .easeInOut(duration: 0.2).repeatForever(autoreverses: true).delay(Double(i) * 0.02) :
                                                    .default,
                                                value: isPlaying
                                            )
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            
                            // Play controls
                            HStack(spacing: 20) {
                                // Play/Pause button
                                Button(action: togglePlayback) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.black)
                                            .frame(width: 56, height: 56)
                                        
                                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(.white)
                                            .offset(x: isPlaying ? 0 : 2) // Slight offset for play icon
                                    }
                                }
                                .scaleEffect(isPlaying ? 1.05 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPlaying)
                                
                                // Duration info
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recording.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                        .lineLimit(1)
                                    
                                    Text("\(formatDuration(recording.duration)) · \(formatDate(recording.timestamp))")
                                        .font(.system(size: 14))
                                        .foregroundColor(.black.opacity(0.6))
                                }
                                
                                Spacer()
                            }
                            
                            // Progress bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.black.opacity(0.1))
                                        .frame(height: 4)
                                    
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.black)
                                        .frame(width: geometry.size.width * playbackProgress, height: 4)
                                        .animation(
                                            .easeOut(duration: 0.05)
                                            .speed(isPlaying ? 1.0 : 2.0),
                                            value: playbackProgress
                                        )
                                }
                            }
                            .frame(height: 4)
                        }
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                        
                        // AI Summary Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.black)
                                
                                Text("AI 总结")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                                
                                Spacer()
                            }
                            
                            if !summary.isEmpty {
                                Text(summary)
                                    .font(.system(size: 15))
                                    .foregroundColor(.black.opacity(0.8))
                                    .lineSpacing(4)
                            } else {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.black)
                                    
                                    Text("正在分析...")
                                        .font(.system(size: 14))
                                        .foregroundColor(.black.opacity(0.5))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(20)
                        .background(Color.black.opacity(0.03))
                        .cornerRadius(16)
                        
                        // Transcription Section
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "text.quote")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.black)
                                
                                Text("转录文本")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                                
                                Spacer()
                                
                                if !transcription.isEmpty {
                                    Button(action: copyTranscription) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 14))
                                            .foregroundColor(.black.opacity(0.6))
                                            .padding(6)
                                            .background(Color.white)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                            
                            if isTranscribing {
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.black)
                                    
                                    Text("正在转录...")
                                        .font(.system(size: 14))
                                        .foregroundColor(.black.opacity(0.5))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                            } else if !transcription.isEmpty {
                                Text(transcription)
                                    .font(.system(size: 15))
                                    .foregroundColor(.black.opacity(0.8))
                                    .lineSpacing(6)
                                    .textSelection(.enabled)
                            } else {
                                Button(action: startTranscription) {
                                    HStack {
                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 14))
                                        
                                        Text("开始转录")
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(Color.black)
                                    .cornerRadius(20)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                            }
                        }
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
                        
                        // Action Buttons
                        HStack(spacing: 12) {
                            // Share button
                            Button(action: {
                                showShareOptions = true
                            }) {
                                VStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 20))
                                        .foregroundColor(.black)
                                    
                                    Text("分享")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.black.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                            }
                            
                            // Delete button
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    deleteRecording()
                                }
                            }) {
                                VStack(spacing: 8) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 20))
                                        .foregroundColor(.red)
                                    
                                    Text("删除")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
                            }
                        }
                        
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 60)  // Extra bottom padding for full screen
                }
            }
            .opacity(showContent ? 1 : 0)
            .offset(x: showContent ? 0 : UIScreen.main.bounds.width)
        }
        .overlay(
            // Share options overlay
            Group {
                if showShareOptions {
                    ShareOptionsOverlay(
                        isPresented: $showShareOptions,
                        selectedType: $selectedShareType,
                        onShare: shareContent
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2000)
                }
            }
        )
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showContent = true
            }
            
            // 🔧 CRITICAL FIX: Force complete state reset to prevent view reuse issues
            print("🔄 AudioDetailView onAppear - FORCING COMPLETE RESET")
            print("🔄 Recording ID: \(recording.id)")
            print("🔄 Recording Title: '\(recording.title)'")
            print("🔄 Before reset - Summary: '\(summary)', Transcription: '\(transcription)'")
            
            // Force complete state reset
            hasLoadedData = false
            transcription = ""
            summary = ""
            isTranscribing = false
            
            print("🔄 After reset - Summary: '\(summary)', Transcription: '\(transcription)'")
            
            // Always load fresh data
            loadAudioData()
        }
        .onDisappear {
            // Clean up audio player and timer
            audioPlayer?.stop()
            audioPlayer?.delegate = nil
            audioPlayer = nil
            audioDelegate = nil
            playbackTimer?.invalidate()
            playbackTimer = nil
        }
        .id(recording.id) // 🔧 CRITICAL: Unique ID prevents SwiftUI view reuse
    }
    
    // MARK: - Functions
    
    func togglePlayback() {
        if isPlaying {
            audioPlayer?.pause()
            playbackTimer?.invalidate()
            playbackTimer = nil
            isPlaying = false
        } else {
            playAudio()
        }
    }
    
    func playAudio() {
        Task {
            do {
                if let remoteURL = recording.remoteURL {
                    // Play from remote URL
                    let freshURL = try await SupabaseManager.shared.getFreshAudioURL(for: recording)
                    guard let url = URL(string: freshURL) else { return }
                    
                    let (data, _) = try await URLSession.shared.data(from: url)
                    
                    await MainActor.run {
                        do {
                            audioPlayer = try AVAudioPlayer(data: data)
                            let delegate = AudioPlayerDelegate {
                                DispatchQueue.main.async {
                                    audioPlayer?.stop()
                                    playbackTimer?.invalidate()
                                    playbackTimer = nil
                                    isPlaying = false
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        playbackProgress = 0
                                    }
                                }
                            }
                            audioDelegate = delegate
                            audioPlayer?.delegate = delegate
                            audioPlayer?.prepareToPlay()
                            if audioPlayer?.play() == true {
                                isPlaying = true
                                startPlaybackTimer()
                            }
                        } catch {
                            print("❌ Failed to play audio: \(error)")
                            isPlaying = false
                        }
                    }
                } else if let localURL = recording.localURL {
                    // Play from local file
                    await MainActor.run {
                        do {
                            audioPlayer = try AVAudioPlayer(contentsOf: localURL)
                            let delegate = AudioPlayerDelegate {
                                DispatchQueue.main.async {
                                    audioPlayer?.stop()
                                    playbackTimer?.invalidate()
                                    playbackTimer = nil
                                    isPlaying = false
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        playbackProgress = 0
                                    }
                                }
                            }
                            audioDelegate = delegate
                            audioPlayer?.delegate = delegate
                            audioPlayer?.prepareToPlay()
                            if audioPlayer?.play() == true {
                                isPlaying = true
                                startPlaybackTimer()
                            }
                        } catch {
                            print("❌ Failed to play local audio: \(error)")
                            isPlaying = false
                        }
                    }
                } else {
                    print("❌ No audio URL available for playback")
                    await MainActor.run {
                        isPlaying = false
                    }
                }
            } catch {
                print("❌ Failed to prepare audio: \(error)")
                await MainActor.run {
                    isPlaying = false
                }
            }
        }
    }
    
    func startPlaybackTimer() {
        playbackTimer?.invalidate()
        // 使用更高频率的timer确保丝滑度
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            DispatchQueue.main.async {
                if let player = audioPlayer, player.duration > 0 {
                    let newProgress = player.currentTime / player.duration
                    let clampedProgress = min(max(newProgress, 0), 1)
                    
                    // 只在进度实际变化时更新，避免不必要的UI刷新
                    if abs(clampedProgress - playbackProgress) > 0.001 {
                        playbackProgress = clampedProgress
                    }
                    
                    // 播放结束检测主要通过delegate处理，这里只做备用检查
                    if !player.isPlaying && !isPlaying {
                        // 播放器已停止但UI状态未更新，清理timer
                        playbackTimer?.invalidate()
                        playbackTimer = nil
                    }
                } else {
                    // 如果播放器无效，清理timer
                    playbackTimer?.invalidate()
                    playbackTimer = nil
                    isPlaying = false
                }
            }
        }
    }
    
    func startTranscription() {
        // Use existing transcription from AI analysis if available
        if !transcription.isEmpty {
            print("📄 转录已存在")
            return
        }
        
        // Check if recording has database identifiers
        guard recording.supabaseId != nil || recording.remoteURL != nil else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.transcription = "本地录音需要先上传才能转录"
            }
            return
        }
        
        isTranscribing = true
        
        Task {
            do {
                var record: AudioRecord? = nil
                
                // Use the same query logic as loadAudioData for consistency
                if let supabaseId = recording.supabaseId {
                    print("🔍 Transcription search: by supabaseId: \(supabaseId)")
                    let records: [AudioRecord] = try await SupabaseManager.shared.client
                        .from("audio_records")
                        .select()
                        .eq("id", value: supabaseId)
                        .execute()
                        .value
                    record = records.first
                } else if let remoteURL = recording.remoteURL,
                          let url = URL(string: remoteURL),
                          let pathComponent = url.path.components(separatedBy: "/audio-files/").last {
                    print("🔍 Transcription fallback search: by file path")
                    let records: [AudioRecord] = try await SupabaseManager.shared.client
                        .from("audio_records")
                        .select()
                        .like("audio_url", pattern: "%\(pathComponent)%")
                        .execute()
                        .value
                    record = records.first
                }
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        if let existingTranscription = record?.transcription, !existingTranscription.isEmpty {
                            self.transcription = existingTranscription
                            print("✅ Loaded existing transcription for manual request")
                        } else {
                            self.transcription = "该录音暂无转录内容"
                            print("⚠️ No transcription found for this recording")
                        }
                        self.isTranscribing = false
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        self.transcription = "加载转录失败"
                        self.isTranscribing = false
                    }
                }
            }
        }
    }
    
    func copyTranscription() {
        UIPasteboard.general.string = transcription
        
        // Could show a toast/alert here
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    func shareContent() {
        // Only share recordings that are uploaded and have remote URLs for online access
        guard let remoteURL = recording.remoteURL else {
            print("⚠️ 只能分享已上传的录音")
            return
        }
        
        Task {
            var itemsToShare: [Any] = []
            
            // Generate web page URL for this share type
            let webPageURL = await generateWebPageURL(for: selectedShareType)
            
            switch selectedShareType {
            case .summary:
                // Share formatted text content with web page link
                var shareText = "🎵 点点滴滴 - 录音摘要\n\n"
                shareText += "📝 总结: \(summary.isEmpty ? "暂无总结" : summary)\n\n"
                
                if !transcription.isEmpty {
                    shareText += "📄 转录内容:\n\(transcription)\n\n"
                }
                
                shareText += "⏱️ 时长: \(formatDuration(recording.duration))\n"
                shareText += "📅 录制时间: \(formatDate(recording.timestamp))\n\n"
                shareText += "🌐 在线查看: \(webPageURL)"
                
                itemsToShare.append(shareText)
                
            case .audio:
                // Share audio with web page link
                var shareText = "🎵 点点滴滴 - 音频分享\n\n"
                shareText += "⏱️ 时长: \(formatDuration(recording.duration))\n"
                shareText += "📅 录制时间: \(formatDate(recording.timestamp))\n\n"
                shareText += "🌐 在线播放: \(webPageURL)"
                
                itemsToShare.append(shareText)
                
            case .combined:
                // Share both text and web page link
                var shareText = "🎵 点点滴滴 - 完整录音\n\n"
                shareText += "📝 总结: \(summary.isEmpty ? "暂无总结" : summary)\n\n"
                
                if !transcription.isEmpty {
                    shareText += "📄 转录内容:\n\(transcription)\n\n"
                }
                
                shareText += "⏱️ 时长: \(formatDuration(recording.duration))\n"
                shareText += "📅 录制时间: \(formatDate(recording.timestamp))\n\n"
                shareText += "🌐 完整体验: \(webPageURL)"
                
                itemsToShare.append(shareText)
            }
            
            await MainActor.run {
                shareItems = itemsToShare
                showShareSheet = true
                showShareOptions = false
            }
        }
    }
    
    func generateWebPageURL(for shareType: ShareType) async -> String {
        guard let supabaseId = recording.supabaseId else {
            return "录音未上传到云端"
        }
        
        // Vercel部署的分享页面URL
        let baseURL = "https://audio-share-nu.vercel.app"
        
        let shareTypeParam = getShareTypeParam(for: shareType)
        return "\(baseURL)?id=\(supabaseId)&type=\(shareTypeParam)"
    }
    
    func getShareTypeParam(for shareType: ShareType) -> String {
        switch shareType {
        case .summary: return "summary"
        case .audio: return "audio"
        case .combined: return "combined"
        }
    }
    
    func loadAudioData() {
        // 重要：每次都重新加载，避免显示错误的数据
        hasLoadedData = true
        
        // 重置状态，避免显示上一个录音的数据
        summary = ""
        transcription = ""
        
        Task {
            do {
                print("🔍 =================================")
                print("🔍 Loading audio data for recording: \(recording.id)")
                print("📋 Recording title: '\(recording.title)'")
                print("🔗 Remote URL: \(recording.remoteURL ?? "none")")
                print("🆔 Supabase ID: \(String(describing: recording.supabaseId))")
                print("🕒 Recording timestamp: \(recording.timestamp)")
                print("🔍 =================================")
                
                // 🔧 关键修复：检查是否有任何数据库标识符
                guard recording.supabaseId != nil || recording.remoteURL != nil else {
                    print("⚠️ This recording has no database identifiers - using local data only")
                    await MainActor.run {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.summary = recording.title.isEmpty || recording.title == "录音" ? "点击开始转录可获取AI总结" : recording.title
                            self.transcription = ""
                        }
                    }
                    return
                }
                
                var record: AudioRecord? = nil
                
                // 🔧 关键修复：优先用supabaseId查询，这是最可靠的方式
                if let supabaseId = recording.supabaseId {
                    print("🔍 PRIMARY SEARCH by supabaseId: \(supabaseId)")
                    print("🔍 Expected to find record with this EXACT ID")
                    
                    let records: [AudioRecord] = try await SupabaseManager.shared.client
                        .from("audio_records")
                        .select()
                        .eq("id", value: supabaseId)
                        .execute()
                        .value
                    
                    record = records.first
                    print("📊 Query returned \(records.count) records")
                    print("📊 supabaseId search result: \(record != nil ? "FOUND" : "NOT_FOUND")")
                    
                    if let foundRecord = record {
                        print("🎯 ✅ FOUND record by supabaseId")
                        print("🎯 Database record ID: \(String(describing: foundRecord.id))")
                        print("🎯 Database record summary: '\(foundRecord.summary ?? "NULL")'")
                        print("🎯 Database record transcription: '\(foundRecord.transcription ?? "NULL")'")
                        print("🎯 Database record audio_url: '\(foundRecord.audio_url)'")
                    } else {
                        print("❌ NO RECORD FOUND with supabaseId: \(supabaseId)")
                    }
                } else {
                    print("⚠️ Recording has NO supabaseId, will try fallback search")
                } 
                
                // 🔧 只有当supabaseId查询失败时才使用remoteURL作为后备
                if record == nil, let remoteURL = recording.remoteURL {
                    print("🔍 Fallback search: by remoteURL (signed URLs may be expired)")
                    
                    // 提取文件路径，不依赖于签名URL
                    if let url = URL(string: remoteURL),
                       let pathComponent = url.path.components(separatedBy: "/audio-files/").last {
                        print("🔍 Extracted file path: \(pathComponent)")
                        
                        // 通过文件路径的一部分查找记录（更可靠的方法）
                        let records: [AudioRecord] = try await SupabaseManager.shared.client
                            .from("audio_records")
                            .select()
                            .like("audio_url", pattern: "%\(pathComponent)%")
                            .execute()
                            .value
                        
                        record = records.first
                        print("📊 File path search result: \(record != nil ? "FOUND" : "NOT_FOUND")")
                        
                        if let foundRecord = record {
                            print("🎯 Found record by file path - ID: \(String(describing: foundRecord.id))")
                            print("🎯 Record summary: '\(foundRecord.summary ?? "none")'")
                            print("🎯 Record transcription: '\(foundRecord.transcription ?? "none")'")
                        }
                    }
                }
                
                print("📊 Final search result: \(record != nil ? "FOUND" : "NOT_FOUND")")
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        if let record = record {
                            // 🔐 CRITICAL: Create completely new strings to avoid any reference issues
                            let dbSummary = record.summary
                            let dbTranscription = record.transcription
                            
                            print("🔍 Raw database values:")
                            print("🔍 - Summary: '\(dbSummary ?? "NULL")'")
                            print("🔍 - Transcription: '\(dbTranscription ?? "NULL")'")
                            
                            // Load summary with complete isolation
                            if let dbSummary = dbSummary, !dbSummary.isEmpty {
                                self.summary = String(dbSummary) // Force new string creation
                                print("✅ FINAL summary set: '\(self.summary)'")
                            } else {
                                if !recording.title.isEmpty && recording.title != "录音" && recording.title != "处理中..." {
                                    self.summary = String(recording.title) // Force new string creation
                                    print("✅ FINAL summary from title: '\(self.summary)'")
                                } else {
                                    self.summary = "暂无总结"
                                    print("✅ FINAL summary placeholder: '\(self.summary)'")
                                }
                            }
                            
                            // Load transcription with complete isolation
                            if let dbTranscription = dbTranscription, !dbTranscription.isEmpty {
                                self.transcription = String(dbTranscription) // Force new string creation
                                print("✅ FINAL transcription set: '\(self.transcription)'")
                            } else {
                                self.transcription = ""
                                print("✅ FINAL transcription empty")
                            }
                            
                            print("🔒 ISOLATION CHECK - Final values for recording \(recording.id):")
                            print("🔒 - Summary: '\(self.summary)'")
                            print("🔒 - Transcription: '\(self.transcription)'")
                        } else {
                            // No database record found
                            print("🚫 No database record found, using local data only")
                            self.summary = recording.title.isEmpty || recording.title == "录音" ? "暂无AI分析数据" : String(recording.title)
                            self.transcription = ""
                            print("✅ Final fallback values - Summary: '\(self.summary)', Transcription: '\(self.transcription)'")
                        }
                    }
                }
            } catch {
                print("❌ Failed to load audio data: \(error)")
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        self.summary = recording.title.isEmpty || recording.title == "录音" ? "加载失败，点击重试" : recording.title
                        self.transcription = ""
                    }
                }
            }
        }

    }
    
    func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter.string(from: date)
    }
    
    func deleteRecording() {
        print("🗑️ AudioDetailView: Starting deletion for recording \(recording.id)")
        print("🗑️ Recording supabaseId: \(String(describing: recording.supabaseId))")
        print("🗑️ Recording remoteURL: \(String(describing: recording.remoteURL))")
        
        Task {
            do {
                // Get device ID as user ID  
                let deviceId = await getDeviceId()
                let userId = try await SupabaseManager.shared.getOrCreateUser(deviceId: deviceId)
                
                print("🗑️ Got userId: \(userId)")
                
                // 🔧 立即关闭视图，不等待网络操作完成
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
                
                // 然后在后台执行删除操作
                print("🗑️ 开始后台删除操作...")
                try await SupabaseManager.shared.deleteAudioRecording(userId: userId, recording: recording)
                print("✅ Recording deleted successfully from AudioDetailView")
                
            } catch {
                print("❌ Failed to delete recording from AudioDetailView: \(error)")
                print("❌ Error details: \(error.localizedDescription)")
                
                // Show deletion failed but still close the view to avoid UI stuck state
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    func getDeviceId() async -> String {
        #if targetEnvironment(simulator)
        return "simulator-device-id"
        #else
        if let deviceId = await UIDevice.current.identifierForVendor?.uuidString {
            return deviceId
        }
        return "unknown-device"
        #endif
    }
}

// AVAudioPlayer Delegate
class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinished: () -> Void
    
    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
        super.init()
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinished()
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("❌ Audio decode error: \(String(describing: error))")
        onFinished()
    }
}

// Share Options Overlay
struct ShareOptionsOverlay: View {
    @Binding var isPresented: Bool
    @Binding var selectedType: AudioDetailView.ShareType
    let onShare: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
            
            VStack {
                Spacer()
                
                // Share panel
                VStack(spacing: 0) {
                    // Drag indicator
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                    
                    // Title
                    Text("选择分享内容")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.bottom, 20)
                    
                    // Share type options
                    VStack(spacing: 12) {
                        ForEach(AudioDetailView.ShareType.allCases, id: \.self) { type in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    selectedType = type
                                }
                            }) {
                                HStack {
                                    // Icon
                                    ZStack {
                                        Circle()
                                            .fill(selectedType == type ? Color.black : Color.black.opacity(0.05))
                                            .frame(width: 44, height: 44)
                                        
                                        Image(systemName: type.icon)
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(selectedType == type ? .white : .black)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(type.rawValue)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.black)
                                        
                                        Text(type.description)
                                            .font(.system(size: 13))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    if selectedType == type {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.black)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedType == type ? Color.black.opacity(0.03) : Color.clear)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Share button
                    Button(action: onShare) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .medium))
                            
                            Text("分享")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.black)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                    
                    // Cancel button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }) {
                        Text("取消")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .background(Color.white)
                .cornerRadius(20, corners: [.topLeft, .topRight])
            }
        }
    }
}

// ShareSheet for native iOS sharing
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Exclude some activities that don't make sense for audio content
        activityViewController.excludedActivityTypes = [
            .assignToContact,
            .addToReadingList,
            .openInIBooks
        ]
        
        return activityViewController
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Preview
struct AudioDetailView_Previews: PreviewProvider {
    static var previews: some View {
        AudioDetailView(
            recording: AudioRecording(
                duration: 125,
                title: "项目会议记录",
                timestamp: Date()
            ),
            isPresented: .constant(true)
        )
    }
}

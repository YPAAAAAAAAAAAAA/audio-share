import SwiftUI
import AVFoundation
import UIKit
import BackgroundTasks

struct ContentView2: View {
    @State private var audioRecordings: [AudioRecording] = []
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isRecording = false
    @State private var recordingTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isUploading = false
    @State private var currentRecordingURL: URL?
    @State private var currentlyPlayingId: UUID?
    @State private var deleteModCardId: UUID? = nil
    @State private var showTestOptions = false
    
    // Step Realtime API Integration
    @StateObject private var realtimeManager = StepRealtimeManager()
    @State private var currentRecordingId: UUID?
    @State private var isProcessingAI = false
    @State private var currentAudioUrl: String? // 存储当前音频的Supabase URL，用于AI回调
    @State private var latestTranscription: String = "" // 🔧 存储WebSocket实际转录结果
    
    // Track upload/analysis tasks for cancellation
    @State private var uploadTasks: [UUID: Task<Void, Never>] = [:]
    
    // Audio Detail View
    @State private var selectedRecording: AudioRecording?
    @State private var showAudioDetail = false
    
    var body: some View {
        recordingView
    }
    
    private var recordingView: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            // Water-like blur overlay when in delete mode - at the very bottom
            if deleteModCardId != nil {
                Rectangle()
                    .fill(.ultraThickMaterial)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: deleteModCardId)
            }
            
            
            GeometryReader { geo in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 12) { // Consistent spacing
                        ForEach(arrangeRecordingsInRows(), id: \.id) { row in
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(row.recordings, id: \.id) { recording in
                                    AudioRecordingCard(
                                        recording: recording,
                                        geo: geo,
                                        audioPlayer: $audioPlayer,
                                        currentlyPlayingId: $currentlyPlayingId,
                                        deleteModCardId: $deleteModCardId,
                                        onDelete: deleteRecording,
                                        onTapToDetail: { recording in
                                            selectedRecording = recording
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                showAudioDetail = true
                                            }
                                        }
                                    )
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                                        removal: .scale(scale: 0.6).combined(with: .opacity).combined(with: .move(edge: .top))
                                    ))
                                }
                                
                                if row.needsSpacer {
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 20)
                }
                .overlay(
                    // Delete button overlay - always on top
                    deleteButtonOverlay(in: geo)
                        .allowsHitTesting(deleteModCardId != nil)
                )
            }
            
            VStack {
                HStack {
                    // Test buttons
                    VStack(spacing: 8) {
                        Button("录音") {
                            if isRecording {
                                stopRecording()
                            } else {
                                startRecording()
                            }
                        }
                        .testOptionButtonStyle(isActive: isRecording)
                        
                        Button("小") {
                            addTestRecording(duration: 15)
                        }
                        .testOptionButtonStyle()
                        
                        Button("中") {
                            addTestRecording(duration: 60)
                        }
                        .testOptionButtonStyle()
                        
                        Button("大") {
                            addTestRecording(duration: 300)
                        }
                        .testOptionButtonStyle()
                    }
                    .padding(.leading, 20)
                    .padding(.top, 50)
                    
                    Spacer()
                }
                Spacer()
            }
            
            // Recording timer
            if isRecording {
                VStack {
                    HStack {
                        Spacer()
                        
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                
                                Text("录音中")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.red)
                            }
                            
                            Text(formatTime(recordingTime))
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        .padding(.trailing, 80)
                        .padding(.top, 50)
                    }
                    
                    Spacer()
                }
            }
            
            // Upload status overlay
            if isUploading {
                VStack {
                    Spacer()
                    
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("上传到云端...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .padding(.bottom, 100)
                }
            }
            
        }
        .overlay(
            // Full screen audio detail view with slide animation
            Group {
                if showAudioDetail, let recording = selectedRecording {
                    AudioDetailView(recording: recording, isPresented: $showAudioDetail)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .trailing)
                        ))
                        .zIndex(1000)
                }
            }
        )
        .onChange(of: showAudioDetail) { _, isShowing in
            if !isShowing {
                // Refresh data when AudioDetailView is dismissed
                print("🔄 AudioDetailView关闭，重新加载录音数据")
                Task {
                    await loadSavedRecordings()
                }
            }
        }
        .onTapGesture {
            // Exit delete mode when tapping background
            if deleteModCardId != nil {
                withAnimation(.easeInOut(duration: 0.35)) {
                    deleteModCardId = nil
                }
            }
            // Close test options when tapping background
            if showTestOptions {
                withAnimation(.spring()) {
                    showTestOptions = false
                }
            }
        }
        .onAppear {
            setupAudioSession()
            // 🔧 设置WebSocket转录回调，捕获实时转录结果
            setupTranscriptionCallback()
            Task {
                await loadSavedRecordings()
            }
        }
    }
    
    func arrangeRecordingsInRows() -> [RecordingRow] {
        var rows: [RecordingRow] = []
        var currentSmallRecordings: [AudioRecording] = []
        
        for recording in audioRecordings {
            if recording.duration < 30 {
                currentSmallRecordings.append(recording)
                if currentSmallRecordings.count == 2 {
                    rows.append(RecordingRow(recordings: currentSmallRecordings, needsSpacer: false))
                    currentSmallRecordings = []
                }
            } else {
                if !currentSmallRecordings.isEmpty {
                    rows.append(RecordingRow(recordings: currentSmallRecordings, needsSpacer: currentSmallRecordings.count == 1))
                    currentSmallRecordings = []
                }
                rows.append(RecordingRow(recordings: [recording], needsSpacer: false))
            }
        }
        
        if !currentSmallRecordings.isEmpty {
            rows.append(RecordingRow(recordings: currentSmallRecordings, needsSpacer: currentSmallRecordings.count == 1))
        }
        
        return rows
    }
    
    
    // MARK: - Recording Functions
    
    func loadSavedRecordings() async {
        do {
            // Get device ID and user
            let deviceId = await getDeviceId()
            let userId = try await SupabaseManager.shared.getOrCreateUser(deviceId: deviceId)
            
            // Fetch recordings from Supabase
            let savedRecords = try await SupabaseManager.shared.fetchAudioRecordings(userId: userId)
            
            // Convert to AudioRecording objects with AI analysis
            let recordings = savedRecords.compactMap { record -> AudioRecording? in
                let audioUrl = record.audio_url
                var title = "录音"
                
                // Only use AI analysis from Supabase database - NO CACHE to prevent data corruption
                if let summary = record.summary, !summary.isEmpty {
                    title = summary
                    print("📊 Using database summary for recording \(String(describing: record.id)): '\(summary)'")
                } else {
                    print("📊 No summary in database for recording \(String(describing: record.id)), using default title")
                }
                
                var recording = AudioRecording(
                    duration: record.duration ?? 0,
                    title: title,
                    timestamp: record.created_at ?? Date()
                )
                recording.remoteURL = audioUrl
                
                // Store the Supabase record ID for proper deletion matching
                recording.supabaseId = record.id
                print("📌 ===== RECORDING LOADED =====")
                print("📌 Local recording ID: \(recording.id)")
                print("📌 Supabase record ID: \(String(describing: record.id))")
                print("📌 Recording title: '\(title)'")
                print("📌 Database summary: '\(record.summary ?? "NULL")'")
                print("📌 Database transcription: '\(record.transcription ?? "NULL")'")
                print("📌 ===============================")
                
                return recording
            }
            
            // Update UI on main thread
            await MainActor.run {
                let oldCount = self.audioRecordings.count
                
                // 🔧 CRITICAL FIX: 保留正在处理的本地录音
                // 判断条件：没有supabaseId的录音（可能有remoteURL但还没保存到数据库）
                let processingRecordings = self.audioRecordings.filter { recording in
                    recording.supabaseId == nil
                }
                
                print("🔄 loadSavedRecordings: \(oldCount) -> \(recordings.count) 远程录音")
                print("🔄 保留 \(processingRecordings.count) 个处理中的本地录音")
                
                // 🔧 验证：检查处理中的录音状态
                for recording in processingRecordings {
                    print("🔍 处理中录音: ID=\(recording.id), 标题='\(recording.title)', supabaseId=\(String(describing: recording.supabaseId))")
                }
                
                // 合并远程录音和本地处理中的录音
                var allRecordings = recordings
                allRecordings.append(contentsOf: processingRecordings)
                
                self.audioRecordings = allRecordings.sorted { $0.timestamp > $1.timestamp }
                print("🔄 最终录音总数: \(self.audioRecordings.count)")
            }
            
        } catch {
            print("Failed to load saved recordings: \(error)")
        }
    }
    
    func setupAudioSession() {
        #if targetEnvironment(simulator)
        // Skip audio setup in simulator/preview
        return
        #endif
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            session.requestRecordPermission { _ in }
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }
    
    
    func setupTranscriptionCallback() {
        // 确保转录回调正确设置
        realtimeManager.onTranscriptionUpdate = { transcription in
            DispatchQueue.main.async {
                self.latestTranscription = transcription
                print("📝 WebSocket转录已捕获并保存到latestTranscription: '\(transcription)'")
            }
        }
        print("🔧 转录回调已重新设置")
    }
    
    func startRecording() {
        // 🔧 CRITICAL: Clear previous transcription to prevent data leakage
        latestTranscription = ""
        print("🔧 清空上一次的转录，准备新录音")
        
        // 🔧 确保转录回调仍然有效
        setupTranscriptionCallback()
        
        #if targetEnvironment(simulator)
        // Fake recording for simulator/preview
        isRecording = true
        recordingTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingTime += 0.1
        }
        return
        #endif
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording_\(Date().timeIntervalSince1970).wav")
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            
            
            currentRecordingURL = audioFilename  // Store for upload later
            isRecording = true
            recordingTime = 0
            
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                recordingTime += 0.1
            }
        } catch {
            print("Could not start recording: \(error)")
        }
    }
    
    func stopRecording() {
        #if !targetEnvironment(simulator)
        audioRecorder?.stop()
        #endif
        
        timer?.invalidate()
        timer = nil
        isRecording = false
        
        // Add the recorded audio to our list
        let duration = Int(recordingTime)
        var newRecording = AudioRecording(
            duration: duration,
            title: "处理中...",  // Will be replaced by AI summary
            timestamp: Date()
        )
        
        // Save the local URL - CRITICAL for playback even if upload fails
        if let url = currentRecordingURL {
            newRecording.localURL = url
            print("💾 本地录音文件保存: \(url.path)")
        } else {
            print("⚠️ 警告：没有本地录音URL，播放可能会失败")
        }
        
        // Store the recording ID for later update
        currentRecordingId = newRecording.id
        isProcessingAI = true
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            audioRecordings.insert(newRecording, at: 0)
        }
        
        print("✅ 录音已添加到UI，总数: \(audioRecordings.count)")
        print("✅ 录音ID: \(newRecording.id)")
        print("✅ 录音标题: \(newRecording.title)")
        
        // Upload to Supabase and analyze with AI
        if let recordingURL = currentRecordingURL {
            print("🚀 开始上传和分析任务...")
            // Store task for potential cancellation
            let uploadTask = Task {
                print("📤 执行上传分析任务中...")
                await uploadToSupabaseAndAnalyze(recording: newRecording, fileURL: recordingURL, duration: duration)
                // Remove from tracking when complete
                await MainActor.run {
                    uploadTasks.removeValue(forKey: newRecording.id)
                    print("🔄 任务完成，从跟踪中移除")
                }
            }
            uploadTasks[newRecording.id] = uploadTask
            print("📋 任务已存储，当前任务数: \(uploadTasks.count)")
        } else {
            print("⚠️ 警告：没有录音URL，跳过上传")
        }
        
        recordingTime = 0
        currentRecordingURL = nil
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
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
    
    func getMaxCardHeight(for recordings: [AudioRecording]) -> CGFloat {
        return recordings.map { recording in
            let fullWidth = UIScreen.main.bounds.width - 40
            let halfWidth = (fullWidth - 12) / 2
            
            if recording.duration < 30 {
                return 100.0
            } else if recording.duration < 180 {
                return 120.0
            } else {
                return 180.0
            }
        }.max() ?? 100.0
    }
    
    func getDeleteButtonWidth(for recording: AudioRecording) -> CGFloat {
        let fullWidth = UIScreen.main.bounds.width - 40
        let halfWidth = (fullWidth - 12) / 2
        
        if recording.duration < 30 {
            return halfWidth
        } else {
            return fullWidth
        }
    }
    
    @ViewBuilder
    func deleteButtonOverlay(in geo: GeometryProxy) -> some View {
        if let selectedCardId = deleteModCardId,
           let selectedCard = audioRecordings.first(where: { $0.id == selectedCardId }) {
            
            // Calculate card position
            if let cardPosition = getCardPosition(for: selectedCard, in: geo) {
                Button(action: {
                    deleteRecording(selectedCard)
                }) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.black, lineWidth: 2)
                        )
                        .overlay(
                            VStack {
                                HStack {
                                    Text("删除")
                                        .font(.system(size: selectedCard.duration < 30 ? 14 : 16, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Rectangle()
                                        .fill(Color.white)
                                        .frame(width: 12, height: 12)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                
                                Spacer()
                            }
                        )
                        .frame(width: getDeleteButtonWidth(for: selectedCard), height: 60)
                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .position(
                    x: cardPosition.x,
                    y: cardPosition.y + getCardHeight(for: selectedCard) / 2 + 15 + 30 // card center + half card height + spacing + half delete button height
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(10000) // Highest z-index
            }
        }
    }
    
    func getCardPosition(for recording: AudioRecording, in geo: GeometryProxy) -> CGPoint? {
        let rows = arrangeRecordingsInRows()
        let fullWidth = geo.size.width - 40
        let halfWidth = (fullWidth - 12) / 2
        
        var cumulativeY: CGFloat = 60 // Start with top padding
        
        for (rowIndex, row) in rows.enumerated() {
            if let cardIndex = row.recordings.firstIndex(where: { $0.id == recording.id }) {
                // Calculate X position
                let cardX: CGFloat
                if recording.duration < 30 {
                    cardX = 20 + halfWidth / 2 + CGFloat(cardIndex) * (halfWidth + 12)
                } else {
                    cardX = 20 + fullWidth / 2
                }
                
                // Y position is at the center of the current card
                let cardHeight = getCardHeight(for: recording)
                let cardCenterY = cumulativeY + cardHeight / 2
                
                return CGPoint(x: cardX, y: cardCenterY)
            }
            
            // Add this row's height plus spacing for next iteration
            cumulativeY += getMaxCardHeightInRow(row) + 12
        }
        return nil
    }
    
    func getCardHeight(for recording: AudioRecording) -> CGFloat {
        if recording.duration < 30 {
            return 100
        } else if recording.duration < 180 {
            return 120
        } else {
            return 180
        }
    }
    
    func getMaxCardHeightInRow(_ row: RecordingRow) -> CGFloat {
        return row.recordings.map { getCardHeight(for: $0) }.max() ?? 100
    }
    
    func addTestRecording(duration: Int) {
        let testRecording = AudioRecording(
            duration: duration,
            title: "测试录音 \(formatTime(TimeInterval(duration)))",
            timestamp: Date()
        )
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            audioRecordings.insert(testRecording, at: 0)
        }
    }
    
    func deleteRecording(_ recording: AudioRecording) {
        print("🗑️ DELETE REQUESTED - Recording ID: \(recording.id)")
        print("🗑️ Recording supabaseId: \(String(describing: recording.supabaseId))")
        print("🗑️ Recording title: \(recording.title)")
        print("🗑️ Recording remoteURL: \(String(describing: recording.remoteURL))")
        
        // First fade out the delete button
        withAnimation(.easeOut(duration: 0.15)) {
            deleteModCardId = nil
        }
        
        // Then remove with a smooth spring animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85, blendDuration: 0)) {
                audioRecordings.removeAll { $0.id == recording.id }
            }
        }
        
        // Cancel any ongoing upload/analysis for this recording
        if let uploadTask = uploadTasks[recording.id] {
            print("🚫 Cancelling ongoing upload/analysis for recording \(recording.id)")
            uploadTask.cancel()
            uploadTasks.removeValue(forKey: recording.id)
        }
        
        // Only delete from Supabase if it has a supabaseId or remoteURL
        if recording.supabaseId != nil || recording.remoteURL != nil {
            // Request background time to complete deletion
            var backgroundTask: UIBackgroundTaskIdentifier = .invalid
            backgroundTask = UIApplication.shared.beginBackgroundTask {
                // Clean up if time expires
                print("⚠️ Background time expired during deletion")
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            
            Task {
                do {
                    print("🗑️ Starting Supabase deletion with background protection...")
                    let deviceId = await getDeviceId()
                    let userId = try await SupabaseManager.shared.getOrCreateUser(deviceId: deviceId)
                    
                    print("🗑️ User ID: \(userId)")
                    
                    // Delete from database and storage
                    try await SupabaseManager.shared.deleteAudioRecording(userId: userId, recording: recording)
                    
                    print("🗑️ ✅ Supabase deletion completed successfully")
                    
                    // End background task
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    
                } catch {
                    print("❌ Failed to delete from Supabase: \(error)")
                    
                    // End background task
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                    
                    // Don't re-add to list - user wanted it deleted
                    // The next sync will handle any inconsistencies
                }
            }
        } else {
            print("⚠️ Recording has no supabaseId or remoteURL, only deleted locally")
        }
    }
    
    func uploadToSupabaseAndAnalyze(recording: AudioRecording, fileURL: URL, duration: Int) async {
        print("🎯 开始uploadToSupabaseAndAnalyze - 录音ID: \(recording.id)")
        print("🎯 当前audioRecordings数量: \(audioRecordings.count)")
        
        #if targetEnvironment(simulator)
        // Skip actual upload in simulator, just show the UI
        await MainActor.run { isUploading = true }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await MainActor.run { 
            isUploading = false
            print("📤 Simulated upload complete for: \(recording.title)")
        }
        return
        #endif
        
        do {
            await MainActor.run { isUploading = true }
            
            // Get device ID as user ID
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
            let userId = try await SupabaseManager.shared.getOrCreateUser(deviceId: deviceId)
            
            // Check if task was cancelled
            if Task.isCancelled {
                print("🚫 Upload cancelled for recording \(recording.id)")
                await MainActor.run {
                    print("🚫 任务取消，保留录音在UI中")
                    if let index = audioRecordings.firstIndex(where: { $0.id == recording.id }) {
                        audioRecordings[index].title = "录音取消"
                    }
                }
                return
            }
            
            // Upload file to Supabase Storage
                let publicURL = try await SupabaseManager.shared.uploadAudioRecording(
                    userId: userId,
                    fileURL: fileURL,
                    recording: recording
                )
                
                // Save metadata to database and get the record ID
                let supabaseId = try await SupabaseManager.shared.saveAudioRecording(
                    userId: userId,
                    recording: recording,
                    fileURL: publicURL
                )
                
                await MainActor.run {
                    // Update the local recording with supabaseId and remoteURL for proper deletion and transcription
                    if let index = audioRecordings.firstIndex(where: { $0.id == recording.id }) {
                        if let supabaseId = supabaseId {
                            audioRecordings[index].supabaseId = supabaseId
                            print("📌 Updated local recording with supabaseId: \(supabaseId)")
                        }
                        // 🔧 重要：更新remoteURL，这样AudioDetailView就能加载转录了
                        audioRecordings[index].remoteURL = publicURL
                        print("📌 Updated local recording with remoteURL for transcription access")
                    }
                    
                    isUploading = false
                    print("✅ Successfully uploaded: \(recording.title)")
                    print("🔗 Starting AI analysis for: \(publicURL)")
                }
                
                // Now analyze with Step Audio-2-Mini API using the actual URL
                let (summary, finalTranscription, audioType) = try await realtimeManager.analyzeAudioWithHTTP(
                    audioURL: publicURL,
                    duration: duration
                )
                
                // 🔧 转录现在直接从analyzeAudioWithHTTP返回，已经是正确的WebSocket转录
                print("🔧 分析完成，获得转录: '\(finalTranscription)'")
                
                await MainActor.run {
                    // Update the recording with AI summary
                    if let index = audioRecordings.firstIndex(where: { $0.id == recording.id }) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            audioRecordings[index].title = summary.isEmpty ? "录音" : summary
                            isProcessingAI = false
                        }
                    }
                }
                
                // 🔧 DEBUG: 检查传递给数据库的转录内容
                print("🔍 AI分析结果准备保存:")
                print("🔍 Summary: '\(summary)'")
                print("🔍 Final Transcription: '\(finalTranscription)'")
                print("🔍 Audio Type: \(audioType.rawValue)")
                print("🔍 Audio URL: \(publicURL)")
                
                // Save AI analysis to Supabase using the final transcription
                try await SupabaseManager.shared.updateAudioRecordingWithAI(
                    audioUrl: publicURL,
                    summary: summary,
                    transcription: finalTranscription,
                    audioType: audioType.rawValue,
                    confidence: 0.95
                )
                
                print("✅ AI analysis completed and saved")
                
                // 🔧 清空转录，准备下次录音
                latestTranscription = ""
                print("🔧 AI分析完成，清空latestTranscription")
                
        } catch {
            print("❌ 捕获到错误: \(error)")
            await MainActor.run {
                print("🔍 错误处理前 - audioRecordings数量: \(audioRecordings.count)")
                
                isUploading = false
                isProcessingAI = false
                if let index = audioRecordings.firstIndex(where: { $0.id == recording.id }) {
                    // Don't remove recording on error - keep it with default title
                    audioRecordings[index].title = "录音失败"
                    print("❌ 找到录音(索引\(index))，设置为'录音失败'")
                } else {
                    print("❌ 警告：找不到录音ID \(recording.id)")
                    print("❌ 当前录音列表: \(audioRecordings.map { ($0.id, $0.title) })")
                }
                
                print("🔍 错误处理后 - audioRecordings数量: \(audioRecordings.count)")
                print("❌ Upload or AI analysis failed: \(error.localizedDescription)")
                print("❌ Error details: \(error)")
            }
        }
    }
    
    func uploadToSupabase(recording: AudioRecording, fileURL: URL) {
        #if targetEnvironment(simulator)
        // Skip actual upload in simulator, just show the UI
        isUploading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isUploading = false
            print("📤 Simulated upload complete for: \(recording.title)")
        }
        return
        #endif
        
        Task {
            do {
                isUploading = true
                
                // Get device ID as user ID
                let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
                let userId = try await SupabaseManager.shared.getOrCreateUser(deviceId: deviceId)
                
                // Upload file to Supabase Storage
                let publicURL = try await SupabaseManager.shared.uploadAudioRecording(
                    userId: userId,
                    fileURL: fileURL,
                    recording: recording
                )
                
                // Save metadata to database and get the record ID
                let supabaseId = try await SupabaseManager.shared.saveAudioRecording(
                    userId: userId,
                    recording: recording,
                    fileURL: publicURL
                )
                
                // Store the audio URL for AI callback
                await MainActor.run {
                    // Update the local recording with supabaseId for proper deletion
                    if let index = audioRecordings.firstIndex(where: { $0.id == recording.id }),
                       let supabaseId = supabaseId {
                        audioRecordings[index].supabaseId = supabaseId
                        print("📌 Updated local recording with supabaseId: \(supabaseId)")
                    }
                    
                    // Set the current audio URL for AI analysis
                    self.currentAudioUrl = publicURL
                    isUploading = false
                    print("✅ Successfully uploaded: \(recording.title)")
                    print("🔗 Audio URL saved for AI: \(publicURL)")
                }
                
            } catch {
                await MainActor.run {
                    isUploading = false
                    print("❌ Upload failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct RecordingRow: Identifiable {
    let id = UUID()
    let recordings: [AudioRecording]
    let needsSpacer: Bool
}

struct AudioRecordingCard: View {
    let recording: AudioRecording
    let geo: GeometryProxy
    @Binding var audioPlayer: AVAudioPlayer?
    @Binding var currentlyPlayingId: UUID?
    @Binding var deleteModCardId: UUID?
    let onDelete: (AudioRecording) -> Void
    let onTapToDetail: (AudioRecording) -> Void
    @State private var isPressed = false
    @State private var waveformAnimation = false
    @State private var playingAnimation = false
    @State private var longPressTimer: Timer?
    
    var isInDeleteMode: Bool {
        deleteModCardId == recording.id
    }
    
    var isPlaying: Bool {
        currentlyPlayingId == recording.id && audioPlayer?.isPlaying == true
    }
    
    var cardSize: (width: CGFloat, height: CGFloat) {
        let fullWidth = geo.size.width - 40
        let halfWidth = (fullWidth - 12) / 2
        
        if recording.duration < 30 {
            return (halfWidth, 100)
        } else if recording.duration < 180 {
            return (fullWidth, 120)
        } else {
            return (fullWidth, 180)
        }
    }
    
    var body: some View {
        ZStack {
            // Main card
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.black, lineWidth: 2)
                    )
                    .overlay(
                VStack(spacing: 0) {
                    HStack {
                        Text(recording.durationText)
                            .font(.system(size: recording.duration < 30 ? 14 : (recording.duration < 180 ? 16 : 18), weight: .bold))
                            .foregroundColor(.black)
                        
                        Spacer()
                        
                        Rectangle()
                            .fill(isPlaying ? Color.red : Color.black)
                            .frame(
                                width: recording.duration < 30 ? 12 : (recording.duration < 180 ? 16 : 20),
                                height: recording.duration < 30 ? 12 : (recording.duration < 180 ? 16 : 20)
                            )
                    }
                    .padding(.horizontal, recording.duration < 30 ? 12 : (recording.duration < 180 ? 16 : 20))
                    .padding(.vertical, recording.duration < 30 ? 10 : (recording.duration < 180 ? 12 : 14))
                    
                    HStack(spacing: recording.duration < 30 ? 1 : 2) {
                        ForEach(0..<getWaveformBars(), id: \.self) { barIndex in
                            Rectangle()
                                .fill(isPlaying ? Color.red : Color.black)
                                .frame(
                                    width: recording.duration < 30 ? 2 : (recording.duration < 180 ? 3 : 4),
                                    height: getAnimatedWaveformHeight(for: barIndex)
                                )
                                .animation(
                                    isPlaying ? 
                                        .easeInOut(duration: 0.5)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(barIndex) * 0.05) : 
                                        .default,
                                    value: isPlaying
                                )
                        }
                    }
                    .padding(.horizontal, recording.duration < 30 ? 12 : (recording.duration < 180 ? 16 : 20))
                    .frame(maxHeight: recording.duration < 30 ? 20 : (recording.duration < 180 ? 30 : 40))
                    
                    Spacer()
                    
                    if recording.duration >= 30 {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(0..<getContentLines(), id: \.self) { lineIndex in
                                HStack {
                                    Rectangle()
                                        .fill(Color.black)
                                        .frame(
                                            width: lineIndex == getContentLines() - 1 ? cardSize.width * 0.6 : cardSize.width * 0.8,
                                            height: 1
                                        )
                                    Spacer()
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                    
                    HStack {
                        Text(recording.title.prefix(recording.duration < 30 ? 8 : (recording.duration < 180 ? 12 : 15)))
                            .font(.system(size: recording.duration < 30 ? 12 : (recording.duration < 180 ? 14 : 16), weight: .medium))
                            .foregroundColor(.black)
                        Spacer()
                        Circle()
                            .fill(Color.black)
                            .frame(
                                width: recording.duration < 30 ? 6 : (recording.duration < 180 ? 8 : 10),
                                height: recording.duration < 30 ? 6 : (recording.duration < 180 ? 8 : 10)
                            )
                    }
                    .padding(.horizontal, recording.duration < 30 ? 12 : (recording.duration < 180 ? 16 : 20))
                    .padding(.bottom, recording.duration < 30 ? 10 : (recording.duration < 180 ? 12 : 14))
                }
            )
            .frame(width: cardSize.width, height: cardSize.height)
            
        }
        .frame(width: cardSize.width, height: cardSize.height) // Fixed height - no change for delete mode
        .scaleEffect(isInDeleteMode ? 1.05 : (isPressed ? 0.96 : (isPlaying ? 1.03 : 1.0))) 
        .opacity(deleteModCardId != nil && !isInDeleteMode ? 0.5 : 1.0) // Dim non-selected cards more
        .zIndex(isInDeleteMode ? 2000 : (isPlaying ? 10 : 1))
        .shadow(color: isInDeleteMode ? Color.red.opacity(0.25) : (isPlaying ? Color.black.opacity(0.25) : Color.black.opacity(0.1)), 
                radius: isInDeleteMode ? 14 : (isPlaying ? 10 : 5), 
                x: 0, 
                y: isInDeleteMode ? 8 : (isPlaying ? 5 : 2))
        .offset(y: isPlaying && !isInDeleteMode ? -3 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isInDeleteMode)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isPressed)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPlaying)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: deleteModCardId)
        .onTapGesture {
            if deleteModCardId != nil && !isInDeleteMode {
                // Exit delete mode when tapping other cards
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    deleteModCardId = nil
                }
            } else if isInDeleteMode {
                // Exit delete mode when tapping selected card
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    deleteModCardId = nil
                }
            } else {
                // Single tap to open detail view
                onTapToDetail(recording)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed && !isInDeleteMode && deleteModCardId == nil {
                        // Start long press timer
                        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                            // Haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.prepare()
                            impactFeedback.impactOccurred()
                            
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                deleteModCardId = recording.id
                            }
                        }
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    // Cancel timer and reset pressed state
                    longPressTimer?.invalidate()
                    longPressTimer = nil
                    if !isInDeleteMode {
                        withAnimation(.interpolatingSpring(stiffness: 400, damping: 35)) {
                            isPressed = false
                        }
                    }
                }
        )
        }
    }
    
    func getWaveformBars() -> Int {
        if recording.duration < 30 { return 10 }
        else if recording.duration < 180 { return 20 }
        else { return 30 }
    }
    
    func getWaveformRange() -> ClosedRange<CGFloat> {
        if recording.duration < 30 { return 6...16 }
        else if recording.duration < 180 { return 10...25 }
        else { return 15...35 }
    }
    
    func getContentLines() -> Int {
        if recording.duration < 180 { return 3 }
        else { return 5 }
    }
    
    func getAnimatedWaveformHeight(for barIndex: Int) -> CGFloat {
        let baseRange = getWaveformRange()
        if isPlaying {
            // Animated heights when playing
            let randomMultiplier = CGFloat.random(in: 0.5...1.2)
            return baseRange.upperBound * randomMultiplier
        } else {
            // Static heights when not playing
            return CGFloat.random(in: baseRange)
        }
    }
    
    func playRecording() {
        // If already playing this recording, stop it
        if isPlaying {
            audioPlayer?.stop()
            currentlyPlayingId = nil
            return
        }
        
        // Stop any other playing audio
        audioPlayer?.stop()
        
        // 🔧 优先使用本地文件，立即响应
        if let localURL = recording.localURL {
            print("🎵 使用本地文件播放: \(localURL.path)")
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: localURL)
                audioPlayer?.play()
                currentlyPlayingId = recording.id
                print("✅ 本地播放成功")
                return // 立即返回，不尝试网络播放
            } catch {
                print("❌ 本地播放失败，尝试网络播放: \(error)")
            }
        }
        
        // 只有本地文件不存在或播放失败时才尝试网络播放
        if recording.remoteURL != nil {
            // Get fresh signed URL and play remote audio
            Task {
                do {
                    // Get fresh signed URL to avoid expiration issues
                    let freshURL = try await SupabaseManager.shared.getFreshAudioURL(for: recording)
                    guard let url = URL(string: freshURL) else { return }
                    
                    let (data, _) = try await URLSession.shared.data(from: url)
                    
                    await MainActor.run {
                        do {
                            audioPlayer = try AVAudioPlayer(data: data)
                            audioPlayer?.play()
                            currentlyPlayingId = recording.id
                        } catch {
                            print("❌ Failed to play audio data: \(error)")
                        }
                    }
                } catch {
                    print("Failed to get fresh URL or download audio: \(error)")
                }
            }
        }
    }
    
}

// Simple blur view for water-like effect
struct BlurView: UIViewRepresentable {
    var style: UIBlurEffect.Style
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style))
        return view
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}


extension View {
    func testButtonStyle() -> some View {
        self
            .foregroundColor(.black)
            .font(.system(size: 14, weight: .medium))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
    }
    
    func testOptionButtonStyle(isActive: Bool = false) -> some View {
        self
            .foregroundColor(isActive ? .white : .black)
            .font(.system(size: 12, weight: .medium))
            .frame(width: 40, height: 40)
            .background(isActive ? Color.red : Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black, lineWidth: 1)
            )
    }
}

#Preview {
    ContentView2()
}

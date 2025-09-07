import SwiftUI

// Web分享页面 - 任何载体都能通过浏览器访问的在线分享
struct WebShareView: View {
    let recording: AudioRecording
    let shareType: AudioDetailView.ShareType
    @State private var shareURL: String = ""
    @State private var isGenerating: Bool = false
    @State private var showCopyFeedback: Bool = false
    
    var body: some View {
        ZStack {
            // 背景
            Color.white.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 30) {
                    // 标题
                    VStack(spacing: 8) {
                        Image(systemName: "globe")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(.black)
                        
                        Text("在线分享")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.black)
                        
                        Text("生成\(shareType.rawValue)，可在任何设备浏览器访问")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 40)
                    
                    // 预览卡片
                    VStack(spacing: 20) {
                        // 录音信息
                        HStack(spacing: 15) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.05))
                                    .frame(width: 60, height: 60)
                                
                                Image(systemName: "waveform")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundColor(.black)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recording.title)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.black)
                                    .lineLimit(2)
                                
                                Text("时长: \(formatDuration(recording.duration))")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                        
                        // Web页面预览
                        WebPagePreview(recording: recording)
                    }
                    .padding(.horizontal, 20)
                    
                    // URL生成区域
                    VStack(spacing: 16) {
                        HStack {
                            Text("分享链接")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                            Spacer()
                        }
                        
                        if isGenerating {
                            // 生成中状态
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("正在生成分享链接...")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                            .padding()
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(12)
                            
                        } else if !shareURL.isEmpty {
                            // 已生成链接
                            VStack(spacing: 12) {
                                HStack {
                                    Text(shareURL)
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                    
                                    Button(action: copyURL) {
                                        Image(systemName: showCopyFeedback ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 16))
                                            .foregroundColor(showCopyFeedback ? .green : .black)
                                            .frame(width: 40, height: 40)
                                            .background(Color.white)
                                            .cornerRadius(8)
                                            .shadow(color: .black.opacity(0.1), radius: 2)
                                    }
                                }
                                
                                // 分享选项
                                HStack(spacing: 12) {
                                    ShareButton(
                                        title: "微信",
                                        icon: "message.fill",
                                        color: .green,
                                        action: { shareToWeChat() }
                                    )
                                    
                                    ShareButton(
                                        title: "QQ",
                                        icon: "bubble.left.and.bubble.right.fill",
                                        color: .blue,
                                        action: { shareToQQ() }
                                    )
                                    
                                    ShareButton(
                                        title: "邮件",
                                        icon: "envelope.fill",
                                        color: .orange,
                                        action: { shareToEmail() }
                                    )
                                    
                                    ShareButton(
                                        title: "更多",
                                        icon: "square.and.arrow.up",
                                        color: .gray,
                                        action: { shareToMore() }
                                    )
                                }
                            }
                            
                        } else {
                            // 未生成状态
                            Button(action: generateShareURL) {
                                HStack(spacing: 8) {
                                    Image(systemName: "link")
                                        .font(.system(size: 16, weight: .medium))
                                    
                                    Text("生成分享链接")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.black)
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // 功能说明
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                            
                            Text("分享说明")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.black)
                            
                            Spacer()
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureItem(
                                icon: "checkmark.circle",
                                text: "任何设备浏览器都能访问"
                            )
                            FeatureItem(
                                icon: "checkmark.circle",
                                text: "包含录音播放和文字内容"
                            )
                            FeatureItem(
                                icon: "checkmark.circle",
                                text: "无需安装App即可查看"
                            )
                            FeatureItem(
                                icon: "checkmark.circle",
                                text: "链接永久有效"
                            )
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
            }
        }
        .onAppear {
            // 检查是否已有分享链接
            checkExistingShareURL()
        }
    }
    
    // MARK: - Functions
    
    func generateShareURL() {
        isGenerating = true
        
        Task {
            do {
                // 生成Web分享页面URL
                let webURL = try await createWebSharePage()
                
                await MainActor.run {
                    withAnimation(.spring()) {
                        self.shareURL = webURL
                        self.isGenerating = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    print("❌ 分享链接生成失败: \(error)")
                }
            }
        }
    }
    
    func createWebSharePage() async throws -> String {
        // 确保录音已上传到Supabase
        guard let supabaseId = recording.supabaseId else {
            throw NSError(domain: "WebShare", code: 1, userInfo: [NSLocalizedDescriptionKey: "录音未上传到云端"])
        }
        
        // 获取Supabase项目URL和Edge Function URL
        let projectRef = "wfxlihpxeeyjlllvoypa"
        let baseURL = "https://\(projectRef).supabase.co"
        
        // 使用部署的Edge Function生成分享链接，包含分享类型参数
        let shareTypeParam = getShareTypeParam()
        let shareURL = "\(baseURL)/functions/v1/share-page?id=\(supabaseId)&type=\(shareTypeParam)"
        
        return shareURL
    }
    
    func getShareTypeParam() -> String {
        switch shareType {
        case .summary: return "summary"
        case .audio: return "audio"
        case .combined: return "combined"
        }
    }
    
    func generateHTMLContent() -> String {
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(recording.title) - 点点滴滴</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body { 
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; 
                    background: #fff; color: #000; line-height: 1.6; padding: 20px; 
                }
                .container { max-width: 600px; margin: 0 auto; }
                .header { text-align: center; margin-bottom: 30px; }
                .title { font-size: 24px; font-weight: bold; margin-bottom: 10px; }
                .meta { color: #666; font-size: 14px; }
                .audio-player { 
                    background: #f5f5f5; padding: 20px; border-radius: 12px; 
                    text-align: center; margin-bottom: 30px; 
                }
                .content { background: #f9f9f9; padding: 20px; border-radius: 12px; }
                .footer { text-align: center; margin-top: 30px; color: #999; font-size: 12px; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1 class="title">\(recording.title)</h1>
                    <div class="meta">时长: \(formatDuration(recording.duration)) | 录制时间: \(formatDate(recording.timestamp))</div>
                </div>
                
                <div class="audio-player">
                    <audio controls style="width: 100%; max-width: 400px;">
                        <source src="\(recording.remoteURL ?? "")" type="audio/mp4">
                        您的浏览器不支持音频播放。
                    </audio>
                </div>
                
                <div class="content">
                    <h3>录音摘要</h3>
                    <p>这里显示AI生成的摘要和转录内容...</p>
                </div>
                
                <div class="footer">
                    <p>来自 点点滴滴 App</p>
                </div>
            </div>
        </body>
        </html>
        """
    }
    
    func checkExistingShareURL() {
        // 检查是否已有现成的分享链接
        // 可以从Supabase或缓存中加载
    }
    
    func copyURL() {
        UIPasteboard.general.string = shareURL
        
        withAnimation(.spring()) {
            showCopyFeedback = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring()) {
                showCopyFeedback = false
            }
        }
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    func shareToWeChat() {
        // 分享到微信
        shareURL(to: "wechat")
    }
    
    func shareToQQ() {
        // 分享到QQ
        shareURL(to: "qq")
    }
    
    func shareToEmail() {
        // 分享到邮件
        shareURL(to: "email")
    }
    
    func shareToMore() {
        // 更多分享选项
        let activityVC = UIActivityViewController(activityItems: [shareURL], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
    
    func shareURL(to platform: String) {
        guard let url = URL(string: shareURL) else { return }
        UIApplication.shared.open(url)
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
}

// MARK: - 组件

// Web页面预览组件
struct WebPagePreview: View {
    let recording: AudioRecording
    
    var body: some View {
        VStack(spacing: 0) {
            // 浏览器地址栏
            HStack {
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Circle().fill(Color.yellow).frame(width: 8, height: 8)
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                }
                
                Spacer()
                
                Text("🌐 share.audios.app/\(recording.id.uuidString.prefix(8))...")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.05))
            
            // 网页内容预览
            VStack(spacing: 16) {
                Text(recording.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                
                // 音频播放器预览
                HStack {
                    Image(systemName: "play.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.black)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                    
                    Text(formatDuration(recording.duration))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
                
                // 内容预览
                VStack(alignment: .leading, spacing: 8) {
                    Text("录音摘要")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 2)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 200, height: 2)
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 150, height: 2)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 16)
            .background(Color.white)
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
    
    func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// 分享按钮组件
struct ShareButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black)
            }
        }
    }
}

// 功能特性项目组件
struct FeatureItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.green)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.black.opacity(0.8))
            
            Spacer()
        }
    }
}

// 预览
struct WebShareView_Previews: PreviewProvider {
    static var previews: some View {
        WebShareView(
            recording: AudioRecording(
                duration: 125,
                title: "咖啡厅的午后对话",
                timestamp: Date()
            ),
            shareType: .combined
        )
    }
}
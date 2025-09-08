# 音频分享系统技术实现文档

## 概述

本文档记录了iOS音频录音应用的Web分享功能的完整技术实现方案，包括双线部署、智能路由、微信兼容性等核心技术。

## 系统架构

### 双服务器部署

为了解决中国大陆访问限制问题，采用了双服务器架构：

```
iOS App → 腾讯云服务器 → 智能IP检测 → 路由到最优服务器
                    ↓
          中国用户：腾讯云 (124.221.156.222)
          国际用户：Vercel (audio-share-nu.vercel.app)
```

### 服务器配置

#### 1. 腾讯云服务器（中国用户）
- **地址**: `http://124.221.156.222`
- **服务**: Nginx静态文件服务
- **部署方式**: SCP手动部署
- **配置文件**: `/etc/nginx/sites-available/default`

```nginx
server {
    listen 80 default_server;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;
    
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

#### 2. Vercel服务器（国际用户）
- **地址**: `https://audio-share-nu.vercel.app`
- **服务**: Edge网络CDN
- **部署方式**: Git自动部署
- **配置文件**: `vercel.json`

```json
{
  "rewrites": [
    { "source": "/(.*)", "destination": "/index.html" }
  ],
  "headers": [
    {
      "source": "/index.html",
      "headers": [
        {
          "key": "Cache-Control",
          "value": "public, max-age=0, must-revalidate"
        }
      ]
    }
  ]
}
```

## 智能路由实现

### IP地理位置检测

使用客户端JavaScript检测访问者地理位置，实现智能路由：

```javascript
// 简单的非中国用户重定向（微信兼容）
if (window.location.hostname === '124.221.156.222') {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', 'https://ipinfo.io/country', true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            var country = xhr.responseText.trim();
            if (country !== 'CN') {
                var currentUrl = window.location.href;
                var vercelUrl = currentUrl.replace(
                    'http://124.221.156.222', 
                    'https://audio-share-nu.vercel.app'
                );
                window.location.href = vercelUrl;
                return;
            }
        }
        // 中国用户或检测失败，直接启动应用
        init();
    };
    xhr.send();
} else {
    // 直接在Vercel服务器，启动应用
    init();
}
```

### 为什么使用XMLHttpRequest

由于微信内置浏览器的限制，现代的`fetch` API和`async/await`语法可能导致崩溃。因此采用传统的XMLHttpRequest确保兼容性。

## 微信分享预览图实现

### 关键技术点

#### 1. Meta标签顺序至关重要

微信解析器对meta标签的位置非常敏感，Open Graph标签必须在viewport之前：

```html
<head>
    <meta charset="UTF-8">
    <!-- Open Graph Meta Tags MUST be first for WeChat -->
    <meta property="og:title" content="音频录音分享" id="og-title" />
    <meta property="og:description" content="点击查看音频录音的详细内容" id="og-description" />
    <meta property="og:type" content="website" />
    <meta property="og:image" content="https://audio-share-nu.vercel.app/clean-preview.png" id="og-image" />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta property="og:url" content="https://audio-share-nu.vercel.app/" id="og-url" />
    <meta property="og:site_name" content="Audio Share" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title id="page-title">音频分享 - Audio Share</title>
    
    <!-- 多平台兼容标签 -->
    <meta name="twitter:card" content="summary_large_image" />
    <link rel="image_src" href="https://audio-share-nu.vercel.app/clean-preview.png" />
    <meta itemprop="image" content="https://audio-share-nu.vercel.app/clean-preview.png" />
</head>
```

#### 2. 预览图规格

- **尺寸**: 1200x630像素（Open Graph标准）
- **格式**: PNG（更好的压缩和质量）
- **内容**: 简洁的英文文字，避免中文字符显示问题
- **设计**: 黑白风格，符合应用整体设计

#### 3. 缓存处理策略

微信有强烈的缓存机制，解决方案：

**iOS端添加版本参数**:
```swift
// 添加版本参数强制微信刷新缓存
let version = Int(Date().timeIntervalSince1970)
return "\(baseURL)?id=\(supabaseId)&type=\(shareTypeParam)&v=\(version)"
```

**服务器端缓存控制**:
```http
Cache-Control: public, max-age=0, must-revalidate
```

## iOS端实现

### 分享URL生成

```swift
private func generateShareURL(for shareType: ShareType) -> String {
    guard let supabaseId = recording.supabaseId else {
        return "录音未上传到云端"
    }
    
    // 使用腾讯云作为主入口，网页端会根据访问者IP智能重定向
    let baseURL = "http://124.221.156.222"
    
    let shareTypeParam = getShareTypeParam(for: shareType)
    // 添加版本参数强制微信刷新缓存
    let version = Int(Date().timeIntervalSince1970)
    return "\(baseURL)?id=\(supabaseId)&type=\(shareTypeParam)&v=\(version)"
}
```

### 富链接预览

```swift
@available(iOS 13.0, *)
func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
    let metadata = LPLinkMetadata()
    metadata.originalURL = url
    metadata.title = title
    
    // 使用与网页一致的预览图
    if let imageURL = URL(string: "https://audio-share-nu.vercel.app/clean-preview.png") {
        metadata.imageProvider = NSItemProvider(contentsOf: imageURL)
    }
    
    return metadata
}
```

## Web端实现

### 页面结构

采用单页面应用(SPA)架构，包含：

1. **音频播放器**：波形可视化、进度条、播放控制
2. **内容展示**：AI摘要、转录文本
3. **响应式设计**：适配移动端和桌面端

### 数据获取

```javascript
// 使用XMLHttpRequest确保微信兼容性
function fetchRecordingData(id) {
    const xhr = new XMLHttpRequest();
    const url = SUPABASE_URL + '/rest/v1/audio_records?id=eq.' + id + '&select=id,audio_url,duration,created_at,summary,transcription';
    
    xhr.open('GET', url, true);
    xhr.setRequestHeader('apikey', SUPABASE_ANON_KEY);
    xhr.setRequestHeader('Authorization', 'Bearer ' + SUPABASE_ANON_KEY);
    xhr.setRequestHeader('Content-Type', 'application/json');
    
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            const data = JSON.parse(xhr.responseText);
            if (data && data.length > 0) {
                displayRecordingData(data[0]);
            }
        }
    };
    
    xhr.send();
}
```

### 动态内容更新

```javascript
function displayRecordingData(data) {
    // 更新页面元数据 - 简单格式: 时间：内容
    const contentText = data.summary && data.summary.trim() ? data.summary : '音频录音';
    const simpleTitle = formatDate(data.created_at) + '：' + contentText;
    
    // 动态更新所有相关标签
    document.getElementById('page-title').textContent = simpleTitle;
    document.getElementById('og-title').setAttribute('content', simpleTitle);
    document.getElementById('header-title').textContent = simpleTitle;
}
```

## 部署流程

### 1. 腾讯云部署

```bash
# 上传HTML文件
scp -i audioshare.pem /path/to/index.html root@124.221.156.222:/usr/share/nginx/html/

# 上传预览图
scp -i audioshare.pem /path/to/clean-preview.png root@124.221.156.222:/usr/share/nginx/html/
```

### 2. Vercel部署

```bash
# 提交到Git仓库，触发自动部署
git add .
git commit -m "Update sharing functionality"
git push origin main
```

## 调试和监控

### 预览图验证

```bash
# 检查图片可访问性
curl -I "http://124.221.156.222/clean-preview.png"
curl -I "https://audio-share-nu.vercel.app/clean-preview.png"

# 验证meta标签
curl -s "http://124.221.156.222" | grep -E '<title|og:title|og:image'
```

### 微信调试

1. **微信开发者工具**：验证页面在微信环境下的表现
2. **微信缓存清理**：使用不同的URL参数强制刷新
3. **IP检测测试**：使用VPN测试不同地区的路由逻辑

## 已知问题和解决方案

### 问题1：微信缓存顽固
**解决方案**：每次分享生成唯一URL参数

### 问题2：中文字体渲染问题
**解决方案**：预览图使用英文，避免字体兼容性问题

### 问题3：async/await导致微信崩溃
**解决方案**：使用传统XMLHttpRequest替代现代JavaScript语法

### 问题4：IP检测服务限制
**解决方案**：多个IP检测服务备选，优雅降级

## 性能优化

1. **图片优化**：预览图使用PNG格式，平衡质量和大小
2. **缓存策略**：静态资源长期缓存，HTML短期缓存
3. **CDN加速**：Vercel提供全球边缘节点
4. **代码压缩**：生产环境移除调试代码

## 安全考虑

1. **HTTPS强制**：Vercel强制使用HTTPS
2. **CORS配置**：适当的跨域资源共享设置
3. **API密钥**：使用匿名密钥，限制访问权限
4. **输入验证**：URL参数验证和清理

## 维护指南

### 定期检查项
- [ ] 预览图可访问性
- [ ] IP检测服务状态
- [ ] SSL证书有效期
- [ ] 服务器磁盘空间

### 更新流程
1. 本地测试
2. 腾讯云服务器测试
3. Vercel部署
4. 微信环境验证
5. iOS应用测试

---

*文档更新时间: 2025年1月8日*  
*技术栈: iOS (Swift) + Node.js/Static HTML + Nginx + Vercel*
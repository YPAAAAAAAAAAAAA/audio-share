# 音频分享页面部署指南

这是一个完全静态的HTML页面，用于公开分享音频录音。

## 🚀 部署选项

### 方案1：Vercel (推荐)
```bash
# 1. 在Vercel中创建新项目
# 2. 连接到你的Git仓库
# 3. 设置构建目录为 public-share
# 4. 部署完成后获得URL: https://your-project.vercel.app
```

### 方案2：Netlify
```bash
# 1. 在Netlify中拖拽 public-share 文件夹
# 2. 或者连接Git仓库，设置构建目录
# 3. 获得URL: https://your-project.netlify.app
```

### 方案3：GitHub Pages
```bash
# 1. 将 public-share 内容放到 gh-pages 分支
# 2. 启用GitHub Pages
# 3. 获得URL: https://username.github.io/repository
```

### 方案4：阿里云OSS/腾讯云COS
```bash
# 1. 上传index.html到OSS存储桶
# 2. 开启静态网站托管
# 3. 配置自定义域名(可选)
```

## 🔧 配置

部署完成后，需要在iOS App中更新分享URL：

```swift
// 在AudioDetailView.swift中修改
func generateWebPageURL(for shareType: ShareType) async -> String {
    let baseURL = "https://your-deployed-url.com"  // 改为你的域名
    return "\(baseURL)?id=\(supabaseId)&type=\(shareTypeParam)"
}
```

## ✨ 特性

- ✅ **完全公开** - 无需任何授权，任何人都能访问
- ✅ **SEO优化** - 支持搜索引擎和社交媒体预览
- ✅ **响应式设计** - 完美适配手机和桌面
- ✅ **音频播放** - 支持进度控制和波形动画
- ✅ **三种模式** - summary/audio/combined
- ✅ **快速加载** - 静态页面，加载极快

## 📱 URL格式

```
https://your-domain.com?id=RECORDING_ID&type=TYPE

参数说明：
- id: 录音的Supabase ID
- type: summary (仅文本) | audio (仅音频) | combined (完整)
```

## 🔒 安全说明

页面使用Supabase的匿名(anon)密钥访问数据，确保：
1. 数据库RLS策略正确配置
2. 只允许读取已发布的录音
3. 敏感信息不会暴露
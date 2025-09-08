#!/bin/bash

# 服务器信息
SERVER_IP="124.221.156.222"
SERVER_USER="root"
LOCAL_DIR="/Users/li/Desktop/audios/public-share"
REMOTE_DIR="/var/www/html"

echo "📦 正在打包文件..."
cd /Users/li/Desktop/audios
tar -czf public-share.tar.gz public-share/

echo "📤 上传到服务器..."
scp public-share.tar.gz ${SERVER_USER}@${SERVER_IP}:/tmp/

echo "🚀 在服务器上部署..."
ssh ${SERVER_USER}@${SERVER_IP} << 'EOF'
# 安装 Nginx
echo "Installing Nginx..."
dnf install -y nginx

# 创建网站目录
mkdir -p /var/www/html

# 解压文件
cd /tmp
tar -xzf public-share.tar.gz
cp -r public-share/* /var/www/html/

# 配置 Nginx
cat > /etc/nginx/conf.d/audio-share.conf << 'NGINX'
server {
    listen 80;
    server_name _;
    root /var/www/html;
    index index.html;
    
    location / {
        try_files $uri $uri/ /index.html;
    }
    
    # 允许跨域访问
    add_header Access-Control-Allow-Origin *;
    add_header Access-Control-Allow-Methods 'GET, POST, OPTIONS';
    add_header Access-Control-Allow-Headers 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';
}
NGINX

# 设置权限
chown -R nginx:nginx /var/www/html
chmod -R 755 /var/www/html

# 关闭 SELinux (如果启用)
setenforce 0 2>/dev/null || true

# 配置防火墙
firewall-cmd --permanent --add-service=http 2>/dev/null || true
firewall-cmd --permanent --add-service=https 2>/dev/null || true
firewall-cmd --reload 2>/dev/null || true

# 启动 Nginx
systemctl enable nginx
systemctl restart nginx

echo "✅ 部署完成！"
echo "🌐 访问地址: http://${SERVER_IP}"
EOF

echo "🎉 部署成功！"
echo "📱 网站地址: http://${SERVER_IP}"
echo ""
echo "在iOS应用中使用这个URL:"
echo "http://${SERVER_IP}/index.html?id=RECORDING_ID"

# 清理临时文件
rm -f public-share.tar.gz
# 毛恬昕 · 视觉设计作品集

网页与完整原图保存在同一仓库。浏览页面使用响应式 WebP 预览，放大和“查看原图”使用原始 PNG/JPG。已有文件的尺寸和字节内容均保留。

## 更新

1. 更新 index.html 中的项目资料，并将原图放入 assets。
2. 在本地安装 Python 3 与 Pillow，然后执行 python3 scripts/optimize-site.py。
3. 检查页面后提交到 main。GitHub Pages 按已有配置自动发布。

优化脚本用 SHA-256 命名提取出的内嵌图片，保留全部原文件。已有预览继续使用，缺少预览的大图会生成独立 WebP，项目目录的原图路径保持可用。请勿使用旧脚本删除原文件。

## 可选服务器自动部署

scripts/deploy-portfolio.sh 适用于 Linux，依赖 bash、git、curl、tar、timeout、flock、diff 和 Python 3。默认拉取本仓库 main，按查到的完整提交 SHA 下载与校验。它不会在服务器上重新压缩图片。

设置 SITE_DIR、STATE_DIR 和 HEALTHCHECK_URL 后运行。HTTP 检查失败会恢复上一版本，成功后才记录提交 SHA。未设置 HEALTHCHECK_URL 时只做本地资源校验。GitHub 直连优先，镜像作为传输后备。

webroot 必须不存在，或是指向 releases 下版本目录的符号链接。若现有部署使用真实目录，须先备份并完成 webroot 迁移，再启用脚本。网站服务器应指向 SITE_DIR/webroot。

例如，将经审查的部署脚本安装在独立、可写的运维目录后，在 crontab 中添加以下内容，并替换目录与网址。

```cron
*/10 * * * * SITE_DIR=/opt/www/host/mao-portfolio STATE_DIR=/opt/portfolio-state HEALTHCHECK_URL=https://example.com/ /bin/bash /opt/portfolio-tools/deploy-portfolio.sh >> /opt/portfolio-state/deploy.log 2>&1
```

域名解析、Web 服务器配置与 HTTPS 证书需要在托管端设置。仓库中的脚本不会自动修改远端服务器配置。

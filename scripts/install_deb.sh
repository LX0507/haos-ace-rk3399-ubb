#!/bin/bash
set -e  # 任何命令失败则退出

mkdir -p cache

# ============================================================
# assismgr 已禁用 (Build #26)
# 原因: assismgr 是 vendor 自定义服务，依赖 MQTT broker (127.0.0.1:1883)
#   和 USB 串口设备 (/dev/ttyGS)，在 HAOS 中均不存在。
#   服务在 :4000 端口启动但无法正常工作，每 10 秒刷屏日志。
#   如需启用，取消下方注释即可。
# ============================================================

# 清理之前构建中可能残留的 assismgr 文件
ASSISMGR_DIRS=(
  "haos-overlay/buildroot-external/rootfs-overlay/usr/bin/assismgr"
  "haos-overlay/buildroot-external/rootfs-overlay/usr/lib/systemd/system/assismgr.service"
  "haos-overlay/buildroot-external/rootfs-overlay/etc/assismgr"
  "haos-overlay/buildroot-external/rootfs-overlay/usr/lib/systemd/system/multi-user.target.wants/assismgr.service"
)
for f in "${ASSISMGR_DIRS[@]}"; do
  if [ -e "$f" ] || [ -L "$f" ]; then
    echo "清理残留: $f"
    rm -rf "$f"
  fi
done

echo "ℹ️  assismgr 已禁用 (不适用于 HAOS)"
echo "✅ install_deb.sh 完成"

# ============================================================
# 如需重新启用 assismgr，取消以下注释:
# ============================================================
# download_assismgr() {
#   local max_retries=3
#   local count=0
#   while [ $count -lt $max_retries ]; do
#     count=$((count+1))
#     echo "尝试获取 assismgr 最新版本 (第 $count/$max_retries 次)..."
#     
#     ASSISMGER_LATEST_VERSION=$(curl -s https://api.github.com/repos/LanSilence/assismgr/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
#     
#     if [ -n "$ASSISMGER_LATEST_VERSION" ]; then
#       echo "最新版本: $ASSISMGER_LATEST_VERSION"
#       echo "下载 assismgr_${ASSISMGER_LATEST_VERSION}_arm64.deb..."
#       wget -O cache/assismgr.deb "https://github.com/LanSilence/assismgr/releases/download/${ASSISMGER_LATEST_VERSION}/assismgr_${ASSISMGER_LATEST_VERSION}_arm64.deb"
#       if [ -f cache/assismgr.deb ]; then
#         echo "✅ assismgr.deb 下载成功"
#         return 0
#       fi
#     fi
#     
#     echo "⚠️ 第 $count 次尝试失败，等待 10s 后重试..."
#     sleep 10
#   done
#   
#   echo "❌ assismgr.deb 下载失败（已重试 $max_retries 次）"
#   return 1
# }
# 
# if [ ! -f cache/assismgr.deb ]; then
#   download_assismgr
# fi
# 
# echo "解包 assismgr.deb 到 rootfs-overlay..."
# dpkg -x cache/assismgr.deb haos-overlay/buildroot-external/rootfs-overlay/

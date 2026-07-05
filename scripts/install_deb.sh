#!/bin/bash
set -e  # 任何命令失败则退出

mkdir -p cache

# 带重试的下载函数
download_assismgr() {
  local max_retries=3
  local count=0
  while [ $count -lt $max_retries ]; do
    count=$((count+1))
    echo "尝试获取 assismgr 最新版本 (第 $count/$max_retries 次)..."
    
    ASSISMGER_LATEST_VERSION=$(curl -s https://api.github.com/repos/LanSilence/assismgr/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    
    if [ -n "$ASSISMGER_LATEST_VERSION" ]; then
      echo "最新版本: $ASSISMGER_LATEST_VERSION"
      echo "下载 assismgr_${ASSISMGER_LATEST_VERSION}_arm64.deb..."
      wget -O cache/assismgr.deb "https://github.com/LanSilence/assismgr/releases/download/${ASSISMGER_LATEST_VERSION}/assismgr_${ASSISMGER_LATEST_VERSION}_arm64.deb"
      if [ -f cache/assismgr.deb ]; then
        echo "✅ assismgr.deb 下载成功"
        return 0
      fi
    fi
    
    echo "⚠️ 第 $count 次尝试失败，等待 10s 后重试..."
    sleep 10
  done
  
  echo "❌ assismgr.deb 下载失败（已重试 $max_retries 次）"
  return 1
}

if [ ! -f cache/assismgr.deb ]; then
  download_assismgr
fi

echo "解包 assismgr.deb 到 rootfs-overlay..."
dpkg -x cache/assismgr.deb haos-overlay/buildroot-external/rootfs-overlay/
echo "✅ install_deb.sh 完成"
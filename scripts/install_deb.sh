#!/bin/bash
set -e  # 任何命令失败则退出

mkdir -p cache

# ============================================================
# assismgr 后台管理 (http://homeassistant.local:4000)
# 来源: https://github.com/LanSilence/assismgr
#
# MQTT 依赖说明: assismgr 依赖 MQTT broker (127.0.0.1:1883)，
#   在 HAOS 中需通过 Supervisor → 加载项商店 安装 Mosquitto broker。
#   USB 串口 (/dev/ttyGS) 告警不影响 Web UI 正常使用。
# ============================================================

# GitHub 下载加速镜像（国内网络优先用镜像，失败回退官方源）
GITHUB_MIRRORS=(
  "https://gh.con.sh/https://github.com"           # 国内 GitHub 加速
  "https://ghproxy.com/https://github.com"         # ghproxy 加速
  "https://github.com"                             # 官方源（备用）
)

download_file() {
  local url="$1"
  local output="$2"
  local max_retries=2

  for attempt in $(seq 1 $max_retries); do
    if wget -q --timeout=30 --tries=2 -O "$output" "$url" 2>/dev/null; then
      if [ -s "$output" ]; then
        return 0
      fi
    fi
    [ $attempt -lt $max_retries ] && sleep 3
  done
  return 1
}

download_assismgr() {
  local max_retries=3
  local count=0

  while [ $count -lt $max_retries ]; do
    count=$((count+1))
    echo "获取 assismgr 最新版本 (第 $count/$max_retries 次)..."

    # 获取最新版本号（通过 GitHub API，使用镜像加速）
    ASSISMGER_LATEST_VERSION=""
    for mirror in "${GITHUB_MIRRORS[@]}"; do
      local api_url="${mirror}/LanSilence/assismgr/releases/latest"
      ASSISMGER_LATEST_VERSION=$(curl -sL "$api_url" 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
      if [ -n "$ASSISMGER_LATEST_VERSION" ]; then
        echo "  最新版本: $ASSISMGER_LATEST_VERSION (via ${mirror%%/*})"
        break
      fi
    done

    if [ -z "$ASSISMGER_LATEST_VERSION" ]; then
      echo "  ⚠️ 无法获取版本号，等待 10s 后重试..."
      sleep 10
      continue
    fi

    local deb_name="assismgr_${ASSISMGER_LATEST_VERSION}_arm64.deb"
    echo "  下载 $deb_name ..."

    # 尝试从多个镜像下载
    local downloaded=0
    for mirror in "${GITHUB_MIRRORS[@]}"; do
      local download_url="${mirror}/LanSilence/assismgr/releases/download/${ASSISMGER_LATEST_VERSION}/${deb_name}"
      echo "    尝试: $download_url"
      if download_file "$download_url" "cache/assismgr.deb"; then
        echo "  ✅ assismgr.deb 下载成功"
        downloaded=1
        break
      fi
    done

    if [ $downloaded -eq 1 ]; then
      return 0
    fi

    echo "  ⚠️ 第 $count 次尝试失败，等待 10s 后重试..."
    sleep 10
  done

  echo "❌ assismgr.deb 下载失败（已重试 $max_retries 次）"
  echo "   请手动下载到 cache/assismgr.deb 后重新构建"
  return 1
}

if [ ! -f cache/assismgr.deb ]; then
  download_assismgr
fi

echo "解包 assismgr.deb 到 rootfs-overlay..."
dpkg -x cache/assismgr.deb haos-overlay/buildroot-external/rootfs-overlay/

# 清理之前构建中可能残留的旧版 assismgr 文件（从禁用期间）
ASSISMGR_STALE=(
  "haos-overlay/buildroot-external/rootfs-overlay/etc/assismgr"
)
for f in "${ASSISMGR_STALE[@]}"; do
  if [ -e "$f" ] || [ -L "$f" ]; then
    echo "清理旧残留: $f"
    rm -rf "$f"
  fi
done

echo "✅ install_deb.sh 完成 (assismgr 已启用)"

#!/bin/bash
# assismgr + hamqtt 安装脚本
# assismgr: 后台管理 Web UI (http://homeassistant.local:4000)
# hamqtt:   MQTT 客户端库（已编译进 assismgr 二进制，无需单独安装）
#
# MQTT 依赖: assismgr 连接 127.0.0.1:1883，需在 HAOS 中安装 Mosquitto addon
# USB 串口: /dev/ttyGS 告警不影响 Web UI 正常使用

# 不使用 set -e — assismgr 下载失败不应中断构建
mkdir -p cache

# ============================================================
# GitHub 下载加速镜像（国内优先，失败回退官方源）
# ============================================================
GITHUB_MIRRORS=(
  "https://gh.con.sh/https://github.com"
  "https://ghproxy.com/https://github.com"
  "https://github.com"
)

# 检测可用的下载工具 (wget 总是可用, curl 可选)
if command -v wget &>/dev/null; then
  download_tool() { wget -q --timeout=30 --tries=2 -O "$2" "$1"; }
  fetch_api()    { wget -qO- --timeout=15 --tries=1 "$1" 2>/dev/null; }
elif command -v curl &>/dev/null; then
  download_tool() { curl -sL --connect-timeout 15 -o "$2" "$1"; }
  fetch_api()    { curl -sL --connect-timeout 15 "$1" 2>/dev/null; }
else
  echo "⚠️  无 wget/curl，跳过 assismgr 下载"
  exit 0
fi

download_assismgr() {
  local max_retries=3
  local count=0

  while [ $count -lt $max_retries ]; do
    count=$((count+1))
    echo "获取 assismgr 最新版本 (第 $count/$max_retries 次)..."

    # 获取最新版本号（通过 GitHub API + 镜像加速）
    local version=""
    for mirror in "${GITHUB_MIRRORS[@]}"; do
      local api_url="${mirror}/LanSilence/assismgr/releases/latest"
      version=$(fetch_api "$api_url" | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
      if [ -n "$version" ]; then
        echo "  最新版本: $version (via $(echo $mirror | cut -d/ -f3))"
        break
      fi
    done

    if [ -z "$version" ]; then
      echo "  ⚠️ 无法获取版本号，等待 10s 后重试..."
      sleep 10
      continue
    fi

    local deb_name="assismgr_${version}_arm64.deb"
    echo "  下载 $deb_name ..."

    for mirror in "${GITHUB_MIRRORS[@]}"; do
      local dl_url="${mirror}/LanSilence/assismgr/releases/download/${version}/${deb_name}"
      echo "    尝试: $dl_url"
      if download_tool "$dl_url" "cache/assismgr.deb" && [ -s "cache/assismgr.deb" ]; then
        echo "  ✅ assismgr.deb 下载成功"
        return 0
      fi
    done

    echo "  ⚠️ 第 $count 次尝试失败，等待 10s 后重试..."
    sleep 10
  done

  return 1
}

# ============================================================
# 尝试下载 assismgr
# 失败不中断构建 — 设备首次启动后仍可通过后台手动安装
# ============================================================
if [ -f cache/assismgr.deb ]; then
  echo "📦 使用已缓存的 assismgr.deb"
elif download_assismgr; then
  echo "✅ assismgr 下载完成"
else
  echo "⚠️  assismgr.deb 下载失败（网络问题），跳过安装"
  echo "   设备启动后可手动安装: dpkg -i assismgr_*.deb"
  echo "✅ install_deb.sh 完成 (assismgr 未安装)"
  exit 0
fi

echo "解包 assismgr.deb 到 rootfs-overlay..."
dpkg -x cache/assismgr.deb haos-overlay/buildroot-external/rootfs-overlay/

# 清理可能冲突的旧版残留
for f in \
  "haos-overlay/buildroot-external/rootfs-overlay/etc/assismgr"; do
  if [ -e "$f" ] || [ -L "$f" ]; then
    echo "清理旧残留: $f"
    rm -rf "$f"
  fi
done

echo "✅ install_deb.sh 完成 (assismgr 已安装)"

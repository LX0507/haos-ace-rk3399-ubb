#!/bin/bash
# assismgr 后台管理安装脚本
# assismgr 提供 http://homeassistant.local:4000 Web UI
# 来源: https://github.com/LanSilence/assismgr (集成 hamqtt MQTT 客户端库)
#
# MQTT 依赖: 需 Supervisor 加载项商店安装 Mosquitto broker
# USB 串口 /dev/ttyGS 告警不影响 Web UI 使用
#
# assismgr v0.1.8 arm64 deb 已 commit 到 cache/assismgr.deb

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

ASSISMGR_DEB="$REPO_ROOT/cache/assismgr.deb"
ROOTFS="$REPO_ROOT/haos-overlay/buildroot-external/rootfs-overlay"

if [ ! -f "$ASSISMGR_DEB" ] || [ ! -s "$ASSISMGR_DEB" ]; then
  echo "⚠️  $ASSISMGR_DEB 不存在或为空，跳过 assismgr 安装"
  exit 0
fi

# ============================================================
# 解包 deb（dpkg-deb 优先，ar+zstd 兜底，python 终极兜底）
# ============================================================
echo "📦 解包 assismgr.deb 到 rootfs-overlay..."

mkdir -p "$ROOTFS"

if command -v dpkg-deb &>/dev/null; then
  # Debian/Ubuntu 标准方式
  dpkg-deb -x "$ASSISMGR_DEB" "$ROOTFS"
elif command -v ar &>/dev/null && command -v zstd &>/dev/null; then
  # 手动方式
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  ar x "$ASSISMGR_DEB"
  if [ -f data.tar.zst ]; then
    tar --use-compress-program=unzstd -xf data.tar.zst -C "$ROOTFS"
  elif [ -f data.tar.xz ]; then
    tar -xJf data.tar.xz -C "$ROOTFS"
  elif [ -f data.tar.gz ]; then
    tar -xzf data.tar.gz -C "$ROOTFS"
  else
    cd "$REPO_ROOT"
    rm -rf "$TMPDIR"
    echo "❌ 未知 deb 格式（需要 dpkg-deb 或 ar+zstd）"
    exit 1
  fi
  cd "$REPO_ROOT"
  rm -rf "$TMPDIR"
else
  # Python 兜底（用环境变量传路径，避免 Bash 转义问题）
  echo "🐍 使用 Python 兜底解包"
  # 关键：Python 接收 Windows 路径需要 E:\ 格式，/e/ 在 Windows 中不存在
  # 将 /e/Users/... 转换为 E:\Users\...
  if command -v cygpath &>/dev/null; then
    export ASSISMGR_DEB_PATH=$(cygpath -w "$ASSISMGR_DEB")
    export ROOTFS_PATH=$(cygpath -w "$ROOTFS")
  else
    # fallback: 手动转换
    WIN_DEB=$(echo "$ASSISMGR_DEB" | sed 's|^/e/|E:\\|; s|/|\\|g')
    WIN_ROOTFS=$(echo "$ROOTFS" | sed 's|^/e/|E:\\|; s|/|\\|g')
    export ASSISMGR_DEB_PATH="$WIN_DEB"
    export ROOTFS_PATH="$WIN_ROOTFS"
  fi
  echo "   源: $ASSISMGR_DEB_PATH"
  echo "   目标: $ROOTFS_PATH"
  /c/Users/lenovo/.workbuddy/binaries/python/versions/3.13.12/python.exe - <<'PYEOF'
import os, sys, io, struct, tarfile

# 读取环境变量（避免 Windows 路径转义问题）
DEB_PATH = os.environ['ASSISMGR_DEB_PATH']
ROOTFS = os.environ['ROOTFS_PATH']
PYTHONPATH_USER = os.environ.get('PYTHONPATH_USER', '')

# 尝试加载 zstandard，否则手动解压
try:
    import zstandard
    HAS_ZSTD = True
except ImportError:
    HAS_ZSTD = False
    print("WARNING: zstandard not available, will use tar+system tools")

if not os.path.exists(DEB_PATH):
    print(f"ERROR: {DEB_PATH} not found")
    sys.exit(1)

with open(DEB_PATH, 'rb') as f:
    data = f.read()

# 解析 ar 格式
pos = 8  # ar magic
data_tar = None
data_tar_format = None
while pos < len(data):
    if pos + 60 > len(data):
        break
    hdr = data[pos:pos+60]
    name = hdr[:16].decode().strip()
    size = int(hdr[48:58].decode().strip())
    pos += 60
    if name.startswith('data.tar'):
        data_tar = data[pos:pos+size]
        # 检测压缩格式
        if data_tar[:4] == b'\x28\xb5\x2f\xfd':
            data_tar_format = 'zstd'
        elif data_tar[:6] == b'\xfd7zXZ\x00':
            data_tar_format = 'xz'
        elif data_tar[:2] == b'\x1f\x8b':
            data_tar_format = 'gz'
        break
    pos += size
    if pos % 2: pos += 1

if not data_tar:
    print("ERROR: data.tar not found in deb")
    sys.exit(1)

# 解压
if data_tar_format == 'zstd':
    if not HAS_ZSTD:
        print("ERROR: zstd compressed but zstandard module not available")
        sys.exit(1)
    dctx = zstandard.ZstdDecompressor()
    decompressed = dctx.decompress(data_tar, max_output_size=200*1024*1024)
elif data_tar_format == 'xz':
    import lzma
    decompressed = lzma.decompress(data_tar)
elif data_tar_format == 'gz':
    import gzip
    decompressed = gzip.decompress(data_tar)
else:
    decompressed = data_tar  # plain tar

# 解压 tar 到 ROOTFS
tar = tarfile.open(fileobj=io.BytesIO(decompressed))
for m in tar.getmembers():
    # 把 "./etc/..." 转换为 "etc/..."
    rel_name = m.name.lstrip('./').lstrip('/')
    if not rel_name or rel_name == '.':
        continue
    target = os.path.join(ROOTFS, rel_name.replace('/', os.sep))
    if m.isdir():
        os.makedirs(target, exist_ok=True)
    elif m.isfile():
        os.makedirs(os.path.dirname(target), exist_ok=True)
        f = tar.extractfile(m)
        if f is not None:
            with open(target, 'wb') as out:
                out.write(f.read())
            if m.mode:
                os.chmod(target, m.mode)
            # 特殊：assismgr 二进制确保可执行
            if rel_name == 'usr/sbin/assismgr' or rel_name.endswith('/assismgr'):
                os.chmod(target, 0o755)
    elif m.issym() or m.islnk():
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if os.path.lexists(target):
            try:
                os.remove(target)
            except:
                pass
        if m.issym():
            try:
                os.symlink(m.linkname, target)
            except (OSError, NotImplementedError) as e:
                # Windows 可能无 symlink 权限，跳过（service 路径仍能找到）
                print(f"   (skip symlink: {target} -> {m.linkname}: {e})")
        # hardlinks 暂不处理（deb 中较少见）

print(f"✅ assismgr 解包完成（{data_tar_format} 压缩格式，{len(tar.getmembers())} 个文件）")
PYEOF
fi

# ============================================================
# 修正 systemd service（适配 HAOS）
# ============================================================
ASSISMGR_SVC="$ROOTFS/usr/lib/systemd/system/assismgr.service"
ASSISMGR_WANTS="$ROOTFS/usr/lib/systemd/system/multi-user.target.wants/assismgr.service"

if [ -f "$ASSISMGR_SVC" ]; then
  # HAOS 需要 service 在网络就绪后才启动
  cat > "$ASSISMGR_SVC" <<'EOF'

[Unit]
Description=Assistant Manager Service (HAOS)
Documentation=https://github.com/LanSilence/assismgr
# 只依赖网络就绪。assismgr 是独立 Go 二进制，连接 127.0.0.1:1883 MQTT，
# 不应耦合 hassos-supervisor.service（否则 supervisor 启动慢/失败会拖垮 4000 端口）
After=network-online.target
Wants=network-online.target

[Service]
User=root
Type=simple
WorkingDirectory=/usr/www/assismgr
ExecStart=/usr/sbin/assismgr -s /usr/www/assismgr -c /etc/assismgr/HaPerfMonitor_config.json
Restart=on-failure
RestartSec=30s
MemoryMax=200M
TasksMax=100

[Install]
WantedBy=multi-user.target
EOF

  # 确保 wants 链接存在
  mkdir -p "$(dirname "$ASSISMGR_WANTS")"
  ln -sf "../assismgr.service" "$ASSISMGR_WANTS"
  echo "✅ assismgr.service 已修正（HAOS network-online 依赖）"
fi

# ============================================================
# 验证关键文件
# ============================================================
if [ -f "$ROOTFS/usr/sbin/assismgr" ] && [ -x "$ROOTFS/usr/sbin/assismgr" ]; then
  echo "✅ /usr/sbin/assismgr 已安装（可执行）"
else
  echo "❌ /usr/sbin/assismgr 未正确安装"
  exit 1
fi

if [ -f "$ROOTFS/usr/lib/systemd/system/assismgr.service" ]; then
  echo "✅ assismgr.service 已安装"
fi

if [ -f "$ROOTFS/etc/assismgr/HaPerfMonitor_config.json" ]; then
  echo "✅ assismgr 配置文件已安装"
fi

# ============================================================
# hassos-dns-cn-init.service (HAOS 中国版 DNS 自动配置)
# ============================================================
# 解决 hassio_dns 默认 fallback=1.1.1.1:853 (CloudFlare DoT) 在国内
# 网络环境被防火墙阻断的问题。启动时通过 supervisor API 注入
# 国内 DNS（阿里 223.5.5.5 + DNSPod 119.29.29.29）并禁用 fallback。
# 依赖 network-online.target + hassos-supervisor.service，并在脚本内部
# 循环等待 supervisor.sock 与 IPv4 网络就绪；失败后 systemd 自动重试。
# 用户后续可手动调整：ha dns options --servers dns://... --fallback=true
DNS_CN_SVC="$ROOTFS/usr/lib/systemd/system/hassos-dns-cn-init.service"
DNS_CN_WANTS="$ROOTFS/usr/lib/systemd/system/multi-user.target.wants/hassos-dns-cn-init.service"

# 仅在仓库中尚未写入时创建（保持 install_deb.sh 幂等；service 文件本体
# 由 git 跟踪的 rootfs-overlay/usr/lib/systemd/system/hassos-dns-cn-init.service
# 提供，install_deb.sh 只确保 wants 软链接存在）
mkdir -p "$(dirname "$DNS_CN_WANTS")"
if [ -f "$DNS_CN_SVC" ]; then
  # 优先用 ln -sf；Windows 主机 CI 不支持 symlink 时退化（CI 用 dpkg-deb 走 Linux 容器）
  ln -sf "../hassos-dns-cn-init.service" "$DNS_CN_WANTS" 2>/dev/null \
    && echo "✅ hassos-dns-cn-init.service wants 链接已创建" \
    || echo "⚠️  hassos-dns-cn-init.service wants 链接创建失败 (Windows?), service 仍可通过 systemctl 手动启用"
else
  echo "⚠️  $DNS_CN_SVC 不存在,跳过 wants 链接"
fi

echo "✅ install_deb.sh 完成 (assismgr 已集成到 rootfs)"

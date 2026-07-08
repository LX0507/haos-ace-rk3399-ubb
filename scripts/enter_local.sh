#!/bin/bash
#
# 本地构建辅助脚本 - 包装 scripts/enter.sh 以支持 sudo docker
# GitHub Actions 不需要这个文件（默认 docker 可用）
#
# 调用方法（从仓库根目录）:
#   ./scripts/enter_local.sh make -j 8 rk3399_ubb
#

# 智能选择 docker 命令
DOCKER="docker"
if ! docker info &> /dev/null; then
    if sudo docker info &> /dev/null; then
        DOCKER="sudo docker"
    else
        echo "❌ Docker 不可用，请先安装并启动 Docker"
        echo "   安装: https://docs.docker.com/engine/install/ubuntu/"
        echo "   启动: sudo systemctl start docker"
        echo "   加组: sudo usermod -aG docker \$USER  (然后重新登录)"
        exit 1
    fi
fi
echo "🐳 使用: $DOCKER"

# 定位仓库根目录（脚本所在目录的父目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OS_DIR="$REPO_ROOT/operating-system"

if [ ! -d "$OS_DIR" ]; then
    echo "❌ 找不到 $OS_DIR"
    echo "   请先执行: git submodule update --init --recursive"
    exit 1
fi

cd "$OS_DIR"

# 参考上游 scripts/enter.sh
BUILDER_UID="$(id -u)"
BUILDER_GID="$(id -g)"
CACHE_DIR="${CACHE_DIR:-$HOME/hassos-cache}"

if [ ! -f buildroot/Makefile ]; then
    git submodule update --init
fi

mkdir -p "${CACHE_DIR}"

# 准备循环设备
if command -v losetup >/dev/null && [ ! -e /dev/loop0 ]; then
    sudo losetup -f > /dev/null 2>&1 || true
fi

# 如果镜像不存在则构建
if ! $DOCKER image inspect hassos:local &> /dev/null; then
    echo "🔨 构建 hassos:local Docker 镜像（首次较慢）..."
    $DOCKER build -t hassos:local .
fi

# 启动容器执行命令
# 不用 -t（非交互环境无 TTY），-i 保持 stdin 可用
exec $DOCKER run --rm --privileged -i \
    -v "$(pwd):/build" -v "${CACHE_DIR}:/cache" \
    -e BUILDER_UID="${BUILDER_UID}" -e BUILDER_GID="${BUILDER_GID}" \
    hassos:local "$@"

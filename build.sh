#!/bin/bash
#
# HAOS-ACE 一键编译脚本
# 兼容 GitHub Actions 和本地 Ubuntu 24.04+ 环境
#

set -e

echo -e "\033[34;43m编译本工程，系统必须支持docker\033[0m"
echo -e "\033[34;43mBuilding this project, the system must support Docker\033[0m"


DEFAULT_TARGET="tn3399_v3 k2b_h618 rk3399_custom rk3399_ubb"

TARGET="${1:-$DEFAULT_TARGET}"

# ============================================================
# 1. 智能 Docker 权限检测
#    - 优先尝试普通用户 docker
#    - 失败时尝试 sudo docker
#    - 完全无权限时给出明确的修复指引
# ============================================================
DOCKER_CMD=""
# 用 ( ... ) 子 shell + 命令替换避免 set -e 误退
if docker info &> /dev/null; then
    DOCKER_CMD="docker"
    echo "✅ Docker 可用（普通用户模式）"
elif sudo -n true &> /dev/null && sudo docker info &> /dev/null; then
    DOCKER_CMD="sudo docker"
    echo "✅ Docker 可用（sudo 模式）"
else
    echo ""
    echo "❌ 无法访问 Docker。请按以下方法之一修复："
    echo ""
    echo "  方法 A（推荐）: 将当前用户加入 docker 组"
    echo "    sudo usermod -aG docker \$USER"
    echo "    newgrp docker    # 或重新登录"
    echo ""
    echo "  方法 B: 用 root 用户执行"
    echo "    sudo ./build.sh $TARGET"
    echo ""
    echo "  方法 C: 确保 docker 服务已启动"
    echo "    sudo systemctl start docker"
    echo "    sudo systemctl enable docker"
    echo ""
    exit 1
fi

# ============================================================
# 2. 初始化 git submodule
#    本地用户经常忘记 --recurse-submodules，导致 operating-system/ 是空目录
#    拉取指定 tag（与 .github/workflows/build.yaml 保持一致）
# ============================================================
SUBMODULE_TAG="17.3"
if [ ! -f operating-system/scripts/enter.sh ] || [ -z "$(ls -A operating-system 2>/dev/null | grep -v '^\.\.\?$')" ]; then
    echo "📦 初始化 git submodule (operating-system/) ..."
    if [ ! -d .git ]; then
        echo "❌ 错误：当前目录不是 git 仓库，无法初始化 submodule"
        echo "  请通过以下方式之一获取代码："
        echo "    git clone --recurse-submodules https://github.com/LX0507/haos-ace-rk3399-ubb.git"
        echo "    # 或者克隆后执行:"
        echo "    git submodule update --init --recursive"
        exit 1
    fi
    # 尝试以指定 tag 初始化（与 GitHub Actions 保持一致）
    if ! git submodule update --init --recursive --depth 1 2>/dev/null; then
        echo "⚠️  默认分支拉取失败，尝试 tag $SUBMODULE_TAG ..."
        cd operating-system
        if ! git fetch --depth 1 origin tag "$SUBMODULE_TAG" 2>/dev/null; then
            cd ..
            echo "❌ submodule 初始化失败，请检查网络或手动执行："
            echo "    git submodule update --init --recursive"
            exit 1
        fi
        git checkout FETCH_HEAD 2>/dev/null
        cd ..
    fi
    if [ ! -f operating-system/scripts/enter.sh ]; then
        echo "❌ submodule 初始化失败（缺少 scripts/enter.sh），请检查网络或手动执行："
        echo "    git submodule update --init --recursive"
        exit 1
    fi
    echo "✅ submodule 初始化完成"
fi

# ============================================================
# 3. 准备 /build 证书目录
#    GitHub Actions 显式创建了 /build/cert.pem 和 /build/key.pem
#    注意：这些证书**当前未被构建系统使用**（RAUC 用工作目录的 cert.pem）。
#    保留这段仅为向前兼容旧版 hooks，失败也不中断构建。
# ============================================================
ensure_build_cert() {
    # 如果 /build 证书已存在，跳过
    if [ -f /build/cert.pem ] && [ -f /build/key.pem ]; then
        return 0
    fi
    # 尝试创建 /build（如无 sudo 权限则跳过）
    if ! sudo -n true 2>/dev/null; then
        echo "ℹ️  无 sudo 权限，跳过 /build 证书准备（构建不受影响）"
        return 0
    fi
    sudo mkdir -p /build
    sudo chmod 777 /build
    if sudo openssl req -x509 -newkey rsa:4096 \
        -keyout /build/key.pem -out /build/cert.pem \
        -days 365 -nodes \
        -subj "/C=CN/ST=Local/L=Local/O=HAOS-ACE/OU=Build/CN=haos-ace.local" 2>/dev/null; then
        sudo chmod 644 /build/cert.pem /build/key.pem
        echo "✅ /build 证书已就绪"
    else
        echo "ℹ️  证书生成失败，跳过（构建不受影响）"
    fi
}
ensure_build_cert

# ============================================================
# 4. 安装 assismgr 等 deb 包
# ============================================================
./scripts/install_deb.sh

# ============================================================
# 5. 拷贝 overlay 到 operating-system
#    使用 rsync 而非 cp -a，避免符号链接处理差异
#    注意：rsync 默认会保留上游的符号链接（如 etc/resolv.conf -> /run/resolv.conf）
# ============================================================
echo "📂 合并 haos-overlay 到 operating-system ..."
if command -v rsync &> /dev/null; then
    # --no-times: 避免 rsync 警告"can only preserve times for owner"
    # --no-perms: 避免 rsync 修改文件权限（cp -a 的兼容性更好）
    # 不加 --delete 以避免误删 upstream 的关键符号链接
    rsync -rltD --no-perms --no-times --exclude='.git' haos-overlay/ operating-system/
else
    # 回退到 cp：先删除目标中可能引起冲突的符号链接
    # 解决"无法访问符号链接 etc/resolv.conf"的问题
    for symlink in \
        "buildroot-external/rootfs-overlay/etc/resolv.conf" \
        "buildroot-external/rootfs-overlay/usr/lib/firmware/updates"; do
        target="operating-system/$symlink"
        if [ -L "$target" ]; then
            echo "  ⚠️  移除 upstream 符号链接: $target"
            rm -f "$target"
        fi
    done
    cp -a haos-overlay/. operating-system/
fi
echo "✅ overlay 合并完成"

# ============================================================
# 5.5 修正 rootfs-overlay 中脚本/服务的执行权限
# rsync --no-perms 不会保留权限，此处显式恢复关键可执行文件
# ============================================================
echo "🔧 修正关键脚本权限 ..."
chmod +x \
    "operating-system/buildroot-external/rootfs-overlay/usr/libexec/hassos-dns-cn-init" \
    "operating-system/buildroot-external/rootfs-overlay/usr/libexec/haos-ensure-files" \
    "operating-system/buildroot-external/rootfs-overlay/usr/libexec/haos-log-capture" \
    2>/dev/null || true
echo "✅ 权限修正完成"

# ============================================================
# 6. 编译（按目标）
# ============================================================

# 计算并行编译数（容器内 2x 物理核数）
PARALLEL_JOBS=$(( $(nproc) * 2 ))

for target in $TARGET; do
    echo -e "Building for target: \033[34;43m$target\033[0m"

    if [ "$DOCKER_CMD" = "docker" ]; then
        # CI 或用户已在 docker 组：直接用上游 enter.sh（最可靠）
        echo "Command: (cd operating-system && ./scripts/enter.sh make -j $PARALLEL_JOBS $target)"
        if ( cd operating-system && ./scripts/enter.sh make -j $PARALLEL_JOBS "$target" ); then
            echo "Build for $target succeeded."
        else
            echo "Build for $target failed."
            exit 1
        fi
    else
        # sudo docker 模式（本地构建）：用 wrapper 脚本
        echo "Command: bash scripts/enter_local.sh make -j $PARALLEL_JOBS $target"
        if bash scripts/enter_local.sh make -j $PARALLEL_JOBS "$target"; then
            echo "Build for $target succeeded."
        else
            echo "Build for $target failed."
            exit 1
        fi
    fi
done

# ============================================================
# 7. 创建 output 符号链接
# ============================================================
if [ ! -d ./output ]; then
    ln -s operating-system/output ./output
fi

echo ""
echo -e "\033[32;1m🎉 编译完成！产物位于 ./output/images/\033[0m"

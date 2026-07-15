# HAOS for RK3399-UBB build system

- 本项目 forked from [twfjcn/haos-ace-tn3399-v3](https://github.com/twfjcn/haos-ace-tn3399-v3)（原项目 forked from [LanSilence/haos-ace](https://github.com/LanSilence/haos-ace)），在原项目基础上增加了对 **RK3399 UBTECH Board Bingo** 主板的适配。
- 针对中国国内网络环境进行了专项优化（Docker 镜像加速、国内 DNS/NTP 服务器、GitHub 下载加速）。
- 保留了上海原项目 [LanSilence/assismgr](https://github.com/LanSilence/assismgr) 后台管理系统（:4000 端口），集成了 [LanSilence/hamqtt](https://github.com/LanSilence/hamqtt) MQTT 客户端库。

> **OTA 升级**：从 [Release](https://github.com/LX0507/haos-ace-rk3399-ubb/releases) 页面下载最新 raucb 升级包，登录 `http://<设备IP>:4000` 后台进行上传升级。
> 后台默认用户名：`admin`，密码：`123456`。

---

# Home Assistant OS Accelerated China Edition（haos-ace） Build System

本工程以 Home Assistant OS 官方源码为子模块，自动拉取并编译。通过本地 `haos-overlay` 目录结构，覆盖和定制官方源码配置，实现新开发板的快速适配。

**内核**: Linux 6.12.85 mainline | **HAOS 基线**: 17.3 | **Buildroot**: 2025.02.12

---

## 支持的主板

| 主板 | SoC | Build目标 | 说明 |
|------|-----|-----------|------|
| TN3399-V3 | RK3399 | `tn3399_v3` | 原项目适配的开发板 |
| KickPi K2B | H618 | `k2b_h618` | Allwinner H618 开发板 |
| RK3399-Custom | RK3399 | `rk3399_custom` | 类似 rk3399pc 的板子 |
| **RK3399-UBB** | **RK3399** | **`rk3399_ubb`** | **RK3399 UBTECH Board Bingo（本项目新增适配）** |

---

## RK3399-UBB 适配说明

### 硬件规格

| 项目 | 规格 |
|------|------|
| 主板型号 | Rockchip RK3399 UBTECH Board Bingo |
| SoC | Rockchip RK3399 (双核 Cortex-A72 + 四核 Cortex-A53) |
| 内存 | 4GB LPDDR3 |
| 存储 | 32GB eMMC |
| WiFi/BT | Broadcom BCM43455 (SDIO/UART) |
| 以太网 | RGMII 千兆以太网 (Realtek RTL8211F) |
| PMIC | RK808 |
| HDMI | HDMI 2.0 (通过 mainline DRM/VOP 驱动) |
| USB | USB 3.0 x1 + USB 2.0 x4 + USB Type-C |

### 启动流程

```
U-Boot SPL (idbloader) → U-Boot → Linux Kernel (6.12.85) + DTB → systemd init
→ mount partitions → overlay init
→ NetworkManager（`end0-china-dns` 连接：IP 走 DHCP，DNS 主用国内公共 DNS 119.29.29.29/223.5.5.5/114.114.114.114，绕过路由器对 Cloudflare 域名解析超时 + systemd-resolved 默认回退到被墙的 Cloudflare DoT 1.1.1.1:853）
→ `hassos-dns-china` 服务（首启后通过官方 `ha dns options` API 把 plugin-dns 上游钉死为公共 DNS，持久化到 /mnt/data，双重保险）
→ Docker/containerd → Supervisor（`hassos-supervisor` 拉取镜像：版本源 Gitee 优先/官方回退，镜像 ghcr.io 优先/国内 ghcr 镜像回退）
→ HA Core（连通性过关后拉取 `ghcr.io` 镜像，landingpage → 完整镜像）
```

### 分区布局

| 分区 | 标签 | 类型 | 大小 | 说明 |
|------|------|------|------|------|
| SPL Boot | — | raw (fixed offset) | — | idbloader + U-Boot |
| Boot | `hassos-boot` | vfat | 8M | Kernel + DTB + U-Boot 脚本 |
| Kernel A | `kernel0` | squashfs | 16M | Linux 内核 |
| System A | `system0` | EROFS | 24M | 根文件系统 |
| Overlay A | `hassos-overlay` | ext4 | 256M | 持久化覆盖层 |
| Kernel B | `kernel1` | squashfs | 24M | 备用内核 (A/B 升级) |
| System B | `system1` | EROFS | 24M | 备用系统 |
| Bootstate | `bootstate` | ext4 | 8M | 启动状态 |
| Data A | `hassos-data` | ext4 | 96M | 用户数据 |
| Docker Data | `hassos-data-docker` | ext4 | 12.8G+ | Docker 镜像/容器存储 |

### 与 TN3399-V3 的主要硬件差异

| 项目 | TN3399-V3 | RK3399-UBB |
|------|-----------|------------|
| 内存类型 | DDR3 | LPDDR3 |
| LED GPIO | gpio1 RK_PC2 (ACTIVE_LOW) | gpio0 RK_PD5 (ACTIVE_HIGH) |
| 以太网 PHY | phy@0 | phy@1 |
| GMAC tx_delay | 0x28 | 0x32 |
| GMAC rx_delay | 0x10 | 0x11 |
| eMMC 模式 | HS400 | HS200（主线内核兼容） |
| SD 卡检测 | cd-gpios | broken-cd |
| WiFi/BT 固件 | BCM4345C5 | BCM43455 (brcmfmac43455-sdio) |
| 音频 codec | RT5640 | 无 |
| RTC | HYM8563 | 无 |
| 风扇 | gpio-fan | 无 |
| 电源按键 | 无独立定义 | gpio0 RK_PA5 (ACTIVE_LOW) |

---

### Supervisor 下载优化（国内网络）

`usr/sbin/hassos-supervisor` 覆盖 stock，仅改动「版本源获取」与「镜像拉取」两处，其余（startup-marker/CIDFILE 处理、`docker container create` 参数、cidfile 挂载）保持 HAOS 17.3 官方原样（已与 `home-assistant/operating-system@17.3` 逐行 diff 校验）。两处均做**有序回退 + 日志说明**，结构清晰、容错性强：

- **版本源（Gitee 镜像优先 / 官方回退）**：依次尝试 `gitee.com/LanSilence/ha-version/raw/master/stable.json`（国内稳定）→ `version.home-assistant.io/stable.json`；全部失败清空 `updater.json` 交 systemd 重试。
- **镜像仓库（ghcr.io 优先 / 国内加速回退）**：依次尝试 `ghcr.io` → `ghcr.nju.edu.cn`（南京大学开源镜像，已实测可达且含该镜像）→ `ghcr.dockerproxy.com`，`timeout 240` 防半死镜像挂起，成功即 `docker tag` 为规范 `ghcr.io/...:latest`；全部失败同样清空 `updater.json` 重试。
- 关键修改点均带 `[INFO]/[WARNING]/[ERROR] [版本源]/[镜像源]` 日志，便于串口排障。

## 后台管理（4000 端口）

`http://<设备IP>:4000` 提供 Web 后台管理界面，由 [LanSilence/assismgr](https://github.com/LanSilence/assismgr) 提供。

### 功能列表

- 📊 性能监控（CPU、内存、磁盘使用率）
- 📋 日志查看（系统日志、服务器日志）
- 🔄 系统更新（OTA raucb 上传升级）
- 🔁 恢复出厂设置
- ⚙️ 系统重启
- 💡 指示灯控制
- 🌐 网络状态检测
- 📡 FRP 配置文件管理
- ℹ️ 版本信息查看

### 技术架构

```
assismgr (Go 二进制, :4000 Web UI)
    ├── 内部 WebSocket 实时推送 (/ws)
    ├── MQTT 客户端 → Mosquitto broker (127.0.0.1:1883)
    │   └── 使用 hamqtt 库发布 Home Assistant MQTT 自动发现
    ├── 系统监控 (gopsutil: CPU/内存/磁盘)
    └── USB 串口通信 (/dev/ttyGS, 可选)
```

### MQTT 依赖

assismgr 集成了 [LanSilence/hamqtt](https://github.com/LanSilence/hamqtt) 作为 MQTT 客户端库，需要 MQTT broker 才能完整工作。在 HAOS 中：

1. 打开 Supervisor → 加载项商店
2. 搜索 "Mosquitto broker" 并安装
3. 确保 Mosquitto 监听 `127.0.0.1:1883`

> 即使未安装 Mosquitto，Web UI 仍可正常访问和使用，仅 MQTT 相关功能不可用。

---

## 指示灯说明

| 状态 | 含义 |
|------|------|
| 常亮 | 系统正常启动 |
| 快闪 | 未连接无线或有线网络 |
| 慢闪 | 已连接网络但无互联网 |
| 心跳 | 网络连接正常 |
| 长灭 | 人为关闭或系统未启动 |

---

## 目录结构

```
haos-ace-rk3399-ubb/
├── build.sh                        # 一键编译脚本
├── .gitattributes                  # 强制 LF 换行（防止 Windows autocrlf 破坏 patch）
├── .github/workflows/build.yaml    # GitHub Actions CI 配置
├── scripts/
│   ├── install_deb.sh              # assismgr 下载安装（含国内镜像加速）
│   └── enter_local.sh              # 本地 Docker 构建封装
├── haos-overlay/
│   ├── Dockerfile                  # 构建容器镜像（含阿里云 APT 加速）
│   └── buildroot-external/
│       ├── configs/
│       │   └── rk3399_ubb_defconfig  # Buildroot defconfig
│       ├── board/hardkernel/rk3399-ubb/
│       │   ├── meta                  # 板级元数据 (SUPERVISOR_MACHINE=qemuarm-64)
│       │   ├── kernel.config         # 内核配置 (VOP/DRM/IOMMU/Watchdog)
│       │   ├── kern-rk3399.config    # RK3399 基础内核配置
│       │   ├── uboot.config          # U-Boot 配置
│       │   ├── cmdline.txt           # 内核启动参数
│       │   ├── uboot-boot.ush        # U-Boot 启动脚本
│       │   ├── hassos-hook.sh        # 构建 hook
│       │   ├── patches/
│       │   │   ├── linux/0001-add-rk3399-ubb-dts.patch   # 内核 DTS
│       │   │   └── uboot/0001-add-rk3399-ubb-u-boot.patch # U-Boot DTS
│       │   └── rkbin/                # Rockchip 预编译二进制
│       └── rootfs-overlay/
│           ├── etc/
│           │   ├── docker/daemon.json          # Docker 配置 (registry-mirrors, 无 dns 字段)
│           │   ├── NetworkManager/
│           │   │   ├── NetworkManager.conf     # 网络管理配置 (dns=default, 连通性 uri=gitee, 无限重试)
│           │   │   └── system-connections/
│           │   │       └── end0-china-dns.nmconnection  # 有线网卡: DNS 主用公共 DNS(忽略路由器 DNS) 绕开 Cloudflare 被墙
│           │   ├── systemd/
│           │   │   ├── resolved.conf           # 覆盖 FallbackDNS 为国内公共 DNS(去掉默认 1.1.1.1)
│           │   │   └── system/
│           │   │       └── hassos-dns-china.service  # 首启把 plugin-dns 上游钉为公共 DNS(官方 API)
│           │   │   ├── timesyncd.conf          # NTP 配置 (国内)
│           │   │   └── journald.conf           # 日志持久化
│           │   └── tmpfiles.d/                 # 临时文件/目录
│           └── usr/
│               ├── libexec/
│               │   ├── haos-ensure-files
│               │   └── haos-log-capture
│               ├── sbin/
│               │   ├── hassos-supervisor     # supervisor 启动脚本（Gitee 优先+官方回退版本源；ghcr.io 优先+国内 ghcr 镜像回退）
│               │   ├── hassos-dns-china      # 首启把 plugin-dns 上游钉为公共 DNS（官方 ha dns options API）
│               │   ├── assismgr             # 后台管理二进制 (:4000)
│               │   ├── led-control          # 指示灯控制
│               │   └── switch_slot          # A/B 槽切换
│               ├── firmware/brcm/            # BCM43455 WiFi/BT 固件
│               └── lib/systemd/system/
│                   ├── haos-ensure-files.service
│                   ├── haos-log-capture.service
│                   └── NetworkManager-wait-online.service
└── operating-system/                # 官方 HAOS 源码（git submodule）
```

---

## 快速开始

### 1. 环境准备 (Ubuntu 24.04+)

- 推荐 Ubuntu 24.04+，需安装 `docker`、`git` 等常用工具。
- 工程会自动下载和准备交叉编译工具链，无需手动配置。

```bash
# 下载代码（必须使用 --recurse-submodules）
git clone --recurse-submodules https://github.com/LX0507/haos-ace-rk3399-ubb.git
cd haos-ace-rk3399-ubb

# 如果已克隆但忘记 --recurse-submodules：
# git submodule update --init --recursive
```

#### Docker 安装

```bash
sudo apt update && sudo apt install apt-transport-https curl

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 将当前用户加入 docker 组
sudo usermod -aG docker $USER
newgrp docker
docker info  # 验证
```

#### 常见本地构建问题

| 错误 | 原因 | 解决方法 |
|------|------|---------|
| `operating-system/scripts/enter.sh: No such file` | submodule 未初始化 | `git submodule update --init --recursive` |
| `permission denied: docker` | 用户不在 docker 组 | `sudo usermod -aG docker $USER` 重新登录 |
| `cannot open /dev/loop0` | 缺少循环设备 | `sudo losetup -f` 或 `sudo mknod /dev/loop0 b 7 0` |
| `cp: 无法通过符号链接` | resolv.conf 符号链接冲突 | 升级到最新代码 (`git pull`) |

### 2. 一键编译

```bash
# 仅编译 RK3399-UBB
./build.sh rk3399_ubb

# 编译所有支持的平台
./build.sh

# 编译特定平台
./build.sh tn3399_v3
./build.sh k2b_h618
```

### 3. 产物说明

编译完成后，产物位于 `output/images/`：

| 文件 | 说明 |
|------|------|
| `haos_rk3399-ubb-<version>.img.xz` | 系统镜像（解压后烧录） |
| `haos_rk3399-ubb-<version>.raucb` | OTA 升级包 |

### 4. 烧录

#### 烧录到 eMMC（推荐）

```bash
xz -d haos_rk3399-ubb-*.img.xz
# 进入 Maskrom 模式后：
rkdeveloptool db MiniLoaderAll.bin
rkdeveloptool wl 0 haos_rk3399-ubb-*.img
rkdeveloptool rd
```

#### 烧录到 SD 卡

```bash
xz -d haos_rk3399-ubb-*.img.xz
sudo dd if=haos_rk3399-ubb-*.img of=/dev/sdX bs=4M status=progress
sync
```

### 5. OTA 升级

1. 从 [Release](https://github.com/LX0507/haos-ace-rk3399-ubb/releases) 下载 `.raucb`
2. 登录 `http://<设备IP>:4000`（默认用户名 `admin`，密码 `123456`）
3. 在"系统更新"页面上传升级

---

## 上电开机与配置

### 首次启动流程

1. **插入网线**（推荐）或等待 WiFi 扫描
2. 设备自动通过 DHCP 获取 IP 地址
3. 等待约 3-5 分钟（首次启动需拉取 Docker 镜像）
4. 浏览器访问：
   - `http://<设备IP>:4000` → 后台管理
   - `http://<设备IP>:8123` → Home Assistant

### 串口调试

- **波特率**: 115200（BROM 阶段 1.5M，U-Boot/内核 115200）
- **串口设备**: UART2 (ttyS2, GPIO 引脚)
- **接线**: GND + TX + RX（3.3V TTL 电平）

### 配网（USB 串口方式）

使用 Type-C 线连接电脑 USB，打开串口终端（推荐 mobaxterm、winderm），输入：

```
wifi -s <SSID> -p <密码>
```

连接成功后显示获取到的 IP 地址。

---
### 开发相关

**Q: 适配新开发板？**
```bash
mkdir -p haos-overlay/buildroot-external/board/hardkernel/new-board/
# 添加配置文件：meta, kernel.config, cmdline.txt, patches/, etc.
./build.sh new-board
```

**Q: 编译时 patch 应用失败？**
A: 检查 `.gitattributes` 确保 patch 文件使用 LF 换行（Windows 下 git autocrlf 可能转换）。patch hunk header 行数必须精确匹配。

---

## 参考

- [Home Assistant OS 官方文档](https://developers.home-assistant.io/docs/hassio/)
- [原项目 twfjcn/haos-ace-tn3399-v3](https://github.com/twfjcn/haos-ace-tn3399-v3)
- [上游 LanSilence/haos-ace](https://github.com/LanSilence/haos-ace)
- [assismgr 后台管理](https://github.com/LanSilence/assismgr)
- [hamqtt MQTT 客户端库](https://github.com/LanSilence/hamqtt)
- [Rockchip RK3399 技术文档](https://opensource.rock-chips.com/wiki_RK3399)

---

## 维护者

- 本项目由 Home Assistant OS 社区爱好者维护
- RK3399-UBB 适配由 [LX0507](https://github.com/LX0507) 完成
- 如有问题请提交 [Issue](https://github.com/LX0507/haos-ace-rk3399-ubb/issues) 或 PR

---

## License

本工程遵循 GPLv2/MIT 等开源协议，详见各源码目录 LICENSE 文件。

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
→ NetworkManager（网卡 up 即由 `99-hassos-dns-cn` 强制 host 国内 DNS）
→ Docker/containerd → Supervisor（`hassos-dns-cn-init` 配置 + `recheck.timer` 保底）
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

## 适配历程与关键修复

### RK3399-UBB 适配解决的问题（Build #11 → #30）

| 问题 | 根因 | 修复 |
|------|------|------|
| eMMC I/O 错误 | HS400 时序不兼容 mainline | 降级为 HS200 |
| Docker 启动失败 | cgroup v2 unified 未配置 | `exec-opts native.cgroupdriver=systemd` |
| 60 秒硬件看门狗重启 | BootROM 启动 DW 看门狗未接管 | `CONFIG_DW_WATCHDOG=y` + `watchdog.open_timeout=0` |
| HDMI 无显示 | VOP 驱动未编译 + patch hunk header 行数不匹配导致 DTS 截断 | `CONFIG_ROCKCHIP_VOP=y` + 修正 patch 行数 |
| 串口后半段乱码 | 波特率过高 (1.5M) + 日志级别过高 | 降为 115200 + loglevel=6 |
| WiFi 固件加载失败 | Vendor 私有 NVRAM 属性与 mainline 冲突 | 清理为纯 mainline DTS |
| DHCP 间歇性失败 | `autoconnect-retries-default=5` 过早放弃 | 改为 0（无限重试） |
| Docker DNS 超时 | dockerd 直连 8.8.8.8 被路由器阻断 | 移除 daemon.json DNS，走 hassio_dns |
| NetworkManager 配置语法错误 | `[connection]` 段不支持 `ipv4.dns` | 改用 `[global-dns]` / `dns=default` |
| 4000 端口后台管理丢失 | assismgr 在适配中被误禁用 | 恢复安装 + GitHub 镜像加速下载 |
| 日志无法持久保存 | 无 ramoops 配置 | pstore/ramoops + haos-log-capture service |
| systemd ordering cycle | haos-ensure-files 依赖形成循环 | 修改 After / WantedBy 目标 |
| Supervisor 机器类型错误 | `SUPERVISOR_MACHINE` 误改 | 保持 `qemuarm-64` |
| containerd snapshotter 冲突 | `storage-driver=overlay2` 与新版冲突 | 移除显式 storage-driver |
| Supervisor 永久 'No connectivity' | hassio_dns 上游 DNS 不可达（路由器 192.168.1.1:53 经常 i/o timeout；或公共 DNS 被阻断） | CoreDNS 多上游故障转移（公共 DNS 119.29.29.29/223.5.5.5/8.8.8.8 + 路由器网关，自动 failover）|

### 中国国内网络加速配置

| 加速项 | 配置 | 说明 |
|--------|------|------|
| Docker Hub 镜像 | `registry-mirrors`: DaoCloud + 1ms + 1panel + 中科大 + 网易（共 5 个） | 加速 `docker.io` 镜像拉取 |
| **Host 系统 DNS** | host 指向 hassio_dns (`172.30.32.3`)，实际解析由 hassio_dns 的 Corefile 多上游故障转移处理 | 不再强行把 host 指向路由器（实测 192.168.1.1:53 经常 i/o timeout 导致 dockerd resolver 超时）|
| CoreDNS 上游（多故障转移） | `ha dns options --servers dns://119.29.29.29 --servers dns://223.5.5.5 --servers dns://8.8.8.8 --servers dns://<网关>` | 多上游：路由器可用走路由器，不可用自动转公共 DNS |
| NTP 时间同步 | ntp.aliyun.com + ntp.tencent.com | 国内 NTP 服务器 |
| APT 源（构建阶段） | `mirrors.aliyun.com` 替代 `deb.debian.org` | 加速 Docker 镜像构建 |

---

## Supervisor 网络连通性修复（关键）

8123 端口长期停留在 landingpage、HA Core 永远起不来的**根因**，不是 Docker 镜像下载慢，而是 **supervisor 永久标记 `No Supervisor connectivity`**：

1. 设备连路由器后，host 系统通过 DHCP 拿到路由器 DNS（如 `192.168.1.1`）。**实测该路由器 DNS 经常 i/o timeout（不响应）**，单一路由器上游会让所有解析失败。
2. supervisor 启动时执行连通性检查 `checkonline.home-assistant.io`，因 DNS 解析超时而被**永久**标记为"无网络"。
3. supervisor 一旦标记无网络，就**永不拉取** `ghcr.io` 的 HA Core / Supervisor 镜像 → 8123 永远停在 landingpage。

### 为什么单一路由器 DNS 不行

不同家庭网络差异极大：有的路由器 DNS 正常，有的（如本项目的 `192.168.1.1`）DNS 代理不可用；有的网络公共 DNS 被阻断。只配一个上游（路由器 **或** 某个公共 DNS）在任何一种异常网络下都会失败。

### 修复方案：CoreDNS 多上游故障转移

`hassos-dns-cn-init` 把 hassio_dns（CoreDNS）的 Corefile 所有 `forward .` 行统一替换为
**多上游列表**：`119.29.29.29`（DNSPod/腾讯）、`223.5.5.5`（AliDNS）、`8.8.8.8`（兜底）+ **运行时检测的默认网关**。
CoreDNS 自动对每个上游做健康检测，不可达的上游会被剔除，解析自动 failover 到可用上游：

- 路由器 DNS 可用 → 走路由器（适配任意家庭网段，符合此前诉求）
- 路由器 DNS 不可用（i/o timeout）→ 自动转移到公共 DNS
- 公共 DNS 个别被阻断 → 自动转移到其它公共 DNS

host 系统 / dockerd 的 DNS 不再强行指向路由器，而是指向 `hassio_dns`（`172.30.32.3`），由 CoreDNS 统一做故障转移（与 stock HA OS 行为一致，也避免 dockerd 直接查已死路由器超时）。

| 脚本 | 触发时机 | 作用 |
|------|----------|------|
| `etc/NetworkManager/dispatcher.d/99-hassos-dns-cn` | 网卡 up（最早，T≈10s） | 立即把 host DNS 指向 hassio_dns，并后台拉起主脚本 |
| `usr/libexec/hassos-dns-cn-init` | `hassos-dns-cn-init.service`（`After=hassos-supervisor`） | 主力：配 host DNS → `ha dns options` 多上游 → 修 Corefile Cloudflare DoT + 多上游 → healthcheck |
| `usr/libexec/hassos-dns-cn-init-supervisor-recheck` | `*.timer` 每 5 分钟保底 | 联网后重新配置 + healthcheck，成功后自禁 timer |

> 三重保险确保无论 supervisor 何时就绪，CoreDNS 多上游都已生效，连通性检查能过关，HA Core 镜像正常拉起。

---

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
│           │   ├── docker/daemon.json          # Docker 配置 (5 个 registry-mirrors)
│           │   ├── NetworkManager/
│           │   │   ├── NetworkManager.conf     # 网络管理配置 (dns=default, 无限重试)
│           │   │   └── dispatcher.d/
│           │   │       └── 99-hassos-dns-cn     # 网卡 up 即配 host DNS（最早触发）
│           │   ├── systemd/
│           │   │   ├── resolved.conf           # DNS 配置 (国内)
│           │   │   ├── timesyncd.conf          # NTP 配置 (国内)
│           │   │   └── journald.conf           # 日志持久化
│           │   └── tmpfiles.d/                 # 临时文件/目录
│           └── usr/
│               ├── libexec/
│               │   ├── haos-ensure-files
│               │   ├── haos-log-capture
│               │   ├── hassos-dns-cn-init                    # host DNS 配置 + supervisor DNS 配置（主力）
│               │   └── hassos-dns-cn-init-supervisor-recheck # 连通性保底重查
│               ├── sbin/
│               │   ├── assismgr             # 后台管理二进制 (:4000)
│               │   ├── led-control          # 指示灯控制
│               │   └── switch_slot          # A/B 槽切换
│               ├── firmware/brcm/            # BCM43455 WiFi/BT 固件
│               └── lib/systemd/system/
│                   ├── haos-ensure-files.service
│                   ├── haos-log-capture.service
│                   ├── NetworkManager-wait-online.service
│                   ├── hassos-dns-cn-init.service                        # 开机自启（After=supervisor）
│                   ├── hassos-dns-cn-init-supervisor-recheck.service
│                   └── hassos-dns-cn-init-supervisor-recheck.timer      # 每 5 分钟保底
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

## 常见问题

### 网络相关

**Q: 设备获取不到 IP 地址？**
A: 检查网线连接，确认路由器 DHCP 服务正常。设备会在启动后持续重试 DHCP。

**Q: 国内下载 HA Core 镜像很慢？**
A: 镜像来自 `ghcr.io`，在中国大陆可直接访问但速度可能较慢。首次启动需等待 10-30 分钟。Docker Hub 镜像已配置国内加速。

**Q: 8123 端口一直停留在 landingpage / HA Core 起不来？**
A: 最常见根因是 supervisor 永久标记 `No Supervisor connectivity`：路由器 DNS（如 192.168.1.1）在国内响应慢，supervisor 启动时的连通性检查 `checkonline.home-assistant.io` 解析超时，被永久标记无网络，从而**永不拉取** `ghcr.io` 的 HA Core 镜像（不是下载慢，是根本不下载）。本项目已通过 **host 层强制 DNS**（223.5.5.5 / 119.29.29.29）修复，使 hassio_dns 的 `locals` 也走国内 DNS。若烧录新版本后仍卡住，请查看串口日志是否有 `No Supervisor connectivity`，并可在设备上手动执行：
```bash
ha dns options --servers dns://223.5.5.5 --servers dns://119.29.29.29
ha core restart
```

**Q: DNS 解析失败 / 域名无法解析？**
A: 系统已配置 CoreDNS 多上游故障转移（公共 DNS 119.29.29.29/223.5.5.5/8.8.8.8 + 运行时检测的路由器网关），host 与 supervisor 都通过 hassio_dns（`172.30.32.3`）解析，任一上游不可达会自动 failover。若仍解析失败，请检查：① `docker exec hassio_dns cat /etc/corefile` 的 `forward .` 是否为多上游列表；② `docker logs hassio_dns` 有无上游全部 unhealthy；③ supervisor 是否仍报 `No Supervisor connectivity`（见上一条）。

### 系统相关

**Q: 系统启动后 60 秒自动重启？**
A: 已在 Build #17-18 修复。如仍出现，检查内核配置是否包含 `CONFIG_DW_WATCHDOG=y` 和 `watchdog.open_timeout=0`。

**Q: HDMI 无显示？**
A: 确认使用 Build #26 或更新版本。VOP 驱动已正确编译，HDMI 输出 HA CLI 字符界面。

**Q: WiFi 无法连接？**
A: BCM43455 使用 mainline `brcmfmac` 驱动，固件文件为 `brcmfmac43455-sdio.bin`。确认固件已正确放置。

**Q: 如何定制内核/U-Boot 配置？**
A: 修改 `haos-overlay/buildroot-external/board/hardkernel/rk3399-ubb/kernel.config` 或 `uboot.config`，重新编译即可。

**Q: 如何打开串口控制台？**
A: 波特率设为 115200（不是 1500000），接入 UART2 TX/RX/GND 引脚即可。

**Q: 查看上次启动的日志？**
A: 系统支持 pstore/ramoops（重启后 `/sys/fs/pstore/` 保留上次日志），以及 `haos-log-capture` 服务每 60 秒保存日志到 `/mnt/data/sos-logs/`。

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

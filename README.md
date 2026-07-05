# HAOS for RK3399-UBB build system

- 本项目forked from [twfjcn/haos-ace-tn3399-v3](https://github.com/twfjcn/haos-ace-tn3399-v3)（原项目forked from [LanSilence/haos-ace](https://github.com/LanSilence/haos-ace)），在原项目基础上增加了对 **RK3399 UBTECH Board Bingo** 主板的适配。
- 时间同步服务器保留使用国内服务器，原项目的国内镜像仓库等加速去掉了，保持跟HA官方一致。

- 系统ota升级请从发布页面下载最新raucb升级包，然后登录 http://ip:4000 后台进行上传升级，后台默认用户名：admin，密码：123456。

---

# Home Assistant OS Accelerated China Edition（haos-ace） Build System

本工程以 Home Assistant OS 官方源码为子模块，自动拉取并编译。通过本地 haos-overlay 目录结构，覆盖和定制官方源码配置，实现新开发板的快速适配。

本工程为 Home Assistant OS 在 Allwinner H618-k2b 和 Rockchip RK3399 平台的完整构建系统，支持内核、U-Boot、固件、根文件系统、分区镜像等一站式自动化编译与打包。

---

## 支持的主板

| 主板 | SoC | Build目标 | 说明 |
|------|-----|-----------|------|
| TN3399-V3 | RK3399 | `tn3399_v3` | 原项目适配的开发板 |
| KickPi K2B | H618 | `k2b_h618` | Allwinner H618开发板 |
| RK3399-Custom | RK3399 | `rk3399_custom` | 类似rk3399pc的板子 |
| **RK3399-UBB** | **RK3399** | **`rk3399_ubb`** | **RK3399 UBTECH Board Bingo（本项目新增适配）** |

---

## RK3399-UBB 适配说明

### 硬件规格

| 项目 | 规格 |
|------|------|
| 主板型号 | Rockchip RK3399 UBTECH Board Bingo |
| SoC | Rockchip RK3399 (双核Cortex-A72 + 四核Cortex-A53) |
| 内存 | 4GB LPDDR3 |
| 存储 | 32GB eMMC (HS400 Enhanced Strobe) |
| WiFi/BT | Broadcom BCM43455 (SDIO/UART) |
| 以太网 | RGMII千兆以太网 (Realtek RTL8211F) |
| PMIC | RK808 |
| HDMI | HDMI 2.0 |
| USB | USB 3.0 x1 + USB 2.0 x4 + USB Type-C |
| IR | 红外接收器 |

### 与TN3399-V3的主要硬件差异

| 项目 | TN3399-V3 | RK3399-UBB |
|------|-----------|------------|
| 内存类型 | DDR3 | LPDDR3 |
| LED GPIO | gpio1 RK_PC2 (ACTIVE_LOW) | gpio0 RK_PD5 (ACTIVE_HIGH) |
| 以太网PHY地址 | phy@0 | phy@1 |
| GMAC tx_delay | 0x28 | 0x32 |
| GMAC rx_delay | 0x10 | 0x11 |
| eMMC模式 | HS400 | HS200 + HS400 + HS400 Enhanced Strobe |
| SD卡检测 | cd-gpios | broken-cd |
| BT芯片 | brcm,bcm4345c5-bt | brcm,bcm43455-bt |
| WiFi板级NVRAM | 无板级特定 | brcm,bcm43455-fmac + keiiot,k019-cw43-dw NVRAM |
| 音频codec | RT5640 | 无 |
| RTC | HYM8563 | 无 |
| 风扇 | gpio-fan | 无 |
| 功放 | NS4258 | 无 |
| IR接收器 | 无 | 有 (gpio0 RK_PA6) |
| 电源按键 | 无独立定义 | gpio0 RK_PA5 (ACTIVE_LOW) |
| USB 5V供电 | 单路 | 多路独立控制 |

### 适配文件清单

```
haos-overlay/buildroot-external/
├── board/hardkernel/rk3399-ubb/
│   ├── meta                          # 板级元数据
│   ├── kernel.config                 # 内核配置片段
│   ├── uboot.config                  # U-Boot配置片段
│   ├── cmdline.txt                   # 内核启动参数
│   ├── boot-env.txt                  # U-Boot环境变量
│   ├── uboot-boot.ush                # U-Boot启动脚本
│   ├── hassos-hook.sh                # 构建hook脚本
│   ├── image-spl-spl.cfg             # genimage镜像配置
│   ├── partition-spl-spl.cfg         # 分区配置
│   ├── rkbin/                        # Rockchip预编译二进制
│   │   ├── idbloader.img
│   │   ├── loaderimage
│   │   ├── rk3399_bl31_v1.36.elf
│   │   ├── rk3399_bl32_v2.12.bin
│   │   └── trust.img
│   ├── patches/
│   │   ├── linux/
│   │   │   └── 0001-add-rk3399-ubb-dts.patch    # Linux内核设备树
│   │   └── uboot/
│   │       └── 0001-add-rk3399-ubb-u-boot.patch  # U-Boot适配
│   └── rootfs-overlay/
│       └── usr/lib/firmware/brcm/                # BCM43455 WiFi/BT固件
│           ├── brcmfmac43455-sdio.bin
│           ├── brcmfmac43455-sdio.clm_blob
│           ├── brcmfmac43455-sdio.txt
│           ├── brcmfmac43455-sdio.keiiot,k019-cw43-dw.txt
│           └── BCM4345C0.hcd
└── configs/
    └── rk3399_ubb_defconfig           # Buildroot defconfig
```

---

## 系统功能

- ✅ 主板适配：H618-k2b、rk3399-custom、TN3399-V3、**RK3399-UBB**
- ✅ 完整官方HAOS功能
- ✅ 丰富的官方加载项
- ✅ OTA升级功能
- ✅ 无终端配网
- ✅ WIFI、有线网络、蓝牙
- ✅ http://homeassistant.local:4000 后台管理

---

## 目录结构说明

- `build.sh`：一键编译脚本，支持多平台参数。
- `haos-overlay/`：本地定制与覆盖目录，结构与官方源码一致。
- `operating-system/`：官方 Home Assistant OS 源码子模块。
- `output/`：编译生成的所有产物，包括镜像、固件、分区文件等。
- `Documentation/`：平台、配置、开发相关文档说明。
- `scripts/`：辅助脚本，如工具链下载、内核更新等。
- `tests/`：自动化测试相关内容。

---

## 快速开始

### 1. 环境准备 (Ubuntu 24.04)

- 推荐 Ubuntu 24.04+，需安装 `docker`、`git` 等常用工具。
- 工程会自动下载和准备交叉编译工具链，无需手动配置。

```bash
# 下载代码
git clone --recurse-submodules https://github.com/LX0507/haos-ace-rk3399-ubb.git
cd haos-ace-rk3399-ubb

# docker 安装
sudo apt update
sudo apt install apt-transport-https curl

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 添加软件源，如果是低于ubuntu24 版本，添加源的方式有所不同
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 更新软件包列表
sudo apt update

# 安装 Docker
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 2. 一键编译

以 RK3399-UBB 为例：
```bash
./build.sh rk3399_ubb
```

编译所有支持的平台：
```bash
./build.sh
```

以其他平台为例：
```bash
./build.sh tn3399_v3
./build.sh k2b_h618
./build.sh rk3399_custom
```

### 3. 产物说明

编译完成后，主要产物位于 `output/images/` 目录，包括：

- 系统镜像（如 `haos_rk3399-ubb-<version>.img.xz`）：用于烧录到eMMC/SD卡，直接启动。
- 升级文件（如 `haos_rk3399-ubb-<version>.raucb`）：用于OTA升级。

不同平台产物名称略有差异，具体请参考 `output/images/` 目录内容。

### 4. 烧录与部署

#### 烧录到eMMC
```bash
# 解压镜像
xz -d haos_rk3399-ubb-*.img.xz

# 使用rkdeveloptool或USB下载工具烧录
# 进入Maskrom模式后：
rkdeveloptool db MiniLoaderAll.bin
rkdeveloptool wl 0 haos_rk3399-ubb-*.img
rkdeveloptool rd
```

#### 烧录到SD卡
```bash
# 解压镜像
xz -d haos_rk3399-ubb-*.img.xz

# 写入SD卡（/dev/sdX替换为实际设备）
sudo dd if=haos_rk3399-ubb-*.img of=/dev/sdX bs=4M status=progress
sync
```

#### OTA升级
1. 从Release页面下载 `.raucb` 升级包。
2. 登录 `http://<设备IP>:4000` 后台管理页面。
3. 在"系统更新"页面上传 `.raucb` 文件进行升级。

---

## 开发与定制

### 覆盖机制说明

- 官方源码作为子模块管理，自动同步最新代码。
- 本地 haos-overlay 目录结构与官方源码一致，支持任意文件的定制与覆盖。
- 编译流程自动应用本地修改，优先使用本地配置，无需直接改动官方源码。
- 适配新开发板只需在 overlay 目录下按官方结构添加/修改配置文件。
- 优先级：本地修改 > 官方配置

### 适配新开发板

```bash
# 以适配 new-board 为例
mkdir -p haos-overlay/buildroot-external/board/hardkernel/new-board/
touch haos-overlay/buildroot-external/configs/new-board_defconfig
# 添加/修改配置文件

# 一键编译
./build.sh new-board
```

---

## 上电开机与网络配置

- 上电后需先配置网络。
- RK3399-UBB 支持有线网络和WiFi，推荐优先使用有线网络。

### 配网方式

1. **USB配网**（如支持USB串口）：
   - 使用 Type-C 线连接电脑 USB 口。
   - 打开串口终端（推荐 mobaxterm、winderm），波特率 1500000（RK3399默认）。
   - 打开后输入：
     ```
     wifi -s <ssid> -p <passwd>
     ```
   - 连接成功后会显示获取到的 IP。

2. **有线网络**：插入网线，设备自动获取IP地址。

3. 电脑浏览器访问 `http://<ip>:4000` 进入管理后台。

4. 建议重启后再访问 `http://<ip>:8123` 进入 Home Assistant 页面。

---

## 后台管理功能

- 性能监控
- 日志查看
- 系统更新
- 恢复出厂设置
- 系统重启
- 指示灯控制
- 网络升级包在线升级、支持升级打断
- FRP 配置文件修改
- 版本信息查看

> 可将管理页面添加到 Home Assistant 导航栏，便于快速访问。

---

## 指示灯说明

- 指示灯常亮：系统正常启动
- 指示灯快闪：未连接无线或者有线
- 指示灯慢闪：无线或者有线已连接，但无网络
- 指示灯心跳：网络连接正常
- 指示灯长灭：人为关闭指示灯或者系统未启动

---

## 常见问题

### Q: 工程找不到工具链？
A: 首次编译会自动下载并解压 toolchain，无需手动干预。

### Q: 如何定制内核/U-Boot配置？
A: 修改 `board/hardkernel/rk3399-ubb/kernel.config` 或 `uboot.config`，重新编译即可。

### Q: 如何添加/修改分区布局？
A: 修改 `board/hardkernel/rk3399-ubb/` 下的 `image-spl-spl.cfg` 和 `partition-spl-spl.cfg` 分区配置文件。

### Q: WiFi无法连接？
A: 确认WiFi固件已正确放置在 `rootfs-overlay/usr/lib/firmware/brcm/` 目录，特别是板级特定NVRAM文件 `brcmfmac43455-sdio.keiiot,k019-cw43-dw.txt`。

### Q: 蓝牙无法使用？
A: 确认BT固件 `BCM4345C0.hcd` 已正确放置，且设备树中BT UART配置正确。

### Q: 如何定制根文件系统？
A: 修改 `board/hardkernel/rk3399-ubb/rootfs-overlay/` 目录内容。

---

## 参考文档

- 官方 Home Assistant OS 文档：https://developers.home-assistant.io/docs/hassio/
- Rockchip RK3399 技术文档
- 原项目：[twfjcn/haos-ace-tn3399-v3](https://github.com/twfjcn/haos-ace-tn3399-v3)
- 上游项目：[LanSilence/haos-ace](https://github.com/LanSilence/haos-ace)

---

## 维护者

- 本工程由 Home Assistant OS 社区爱好者维护
- RK3399-UBB 适配由 [LX0507](https://github.com/LX0507) 完成
- 如有问题请提交 issue 或 PR

---

## License

本工程遵循 GPLv2/MIT 等开源协议，详见各源码目录 LICENSE 文件。

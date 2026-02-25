# SD 卡烧录文件说明

## 目录结构

```
sd_card/
├── BOOT_partition/    # BOOT 分区文件（直接拷贝到 BOOT 分区）
│   ├── BOOT.BIN       # 启动文件（必需，不含 PL bit）
│   ├── image.ub       # Linux 镜像（必需）
│   ├── boot.scr       # U-Boot 启动脚本（可选）
│   ├── system.bin     # PL bitstream（bootgen 从 system.bit 转，供 fpga load + 首屏）
│   ├── splash.rgb565  # 首屏 logo（可选，scripts/make_splash.sh 生成）
│   └── .env.sample    # BOOT 启动变量样本（复制为 .env 可启用 splash）
└── rootfs.ext4        # 根文件系统镜像（使用 dd 烧录到 rootfs 分区）
```

## 使用方法

### BOOT 分区

将 `BOOT_partition/` 文件夹下的所有文件直接拷贝到 SD 卡的 BOOT 分区（FAT32 格式）。

**重要提示**：
- `BOOT.BIN` 文件名必须全大写（不是 `boot.bin`）
- `image.ub` 文件名是小写（不是 `boot.ub`）

### 启用开机 splash（可选）

1. 在 `BOOT_partition/` 中复制样本：`.env.sample` -> `.env`
2. 编辑 `.env`，至少包含：

```bash
PL_SPLASH_ENABLE=1
PL_COLORBAR_HOLD=2
PL_SPLASH_HOLD=1
```

3. 确保 BOOT 分区存在 `splash.rgb565`（否则仅显示色条）

说明：若没有 `.env` 或 `PL_SPLASH_ENABLE` 不为 `1/yes/on`，U-Boot 会跳过 PL 首屏链路。

### rootfs 分区

在 macOS 上使用 `dd` 命令将 `rootfs.ext4` 烧录到 SD 卡的 rootfs 分区：

```bash
sudo dd if=rootfs.ext4 of=/dev/diskXs2 bs=1M status=progress
```

其中 `/dev/diskXs2` 是 SD 卡的 rootfs 分区设备（请根据实际情况替换）。

**注意**：
- 需要 root 权限（使用 `sudo`）
- 请确认设备路径正确，避免误操作
- 烧录过程可能需要几分钟

## 详细说明

更多详细的烧录说明和 macOS 脚本使用方法，请参考 macOS 工程中的具体说明文档。

---

**生成时间**: 2026-02-25 21:17:44

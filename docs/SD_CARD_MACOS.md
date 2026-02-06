# macOS 下 SD 卡制作流程

本文档描述在 **macOS** 上制作可启动 SD 卡的完整流程。**不论 SD 卡当前是否分区、分区表是什么状态**，都可以按下面步骤操作。

---

## ⚠️ 重要安全提示（请务必阅读）

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ⛔  操作前必须确认磁盘名称、容量、型号，确认为 SD 卡后再执行格式化/写入！   │
│  ⛔  选错磁盘会导致系统盘或数据盘被清空，造成无法恢复的损失！                 │
│  ⛔  若同时连接多张 SD 卡，务必谨慎核对设备号，建议只插一张卡时操作。         │
└─────────────────────────────────────────────────────────────────────────────┘
```

- 所有 `diskutil` / `dd` 操作对象必须是 **SD 卡设备**（如 `/dev/disk5`），**绝不能**是系统盘（通常是 `/dev/disk0`）或其它数据盘。
- 建议：只插入要制作的那张 SD 卡，再执行 `diskutil list`，根据容量和名称二次确认。

---

## 1. 查看磁盘，找到 SD 卡

```bash
diskutil list
```

根据 **大小**、**名称**（如 "SD Card"、"USB SD Reader" 等）确认 SD 卡对应的设备，例如 `/dev/disk5`。下文中均以 `disk5` 为例，请按实际设备号替换。

---

## 2. 解除挂载

**先卸载该磁盘上的所有分区**，否则后续分区或 dd 可能失败或误伤其它挂载点。

```bash
sudo diskutil unmountDisk /dev/disk5
```

（若为其它设备，将 `disk5` 改为对应编号，如 `disk4`、`disk6`。）

---

## 3. 创建 BOOT 分区（512MB FAT32）

将整盘重新分区：**MBR 分区表**，第一分区 **512MB FAT32** 命名为 **BOOT**，剩余空间留空（后续用 dd 写入 rootfs.ext4，不建第二个分区）。

```bash
sudo diskutil partitionDisk /dev/disk5 MBR FAT32 BOOT 512M free none R
```

参数含义简要说明：

- `partitionDisk /dev/disk5`：对指定磁盘分区。
- `MBR`：使用 MBR 分区表。
- `FAT32 BOOT 512M`：第一个分区为 FAT32，卷名 BOOT，大小 512MB。
- `free none R`：剩余空间不创建新分区（`free`），名称 `none`，类型 `R` 表示“剩余空间”。

完成后，整盘布局为：**前 512MB 为 BOOT（FAT32）**，**后面是剩余空间**。接下来需用 **fdisk** 将剩余空间做成第二分区并设为 Linux 类型（83），才能从固定扇区起正确 dd 写入 rootfs.ext4。

---

### 3.1 彻底卸载磁盘（关键）

在进入 fdisk 前，必须先**彻底卸载整张磁盘**，否则 fdisk 可能无法正确写入分区表。

```bash
sudo diskutil unmountDisk /dev/disk5
```

**注意：** 必须是 **`unmountDisk`**（卸载整盘），而不是 `unmount`（仅卸载单个分区）。

---

### 3.2 使用 fdisk 将剩余空间设为 Linux 分区 (83)

进入 fdisk 交互，编辑第二分区：类型改为 **83 (Linux)**，起始扇区 **1048576**（即 512MB 处），大小保持默认（占满剩余空间）。

```bash
sudo fdisk -e /dev/disk5
```

在 `fdisk>` 提示下依次输入：

| 输入 | 含义 |
|------|------|
| `edit 2` | 编辑第 2 个分区表项 |
| `83` | Partition ID：Linux (83) |
| `n` | 使用 CHS 模式（按提示选 n） |
| `1048576` | Offset（起始扇区，512MB = 1048576 扇区） |
| 回车 | Size：直接回车表示用默认最大（占满剩余空间） |
| `write` | 写入分区表 |
| `y` | 确认写入 |
| `quit` | 退出 fdisk |

完成后，第二分区从扇区 1048576 开始，类型为 Linux (83)，即可在步骤 4 中用 dd 写入 rootfs.ext4。

---

## 4. 使用 dd 将 rootfs.ext4 写入 root 区域

两分区时（BOOT 512M + ROOT R），第二分区从 **第 1048576 个扇区**开始（512MB = 1048576×512）。使用 **字符设备** `rdisk` 比 `disk` 更快。

```bash
sudo dd if=/Users/norman/FPGAProjects/OMP/sd_card/rootfs.ext4 of=/dev/rdisk5 bs=1m seek=512 conv=sync status=progress
```

**参数说明：**

| 参数 | 含义 |
|------|------|
| `if=...` | **输入文件**：本仓库中的 `rootfs.ext4` 镜像路径，按你的实际路径修改。 |
| `of=/dev/rdisk5` | **输出设备**：SD 卡对应的**原始（raw）设备**。`rdisk5` 对应 `disk5`，写入时不经系统缓存，速度更快。 |
| `bs=1m` | **块大小**：每次读写 1MB，比 `bs=512` 少很多 I/O 次数，写入更快。 |
| `seek=512` | **跳过前 512 个 1MB 块**（即 512MB），从第二分区（ROOT）起始开始写，不会覆盖 BOOT。 |
| `conv=sync` | 保证数据完整同步到设备；若输入不足一个块，用零填充到 `bs` 大小。 |
| `status=progress` | 在写入过程中打印进度。 |

**提速说明：** 使用 `bs=1m seek=512` 比 `bs=512 seek=1048576` 通常快数倍；若仍只有约 2MB/s，多为读卡器或 SD 卡本身限制（如 USB 2.0、Class 4 卡）。

**注意：** `of=` 必须是 **你的 SD 卡** 的 `rdisk` 设备（如 `rdisk5`），切勿写错成系统盘或其它磁盘。

---

## 5. 再次卸载

写入完成后卸载整盘，便于安全拔卡：

```bash
sudo diskutil unmountDisk /dev/disk5
```

---

## 6. 验证

拔掉 SD 卡再重新插入。在 macOS 下应能识别出 **BOOT** 分区（FAT32），可打开查看其中的启动文件。root 分区为 ext4，macOS 无法直接挂载，属正常现象。  
若 BOOT 分区能识别且内容正确，即表示 SD 卡在 macOS 侧制作完成。

---

## 7. 后续：从 rootfs.tar.gz 制作 rootfs.ext4

在 macOS 上无法直接挂载 ext4，若在 macOS 挂载后解压 rootfs.tar.gz 也会存在路径、权限等引用问题，不适合直接使用。  
因此 **rootfs.ext4** 建议在 **Linux 环境**（如虚拟机、WSL 或开发板）中由 rootfs.tar.gz 制作，得到 `rootfs.ext4` 后再拷贝回本仓库 `sd_card/` 目录，在 macOS 上按本文档步骤 4 用 dd 写入。  
从 rootfs.tar.gz 制作 rootfs.ext4 的具体步骤将另行说明。

---

## 小结（macOS 流程一览）

1. `diskutil list` → 确认 SD 卡设备（如 `/dev/disk5`）。
2. **再次确认设备名、容量、型号，避免误操作系统盘或其它盘。**
3. `sudo diskutil unmountDisk /dev/disk5`
4. `sudo diskutil partitionDisk /dev/disk5 MBR FAT32 BOOT 512M free none R`（BOOT 512MB + 剩余空间）
5. **再次** `sudo diskutil unmountDisk /dev/disk5`（关键：必须 unmountDisk 整盘）
6. `sudo fdisk -e /dev/disk5` → `edit 2` → `83` → `n` → `1048576` → 回车 → `write` → `y` → `quit`（将剩余空间设为 Linux 分区）
7. `sudo dd if=.../sd_card/rootfs.ext4 of=/dev/rdisk5 bs=1m seek=512 conv=sync status=progress`
8. `sudo diskutil unmountDisk /dev/disk5`
9. 重新插拔，确认 BOOT 分区可识别即表示制作完成。

脚本自动化：可使用仓库中的 `scripts/step5_flash_sd_card.sh`（在 macOS 上执行），在已按上述步骤做好分区的前提下，自动拷贝 BOOT 文件并 dd 写入 rootfs.ext4。

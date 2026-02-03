# Step4 方案A 步骤4.2 rootfs 镜像创建脚本 - 问题与修复

## 问题 1：rootfs.ext4 在 Mac 上是全零（无 ext4 魔数）

**可能原因：**

1. **脚本中途失败**：若 `mkfs.ext4` 或 `mount` 需要 sudo 时失败（例如未输入密码），脚本在 `set -e` 下会退出，此时 `rootfs.ext4` 仍是步骤 3 里 `dd if=/dev/zero` 生成的全零文件，却被后续步骤复制到 sd_card，传到 Mac 后就是全零。
2. **步骤 1 大小计算错误**：`tar -zxf rootfs.tar.gz --to-stdout .` 里用 `.` 作为成员名，很多 tar 里没有名为 `.` 的成员，会解出 0 字节，导致 `ROOTFS_ACTUAL_SIZE_MB=0`，镜像偏小或后续逻辑异常。
3. **从 VM 拷到 Mac 时出错**：例如 RDP 复制到编辑器可能产生空文件或截断，应用 scp/共享文件夹拷贝。

---

## 修复 1：步骤 1 - 可靠计算解压后大小

**原命令（可能得到 0）：**
```bash
ROOTFS_ACTUAL_SIZE_MB=$(tar -zxf rootfs.tar.gz --to-stdout . 2>/dev/null | wc -c | awk '{print int($1/1024/1024)}')
```

**推荐改为（二选一）：**

```bash
# 方法 A：用 gzip -l（快，4GB 以下准确）
ROOTFS_ACTUAL_SIZE_MB=$(gzip -l rootfs.tar.gz | tail -1 | awk '{print int($2/1024/1024)}')

# 方法 B：解压到 stdout 再计字节（任意大小，稍慢）
ROOTFS_ACTUAL_SIZE_MB=$(zcat rootfs.tar.gz | wc -c | awk '{print int($1/1024/1024)}')
```

若 `ROOTFS_ACTUAL_SIZE_MB` 仍为 0，应报错退出，例如：

```bash
if [ -z "$ROOTFS_ACTUAL_SIZE_MB" ] || [ "$ROOTFS_ACTUAL_SIZE_MB" -eq 0 ]; then
    echo -e "${RED}错误: 无法计算 rootfs 大小（请检查 rootfs.tar.gz）${NC}"
    exit 1
fi
```

---

## 修复 2：步骤 4/5 之后增加 ext4 魔数校验

在**步骤 5 卸载镜像之后**、**步骤 6 复制之前**，增加校验，避免把全零文件当 rootfs 拷走：

```bash
# 校验 rootfs.ext4 是否为合法 ext4（魔数 0x53 0xEF 在偏移 1080）
EXT4_MAGIC=$(dd if=./rootfs.ext4 bs=1 skip=1080 count=2 2>/dev/null | hexdump -e '2/1 "%02x"' | tr -d ' ')
if ! echo "$EXT4_MAGIC" | grep -qE '53ef|ef53'; then
    echo -e "${RED}错误: rootfs.ext4 无 ext4 魔数（当前: $EXT4_MAGIC），镜像可能未正确格式化或为空${NC}"
    exit 1
fi
echo -e "${GREEN}✓ rootfs.ext4 校验通过（ext4 魔数正确）${NC}"
echo ""
```

这样若脚本在 mkfs/mount 处失败，留下的是全零文件，就不会被误复制到 sd_card。

---

## 修复 3：步骤 6 冗余复制

当前脚本在 `cd "${IMAGES_DIR}"` 下执行，步骤 6 的：

```bash
cp ./rootfs.ext4 "${IMAGES_DIR}/rootfs.ext4"
```

是同一目录自拷，可删除；步骤 8 直接从 `./rootfs.ext4` 拷到 sd_card 即可。

---

## 建议操作流程

1. **在 VM（PetaLinux 工程）里**按上面修改步骤 1、增加魔数校验、去掉冗余步骤 6。
2. **用 sudo 完整跑一遍脚本**，确保所有 sudo 步骤（mkfs、mount、umount）都成功。
3. **在 VM 上先本地校验**：
   ```bash
   dd if=images/linux/rootfs.ext4 bs=1 skip=1080 count=2 | hexdump -C
   ```
   应看到 `53 ef`。
4. **再用 scp 或共享文件夹**把 `sd_card/rootfs.ext4` 拷到 Mac，不要用 RDP 直接粘贴到编辑器。

按上述修改后，生成的 rootfs.ext4 应为合法 ext4，在 Mac 上 dd 到 SD 卡后，板子即可正常挂载 rootfs。

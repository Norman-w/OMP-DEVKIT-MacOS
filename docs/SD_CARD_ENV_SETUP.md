# SD卡一键烧录环境配置说明

本脚本支持自动检测SD卡、自动烧录、自动输入密码。

## 环境变量配置

请在项目根目录创建 `dev.env` 文件（参考 dev.env.sample），内容如下：

```
VM_IP=192.168.7.234
VM_USER=norman
VM_PASSWORD=your_password_here
VM_SD_PATH=/home/norman/petalinux-projects/OMP/sd_card
```

- VM_IP：虚拟机IP
- VM_USER：虚拟机用户名
- VM_PASSWORD：虚拟机密码（用于sshpass自动登录）
- VM_SD_PATH：虚拟机sd_card路径

> dev.env 不要提交到版本库，dev.env.sample可提交。

## 自动烧录说明

- 插入SD卡后，脚本会自动检测。
- 若只检测到一个SD卡且结构符合预期，将自动烧录，无需手动输入编号和确认。
- 若需密码，自动读取dev.env并用sshpass处理。

## 适用脚本

- onekey_sd_card.sh
- step5_flash_sd_card.sh

## 依赖

- sshpass（如需自动输入密码）

## 示例

1. 复制dev.env.sample为dev.env并填写真实信息。
2. 执行 `./scripts/onekey_sd_card.sh`。


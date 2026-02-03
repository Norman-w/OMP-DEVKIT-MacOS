# 远程工作时使用


* 在Windows上执行PL工程编辑
* 在Windows内的VM Ubuntu编码PetaLinux工程
  * 执行build
  * 使用dd打包成ext4 64M+镜像(WIFI基础版实际上只有22M解压后)
  * 复制到Windows目录中
* 在MacOS中远程Windows
  * 把Win通过 VM共享->Win 的文件拷贝到MacOS
  * 使用dd烧录ext4到rootfs分区
  * 把必要的文件拷贝到ROOT(FAT/32)分区
  * 拔卡
* 在开发板测试
  * 插卡
  * 开机
  * 使用MacOS串口调试助手看输出,也可以执行一些命令比如配网
  * 使用ssh连接到开发板(已配网或已插网线的情况下)
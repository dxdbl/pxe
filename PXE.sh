#!/bin/bash
# ###############################
# 半自动安装配置PXE+Kickstart
# Author dxdbl
# 
# 
# 
# 
# ###############################
# 
# 前期准备
unalias mv
unalias cp

# 关闭 firewalld 和 iptables
systemctl stop firewalld.service
systemctl disable firewalld.service
service iptables stop
systemctl disable iptables

# 关闭 seliniux
sed  -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

# 利用 iso 文件创建本地yum源
# 上传镜像文件到 /opt/centos7.4 目录
# 挂载 iso 镜像
mkdir -p /data/yum
mkdir -p /opt/centos7.4
mount -o loop /opt/centos7.4/CentOS-7.4-x86_64-DVD-1708.iso /data/yum

# 备份原来的 yum 源目录
mv /etc/yum.repos.d /etc/yum.repos.d.bak
mkdir -p /etc/yum.repos.d

echo "[centos-source]
name=CentOS 7.4 Linux Local Source
baseurl=file:///data/yum
enabled=1
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release" >> /etc/yum.repos.d/local.repo

# 安装 HTTP、TFTP、DHCP 服务
yum -y install dhcp tftp-server httpd syslinux syslinux-tftpboot  #安装相应的服务包
yum -y install xinetd             # 安装超级守护进程xinetd
systemctl enable dhcpd.service    # 设置dhcp开机启动
systemctl enable tftp             # 设置tftp开机启动
systemctl start tftp              # 启动tftp服务
systemctl enable httpd
systemctl start httpd             # 启动http服务
systemctl enable tftp.service

# 配置DHCP服务(dhcp文件目录需手动修改)
cd /etc/dhcp/
cp /usr/share/doc/dhcp-4.2.5/dhcpd.conf.example .   # 复制模板配置文件
mv dhcpd.conf.example dhcpd.conf     # 改名为dhcpd.conf，顶替以前的配置文件

# 配置dhcp的IP地址池(需手动修改)
sed -i '/DHCP server to understand the network topology/a\subnet 10.11.220.0 netmask 255.255.255.0{\nrange 10.11.220.4 10.11.220.16;\nnext-server 10.11.220.3;\nfilename "pxelinux.0";\n}' dhcpd.conf
# 重启DHCP服务
systemctl restart dhcpd.service     

# 准备yum源文件及kickstart文件(默认root密码为root,安装完请及时修改)
cd /var/www/html
mkdir centos7.4
mkdir ksdir
mount -o loop /opt/centos7.4/CentOS-7.4-x86_64-DVD-1708.iso centos7.4

# 文件名可能不同(手动修改)
cp /root/anaconda-ks.cfg ksdir/ks7.cfg
chmod +r ksdir/ks7.cfg 
cat >  ksdir/ks7.cfg  <<EOF
#version=DEVEL
# System authorization information
auth --enableshadow --passalgo=sha512
# Use CDROM installation media
url --url=http://10.11.220.100/centos7.4/     #  指明yum源的路径
# Use graphical install
text
# Run the Setup Agent on first boot
firstboot --enable
ignoredisk --only-use=sda
# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'
# System language
lang zh_CN.UTF-8

# Network information #网卡配置(自己手动修改网卡信息)
network  --bootproto=dhcp --device=eno1 --onboot=off --ipv6=auto --no-activate
network  --bootproto=dhcp --device=eno2 --onboot=off --ipv6=auto
network  --bootproto=dhcp --device=enp5s0f0 --onboot=on --ipv6=auto
network  --bootproto=dhcp --device=enp5s0f1 --onboot=off --ipv6=auto
network  --bootproto=dhcp --device=enp8s0f0 --onboot=off --ipv6=auto
network  --bootproto=dhcp --device=enp8s0f1 --onboot=off --ipv6=auto
network  --hostname=localhost

# Root password ()
rootpw root
# System services
services --enabled="chronyd"
# System timezone
timezone Asia/Shanghai --isUtc
# X Window System configuration information
xconfig  --startxonboot
# System bootloader configuration
bootloader --location=mbr --boot-drive=sda
# autopart --type=lvm #autopart --type=lvm  # 不能和后面的 part重复
# Partition clearing information
#clearpart --none --initlabel
zerombr
clearpart --all
# Disk partitioning information
# 分区表信息，如果你想添加分区，可按照该格式添加

part biosboot --fstype="BIOS Boot" --ondisk=sda --size=1   
part /boot --fstype="xfs" --ondisk=sda --size=1024
part swap --fstype="swap" --ondisk=sda --size=32768  
part / --asprimary --fstype="xfs" --ondisk=sda --size=512000
part /var/log --asprimary --fstype="xfs" --ondisk=sda --size=307200
part /var/lib/docker --asprimary --fstype="xfs" --ondisk=sda --size=307200

reboot         # 安装完成之后重启

%packages
@^gnome-desktop-environment
@base
@core
@desktop-debugging
@development
@dial-up
@directory-client
@fonts
@gnome-desktop
@guest-agents
@guest-desktop-agents
@input-methods
@internet-browser
@java-platform
@multimedia
@network-file-system-client
@networkmanager-submodules
@print-client
@x11
chrony

%end

%addon com_redhat_kdump --disable --reserve-mb='auto'

%end

%anaconda
pwpolicy root --minlen=6 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=6 --minquality=1 --notstrict --nochanges --notempty
%end

EOF


# 准备内核文件,菜单文件

cd /var/lib/tftpboot/
mkdir -p /var/lib/tftpboot/centos7.4
cp /var/www/html/centos7.4/images/pxeboot/{vmlinuz,initrd.img} centos7.4
cp /usr/share/syslinux/pxelinux.0 .
mkdir pxelinux.cfg
cp /var/www/html/centos7.4/isolinux/isolinux.cfg  pxelinux.cfg/default
cp /var/www/html/centos7.4/isolinux/vesamenu.c32 .
cp /data/yum/isolinux/splash.png .
cp /var/www/html/centos7.4/isolinux/boot.msg .

cat > pxelinux.cfg/default <<EOF
default vesamenu.c32
timeout 600

display boot.msg

# Clear the screen when exiting the menu, instead of leaving the menu displayed.
# For vesamenu, this means the graphical background is still displayed without
# the menu itself for as long as the screen remains in graphics mode.
menu clear
menu background splash.png
menu title CentOS 7.4
menu vshift 8
menu rows 18
menu margin 8
#menu hidden
menu helpmsgrow 15
menu tabmsgrow 13

# Border Area
menu color border * #00000000 #00000000 none

# Selected item
menu color sel 0 #ffffffff #00000000 none

# Title bar
menu color title 0 #ff7ba3d0 #00000000 none

# Press [Tab] message
menu color tabmsg 0 #ff3a6496 #00000000 none

# Unselected menu item
menu color unsel 0 #84b8ffff #00000000 none

# Selected hotkey
menu color hotsel 0 #84b8ffff #00000000 none

# Unselected hotkey
menu color hotkey 0 #ffffffff #00000000 none

# Help text
menu color help 0 #ffffffff #00000000 none

# A scrollbar of some type? Not sure.
menu color scrollbar 0 #ffffffff #ff355594 none

# Timeout msg
menu color timeout 0 #ffffffff #00000000 none
menu color timeout_msg 0 #ffffffff #00000000 none

# Command prompt text
menu color cmdmark 0 #84b8ffff #00000000 none
menu color cmdline 0 #ffffffff #00000000 none

# Do not display the actual menu unless the user presses a key. All that is displayed is a timeout message.

menu tabmsg Press Tab for full configuration options on menu items.

menu separator # insert an empty line
menu separator # insert an empty line

label centos7.4
  menu default        # 默认光标停在这一行
  menu label Auto Install CentOS Linux ^7
  kernel centos7.4/vmlinuz
  append initrd=centos7.4/initrd.img ks=http://10.11.220.100/ksdir/ks7.cfg   # 指明ks文件位置 
  
label local
  menu label Boot from ^local drive
  localboot 0xffff
menu end

EOF



# 善后工作
alias cp='cp -i'
alias mv='mv -i'


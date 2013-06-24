##dsnat简介

dsnat(Dynamic Source  Network Address Translation) 是一个基于lvs的模块,在taobao开源的[FNAT][]基础上开发,dsnat位于网络的网关位置,内网访问外网时,会将内网地址改成公网地址池中的ip,轮询选择

目前该模块只支持ipv4下的TCP,UDP协议, ICMP暂时还不支持

dsnat_tools包含ipvsadm和keepalived这2个工具,在官方源码的基础上修改添加了对dsnat的支持
- ipvsadm是对lvs进行配置的用户空间工具,ipvsadm->lvs类似于iptables->netfilter
- keepalived是对lvs集群的一个自动化配置工具(以服务形式常驻内存),可针对rs自动摘除和添加rs到vs中;并带有HA功能,提供热备容灾



## 安装

##### 安装二进制包(xiaomi内网可访问)

1. 内核

```
rpm -ivh http://xiaomi-kernel.xae.xiaomi.com/mi4-dsnat/kernel-firmware-2.6.32-279.23.1.mi4.el6.x86_64.rpm
rpm -ivh http://xiaomi-kernel.xae.xiaomi.com/mi4-dsnat/kernel-2.6.32-279.23.1.mi4.el6.x86_64.rpm
#开发包
rpm -ivh http://xiaomi-kernel.xae.xiaomi.com/mi4-dsnat/kernel-devel-2.6.32-279.23.1.mi4.el6.x86_64.rpm
rpm -ivh http://xiaomi-kernel.xae.xiaomi.com/mi4-dsnat/kernel-headers-2.6.32-279.23.1.mi4.el6.x86_64.rpm 
```

2. ipvsadm/keepalive

```
#如发现/usr/local目录下的ipvsadm/keepalived,删掉
wget http://xiaomi-kernel.xae.xiaomi.com/mi4-dsnat/tools/ipvsadm -O /sbin/ipvsadm
wget http://xiaomi-kernel.xae.xiaomi.com/mi4-dsnat/tools/keepalived -O /sbin/keepalived

```


##### 源码安装

过程可以参考[FNAT][],将补丁换成[dsnat][]即可

<!--more-->

1. 下载 redhat 6.3的内核

```
wget ftp://ftp.redhat.com/pub/redhat/linux/enterprise/6Server/en/os/SRPMS/kernel-2.6.32-279.23.1.el6.src.rpm
```

2. 准备代码

```
cat > ~/.rpmmacros << 'EOF'
%_topdir ~/rpms
%_tmppath ~/rpms/tmp
%_sourcedir ~/rpms/SOURCES
%_specdir ~/rpms/SPECS
%_srcrpmdir ~/rpms/SRPMS
%_rpmdir ~/rpms/RPMS
%_builddir ~/rpms/BUILD
EOF

cd
mkdir -p ~/rpms/{tmp,BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
rpm -ivh kernel-2.6.32-279.23.1.el6.src.rpm
cd ~/rpms/SPECS
rpmbuild -bp kernel.spec
```

3. 打补丁

```
cd ~/rpms/BUILD/
cd kernel-2.6.32-220.23.1.el6/linux-2.6.32-279.23.1.el6.x86_64/
wget https://raw.github.com/xiaomi-sa/dsnat/master/dsnat-kernel-2.6.32-279.23.1.el6/dsnat-2.6.32-279.23.1.el6.xiaomi.noconfig.patch
patch -p1 < dsnat-2.6.32-279.23.1.el6.xiaomi.noconfig.patch
```

4. 编译安装

```
make -j16
make modules_install
make install
##重启使用新内核
init 6
```

## LVS TOOL 安装

标准的ipvsadm和keepalive将无法正常使用,
需要编译安装ipvsadm和keepalived,在[dsnat_tools][]下载工具源码

```
git clone git@github.com:xiaomi-sa/dsnat.git
cd dsnat/dsnat_tools/ipvsadm
make && make install
cd ../keepalived
make && make install
```

## 配置用例
将lvs放在网关的位置,假设网络环境是这样的

```
client eth0　  1.1.1.1      255.255.0.0     (cip)
lvs    eth0    1.1.100.1    255.255.0.0     (gw ip)
lvs    eth1    1.2.100.1-4  255.255.0.0     (lip)
rs     eth1    1.2.1.4      255.255.0.0     (rip)
```

网络环境是(模拟一下)

- client在内网
- realserver在外网
- 内网到外网的路由指向lvs
 - route add -net 1.2.0.0 netmask 255.255.0.0 gw 1.1.100.1(用默认路由也可以)
- 外网服务器可以访问lvs的lip


![Alt text][dsnat_img]


### 网关的配置

```
##写入开机启动脚本

# echo >> /etc/rc.local << 'EOF'
#打开转发设置
echo 1 > /proc/sys/net/ipv4/ip_forward

#由于gro/lro功能会影响转发后数据包大小,超过MTU后会被丢弃重发,系统默认是开启的
#关掉gw ip所在的网卡gro/lro
ethtool -K eth0 gro off
ethtool -K eth0 lro off

#绑定网卡中断,让中断在多核cpu上轮训,效果很赞,同样是gw ip所在的网卡
set_irq_affinity.sh eth0
EOF

##关闭irqbalance
# service irqbalance stop
# chkconfig --level 2345 irqbalance off

## 绑定local address
# echo >> /etc/rc.local << 'EOF'
ip addr add 1.2.100.1/16 dev eth1
ip addr add 1.2.100.2/16 dev eth1
ip addr add 1.2.100.3/16 dev eth1
ip addr add 1.2.100.4/16 dev eth1
EOF
```

### zone 说明

- zone是有序的
- zone是local address的容器
- 源地址会从第一个网段开始,依次检查到最后一个,一旦找到相匹配的网段即终止检查
- 网段内如果没有local address
- 或者local address中的ip上的所有端口都被占用
- 或者没有匹配到任何网段lvs将不会做任何处理(可视为丢弃)


### 通过ipvsadm配置lvs规则

如果执行报错,请核对一下使用的内核补丁是否生效,ipvsadm是否为[dsnat_tools][]编译安装版本

```
#打开添加一个0/0的虚拟服务,开启dsnat,让所有的内网请求都能命中该服务
ipvsadm –A –t 0.0.0.0:0 –s rr


#添加一个1.1.0.0/16的网段,用来做源地址匹配(client的ip是1.1.1.1/16)
ipvsadm -K  --zone 1.1.0.0/16

#为1.0.0.0/16的zone添加local address
ipvsadm -P --zone 1.1.0.0/16 -z 1.2.100.1
ipvsadm -P --zone 1.1.0.0/16 -z 1.2.100.2

#再添加一个缺省的网段0/0
ipvsadm -K  --zone 0.0.0.0/0

#为缺省网段添加local address
ipvsadm -P --zone 0.0.0.0/0 -z 1.2.100.3
...



#查看vs
ipvsadm -ln
  
#查看公网ip地址池
ipvsadm -G
```



### 通过keepalive配置lvs规则
如果执行报错,请核对一下使用的内核补丁是否生效,keepalive是否为[dsnat_tools][]编译安装版本,
keepalive需要2台机器了,这里给出一台的配置

- 启动：service keepalived start
- 更新：service keepalived reload
- 停止：service keepalived stop

```
## /etc/keepalived/keepalived.conf
global_defs {
   router_id LVS_DEVEL
}
  
##这是lvs的配置,写好公网ip地址池的ip
local_address_group laddr_g1 {
        1.2.100.1
        1.2.100.2
}

local_address_group laddr_g2 {
        1.2.100.3
}

zone 1.1.0.0 16 {
    laddr_group_name laddr_g1
}

zone 0.0.0.0 0.0.0.0 {
    laddr_group_name laddr_g2
}

##这是High Availability部分的配置,会根据lvs的状况,让virtual_ipaddress在合适的机器上浮动
vrrp_sync_group G1 {
  group {
    VI_1
    VI_2
  }
}

##配置eth0浮动ip
vrrp_instance VI_1 {
        state MASTER
        interface eth0
        virtual_router_id 52
        priority 100 
        advert_int 1
        authentication {
                auth_type pass
                auth_pass 1111
        }
  
        virtual_ipaddress {
                1.1.100.1
        }
}

#配置eth1浮动ip
vrrp_instance VI_2 {
        state master
        interface eth1
        virtual_router_id 53
        priority 100
        advert_int 1
        authentication {
                auth_type pass
                auth_pass 1111
        }

        virtual_ipaddress {
                1.2.100.1/16
                1.2.100.2/16
        }
}

##配置lvs,添加一个0/0的虚拟服务,开启dsnat,让所有的内网请求都能命中该服务
virtual_server 0.0.0.0 0 {
        delay_loop 6
        lb_algo rr
        lb_kind FNAT
        protocol TCP
        laddr_group_name laddr_g1
}
```


## 资源

* [FNAT][]
* [dsnat][]
* [dsnat_tools][]


[FNAT]:http://kb.linuxvirtualserver.org/wiki/IPVS_FULLNAT_and_SYNPROXY
[dsnat_img]:https://raw.github.com/xiaomi-sa/dsnat/master/dsnat-kernel-2.6.32-220.23.1.el6/dsnat.jpg
[dsnat]:https://github.com/xiaomi-sa/dsnat/tree/master/dsnat-kernel-2.6.32-279.23.1.el6/dsnat-2.6.32-279.23.1.el6.xiaomi.noconfig.patch
[dsnat_tools]:https://github.com/xiaomi-sa/dsnat/tree/master/dsnat_tools

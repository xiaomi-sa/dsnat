##dsnat简介
dsnat(Dynamic Source  Network Address Translation) 是一个基于lvs的模块,在taobao开源的[FNAT][]基础上开发,dsnat位于网络的网关位置,内网访问外网时,会将内网地址改成公网地址池中的ip,轮询选择

目前该模块只支持ipv4下的TCP,UDP协议, ICMP暂时还不支持

## 安装
过程可以参考[FNAT][],将补丁换成[dsnat][]即可
<!--more-->
1\. 下载 redhat 6.2的内核
<pre>
wget ftp://ftp.redhat.com/pub/redhat/linux/enterprise/6Server/en/os/SRPMS/kernel-2.6.32-220.23.1.el6.src.rpm
</pre>

2\. 提取源码
<pre>
 vim ~/.rpmmacros;
   add:
     %_topdir ~/rpms
     %_tmppath ~/rpms/tmp
     %_sourcedir ~/rpms/SOURCES
     %_specdir ~/rpms/SPECS
     %_srcrpmdir ~/rpms/SRPMS
     %_rpmdir ~/rpms/RPMS
     %_builddir ~/rpms/BUILD
 cd;
   mkdir rpms;
   mkdir rpms/tmp;
   mkdir rpms/SOURCES;
   mkdir rpms/SPECS;
   mkdir rpms/SRPMS;
   mkdir rpms/RPMS;
   mkdir rpms/BUILD;
 rpm -ivh kernel-2.6.32-220.23.1.el6.src.rpm;
 cd ~/rpms/SPECS;
 rpmbuild -bp kernel.spec;
</pre>

3\. 打补丁
<pre>
 git clone git@github.com:yubo/patch.git
 cd ~/rpms/BUILD/;
 cd kernel-2.6.32-220.23.1.el6/linux-2.6.32-220.23.1.el6.x86_64/;
 cp ~/patch/dsnat-kernel-2.6.32-220.23.1.el6/dsnat-2.6.32-220.23.1.el6.xiaomi.noconfig.patch ./;
 patch -p1 < dsnat-2.6.32-220.23.1.el6.xiaomi.noconfig.patch;
</pre>

4\. 编译
<pre>
 make -j16;
 make modules_install;
 make install;
</pre>

## LVS TOOL 安装
内核编译完成后,重启使新内核生效后,开始编译安装ipvsadm和keepalived,在[dsnat_tools][]下载工具,展开
<pre>
cd ~/patch/dsnat-kernel-2.6.32-220.23.1.el6/dsnat_tools/ipvsadm;
 make;
 make install;

cd ~/patch/dsnat-kernel-2.6.32-220.23.1.el6/dsnat_tools/keepalived;
 ./configure --with-kernel-dir="/lib/modules/`uname -r`/build";
 make;
 make install;
</pre>

## 配置
将lvs放在网关的位置
![Alt text][dsnat_img]

<pre>
#打开转发设置
echo 1 > /proc/sys/net/ipv4/ip_forward

#打开添加一个0/0的虚拟服务,让所有的内网请求都能命中该服务
ipvsadm –A –t 0.0.0.0:0 –s rr

#为vs的地址池添加公网ip
ipvsadm –P –t 0.0.0.0:0 -z 1.2.100.1
ipvsadm –P –t 0.0.0.0:0 -z 1.2.100.2
ipvsadm –P –t 0.0.0.0:0 -z 1.2.100.3
...

#查看vs
ipvsadm -ln

#查看地址池
ipvsadm -G
</pre>

## 资源

* [FNAT][]
* [dsnat][]
* [dsnat_tools][]


[FNAT]:http://kb.linuxvirtualserver.org/wiki/IPVS_FULLNAT_and_SYNPROXY
[dsnat_img]:https://raw.github.com/xiaomi-sa/dsnat/master/dsnat-kernel-2.6.32-220.23.1.el6/dsnat.jpg
[dsnat]:https://github.com/xiaomi-sa/dsnat/tree/master/dsnat-kernel-2.6.32-220.23.1.el6/dsnat-2.6.32-220.23.1.el6.xiaomi.noconfig.patch
[dsnat_tools]:https://github.com/xiaomi-sa/dsnat/tree/master/dsnat-kernel-2.6.32-220.23.1.el6/dsnat_tools

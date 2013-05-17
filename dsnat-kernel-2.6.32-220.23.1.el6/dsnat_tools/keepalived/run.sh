#!/bin/sh
yum install libnl-devel
./configure --prefix=/ --mandir=/usr/local/share/man/ --with-kernel-dir=/usr/src/kernels/`uname  -r`

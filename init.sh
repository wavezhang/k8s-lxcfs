#!/bin/bash

#wget https://copr-be.cloud.fedoraproject.org/results/ganto/lxd/epel-7-x86_64/00486278-lxcfs/lxcfs-2.0.5-3.el7.centos.x86_64.rpm
yum install lxcfs-2.0.5-3.el7.centos.x86_64.rpm -y

systemctl enable lxcfs
systemctl start lxcfs

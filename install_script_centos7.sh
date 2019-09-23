# https://www.howtoforge.com/tutorial/centos-kubernetes-docker-cluster/

# centos7
# vim /etc/hosts

# 10.0.15.10      k8s-master
# 10.0.15.21      node01
# 10.0.15.22      node02

# Disable SELinux
setenforce 0
sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux

# Enable br_netfilter Kernel Module
modprobe br_netfilter
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables

# Disable SWAP
swapoff -a
# vim /etc/fstab
# Comment the swap line

# install
yum update -y
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
        https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

yum install -y docker-ce-18.06.1.ce-3.el7 kubelet-1.13.5-0 kubeadm-1.13.5-0 kubectl-1.13.5-0
yum install -y yum-plugin-versionlock
yum versionlock add docker-ce kubelet kubeadm kubectl

# start svc
reboot

systemctl start docker && systemctl enable docker
systemctl start kubelet && systemctl enable kubelet

# - Change the cgroup-driver
# We need to make sure the docker-ce and kubernetes are using same 'cgroup'.

# Check docker cgroup using the docker info command.

# docker info | grep -i cgroup

# And you see the docker is using 'cgroupfs' as a cgroup-driver.

# Now run the command below to change the kuberetes cgroup-driver to 'cgroupfs'.

sed -i 's/cgroup-driver=systemd/cgroup-driver=cgroupfs/g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Reload the systemd system and restart the kubelet service.

systemctl daemon-reload
systemctl restart kubelet

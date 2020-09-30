#!/bin/bash


# Ensure that modprobe is loaded
modprobe br_netfilter

# Allow IPtables to see bridge traffic
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system


# Add exceptions for the required firewalls
# Kubernetes API Server
firewall-cmd --zone=public --add-port=6443/tcp --permanent
# etcd server client API
firewall-cmd --zone=public --add-port=2379-2380/tcp --permanent
# Kubelet API
firewall-cmd --zone=public --add-port=10250/tcp --permanent
# Kube-scheduler
firewall-cmd --zone=public --add-port=10251/tcp --permanent
# Kube-controller-manager
firewall-cmd --zone=public --add-port=10252/tcp --permanent
# Node Port sericest
firewall-cmd --zone=public --add-port=30000-32767/tcp --permanent

# restart firewalld
systemctl restart firewalld

# Setup the kubernetes repository
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF

# Set SELinux in permissive mode (effectively disabling it)
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Install Kubernetes required packages
sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

# start up kubelet
sudo systemctl enable --now kubelet

# Disable swap
sudo swapoff -a
# Disable in fstab
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Either have DNS or add master to /etc/hosts
192.168.122.92 master.localdomain

# Setup container runtime to work with Docker

cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF

# restart docker

sudo systemctl restart docker.service

### Test to see if it can get the kubeadm images

kubeadm config images pull

# To use Calico CNI
sudo kubeadm init --pod-network-cidr=192.168.0.0/16

# ubstakk tugera Cakuci ioeratir abd cystin resource definitions
sudo kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml

# Create a custom resource for calico
sudo kubectl create -f https://docs.projectcalico.org/manifests/custom-resources.yaml

# make sure calico is running
watch kubectl get pods -n calico-system

# Make sure that coredns is running
kubectl get pods --all-namespaces

# to allow a non-root user to run kubectl commands
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
# or can use 
export KUBECONFIG=/etc/kubernetes/admin.conf

# Enable kubectl autocompletion
echo 'alias k=kubectl' >>~/.bashrc
echo 'complete -F __start_kubectl k' >>~/.bashrc

# Note down the kubeadm join key 
    kubeadm join 192.168.122.92:6443 --token 8iundv.t1sy6d50rnh37f82 \
    --discovery-token-ca-cert-hash sha256:bd2f89144cdab9f2faf1489359b08c850066fee465f98558f73f311739f30f1e --v=2

# To view all of the nodes connected
kubectl get nodes

# To label the nodes

kubectl label node worker2.localdomain node-role.kubernetes.io/worker=worker
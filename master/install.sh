#!/bin/bash

# KUBE_REPO_PREFIX=registry.cn-hangzhou.aliyuncs.com/google-containers
# KUBE_HYPERKUBE_IMAGE=registry.cn-hangzhou.aliyuncs.com/google-containers/hyperkube-amd64:v1.7.0
# KUBE_DISCOVERY_IMAGE=registry.cn-hangzhou.aliyuncs.com/google-containers/kube-discovery-amd64:1.0
# KUBE_ETCD_IMAGE=registry.cn-hangzhou.aliyuncs.com/google-containers/etcd-amd64:3.0.17

# KUBE_REPO_PREFIX=$KUBE_REPO_PREFIX KUBE_HYPERKUBE_IMAGE=$KUBE_HYPERKUBE_IMAGE KUBE_DISCOVERY_IMAGE=$KUBE_DISCOVERY_IMAGE kubeadm init --ignore-preflight-errors=all --pod-network-cidr="10.244.0.0/16"

set -x

USER=$USER # 用户
GROUP=$USER # 组(默认为USER默认所属组)
FLANELADDR=https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
KUBECONF=../kubeadm.conf # 文件地址, 改成你需要的路径
REGMIRROR=YOUR_OWN_DOCKER_REGISTRY_MIRROR_URL # docker registry mirror 地址

install_docker() {
  mkdir /etc/docker
  mkdir -p /data/docker # graph为docker的储存路径
  cat << EOF > /tmp/daemon.json
{
  "registry-mirrors": ["$REGMIRROR"],
  "graph": "/data/docker"  
}
EOF

  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
  add-apt-repository \
    "deb [arch=amd64] https://mirrors.ustc.edu.cn/docker-ce/linux/$(. /etc/os-release; echo "$ID") \
    $(lsb_release -cs) \
    stable"
  apt-get update && apt-get install -y docker-ce=$(apt-cache madison docker-ce | grep 17.03 | head -1 | awk '{print $3}') # 默认安装docker17.03版本
}

add_user_to_docker_group() {
  groupadd docker
  gpasswd -a $USER docker 
}

install_kube_commands() {
  cat ../kube_apt_key.gpg | apt-key add -
  echo "deb [arch=amd64] https://mirrors.ustc.edu.cn/kubernetes/apt kubernetes-$(lsb_release -cs) main" >> /etc/apt/sources.list
  apt-get update && apt-get install -y kubelet kubeadm kubectl
}

restart_kubelet() {
  sed -i "s,ExecStart=$,Environment=\"KUBELET_EXTRA_ARGS=--pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google_containers/pause-amd64:3.1\"\nExecStart=,g" /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
  systemctl daemon-reload
  systemctl restart kubelet
}

enable_kubectl() {
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
}

apply_flannel() {
  curl -o /$HOME/kube-flannel.yml $FLANELADDR
  sudo sed -i "s,quay\.io/coreos/flannel:v0\.9\.1-amd64,registry.registry.cn-hangzhou.aliyuncs.com/acs/flannel:v0\.9\.0-amd64,g" /$HOME/kube-flannel.yml
  kubectl apply -f /$HOME/flannel
}

case "$1" in
  "pre")
    install_docker
    add_user_to_docker_group
    install_kube_commands
    ;;
  "kubernetes")
    sysctl net.bridge.bridge-nf-call-iptables=1
    restart_kubelet
    sudo sed -i '3s/.*$/Environment="KUBELET_SYSTEM_PODS_ARGS=--pod-manifest-path=/etc/kubernetes/manifests --allow-privileged=true --fail-swap-on=false"' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
    kubeadm init --config $KUBECONF --ignore-preflight-errors 'Swap'
    ;;
  "post")
    if [[ $EUID -ne 0 ]]; then
      echo "do not run as root"
      exit
    fi
    enable_kubectl
    # apply_flannel
    ;;
  *)
    echo "huh ????"
    ;;
esac

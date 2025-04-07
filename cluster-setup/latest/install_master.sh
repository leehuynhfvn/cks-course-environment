bin/sh/bin/sh

# Source: http://kubernetes.io/docs/getting-started-guides/kubeadm

set -e

source /etc/lsb-release
if [ "$DISTRIB_RELEASE" != "20.04" ]; then
    echo "################################# "
    echo "############ WARNING ############ "
    echo "################################# "
    echo
    echo "This script only works on Ubuntu 20.04!"
    echo "You're using: ${DISTRIB_DESCRIPTION}"
    echo "Better ABORT with Ctrl+C. Or press any key to continue the install"
    read
fi

# Sử dụng từ khóa 'latest' để cài đặt phiên bản mới nhất
KUBE_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt | cut -d'v' -f2)
# Đảm bảo chỉ cài đặt phiên bản 1.32.x
if [[ ! $KUBE_VERSION =~ ^1\.32\. ]]; then
    # Nếu không có phiên bản 1.32 trong stable, sử dụng phiên bản 1.32 mới nhất
    KUBE_VERSION=$(curl -L -s https://dl.k8s.io/release/stable-1.32.txt | cut -d'v' -f2)
fi
echo "Installing Kubernetes version: ${KUBE_VERSION}"

# get platform
PLATFORM=`uname -p`

if [ "${PLATFORM}" == "aarch64" ]; then
  PLATFORM="arm64"
elif [ "${PLATFORM}" == "x86_64" ]; then
  PLATFORM="amd64"
else
  echo "${PLATFORM} has to be either amd64 or arm64/aarch64. Check containerd supported binaries page"
  echo "https://github.com/containerd/containerd/blob/main/docs/getting-started.md#option-1-from-the-official-binaries"
  exit 1
fi

### setup terminal
apt-get --allow-unauthenticated update
apt-get --allow-unauthenticated install -y bash-completion binutils
echo 'colorscheme ron' >> ~/.vimrc
echo 'set tabstop=2' >> ~/.vimrc
echo 'set shiftwidth=2' >> ~/.vimrc
echo 'set expandtab' >> ~/.vimrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'alias c=clear' >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc
sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc


### disable linux swap and remove any existing swap partitions
swapoff -a
sed -i '/\sswap\s/ s/^\(.*\)$/#\1/g' /etc/fstab


### remove packages
kubeadm reset -f || true
crictl rm --force $(crictl ps -a -q) || true
apt-mark unhold kubelet kubeadm kubectl kubernetes-cni || true
apt-get remove -y docker.io containerd kubelet kubeadm kubectl kubernetes-cni || true
apt-get autoremove -y
systemctl daemon-reload



### install podman
. /etc/os-release
echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:testing.list
curl -L "http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/Release.key" | sudo apt-key add -
apt-get update -qq
apt-get -qq -y install podman cri-tools containers-common
rm /etc/apt/sources.list.d/devel:kubic:libcontainers:testing.list
cat <<EOF | sudo tee /etc/containers/registries.conf
[registries.search]
registries = ['docker.io']
EOF


### install packages
apt-get install -y apt-transport-https ca-certificates curl apt-transport-https
mkdir -p /etc/apt/keyrings
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg || true

# Sử dụng repository mới của Kubernetes v1.32
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

apt-get --allow-unauthenticated update
apt-get --allow-unauthenticated install -y docker.io containerd kubelet kubeadm kubectl kubernetes-cni
apt-mark hold kubelet kubeadm kubectl kubernetes-cni


### install containerd 
# Lấy phiên bản containerd mới nhất
CONTAINERD_VERSION=$(curl -s https://api.github.com/repos/containerd/containerd/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
echo "Installing containerd version: ${CONTAINERD_VERSION}"
wget https://github.com/containerd/containerd/releases/download/${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION:1}-linux-${PLATFORM}.tar.gz
tar xvf containerd-${CONTAINERD_VERSION:1}-linux-${PLATFORM}.tar.gz
systemctl stop containerd
mv bin/* /usr/bin
rm -rf bin containerd-${CONTAINERD_VERSION:1}-linux-${PLATFORM}.tar.gz
systemctl unmask containerd
systemctl start containerd


### containerd
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system
sudo mkdir -p /etc/containerd


### containerd config
cat > /etc/containerd/config.toml <<EOF
disabled_plugins = []
imports = []
oom_score = 0
plugin_dir = ""
required_plugins = []
root = "/var/lib/containerd"
state = "/run/containerd"
version = 2

[plugins]

  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
      base_runtime_spec = ""
      container_annotations = []
      pod_annotations = []
      privileged_without_host_devices = false
      runtime_engine = ""
      runtime_root = ""
      runtime_type = "io.containerd.runc.v2"

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        BinaryName = ""
        CriuImagePath = ""
        CriuPath = ""
        CriuWorkPath = ""
        IoGid = 0
        IoUid = 0
        NoNewKeyring = false
        NoPivotRoot = false
        Root = ""
        ShimCgroup = ""
        SystemdCgroup = true
EOF


### crictl uses containerd as default
{
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF
}


### kubelet should use containerd
{
cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS="--container-runtime-endpoint unix:///run/containerd/containerd.sock"
EOF
}



### start services
systemctl daemon-reload
systemctl enable containerd
systemctl restart containerd
systemctl enable kubelet && systemctl start kubelet


### init k8s
rm /root/.kube/config || true
kubeadm init --kubernetes-version=v${KUBE_VERSION} --ignore-preflight-errors=NumCPU --skip-token-print --pod-network-cidr 192.168.0.0/16

mkdir -p ~/.kube
sudo cp -i /etc/kubernetes/admin.conf ~/.kube/config

### CNI
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calico.yaml


# etcdctl
ETCDCTL_VERSION=$(curl -s https://api.github.com/repos/etcd-io/etcd/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
ETCDCTL_ARCH=$(dpkg --print-architecture)
ETCDCTL_VERSION_FULL=etcd-${ETCDCTL_VERSION}-linux-${ETCDCTL_ARCH}
wget https://github.com/etcd-io/etcd/releases/download/${ETCDCTL_VERSION}/${ETCDCTL_VERSION_FULL}.tar.gz
tar xzf ${ETCDCTL_VERSION_FULL}.tar.gz ${ETCDCTL_VERSION_FULL}/etcdctl
mv ${ETCDCTL_VERSION_FULL}/etcdctl /usr/bin/
rm -rf ${ETCDCTL_VERSION_FULL} ${ETCDCTL_VERSION_FULL}.tar.gz

echo
echo "### COMMAND TO ADD A WORKER NODE ###"
kubeadm token create --print-join-command --ttl 0

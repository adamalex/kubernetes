#!/bin/bash

bootstrap_docker() {
  if [[ ! -f /usr/bin/docker ]]; then
    echo "debconf debconf/frontend select Noninteractive" | sudo debconf-set-selections
    sudo apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
    echo "deb https://apt.dockerproject.org/repo ubuntu-wily main" | sudo tee /etc/apt/sources.list.d/docker.list
    sudo apt-get -qq update
    sudo apt-get -qq -y install docker-engine
  fi
}

write_hosts_file() {
  servers=$(sudo /usr/local/bin/rsc --rl10 \
    --xm '.tags' cm15 by_tag tags/by_tag \
    resource_type=instances tags[]="kube:cluster=$KUBE_CLUSTER" \
    include_tags_with_prefix="kube:")

  grep -v kube- /etc/hosts > /tmp/hosts

  for server in $servers; do
    ip=$(echo "$server" | grep -oP 'kube:ip=\K[.\w]+')
    role=$(echo "$server" | grep -oP 'kube:role=\K[.\w]+')
    node_id=$(echo "$server" | grep -oP 'kube:node_id=\K[.\w]+' || true)
    echo "$ip" kube-"$role$node_id" >> /tmp/hosts
  done

  sudo cp /tmp/hosts /etc/hosts
}

install_kubernetes() {
  if [[ ! -d /opt/kubernetes ]]; then
    wget -qP /tmp "https://github.com/kubernetes/kubernetes/releases/download/$KUBE_RELEASE_TAG/kubernetes.tar.gz"
    tar xfz /tmp/kubernetes.tar.gz -C /tmp
    sudo tar xfz /tmp/kubernetes/server/kubernetes-server-linux-amd64.tar.gz -C /opt
    grep -Po "(?<=TAG\?=).*" /tmp/kubernetes/cluster/images/etcd/Makefile | sudo tee /opt/kubernetes/ETCD_TAG > /dev/null
    echo "export PATH=$PATH:/opt/kubernetes/server/bin" | sudo tee /etc/profile.d/kubernetes.sh > /dev/null
  fi

  sudo mkdir -p /etc/kubernetes/manifests
}

pull_docker_images() {
  ETCD_IMAGE="quay.io/coreos/etcd:v$(cat /opt/kubernetes/ETCD_TAG)"
  [[ $(sudo docker images -q "$ETCD_IMAGE") ]] || sudo docker pull "$ETCD_IMAGE"

  HYPERKUBE_IMAGE="gcr.io/google_containers/hyperkube:$KUBE_RELEASE_TAG"
  [[ $(sudo docker images -q "$HYPERKUBE_IMAGE") ]] || sudo docker pull "$HYPERKUBE_IMAGE"
}

start_etcd() {
  if [[ $(sudo docker ps -a -q --filter=name=etcd) ]]; then
    sudo docker start etcd > /dev/null
  else
    sudo docker run -d -p "2379:2379" --add-host kube-master:"$MY_IP" \
      --name etcd "$ETCD_IMAGE" --listen-client-urls "http://0.0.0.0:2379" \
      --advertise-client-urls "http://kube-master:2379"
  fi

  set +e
  until sudo docker exec -i etcd /etcdctl ls / &> /dev/null; do
    sleep 1
  done
  set -e
}

write_flannel_config_to_etcd() {
  cat <<-EOF | sudo docker exec -i etcd /etcdctl set /coreos.com/network/config > /dev/null
	{
	  "Network": "18.16.0.0/16",
	  "SubnetLen": 24,
	  "Backend": { "Type": "vxlan" }
	}
	EOF
}

bootstrap_flannel() {
  if [[ ! -d /opt/flannel ]]; then
    wget -qP /tmp "https://github.com/coreos/flannel/releases/download/v$FLANNEL_VERSION/flannel-${FLANNEL_VERSION}-linux-amd64.tar.gz"
    sudo tar xfz /tmp/flannel-"$FLANNEL_VERSION"-linux-amd64.tar.gz -C /opt
    sudo mv /opt/flannel-"$FLANNEL_VERSION" /opt/flannel
  fi

  sudo /opt/flannel/flanneld -etcd-endpoints="http://kube-master:2379" --ip-masq=true &> /dev/null &

  until [[ -f /run/flannel/subnet.env ]]; do
    sleep 1
  done
}

create_flannel_bridge() {
  sudo brctl addbr "$1"
  sudo ip link set dev "$1" mtu "$FLANNEL_MTU"
  sudo ip addr add "$FLANNEL_SUBNET" dev "$1"
  sudo ip link set dev "$1" up
}

prepare_node_docker_config() {
  sudo mkdir -p /etc/systemd/system/docker.service.d

  cat <<-"EOF" | sudo tee /etc/systemd/system/docker.service.d/systemd.conf > /dev/null
	[Service]
	EnvironmentFile=/run/flannel/subnet.env
	Environment="DOCKER_NOFILE=1000000"
	ExecStart=
	ExecStart=/usr/bin/docker daemon -H fd:// --mtu=${FLANNEL_MTU} --bridge=cbr0 --ip-masq=false --iptables=false
	EOF
}

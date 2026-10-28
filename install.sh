#! /bin/bash

cat <<EOF
#######################
# Docker Installation #
#######################
EOF

# from https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository
# Add Docker's official GPG key:
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y

sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

netplan set ethernets.eth0.mtu=1450 && sudo netplan apply

sed -i "0,\/ExecStart=\/usr\/bin\/dockerd -H fd:\/\/ --containerd=\/run\/containerd\/containerd.sock/s//ExecStart=\/usr\/bin\/dockerd --mtu 1450 -H fd:\/\/ --containerd=\/run\/containerd\/containerd.sock/" /lib/systemd/system/docker.service

systemctl daemon-reload
service docker restart

cat <<EOF
##############################
# DevContainers Installation #
##############################
EOF

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

source ~/.bashrc

nvm install node

apt install libatomic1

npm install -g @devcontainers/cli

devcontainer up --workspace-folder . 

devcontainer exec --workspace-folder . kind create cluster --name pelican --config kind-prod-config.yaml --kubeconfig ./.pelican-cluster-kubeconfig

chmod -R 0777 ./.pelican-cluster-kubeconfig

sudo bash
curl -fsSL -o get-docker.sh https://get.docker.com/
curl -fsSL -o get-k3d.sh https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh

chmod +x ./get-docker.sh
chmod +x ./get-k3d.sh

./get-docker.sh
./get-k3d.sh

sudo user -aH docker $user
newgrp docker

k3d cluster create --config="./confs/k3d/config.yaml"

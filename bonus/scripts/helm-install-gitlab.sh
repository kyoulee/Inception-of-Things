curl -fsSL -o get-helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4

chmod +x ./get-helm.sh

./get-helm.sh

helm repo add gitlab https://charts.gitlab.io/
helm repo update
helm install gitlab gitlab/gitlab \
  --version 9.11.14 \
  --namespace gitlab \
  --create-namespace \
  -f values.yaml \
  --debug

docker cp ./confs/server  k3d-argocd-cluster-server-0:/tmp
docker exec -i k3d-argocd-cluster-server-0 kubectl apply -f /tmp/server/init-ns.yaml
docker exec k3d-argocd-cluster-server-0 kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.6.15/manifests/install.yaml
docker exec -i k3d-argocd-cluster-server-0 kubectl apply -f /tmp/server/argocd/service.yaml

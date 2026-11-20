# Inception-of-Things
Inception of Things


# 1. coredns-custom ConfigMap 내용 확인
docker exec k3d-<클러스터명>-server-0 kubectl get cm coredns-custom -n kube-system -o yaml

# 2. ArgoCD repo-server Pod 내부에서 직접 DNS 조회 테스트
docker exec k3d-argocd-server-0 kubectl exec -n argocd deploy/argocd-repo-server -- getent hosts gitlab.localhost || echo "DNS_FAILED"










# 알아보는거
  kubectl get cm coredns-custom -n kube-system -o yaml

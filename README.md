# multi-cluster
This project creates 2 kubernetes clusters using kind and connects them with cilium cluster mesh. Services across each cluster can be reached by dns redirection and by using the global service annotation.
Everything in this repo can be adapated for use in flux which provides gitops continuous delivery. 
You must have docker, kind, helm and cilium-cli installed first.

1. Create the kind clusters:
```
export KUBECONFIG=./cluster1.kube
kind create cluster --config=./cluster-def/cluster1.yaml
export KUBECONFIG=./cluster2.kube
kind create cluster --config=./cluster-def/cluster2.yaml
KUBECONFIG=./cluster1.kube:./cluster2.kube
kubectl config view --flatten > multicluster.kube
export KUBECONFIG=./multicluster.kube
```

2. On each cluster, install cilium using helm ensuring that the pod cidr ranges do not overlap:
```
docker pull quay.io/cilium/cilium:v1.16.5
kind load docker-image quay.io/cilium/cilium:v1.16.5  --name  cluster1
kind load docker-image quay.io/cilium/cilium:v1.16.5  --name  cluster2

helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium --version 1.16.5 \
  --namespace kube-system \
  --set image.pullPolicy=IfNotPresent \
  --set ipam.mode=kubernetes \
  --set hubble.enabled=false \
  --kube-context kind-cluster1

helm install cilium cilium/cilium --version 1.16.5 \
  --namespace kube-system \
  --set image.pullPolicy=IfNotPresent \
  --set ipam.mode=kubernetes \
  --set hubble.enabled=false \
  --kube-context kind-cluster2
         
```

4. Install cert-mananger
```
helm repo add jetstack https://charts.jetstack.io
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.6.3 \
  --set installCRDs=true \
  --kube-context kind-cluster1

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.6.3 \
  --set installCRDs=true \
  --kube-context kind-cluster2
```

5. Create a certificate that can be used as Ciliums common CA for both clusters
```openssl req -newkey rsa:2048 -nodes -keyout private_key.pem -x509 -days 3650 -out public_certificate.pem -subj "/CN=Cilium CA"```

6. On each cluster, create a cert-manager issuer and the certificate using the files generated by step 5:
```

cat <<EOF > cilium-ca-certificate.yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: cilium-issuer
  namespace: kube-system
spec:
  ca:
    secretName: cilium-issuer
---
EOF
kubectl -n kube-system create secret tls cilium-issuer --cert=public_certificate.pem --key=private_key.pem --dry-run=client -oyaml >> cilium-ca-certificate.yaml
kubectl apply -f cilium-ca-certificate.yaml --context kind-cluster1
kubectl apply -f cilium-ca-certificate.yaml --context kind-cluster2
```

7. On each cluster install metallb

```
helm repo add metallb https://metallb.github.io/metallb
helm install \
  cert-manager metallb/metallb \
  --namespace metallb-system \
  --create-namespace \
  --set installCRDs=true \
  --kube-context kind-cluster1

cat <<EOF > cluster1-metallb-config.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-ip
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.0.100/32
  - 172.18.0.101/32
EOF
kubectl apply -f cluster1-metallb-config.yaml --context kind-cluster1


helm install \
  cert-manager metallb/metallb \
  --namespace metallb-system \
  --create-namespace \
  --set installCRDs=true \
  --kube-context kind-cluster2

cat <<EOF > cluster2-metallb-config.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-ip
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 172.18.0.200/32
    - 172.18.0.201/32
EOF
kubectl apply -f cluster2-metallb-config.yaml --context kind-cluster2
```

8. For each cluster expose the kube-dns service with a Loadbalancer
```
kubectl  -n kube-system patch svc kube-dns --patch '{ "spec": { "type": "LoadBalancer", "loadBalancerIP": "172.18.0.101" } }' --context kind-cluster1
kubectl  -n kube-system patch svc kube-dns --patch '{ "spec": { "type": "LoadBalancer", "loadBalancerIP": "172.18.0.201" } }' --context kind-cluster2
```

9. On both clusters, update coredns config to perform redirection for both clusters
```
kubectl -n kube-system delete cm coredns --context kind-cluster1
kubectl -n kube-system apply -f coredns-cm-cluster1.yaml --context kind-cluster1
kubectl -n kube-system rollout restart deploy/coredns --context kind-cluster1

kubectl -n kube-system delete cm coredns --context kind-cluster2
kubectl -n kube-system apply -f coredns-cm-cluster2.yaml --context kind-cluster2
kubectl -n kube-system rollout restart deploy/coredns --context kind-cluster2
```

10. On both clusters update cilium with the cluster mesh values:
```
helm upgrade cilium cilium/cilium --version 1.16.5 \
  --kube-context kind-cluster1 \
  --namespace kube-system \
  --values cluster1-cilium-values.yaml

helm upgrade cilium cilium/cilium --version 1.16.5 \
  --kube-context kind-cluster2 \
  --namespace kube-system \
  --values cluster2-cilium-values.yaml 
# If you need to restart the pods use this command
kubectl -n kube-system delete pods -l k8s-app=cilium --context kind-cluster1
kubectl -n kube-system delete pods -l k8s-app=cilium --context kind-cluster2
```

11. If you going to use glabal services rather than DNS resolution then you can use the copy-svc.sh script to annotate and copy the services.

12. Deploy sample apps:
```
kubectl create -f https://raw.githubusercontent.com/cilium/cilium/1.16.5/examples/minikube/http-sw-app.yaml --context kind-cluster1
kubectl apply -f https://k8s.io/examples/admin/dns/dnsutils.yaml --context kind-cluster1
kubectl create -f https://raw.githubusercontent.com/cilium/cilium/1.16.5/examples/minikube/http-sw-app.yaml --context kind-cluster2
kubectl apply -f https://k8s.io/examples/admin/dns/dnsutils.yaml --context kind-cluster2
```

13. Test  - to cpomplete
kubectl get po,svc
kubectl --context kind-cluster1 exec -it dnsutils -- nslookup kubernetes.default
kubectl --context kind-cluster2 exec -it dnsutils -- nslookup kubernetes.default
kubectl --context kind-cluster1 exec -it dnsutils -- nslookup deathstar.default.svc.cluster.local
kubectl --context kind-cluster2 exec -it dnsutils -- nslookup deathstar.default.svc.cluster.local
kubectl --context kind-cluster1 exec -it dnsutils -- nslookup deathstar.default.svc.cluster1.local
kubectl --context kind-cluster2 exec -it dnsutils -- nslookup deathstar.default.svc.cluster1.local
kubectl --context kind-cluster1 exec -it dnsutils -- nslookup deathstar.default.svc.cluster2.local
kubectl --context kind-cluster2 exec -it dnsutils -- nslookup deathstar.default.svc.cluster2.local



kubectl --context kind-cluster1 exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster1.local/v1/request-landing
kubectl --context kind-cluster2 exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster1.local/v1/request-landing
kubectl --context kind-cluster1 exec xwing -- curl -s -XPOST deathstar.default.svc.cluster1.local/v1/request-landing
kubectl --context kind-cluster2 exec xwing -- curl -s -XPOST deathstar.default.svc.cluster1.local/v1/request-landing



14. To delete both clusters run
kind delete cluster -n cluster1
kind delete cluster -n cluster2


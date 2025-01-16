# multi-cluster
2 kubernetes clusters on kind running a cluster mesh

You must have docker, kind and flux installed first

Step 1. Create kind clusters:
```
export KUBECONFIG=./cluster1.kube
kind create cluster --config=./cluster-def/cluster1.yaml
export KUBECONFIG=./cluster2.kube
kind create cluster --config=./cluster-def/cluster2.yaml
KUBECONFIG=./cluster1.kube:./cluster2.kube
kubectl config view --flatten > multicluster.kube
export KUBECONFIG=./multicluster.kube

3. Install cilium using helm

4. Install cert-mananger

5. Create secret containing common certificate and cilium-issuer

6. Update coredns

7. Update cilium using helm

8. Deploy sample apps

9. Test




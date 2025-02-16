
CLUSTER1=cluster1
CLUSTER2=cluster3
CLUSTER3=cluster3
NAMESPACE=$NAMESPACE

echo annoate services
kubectl -n $NAMESPACE get svc -o name | xargs -I{} sh -c 'kubectl -n $NAMESPACE annotate {} service.cilium.io/global=true --overwrite'
kubectl -n $NAMESPACE get svc -o name | xargs -I{} sh -c 'kubectl -n $NAMESPACE annotate {} service.cilium.io/shared=true --overwrite'	
echo obtain config
kubectl -n $NAMESPACE get svc -oyaml --context $CLUSTER1 > $CLUSTER1-svc.yaml
kubectl -n $NAMESPACE get svc -oyaml --context $CLUSTER2 > $CLUSTER2-svc.yaml
kubectl -n $NAMESPACE get svc -oyaml --context $CLUSTER3 > $CLUSTER3-svc.yaml

sed -i '/last-applied-configuration:/d' $CLUSTER1-svc.yaml 
sed -i '/last-applied-configuration:/d' $CLUSTER2-svc.yaml 
sed -i '/last-applied-configuration:/d' $CLUSTER3-svc.yaml 

sed -i '/{"apiVersion":"v1","kind":"Service"/d' $CLUSTER1-svc.yaml
sed -i '/{"apiVersion":"v1","kind":"Service"/d' $CLUSTER2-svc.yaml
sed -i '/{"apiVersion":"v1","kind":"Service"/d' $CLUSTER3-svc.yaml

sed -i '/creationTimestamp:/d' $CLUSTER1-svc.yaml
sed -i '/creationTimestamp:/d' $CLUSTER2-svc.yaml
sed -i '/creationTimestamp:/d' $CLUSTER3-svc.yaml

sed -i '/resourceVersion:/d' $CLUSTER1-svc.yaml
sed -i '/resourceVersion:/d' $CLUSTER2-svc.yaml
sed -i '/resourceVersion:/d' $CLUSTER3-svc.yaml

sed -i '/uid/d' $CLUSTER1-svc.yaml 
sed -i '/uid/d' $CLUSTER2-svc.yaml 
sed -i '/uid/d' $CLUSTER3-svc.yaml 

echo applying config

kubectl -n $NAMESPACE --context $CLUSTER1 apply -f ${CLUSTER2}-svc.yaml
kubectl -n $NAMESPACE --context $CLUSTER1 apply -f ${CLUSTER3}-svc.yaml
kubectl -n $NAMESPACE --context $CLUSTER2 apply -f ${CLUSTER1}-svc.yaml
kubectl -n $NAMESPACE --context $CLUSTER2 apply -f ${CLUSTER3}-svc.yaml
kubectl -n $NAMESPACE --context $CLUSTER3 apply -f ${CLUSTER1}-svc.yaml
kubectl -n $NAMESPACE --context $CLUSTER3 apply -f ${CLUSTER2}-svc.yaml

rm $CLUSTER1-svc.yaml
rm $CLUSTER2-svc.yaml
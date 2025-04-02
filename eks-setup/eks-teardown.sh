cluster=$1

# uninstall NATS
echo "Uninstalling NATS"
helm uninstall nats-eks

# uninstall the AWS Load Balancer Controller
echo "Uninstalling the AWS Load Balancer Controller"
helm uninstall aws-load-balancer-controller -n kube-system

# remove cloudformation stack
echo "Deleting the CloudFormation stack"
eksctl delete iamserviceaccount \
  --cluster=$cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller
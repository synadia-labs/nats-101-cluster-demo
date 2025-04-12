# store the cluster name in an environment variable
cd tofu-eks
export EKS_CLUSTER=$(tofu output -raw cluster_name)
cd ../

# uninstall NATS
echo "Uninstalling NATS"
helm uninstall nats-eks

# uninstall the AWS Load Balancer Controller
echo "Uninstalling the AWS Load Balancer Controller"
helm uninstall aws-load-balancer-controller -n kube-system

# remove cloudformation stack
echo "Deleting the CloudFormation stack"
eksctl delete iamserviceaccount \
  --cluster=$EKS_CLUSTER \
  --namespace=kube-system \
  --name=aws-load-balancer-controller

# remove the EKS cluster
echo "Deleting the EKS cluster"
cd tofu-eks
tofu destroy --auto-approve
cd ../

# remove the kubeconfig file
echo "Removing the kubeconfig file"
rm nats-admin.config
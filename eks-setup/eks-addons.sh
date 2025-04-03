cluster=$1

# fetch AWS account ID
account_id=$(aws sts get-caller-identity --query Account --output text)
if [ $? -ne 0 ]; then
  echo "Error: Unable to fetch AWS account ID"
  exit 1
fi

# Create a new context for the service account
echo "Creating a new context in the default kubeconfig file"
aws eks --region us-east-1 update-kubeconfig  --alias nats-eks --name $cluster

# Set the default storage class
echo "Setting the default storage class"
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Install the AWS Load Balancer Controller
echo "Creating the IAM service account for the LBC"
eksctl create iamserviceaccount \
  --cluster=$cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$account_id:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve \
  --override-existing-serviceaccounts \
  --verbose 5

echo "Installing the AWS Load Balancer Controller"
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# wait for the AWS Load Balancer Controller to be ready
echo "Waiting for the AWS Load Balancer Controller to be ready"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-load-balancer-controller -n kube-system --timeout=120s

# install NATS
echo "Installing NATS"

helm upgrade --install nats nats/nats -f eks-nats-values.yaml
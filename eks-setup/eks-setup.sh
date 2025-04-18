#!/bin/bash
# cd to the directory where the OpenTofu script is located
cd tofu-eks
# ensure the plan runs successfully
echo "Planning to create a new EKS cluster"
tofu plan --out plan
# apply the plan
echo "Applying the plan to create the EKS cluster"
tofu apply plan
# store the cluster name in an environment variable
export EKS_CLUSTER=$(tofu output -raw cluster_name)
# change to the directory where the K8s configs are located
cd ../
# fetch AWS account ID
account_id=$(aws sts get-caller-identity --query Account --output text)
if [ $? -ne 0 ]; then
echo "Error: Unable to fetch AWS account ID"
exit 1
fi
# Create a new context for the service account
echo "Creating a new context in the default kubeconfig file"
aws eks --region us-east-1 update-kubeconfig --alias east-cluster --name $EKS_CLUSTER
# Set the default storage class
echo "Setting the default storage class"
kubectl patch storageclass gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
# Add the EKS Helm chart repository
echo "Adding the EKS Helm chart repository"
helm repo add eks https://aws.github.io/eks-charts
helm repo update
# Install the AWS Load Balancer Controller
echo "Creating the IAM service account for the LBC"
eksctl create iamserviceaccount \
--cluster=$EKS_CLUSTER \
--namespace=kube-system \
--name=aws-load-balancer-controller \
--role-name AmazonEKSLoadBalancerControllerRole \
--attach-policy-arn=arn:aws:iam::$account_id:policy/AWSLoadBalancerControllerIAMPolicy \
--approve \
--override-existing-serviceaccounts \
--verbose 5

# Wait for service account to be fully available before proceeding
echo "Waiting for service account to be fully available..."
kubectl wait --for=condition=present serviceaccount/aws-load-balancer-controller -n kube-system --timeout=60s

echo "Installing the AWS Load Balancer Controller"
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
-n kube-system \
--set clusterName=$EKS_CLUSTER \
--set serviceAccount.create=false \
--set serviceAccount.name=aws-load-balancer-controller
# Wait for the AWS Load Balancer Controller deployment to be ready
echo "Waiting for the AWS Load Balancer Controller deployment to be ready"
kubectl wait --for=condition=available deployment/aws-load-balancer-controller -n kube-system --timeout=180s
# Also wait for the webhook service to have endpoints
echo "Waiting for the AWS Load Balancer webhook service to have endpoints"
while [ "$(kubectl get endpoints aws-load-balancer-webhook-service -n kube-system -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)" = "" ]; do
echo "Waiting for webhook service endpoints to be available..."
sleep 10
done
echo "Webhook service is ready!"
# Add the NATS Helm repository
echo "Adding NATS Helm repository"
helm repo add nats https://nats-io.github.io/k8s/helm/charts/
helm repo update
# Install NATS
echo "Installing NATS"
helm upgrade --install nats-east nats/nats -f eks-nats-values.yaml
# Verify NATS installation
echo "Verifying NATS installation"
kubectl get pods -l app.kubernetes.io/name=nats
kubectl get services -l app.kubernetes.io/name=nats
#!/bin/sh

# Set default GCP values if not provided as environment variables
PROJECT_ID=${PROJECT_ID:-your-project-id}
REGION=${REGION:-us-central1}
ZONE=${ZONE:-us-central1-a}
MACHINE_TYPE=${MACHINE_TYPE:-e2-medium}
NODE_COUNT=${NODE_COUNT:-1}
CREDENTIALS_FILE=${CREDENTIALS_FILE:-/path/to/your/credentials.json}

# Function to check if a command exists
check_command() {
  if ! command -v $1 > /dev/null 2>&1; then
    echo "Error: $1 command not found. Please install it first."
    exit 1
  fi
}

# Check for required commands
check_command tofu
check_command kubectl
check_command helm

# Set the current project for gcloud (for kubectl auth)
echo "Setting project to $PROJECT_ID"
gcloud config set project $PROJECT_ID

# Change to the OpenTofu directory
echo "Changing to OpenTofu directory"
cd tofu-gke

# Initialize, plan, and apply the OpenTofu configuration
echo "Initializing OpenTofu"
tofu init

echo "Planning GKE cluster with OpenTofu"
tofu plan \
  -var="project=$PROJECT_ID" \
  -var="zone=$ZONE" \
  -var="machine_type=$MACHINE_TYPE" \
  -var="node_count=$NODE_COUNT" \
  -var="credentials_file=$CREDENTIALS_FILE" \
  -out=plan.out

echo "Applying OpenTofu configuration"
tofu apply plan.out

# Get the cluster name from OpenTofu output
GKE_CLUSTER=$(tofu output -raw cluster_name)
GKE_ZONE=$(tofu output -raw zone)

# Return to the original directory
cd ../

# Get credentials for the cluster to update kubeconfig
echo "Getting credentials for the cluster"
gcloud container clusters get-credentials $GKE_CLUSTER --zone=$GKE_ZONE --project=$PROJECT_ID

# Create necessary Kubernetes resources for the NATS deployment
echo "Creating Kubernetes resources for NATS"
kubectl create namespace nats-system 2>/dev/null || echo "Namespace nats-system already exists"

# Add the NATS Helm repository
echo "Adding NATS Helm repository"
helm repo add nats https://nats-io.github.io/k8s/helm/charts/ 2>/dev/null || echo "Repository already added"
helm repo update

# Create a values file for NATS with minimal resource usage
echo "Creating NATS values file with minimal resources"
cat > gke-nats-values.yaml << EOF
# NATS Helm chart values for GKE
cluster:
  enabled: true
  replicas: 1
nats:
  jetstream:
    enabled: true
    memStorage:
      enabled: true
      size: 256Mi
    fileStorage:
      enabled: true
      size: 2Gi
      storageClassName: standard
EOF

# Install/upgrade NATS
echo "Installing/upgrading NATS"
helm upgrade --install nats-gke nats/nats -f gke-nats-values.yaml -n nats-system

# Wait for NATS pods to be ready
echo "Waiting for NATS pods to be ready"
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=nats" -n nats-system --timeout=300s || echo "Warning: Timed out waiting for NATS pods"

# Create LoadBalancer service if it doesn't exist
if ! kubectl get service nats-lb -n nats-system > /dev/null 2>&1; then
  echo "Creating LoadBalancer service for external NATS access"
  kubectl apply -f - << EOF
apiVersion: v1
kind: Service
metadata:
  name: nats-lb
  namespace: nats-system
spec:
  selector:
    app.kubernetes.io/name: nats
  ports:
  - name: client
    port: 4222
    targetPort: 4222
  - name: monitoring
    port: 8222
    targetPort: 8222
  type: LoadBalancer
EOF
else
  echo "LoadBalancer service already exists"
fi

# Get the external IP for the LoadBalancer
echo "Waiting for LoadBalancer external IP..."
for i in $(seq 1 12); do
  EXTERNAL_IP=$(kubectl get service nats-lb -n nats-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [ -n "$EXTERNAL_IP" ]; then
    break
  fi
  echo "Waiting for external IP... (attempt $i/12)"
  sleep 10
done

echo "==============================================================="
echo "NATS cluster deployment on GKE!"
echo "Cluster name: $GKE_CLUSTER"
if [ -n "$EXTERNAL_IP" ]; then
  echo "NATS namespace: nats-system"
  echo "External IP: $EXTERNAL_IP"
  echo "Client port: 4222"
  echo "Monitoring port: 8222"
else
  echo "External IP not yet available. You can check later with:"
  echo "kubectl get service nats-lb -n nats-system"
fi
echo "==============================================================="

# Verify NATS installation
echo "Verifying NATS installation"
kubectl get pods -n nats-system
kubectl get services -n nats-system
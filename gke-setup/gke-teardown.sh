#!/bin/sh

# Set default GCP values if not provided as environment variables
PROJECT_ID=${PROJECT_ID:-your-project-id}
CREDENTIALS_FILE=${CREDENTIALS_FILE:-/path/to/your/credentials.json}

# Change to the OpenTofu directory
cd tofu-gke

# Get the cluster name from OpenTofu output before destroying
GKE_CLUSTER=$(tofu output -raw cluster_name 2>/dev/null || echo "")
GKE_ZONE=$(tofu output -raw zone 2>/dev/null || echo "us-central1-a")

# Set the current project for gcloud (for kubectl auth)
echo "Setting project to $PROJECT_ID"
gcloud config set project $PROJECT_ID

# Back to original directory
cd ../

# Uninstall NATS
echo "Uninstalling NATS"
helm uninstall nats-gke -n nats-system || true

# Delete LoadBalancer service
echo "Deleting LoadBalancer service"
kubectl delete service nats-lb -n nats-system --ignore-not-found=true

# Remove the namespace
echo "Removing nats-system namespace"
kubectl delete namespace nats-system --wait=false --ignore-not-found=true

# Change to the OpenTofu directory
cd tofu-gke

# Initialize OpenTofu before destroying
echo "Initializing OpenTofu"
tofu init

# Destroy the GKE cluster using OpenTofu
echo "Destroying GKE cluster with OpenTofu"
tofu destroy \
  -var="project=$PROJECT_ID" \
  -var="credentials_file=$CREDENTIALS_FILE" \
  --auto-approve

# Return to the original directory
cd ../

# Remove the kubeconfig context
if [ -n "$GKE_CLUSTER" ] && [ -n "$PROJECT_ID" ] && [ -n "$GKE_ZONE" ]; then
  echo "Removing GKE context from kubeconfig"
  kubectl config delete-context gke_${PROJECT_ID}_${GKE_ZONE}_${GKE_CLUSTER} || true
fi

echo "==============================================================="
echo "GKE cluster teardown complete!"
echo "==============================================================="
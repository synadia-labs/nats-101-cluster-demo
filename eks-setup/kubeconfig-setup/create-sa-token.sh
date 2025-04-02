secret=nats-admin-token

context=$(kubectl config current-context)
cluster=$(kubectl config view -o jsonpath="{.contexts[?(@.name == \"$context\")].context.cluster}")
server=$(kubectl config view -o jsonpath="{.clusters[?(@.name == \"$cluster\")].cluster.server}")
ca=$(kubectl get secret/$secret -o jsonpath='{.data.ca\.crt}')
sa=$(kubectl get secret/$secret -o jsonpath='{.metadata.annotations.kubernetes\.io/service-account\.name}')
token=$(kubectl get secret/$secret -o jsonpath='{.data.token}' | base64 --decode)
namespace=$(kubectl get secret/$secret -o jsonpath='{.data.namespace}' | base64 --decode)

echo "
apiVersion: v1
kind: Config
clusters:
- name: ${cluster}
  cluster:
    certificate-authority-data: ${ca}
    server: ${server}
contexts:
- name: $sa-context
  context:
    cluster: ${cluster}
    user: $sa
current-context: $sa-context
users:
- name: $sa
  user:
    token: ${token}
" > $sa.config
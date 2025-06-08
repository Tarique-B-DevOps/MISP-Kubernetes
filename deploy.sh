#!/bin/bash

# TODO:
# - allow non-interactive mode by checking for environment variables for secrets - ✅
# - Add --delete arg support to clean up resources
# - Intelligently create the resources

set -e

NAMESPACE="misp-dev"
CONFIG_FILE="misp-configs.yml"
SECRETS_NAME="misp-secrets"

echo "[1/5] Creating namespace and setting context..."
kubectl create namespace $NAMESPACE 2>/dev/null || echo "Namespace $NAMESPACE already exists"
kubectl config set-context --current --namespace=$NAMESPACE

echo "[2/5] Creating Kubernetes secrets..."

read_secret() {
  VAR_NAME="$1"
  PROMPT_LABEL="$2"

  if [ -z "${!VAR_NAME}" ]; then
    read -s -p "Enter ${PROMPT_LABEL}: " input
    echo
    export "$VAR_NAME"="$input"
  else
    echo "✅ Using ${PROMPT_LABEL} from environment"
  fi
}

read_secret REDIS_PASSWORD "REDIS_PASSWORD"
read_secret MYSQL_PASSWORD "MYSQL_PASSWORD"
read_secret MYSQL_ROOT_PASSWORD "MYSQL_ROOT_PASSWORD"
read_secret ADMIN_PASSWORD "ADMIN_PASSWORD"

kubectl create secret generic $SECRETS_NAME \
  --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
  --from-literal=MYSQL_PASSWORD="$MYSQL_PASSWORD" \
  --from-literal=MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
  --from-literal=ADMIN_PASSWORD="$ADMIN_PASSWORD" || echo "Secret $SECRETS_NAME already exists"

echo "[3/5] Creating MISP core LoadBalancer service..."
kubectl apply -f misp-core-svc.yml

echo "⏳ Waiting for external IP..."
EXTERNAL_IP=""
while [[ -z "$EXTERNAL_IP" ]]; do
  EXTERNAL_IP=$(kubectl get svc misp-core -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  [[ -z "$EXTERNAL_IP" ]] && sleep 5
done
echo "🌐 External IP acquired: $EXTERNAL_IP"

echo "[4/5] Updating BASE_URL in config and creating ConfigMap..."
TMP_CONFIG="misp-configs.generated.yml"
sed -E "s|^( *BASE_URL:).*|\1 \"https://$EXTERNAL_IP\"|" "$CONFIG_FILE" > "$TMP_CONFIG"
kubectl apply -f "$TMP_CONFIG"

echo "[5/5] Deploying MISP Components..."

echo "📦 1 - Creating persistent volume claims..."
kubectl apply -f misp-pvcs.yml

echo "📧 2 - Deploying misp-mail..."
kubectl apply -f misp-mail.yml
sleep 30

echo "🧠 3 - Deploying misp-redis..."
kubectl apply -f misp-redis.yml
sleep 60

echo "🗃️  4 - Deploying misp-db..."
kubectl apply -f misp-db.yml
sleep 60

echo "🔌 5 - Deploying misp-modules..."
kubectl apply -f misp-modules.yml
sleep 60

echo "🧰 6 - Deploying misp-core..."
kubectl apply -f misp-core.yml
sleep 300

echo "✅ MISP deployed successfully!"
echo "🌐 Access it at: https://$EXTERNAL_IP"

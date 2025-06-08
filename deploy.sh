#!/bin/bash

# TODO:
# - allow non-interactive mode by checking for environment variables for secrets
# - Add --delete arg support to clean up resources
# - Integligently create the resources

set -e

NAMESPACE="misp-dev"
CONFIG_FILE="misp-configs.yml"
SECRETS_NAME="misp-secrets"

echo "[1/5] Creating namespace and setting context..."
kubectl create namespace $NAMESPACE 2>/dev/null || echo "Namespace $NAMESPACE already exists"
kubectl config set-context --current --namespace=$NAMESPACE

echo "[2/5] Creating Kubernetes secrets..."
read -s -p "Enter REDIS_PASSWORD: " REDIS_PASSWORD; echo
read -s -p "Enter MYSQL_PASSWORD: " MYSQL_PASSWORD; echo
read -s -p "Enter MYSQL_ROOT_PASSWORD: " MYSQL_ROOT_PASSWORD; echo
read -s -p "Enter ADMIN_PASSWORD: " ADMIN_PASSWORD; echo

kubectl create secret generic $SECRETS_NAME \
  --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
  --from-literal=MYSQL_PASSWORD="$MYSQL_PASSWORD" \
  --from-literal=MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
  --from-literal=ADMIN_PASSWORD="$ADMIN_PASSWORD" || echo "Secret already exists"


echo "[3/5] Creating MISP core LoadBalancer service..."
kubectl apply -f misp-core-svc.yml

echo "Waiting for external IP..."
EXTERNAL_IP=""
while [[ -z "$EXTERNAL_IP" ]]; do
  EXTERNAL_IP=$(kubectl get svc misp-core -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  [[ -z "$EXTERNAL_IP" ]] && sleep 5
done
echo "External IP acquired: $EXTERNAL_IP"

echo "[4/5] Updating BASE_URL in config and creating ConfigMap..."
TMP_CONFIG="misp-configs.generated.yml"
sed -E "s|^( *BASE_URL:).*|\1 \"https://$EXTERNAL_IP\"|" "$CONFIG_FILE" > "$TMP_CONFIG"
kubectl apply -f "$TMP_CONFIG"

echo "[5/5] Deploying MISP Components..."

echo "1 - Creating persistent volume claims..."
kubectl apply -f misp-pvcs.yml

echo "2 - Deploying misp-mail..."
kubectl apply -f misp-mail.yml
sleep 30

echo "3 - Deploying misp-redis..."
kubectl apply -f misp-redis.yml
sleep 60

echo "4 - Deploying misp-db..."
kubectl apply -f misp-db.yml
sleep 60

echo "5 - Deploying misp-modules..."
kubectl apply -f misp-modules.yml
sleep 60

echo "6 - Deploying misp-core..."
kubectl apply -f misp-core.yml
sleep 120


echo "✅ MISP deployed! Access it at: https://$EXTERNAL_IP"

#!/bin/bash

set -e

NAMESPACE="misp-dev"
CONFIG_FILE="misp-configs.yml"
SECRETS_NAME="misp-secrets"

declare -A SLEEP_MAP=(
  ["misp-mail.yml"]=30
  ["misp-redis.yml"]=30
  ["misp-db.yml"]=60
  ["misp-modules.yml"]=60
  ["misp-core.yml"]=300
)

read_secret() {
  VAR_NAME="$1"
  LABEL="$2"
  if [ -z "${!VAR_NAME}" ]; then
    read -s -p "Enter ${LABEL}: " input
    echo
    export "$VAR_NAME"="$input"
  else
    echo "✔️  Using ${LABEL} from environment"
  fi
}

apply_direct() {
  local file="$1"
  echo "→ Applying $file"
  kubectl apply -f "$file"
}

apply_with_options() {
  local file="$1"
  echo "→ Applying $file"
  result=$(kubectl apply -f "$file" 2>&1)
  echo "$result"
  if echo "$result" | grep -q "created"; then
    sleep_time="${SLEEP_MAP[$file]:-0}"
    echo "⏱️  Resources created, sleeping ${sleep_time}s"
    sleep "$sleep_time"
  else
    echo "✔️  Resource created or unchanged"
  fi
}

rollout_update() {
  echo "🔄 Restarting deployments..."
  for dep in mail redis db misp-modules misp-core; do
    kubectl rollout restart deployment "$dep"
  done
}

if [[ "$1" == "--rollout" ]]; then
  echo "→ Applying config map"
  kubectl apply -f "$CONFIG_FILE"
  rollout_update
  echo "✅ Rollout complete"
  exit 0
fi

if [[ "$1" == "--delete" ]]; then
  echo "🧹 Deleting all resources..."
  for file in misp-mail.yml misp-redis.yml misp-db.yml misp-modules.yml misp-core.yml misp-core-svc.yml misp-pvcs.yml "$CONFIG_FILE"; do
    echo "→ Deleting from $file"
    kubectl delete -f "$file" --ignore-not-found
  done
  echo "🔐 Deleting secret $SECRETS_NAME"
  kubectl delete secret "$SECRETS_NAME" --ignore-not-found
  echo "🚪 Deleting namespace $NAMESPACE"
  kubectl delete ns "$NAMESPACE" --ignore-not-found
  echo "✅ Cleanup complete"
  exit 0
fi

echo "[1/6] Creating namespace and setting context..."
kubectl create namespace "$NAMESPACE" 2>/dev/null || echo "✔️  Namespace $NAMESPACE already exists"

CURRENT_NS=$(kubectl config view --minify --output 'jsonpath={..namespace}')
if [[ "$CURRENT_NS" != "$NAMESPACE" ]]; then
  echo "→ Switching kubectl context to $NAMESPACE"
  kubectl config set-context --current --namespace="$NAMESPACE"
else
  echo "✔️  Context already set to $NAMESPACE"
fi

echo "[2/6] Creating Kubernetes secrets..."
read_secret REDIS_PASSWORD "REDIS_PASSWORD"
read_secret MYSQL_PASSWORD "MYSQL_PASSWORD"
read_secret MYSQL_ROOT_PASSWORD "MYSQL_ROOT_PASSWORD"
read_secret ADMIN_PASSWORD "ADMIN_PASSWORD"

if ! kubectl get secret "$SECRETS_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  kubectl create secret generic "$SECRETS_NAME" \
    --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
    --from-literal=MYSQL_PASSWORD="$MYSQL_PASSWORD" \
    --from-literal=MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
    --from-literal=ADMIN_PASSWORD="$ADMIN_PASSWORD"
else
  echo "✔️  Secret $SECRETS_NAME already exists"
fi

echo "[3/6] Deploying MISP core LoadBalancer service..."
apply_direct "misp-core-svc.yml"

echo "⏳ Waiting for external IP..."
EXTERNAL_IP=""
while [[ -z "$EXTERNAL_IP" ]]; do
  EXTERNAL_IP=$(kubectl get svc misp-core -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [[ -z "$EXTERNAL_IP" ]] && sleep 5
done
echo "🌐 External IP acquired: $EXTERNAL_IP"

echo "[4/6] Updating BASE_URL in configs and creating ConfigMap..."
BASE_URL_LINE=$(grep -E '^ *BASE_URL:' "$CONFIG_FILE" || true)
CURRENT_URL=$(echo "$BASE_URL_LINE" | sed -E 's/^ *BASE_URL: *"?([^"]*)"?/\1/')
TARGET_URL="https://$EXTERNAL_IP"

if [[ "$CURRENT_URL" != "$TARGET_URL" ]]; then
  echo "→ Updating BASE_URL from '$CURRENT_URL' to '$TARGET_URL'"
  sed -i.bak -E "s|^( *BASE_URL:).*|\1 \"$TARGET_URL\"|" "$CONFIG_FILE"
else
  echo "✔️  BASE_URL already set"
fi

echo "→ Applying config map"
kubectl apply -f "$CONFIG_FILE"

echo "[5/6] Creating persistent volume claims..."
apply_direct "misp-pvcs.yml"

echo "[6/6] Deploying MISP Components..."
for file in misp-mail.yml misp-redis.yml misp-db.yml misp-modules.yml misp-core.yml; do
  apply_with_options "$file"
done

echo "✅ MISP deployed"
echo "🔗 Access it at: https://$EXTERNAL_IP"

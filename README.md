# MISP Kubernetes Deployment

- This repository provides Kubernetes manifests to deploy [MISP (Malware Information Sharing Platform)](https://www.misp-project.org/) in a cloud-native environment   
- Enables external access via a LoadBalancer service  
- Modular deployments for mail, Redis, MySQL, core app, and MISP modules  
- Uses ConfigMaps and Secrets for flexible and secure configuration  
- Quick to set up for testing, demos, and development use cases on managed Kubernetes cluster

> **NOTE:** Based on official Docker images and configurations from the [MISP Docker](https://github.com/MISP/misp-docker/tree/master)

## 🚀 Quick Deployment Guide

## ⚙️ Method 1:

### 1. Create Namespace and Set Context

Run the following command to create the `misp-dev` namespace and set your kubectl context to use it:

```sh
kubectl create namespace misp-dev && \
kubectl config set-context --current --namespace=misp-dev
```

### 2. Create Kubernetes Secrets

- Set your required secret environment variables (replace placeholders with actual values):

```sh
export REDIS_PASSWORD="REPLACE_ME_REDIS_PASSWORD" \
       MYSQL_PASSWORD="REPLACE_ME_MYSQL_PASSWORD" \
       MYSQL_ROOT_PASSWORD="REPLACE_ME_MYSQL_ROOT_PASSWORD" \
       ADMIN_PASSWORD="REPLACE_ME_ADMIN_PASSWORD"
```       

- Create the Kubernetes secret:

```sh
kubectl create secret generic misp-secrets \
  --from-literal=REDIS_PASSWORD="${REDIS_PASSWORD}" \
  --from-literal=MYSQL_PASSWORD="${MYSQL_PASSWORD}" \
  --from-literal=MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
  --from-literal=ADMIN_PASSWORD="${ADMIN_PASSWORD}"
```


### 3. Deploy MISP Core LoadBalancer Service

- This exposes the MISP web UI to the outside world. Run:

```sh
kubectl create -f misp-core-svc.yml
```

- **Wait** until the **External IP** is provisioned. to check run:

```sh
kubectl get svc misp-core --watch
```

- Once the `EXTERNAL-IP` appears, copy it for the next step.

## 4: Update the ConfigMap with the External IP

- Open `misp-configs.yml` and locate the `BASE_URL` setting. Replace its value with your external IP and save, e.g.:

```sh
BASE_URL=https://<EXTERNAL_IP>
```
---

- Create ConfigMap

Edit `misp-configs.yml` to customize as needed. Then run:

```sh
kubectl create -f misp-configs.yml
```


### 5. Create Persistent Volume Claims (PVCs)

- PVCs provide persistent storage so MISP data isn’t lost when pods restart or move.

```sh
kubectl create -f misp-pvcs.yml
```


### 6. Deploy MISP Components

- This includes all core modules: mail, redis, MySQL database, modules, and core app:
- It creates following resources for each:
    - Service
    - Deployment

run:

```sh
kubectl create -f misp-mail.yml && \
      sleep 30 && \
      kubectl create -f misp-redis.yml && \
      sleep 60 && \
      kubectl create -f misp-db.yml && \
      sleep 60 && \
      kubectl create -f misp-modules.yml && \
      sleep 60 && \
      kubectl create -f misp-core.yml
```               

### 7. Access MISP

After all pods are `Running` and `Ready`:

![Image](https://github.com/user-attachments/assets/b8a871d5-0539-4c0a-ad3a-0c071bf47368)

```sh
https://<EXTERNAL_IP>
```

Login using the email set in the `ADMIN_EMAIL` value of the config map and the password from the `ADMIN_PASSWORD` in your secret.

If all went well, you should land on the MISP **homepage**.

![Image](https://github.com/user-attachments/assets/54b9d453-9849-4c91-ace1-d19b986b4a25)


## 🧹 Cleanup

To remove all resources created:

```sh
kubectl delete -f misp-mail.yml \
               -f misp-redis.yml \
               -f misp-db.yml \
               -f misp-modules.yml \
               -f misp-core.yml \
               -f misp-core-svc.yml \
               -f misp-pvcs.yml \
               -f misp-configs.yml && \
kubectl delete secret misp-secrets && \
kubectl delete ns misp-dev
```


## ⚙️ Method 2: Automated Deployment (One-Click Setup)

This method allows deploying the entire MISP stack using a single script quick setups.

### What the Script Does

- Creates the namespace `misp-dev` and sets the kubectl context
- Prompts you securely for secrets
- Creates the required Kubernetes Secret and ConfigMap
- Waits for the external IP to be provisioned and sets `BASE_URL` accordingly
- Applies all component manifests (services, PVCs, deployments)
- Waits intelligently between deployments to avoid race conditions

### 🔧 Steps

1. Make the script executable:

```sh
chmod +x deploy.sh
```

2. Run the script:

```sh
./deploy.sh
```

3. When prompted, enter the required secret values:

- `REDIS_PASSWORD`
- `MYSQL_PASSWORD`
- `MYSQL_ROOT_PASSWORD`
- `ADMIN_PASSWORD`

Then wait for the script execution to complete.

> 🔐 For non-interactive use, copy and run the `export` command from the
> [Create Kubernetes Secrets](#2-create-kubernetes-secrets) section before running the script.

```sh
./deploy.sh

[1/5] Creating namespace and setting context...
namespace/misp-dev created
Context "gke_staging-457318_us-central1-a_staging" modified.
[2/5] Creating Kubernetes secrets...
Enter REDIS_PASSWORD: 
Enter MYSQL_PASSWORD: 
Enter MYSQL_ROOT_PASSWORD: 
Enter ADMIN_PASSWORD: 
secret/misp-secrets created
[3/5] Creating MISP core LoadBalancer service...
service/misp-core created
⏳ Waiting for external IP...
🌐 External IP acquired: <EXTERNAL_IP_HERE>
[4/5] Updating BASE_URL in config and creating ConfigMap...
configmap/misp-configs created
[5/5] Deploying MISP Components...
📦 1 - Creating persistent volume claims...
persistentvolumeclaim/mysql-data created
persistentvolumeclaim/misp-configs created
persistentvolumeclaim/misp-logs created
persistentvolumeclaim/misp-files created
persistentvolumeclaim/misp-ssl created
persistentvolumeclaim/misp-gnupg created
persistentvolumeclaim/misp-action-mod created
persistentvolumeclaim/misp-expansion created
persistentvolumeclaim/misp-export-mod created
persistentvolumeclaim/misp-import-mod created
📧 2 - Deploying misp-mail...
service/mail created
deployment.apps/mail created
🧠 3 - Deploying misp-redis...
service/redis created
deployment.apps/redis created
🗃️  4 - Deploying misp-db...
service/db created
deployment.apps/db created
🔌 5 - Deploying misp-modules...
service/misp-modules created
deployment.apps/misp-modules created
🧰 6 - Deploying misp-core...
deployment.apps/misp-core created
✅ MISP deployed successfully!
🌐 Access it at: https://<EXTERNAL_IP_HERE>
```
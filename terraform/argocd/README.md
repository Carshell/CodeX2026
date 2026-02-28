# Terraform: Argo CD on GKE

This Terraform stack installs Argo CD on a GKE cluster in Google Cloud.

## What this stack does

1. Optionally enables required Google Cloud APIs.
2. Connects to an existing GKE cluster.
3. Creates the `argocd` namespace.
4. Installs Argo CD via the official `argo-cd` Helm chart.
5. Supports existing ingress (`nginx`) and monitoring (`kube-prometheus-stack`) integration.

## Files

- `versions.tf`: Terraform and provider constraints.
- `providers.tf`: Google, Kubernetes, and Helm provider config.
- `variables.tf`: Inputs for project, cluster, and Argo CD options.
- `main.tf`: API enablement + namespace + Helm release.
- `outputs.tf`: Useful post-apply commands and names.
- `terraform.tfvars.example`: Example input values.
- `scripts/bootstrap-gcp-terraform.sh`: GCP CLI bootstrap helper.

## Prerequisites

- `gcloud` CLI authenticated (`gcloud auth login`)
- `terraform` CLI
- IAM permissions to:
  - enable APIs
  - read/create GKE clusters (optional create path)
  - create/read GCS buckets
  - install resources in the target cluster, including Kubernetes RBAC resources (`roles.rbac.authorization.k8s.io` create/delete)

## Quickstart

### 1) Bootstrap project and Terraform inputs

From repo root:

```bash
./terraform/argocd/scripts/bootstrap-gcp-terraform.sh \
  --project-id <PROJECT_ID> \
  --cluster-name <CLUSTER_NAME> \
  --cluster-location <REGION_OR_ZONE> \
  --state-bucket <TF_STATE_BUCKET> \
  --argocd-host <ARGOCD_HOSTNAME>
```

If the cluster does not exist yet, add `--create-cluster`.

### 2) Apply Terraform

```bash
cd terraform/argocd
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

### 3) Access Argo CD

```bash
kubectl -n argocd get svc argocd-argocd-server
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

## Common options

- Pin chart version:

```hcl
argocd_chart_version = "7.7.16"
```

- Use ClusterIP instead of LoadBalancer (recommended with existing ingress):

```hcl
argo_server_service_type = "ClusterIP"
```

- Enable ingress (nginx + cert-manager):

```hcl
enable_argocd_ingress         = true
argocd_ingress_class_name     = "nginx"
argocd_ingress_hostname       = "argocd.example.com"
argocd_ingress_tls_secret_name = "argocd-server-tls"
argocd_ingress_cluster_issuer = "letsencrypt-prod"
```

- Enable ServiceMonitors for existing kube-prometheus-stack:

```hcl
enable_service_monitors = true
service_monitor_additional_labels = {
  release = "prometheus"
}
```

- Provide custom Helm values file:

```hcl
argocd_helm_values_file = "values.argocd.yaml"
```

## Notes

- This stack intentionally targets an existing GKE cluster.
- Use the bootstrap script to create/check cluster and remote Terraform state.
- For GitOps rollout, add Argo CD `Application` manifests in your deploy repo and let Argo sync them.

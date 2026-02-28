# Full Setup: CI + Terraform Argo CD + GitOps CD (GKE)

This guide is the full path from zero to a working setup for this repo.

## 1. Prerequisites (local machine)

Install and authenticate:

- `gcloud` CLI
- `kubectl`
- `terraform` (>= 1.5)
- `skaffold`
- `git`

Authenticate:

```bash
gcloud auth login
gcloud auth application-default login
```

## 2. One-time tasks in Web UI (Google Cloud Console)

1. Create or choose a Google Cloud project.
2. Enable Billing for that project.
3. Confirm your user (or CI service account) has enough IAM, at least:
   - Project IAM Admin (or equivalent for role grants)
   - Kubernetes Engine Admin (must include Kubernetes RBAC create/delete permissions such as `container.roles.create` and `container.roles.delete`)
   - Service Usage Admin
   - Storage Admin
   - Artifact Registry Admin
4. (Optional) Create a dedicated service account for Terraform and CI.

## 3. Bootstrap GCP and Terraform inputs (CLI)

Run from repo root:

```bash
./terraform/argocd/scripts/bootstrap-gcp-terraform.sh \
  --project-id project-37ed24a7-5563-4ce5-a6f \
  --region us-central1 \
  --cluster-name online-boutique \
  --cluster-location us-central1 \
  --state-bucket project-37ed24a7-5563-4ce5-a6f-tfstate-argocd \
  --argocd-host argocd.codexhakaton.srvx.space \
  --init --plan
```

What this does:

1. Enables required APIs.
2. Validates the existing GKE cluster.
3. Creates Terraform remote state bucket.
4. Creates Artifact Registry repo (`microservices-demo`) unless disabled.
5. Writes `terraform/argocd/backend.hcl` and `terraform/argocd/terraform.tfvars` with:
   - `nginx` ingress integration
   - cert-manager issuer `letsencrypt-prod`
   - ServiceMonitor labels compatible with kube-prometheus-stack (`release=prometheus`)

## 4. Install Argo CD with Terraform

```bash
cd terraform/argocd
terraform apply
```

After apply:

```bash
kubectl -n argocd get svc argocd-argocd-server
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

## 5. Configure GitOps manifests in this repo

### 5.1 Set your Git repo URL in Argo manifests

```bash
export GIT_REPO_URL="https://github.com/<ORG>/<REPO>.git"
perl -pi -e 's|https://github.com/REPLACE_ME/REPLACE_ME.git|$ENV{GIT_REPO_URL}|g' \
  deploy/argocd/project.yaml \
  deploy/argocd/root-application.yaml \
  deploy/argocd/apps/dev.yaml \
  deploy/argocd/apps/staging.yaml \
  deploy/argocd/apps/prod.yaml
```

### 5.2 Set your GCP project ID in overlay image registry paths

```bash
export PROJECT_ID="<PROJECT_ID>"
perl -pi -e 's|PROJECT_ID|$ENV{PROJECT_ID}|g' deploy/overlays/*/kustomization.yaml
```

For this repo/project these are already prefilled:

- repo URL: `https://github.com/Carshell/CodeX2026.git`
- GCP project ID: `project-37ed24a7-5563-4ce5-a6f`

### 5.3 Commit and push these manifest changes

Argo CD pulls from Git, so these files must be in the remote branch Argo watches (`main` by default).

```bash
git add deploy/ SETUP.md terraform/argocd/
git commit -m "Add GitOps overlays, Argo app-of-apps, and setup docs"
git push
```

## 6. Push initial container images (so Argo deploys successfully)

Overlays currently expect tags:

- `dev-latest`
- `staging-latest`
- `prod-latest`

### 6.1 Build and push once (`dev-latest`)

```bash
export REGION="us-central1"
export REPO="${REGION}-docker.pkg.dev/${PROJECT_ID}/microservices-demo"

gcloud auth configure-docker "${REGION}-docker.pkg.dev" -q
skaffold build --default-repo="${REPO}" --tag=dev-latest
```

### 6.2 Promote same images to staging/prod tags

```bash
SERVICES="adservice cartservice checkoutservice currencyservice emailservice frontend loadgenerator paymentservice productcatalogservice recommendationservice shippingservice"
for svc in ${SERVICES}; do
  gcloud artifacts docker tags add \
    "${REPO}/${svc}:dev-latest" \
    "${REPO}/${svc}:staging-latest"

  gcloud artifacts docker tags add \
    "${REPO}/${svc}:dev-latest" \
    "${REPO}/${svc}:prod-latest"
done
```

## 7. Register repo in Argo CD (Web UI)

1. Open Argo CD UI at `https://argocd.codexhakaton.srvx.space`.
2. Log in as `admin` with initial secret password.
3. Change password immediately.
4. Go to `Settings` -> `Repositories` -> `Connect Repo`.
5. Add your repo:
   - Public repo: HTTPS URL only.
   - Private repo: add PAT/SSH credentials.

## 8. Install AppProject + root app (CLI)

```bash
kubectl apply -k deploy/argocd
```

This creates:

- `AppProject` (`online-boutique`)
- Root `Application` (`online-boutique-root`)
- Child apps for `dev`, `staging`, `prod` (via app-of-apps)

## 9. Sync and verify (Argo UI + CLI)

### 9.1 Argo UI

1. Open `online-boutique-root` and sync if needed.
2. Confirm `online-boutique-dev`, `online-boutique-staging`, `online-boutique-prod` appear.
3. `dev` is auto-sync; `staging` and `prod` are manual sync by design.

### 9.2 CLI checks

```bash
kubectl -n argocd get applications
kubectl get ns | rg 'onlineboutique-(dev|staging|prod)'

kubectl -n onlineboutique-dev get pods
kubectl -n onlineboutique-staging get pods
kubectl -n onlineboutique-prod get pods
```

Frontend ingress endpoints:

```bash
kubectl -n onlineboutique-dev get ingress frontend-ingress
kubectl -n onlineboutique-staging get ingress frontend-ingress
kubectl -n onlineboutique-prod get ingress frontend-ingress
```

Expected hostnames:

1. `dev.codexhakaton.srvx.space` -> dev
2. `staging.codexhakaton.srvx.space` -> staging
3. `codexhakaton.srvx.space` -> prod

### 9.3 DNS records

Point these records to your NGINX ingress controller public IP:

```bash
kubectl get ingress -A -o wide
```

Create or update DNS A records:

1. `argocd.codexhakaton.srvx.space`
2. `dev.codexhakaton.srvx.space`
3. `staging.codexhakaton.srvx.space`
4. `codexhakaton.srvx.space`
5. `monitoring.codexhakaton.srvx.space`

If you still have a legacy ingress using `codexhakaton.srvx.space`, remove or change that old ingress before syncing the new prod app to avoid host conflicts.
```

## 10. Monitoring HTTPS on subdomain

Monitoring UI (Grafana) is managed by Helm release `prometheus` in namespace `monitoring`.

Apply the tracked override values:

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --reuse-values \
  --force-conflicts \
  -f deploy/monitoring/grafana-ingress-values.yaml
```

Validate:

```bash
kubectl -n monitoring get ingress prometheus-grafana
kubectl -n monitoring get certificate monitoring-tls
```

Expected Monitoring URL:

1. `https://monitoring.codexhakaton.srvx.space`

Apply persistent monitoring dashboards (Git-tracked ConfigMaps):

```bash
kubectl apply -k deploy/monitoring
```

## 11. CircleCI setup (Web UI)

Pipeline now includes:

1. PR/branch CI jobs: tests + kustomize validation.
2. Main-branch job: build/push images and open GitOps PR updating `deploy/overlays/dev/kustomization.yaml`.

### 11.1 Connect repo

1. In CircleCI, connect `Carshell/CodeX2026`.
2. Ensure config path is `.circleci/config.yml`.

### 11.2 Create a CircleCI Context (recommended)

Create context (for example `gcp-gitops`) and add:

1. `GOOGLE_CREDENTIALS`: JSON key for CI service account.
2. `GCP_PROJECT_ID`: `project-37ed24a7-5563-4ce5-a6f`
3. `GCP_REGION`: `us-central1`
4. `GAR_REPOSITORY`: `microservices-demo`
5. `GITOPS_PUSH_TOKEN`: GitHub token with `repo` scope to push branch + open PR.
6. Optional `GITOPS_TARGET_BRANCH`: defaults to `main`.

### 11.3 Service account IAM

Grant CI service account:

1. `roles/artifactregistry.writer`
2. `roles/storage.admin` (if your build tooling requires registry/storage interactions)

### 11.4 Branch protection in GitHub

1. Protect `main`.
2. Require status checks from CircleCI.
3. Keep direct pushes blocked so GitOps PRs are reviewed.

## 12. Day-2 GitOps flow

1. Merge code to `main`.
2. CircleCI builds images tagged with commit SHA and pushes to Artifact Registry.
3. CircleCI opens PR:
   - `ci/dev-images-<sha>`
4. Merge `dev` PR to deploy dev (auto-sync in Argo).
5. Promote to staging/prod by creating PRs that update:
   - `deploy/overlays/staging/kustomization.yaml`
   - `deploy/overlays/prod/kustomization.yaml`
6. Manually sync `online-boutique-staging` and `online-boutique-prod` in Argo UI after merge.

## 13. Files added for this setup

- Terraform Argo stack: `terraform/argocd/*`
- Bootstrap script: `terraform/argocd/scripts/bootstrap-gcp-terraform.sh`
- Argo manifests: `deploy/argocd/*`
- Env overlays: `deploy/overlays/*`
- Monitoring config: `deploy/monitoring/*`

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_ID=""
REGION="us-central1"
CLUSTER_NAME="online-boutique"
CLUSTER_LOCATION=""
STATE_BUCKET=""
STATE_BUCKET_LOCATION="US"
STATE_PREFIX="terraform/argocd"
ARTIFACT_REPO="microservices-demo"
CREATE_CLUSTER="false"
CREATE_ARTIFACT_REPO="true"
ENABLE_ARGOCD_INGRESS="true"
ARGOCD_HOSTNAME=""
ARGOCD_INGRESS_CLASS="nginx"
ARGOCD_INGRESS_TLS_SECRET="argocd-server-tls"
ARGOCD_CLUSTER_ISSUER="letsencrypt-prod"
ENABLE_SERVICE_MONITORS="true"
SERVICE_MONITOR_RELEASE_LABEL="prometheus"
RUN_TERRAFORM_INIT="false"
RUN_TERRAFORM_PLAN="false"
RUN_TERRAFORM_APPLY="false"

usage() {
  cat <<USAGE_EOF
Usage:
  $(basename "$0") --project-id <PROJECT_ID> [options]

Options:
  --project-id <id>            GCP project ID (required)
  --region <region>            Default GCP region (default: us-central1)
  --cluster-name <name>        GKE cluster name (default: online-boutique)
  --cluster-location <loc>     GKE location (region/zone). Defaults to --region
  --create-cluster             Create GKE Autopilot cluster if it does not exist
  --state-bucket <name>        GCS bucket for Terraform remote state
  --state-bucket-location <l>  GCS bucket location (default: US)
  --state-prefix <prefix>      Terraform state key prefix (default: terraform/argocd)
  --artifact-repo <name>       Artifact Registry repo name (default: microservices-demo)
  --no-artifact-repo           Skip Artifact Registry repo creation
  --argocd-host <hostname>     Argo CD ingress host (for existing ingress)
  --argocd-ingress-class <c>   Ingress class (default: nginx)
  --argocd-ingress-tls <name>  TLS secret name for Argo ingress (default: argocd-server-tls)
  --argocd-cluster-issuer <i>  cert-manager cluster issuer (default: letsencrypt-prod)
  --disable-argocd-ingress     Disable Argo CD ingress
  --disable-service-monitors   Disable Argo CD ServiceMonitor resources
  --service-monitor-release-label <v>  ServiceMonitor release label (default: prometheus)
  --init                       Run 'terraform init' after bootstrap
  --plan                       Run 'terraform plan' after bootstrap
  --apply                      Run 'terraform apply -auto-approve' after bootstrap
  -h, --help                   Show this help message

Examples:
  $(basename "$0") --project-id my-project --cluster-name online-boutique --cluster-location us-central1
  $(basename "$0") --project-id my-project --create-cluster --init --plan
  $(basename "$0") --project-id my-project --argocd-host argocd.example.com --apply
USAGE_EOF
}

log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --cluster-name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --cluster-location)
      CLUSTER_LOCATION="$2"
      shift 2
      ;;
    --create-cluster)
      CREATE_CLUSTER="true"
      shift
      ;;
    --state-bucket)
      STATE_BUCKET="$2"
      shift 2
      ;;
    --state-bucket-location)
      STATE_BUCKET_LOCATION="$2"
      shift 2
      ;;
    --state-prefix)
      STATE_PREFIX="$2"
      shift 2
      ;;
    --artifact-repo)
      ARTIFACT_REPO="$2"
      shift 2
      ;;
    --no-artifact-repo)
      CREATE_ARTIFACT_REPO="false"
      shift
      ;;
    --argocd-host)
      ARGOCD_HOSTNAME="$2"
      shift 2
      ;;
    --argocd-ingress-class)
      ARGOCD_INGRESS_CLASS="$2"
      shift 2
      ;;
    --argocd-ingress-tls)
      ARGOCD_INGRESS_TLS_SECRET="$2"
      shift 2
      ;;
    --argocd-cluster-issuer)
      ARGOCD_CLUSTER_ISSUER="$2"
      shift 2
      ;;
    --disable-argocd-ingress)
      ENABLE_ARGOCD_INGRESS="false"
      shift
      ;;
    --disable-service-monitors)
      ENABLE_SERVICE_MONITORS="false"
      shift
      ;;
    --service-monitor-release-label)
      SERVICE_MONITOR_RELEASE_LABEL="$2"
      shift 2
      ;;
    --init)
      RUN_TERRAFORM_INIT="true"
      shift
      ;;
    --plan)
      RUN_TERRAFORM_PLAN="true"
      shift
      ;;
    --apply)
      RUN_TERRAFORM_APPLY="true"
      RUN_TERRAFORM_PLAN="true"
      RUN_TERRAFORM_INIT="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${PROJECT_ID}" ]] || die "--project-id is required"
[[ -n "${CLUSTER_LOCATION}" ]] || CLUSTER_LOCATION="${REGION}"
[[ -n "${STATE_BUCKET}" ]] || STATE_BUCKET="${PROJECT_ID}-tfstate-argocd"
if [[ "${ENABLE_ARGOCD_INGRESS}" == "true" && -z "${ARGOCD_HOSTNAME}" ]]; then
  log "No --argocd-host provided, disabling Argo CD ingress for safety."
  ENABLE_ARGOCD_INGRESS="false"
fi

require_cmd gcloud
require_cmd terraform

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1 || true)"
[[ -n "${ACTIVE_ACCOUNT}" ]] || die "No active gcloud account. Run: gcloud auth login"

log "Using gcloud account: ${ACTIVE_ACCOUNT}"
log "Setting active project: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}" >/dev/null

PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
[[ -n "${PROJECT_NUMBER}" ]] || die "Unable to resolve project number for ${PROJECT_ID}"

REQUIRED_APIS=(
  serviceusage.googleapis.com
  cloudresourcemanager.googleapis.com
  iam.googleapis.com
  iamcredentials.googleapis.com
  container.googleapis.com
)

if [[ "${CREATE_CLUSTER}" == "true" ]]; then
  REQUIRED_APIS+=(compute.googleapis.com)
fi

if [[ "${CREATE_ARTIFACT_REPO}" == "true" ]]; then
  REQUIRED_APIS+=(artifactregistry.googleapis.com)
fi

log "Enabling required APIs"
gcloud services enable "${REQUIRED_APIS[@]}" --project "${PROJECT_ID}"

log "Ensuring Terraform state bucket exists: gs://${STATE_BUCKET}"
if ! gcloud storage buckets describe "gs://${STATE_BUCKET}" --project "${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project "${PROJECT_ID}" \
    --location "${STATE_BUCKET_LOCATION}" \
    --uniform-bucket-level-access
fi

gcloud storage buckets update "gs://${STATE_BUCKET}" --versioning >/dev/null

if [[ "${CREATE_ARTIFACT_REPO}" == "true" ]]; then
  log "Ensuring Artifact Registry repo exists: ${ARTIFACT_REPO} (${REGION})"
  if ! gcloud artifacts repositories describe "${ARTIFACT_REPO}" \
    --location "${REGION}" \
    --project "${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud artifacts repositories create "${ARTIFACT_REPO}" \
      --repository-format=docker \
      --location="${REGION}" \
      --project "${PROJECT_ID}" \
      --description="Container images for microservices deployments"
  fi

  gcloud auth configure-docker "${REGION}-docker.pkg.dev" -q
fi

if [[ "${CREATE_CLUSTER}" == "true" ]]; then
  log "Checking GKE cluster: ${CLUSTER_NAME}"
  if ! gcloud container clusters describe "${CLUSTER_NAME}" \
    --location "${CLUSTER_LOCATION}" \
    --project "${PROJECT_ID}" >/dev/null 2>&1; then
    log "Creating GKE Autopilot cluster: ${CLUSTER_NAME}"
    gcloud container clusters create-auto "${CLUSTER_NAME}" \
      --location "${CLUSTER_LOCATION}" \
      --project "${PROJECT_ID}"
  fi
else
  log "Validating existing GKE cluster: ${CLUSTER_NAME}"
  gcloud container clusters describe "${CLUSTER_NAME}" \
    --location "${CLUSTER_LOCATION}" \
    --project "${PROJECT_ID}" >/dev/null
fi

log "Fetching cluster credentials"
gcloud container clusters get-credentials "${CLUSTER_NAME}" \
  --location "${CLUSTER_LOCATION}" \
  --project "${PROJECT_ID}"

log "Writing Terraform backend config: ${TF_DIR}/backend.hcl"
cat > "${TF_DIR}/backend.hcl" <<BACKEND_EOF
bucket = "${STATE_BUCKET}"
prefix = "${STATE_PREFIX}"
BACKEND_EOF

log "Writing Terraform variables: ${TF_DIR}/terraform.tfvars"
cat > "${TF_DIR}/terraform.tfvars" <<TFVARS_EOF
project_id       = "${PROJECT_ID}"
region           = "${REGION}"
cluster_name     = "${CLUSTER_NAME}"
cluster_location = "${CLUSTER_LOCATION}"
argo_server_service_type      = "ClusterIP"
enable_argocd_ingress         = ${ENABLE_ARGOCD_INGRESS}
argocd_ingress_class_name     = "${ARGOCD_INGRESS_CLASS}"
argocd_ingress_hostname       = "${ARGOCD_HOSTNAME}"
argocd_ingress_tls_secret_name = "${ARGOCD_INGRESS_TLS_SECRET}"
argocd_ingress_cluster_issuer = "${ARGOCD_CLUSTER_ISSUER}"
enable_service_monitors       = ${ENABLE_SERVICE_MONITORS}
service_monitor_additional_labels = { release = "${SERVICE_MONITOR_RELEASE_LABEL}" }
TFVARS_EOF

pushd "${TF_DIR}" >/dev/null

if [[ "${RUN_TERRAFORM_INIT}" == "true" ]]; then
  log "Running terraform init"
  terraform init -backend-config=backend.hcl
fi

if [[ "${RUN_TERRAFORM_PLAN}" == "true" ]]; then
  log "Running terraform plan"
  terraform plan
fi

if [[ "${RUN_TERRAFORM_APPLY}" == "true" ]]; then
  log "Running terraform apply"
  terraform apply -auto-approve
fi

popd >/dev/null

cat <<SUMMARY_EOF

Bootstrap complete.

Project:           ${PROJECT_ID} (${PROJECT_NUMBER})
Cluster:           ${CLUSTER_NAME}
Cluster location:  ${CLUSTER_LOCATION}
State bucket:      gs://${STATE_BUCKET}
State prefix:      ${STATE_PREFIX}
Terraform dir:     ${TF_DIR}
Argo ingress:      ${ENABLE_ARGOCD_INGRESS}
Argo host:         ${ARGOCD_HOSTNAME:-<disabled>}
Service monitors:  ${ENABLE_SERVICE_MONITORS}

Next commands:
  cd ${TF_DIR}
  terraform init -backend-config=backend.hcl
  terraform plan
  terraform apply

After apply:
  kubectl -n argocd get svc
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo
SUMMARY_EOF

variable "project_id" {
  type        = string
  description = "GCP project ID where GKE cluster exists."
}

variable "region" {
  type        = string
  description = "Default Google Cloud region for provider operations."
  default     = "us-central1"
}

variable "cluster_name" {
  type        = string
  description = "Name of the target GKE cluster where Argo CD will be installed."
}

variable "cluster_location" {
  type        = string
  description = "Region or zone of the target GKE cluster."
  default     = "us-central1"
}

variable "argocd_namespace" {
  type        = string
  description = "Namespace where Argo CD is installed."
  default     = "argocd"
}

variable "argocd_release_name" {
  type        = string
  description = "Helm release name for Argo CD."
  default     = "argocd"
}

variable "argocd_chart_version" {
  type        = string
  description = "Optional pinned Helm chart version for argo-cd. Leave empty to use latest chart version."
  default     = ""
}

variable "argo_server_service_type" {
  type        = string
  description = "Kubernetes Service type for Argo CD API/UI server."
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.argo_server_service_type)
    error_message = "argo_server_service_type must be one of: ClusterIP, NodePort, LoadBalancer."
  }
}

variable "helm_timeout_seconds" {
  type        = number
  description = "Timeout for Helm installation/upgrade operations."
  default     = 900
}

variable "argocd_helm_values_file" {
  type        = string
  description = "Optional path to a custom Helm values YAML file for Argo CD."
  default     = ""
}

variable "enable_argocd_ingress" {
  type        = bool
  description = "Enable Argo CD server ingress resource via Helm chart."
  default     = true
}

variable "argocd_ingress_class_name" {
  type        = string
  description = "Ingress class name used by Argo CD ingress."
  default     = "nginx"
}

variable "argocd_ingress_hostname" {
  type        = string
  description = "Hostname for Argo CD ingress. Required when enable_argocd_ingress is true."
  default     = ""
}

variable "argocd_ingress_tls_secret_name" {
  type        = string
  description = "TLS secret name for Argo CD ingress."
  default     = "argocd-server-tls"
}

variable "argocd_ingress_cluster_issuer" {
  type        = string
  description = "cert-manager cluster issuer for Argo CD ingress certificate. Set empty to skip issuer annotation."
  default     = "letsencrypt-prod"
}

variable "argocd_ingress_annotations" {
  type        = map(string)
  description = "Extra annotations for Argo CD ingress."
  default     = {}
}

variable "manage_argocd_certificate" {
  type        = bool
  description = "Create a cert-manager Certificate resource for Argo CD ingress TLS secret."
  default     = true
}

variable "enable_service_monitors" {
  type        = bool
  description = "Enable ServiceMonitor resources for Argo CD metrics components."
  default     = true
}

variable "service_monitor_additional_labels" {
  type        = map(string)
  description = "Additional labels applied to Argo CD ServiceMonitor resources."
  default = {
    release = "prometheus"
  }
}

variable "enable_required_apis" {
  type        = bool
  description = "Enable required Google Cloud APIs before installing Argo CD."
  default     = true
}

variable "required_apis" {
  type        = list(string)
  description = "Google Cloud APIs to ensure are enabled in the target project."
  default = [
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "container.googleapis.com"
  ]
}

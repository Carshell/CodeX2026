locals {
  argocd_values = var.argocd_helm_values_file != "" ? [file(var.argocd_helm_values_file)] : []

  argocd_ingress_annotations = merge(
    var.argocd_ingress_annotations,
    {
      "kubernetes.io/ingress.class" = var.argocd_ingress_class_name
    },
    var.argocd_ingress_cluster_issuer != "" ? {
      "cert-manager.io/cluster-issuer"            = var.argocd_ingress_cluster_issuer
      "acme.cert-manager.io/http01-edit-in-place" = "true"
    } : {}
  )

  ingress_values = jsondecode(
    var.enable_argocd_ingress && var.argocd_ingress_hostname != "" ?
    jsonencode({
      ingress = {
        enabled          = true
        ingressClassName = var.argocd_ingress_class_name
        hostname         = var.argocd_ingress_hostname
        path             = "/"
        pathType         = "Prefix"
        annotations      = local.argocd_ingress_annotations
        tls              = true
        extraTls = [
          {
            hosts      = [var.argocd_ingress_hostname]
            secretName = var.argocd_ingress_tls_secret_name
          }
        ]
      }
    }) : "{\"ingress\":{\"enabled\":false}}"
  )

  server_values = merge(
    {
      service = {
        type = var.argo_server_service_type
      }
    },
    local.ingress_values
  )

  service_monitor_values = {
    controller = {
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled          = true
          additionalLabels = var.service_monitor_additional_labels
        }
      }
    }
    server = merge(local.server_values, {
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled          = true
          additionalLabels = var.service_monitor_additional_labels
        }
      }
    })
    repoServer = {
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled          = true
          additionalLabels = var.service_monitor_additional_labels
        }
      }
    }
    applicationSet = {
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled          = true
          additionalLabels = var.service_monitor_additional_labels
        }
      }
    }
    notifications = {
      metrics = {
        enabled = true
        serviceMonitor = {
          enabled          = true
          additionalLabels = var.service_monitor_additional_labels
        }
      }
    }
  }

  generated_values = merge(
    {
      crds = {
        install = true
      }
      configs = {
        params = {
          "server.insecure" = var.enable_argocd_ingress ? "true" : "false"
        }
      }
      server = local.server_values
    },
    jsondecode(var.enable_service_monitors ? jsonencode(local.service_monitor_values) : "{}")
  )
}

resource "google_project_service" "required" {
  for_each = var.enable_required_apis ? toset(var.required_apis) : toset([])

  project                    = var.project_id
  service                    = each.key
  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
    labels = {
      "app.kubernetes.io/part-of" = "argocd"
      "managed-by"                = "terraform"
    }
  }

  depends_on = [google_project_service.required]
}

resource "helm_release" "argocd" {
  name             = var.argocd_release_name
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = kubernetes_namespace.argocd.metadata[0].name
  create_namespace = false
  version          = var.argocd_chart_version != "" ? var.argocd_chart_version : null

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = var.helm_timeout_seconds

  values = concat(local.argocd_values, [yamlencode(local.generated_values)])

  depends_on = [google_project_service.required]
}

resource "kubernetes_manifest" "argocd_certificate" {
  count = var.manage_argocd_certificate && var.enable_argocd_ingress && var.argocd_ingress_hostname != "" && var.argocd_ingress_cluster_issuer != "" ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = var.argocd_ingress_tls_secret_name
      namespace = var.argocd_namespace
      labels = {
        "app.kubernetes.io/part-of" = "argocd"
        "managed-by"                = "terraform"
      }
    }
    spec = {
      secretName = var.argocd_ingress_tls_secret_name
      dnsNames   = [var.argocd_ingress_hostname]
      issuerRef = {
        kind = "ClusterIssuer"
        name = var.argocd_ingress_cluster_issuer
      }
    }
  }

  depends_on = [helm_release.argocd]
}

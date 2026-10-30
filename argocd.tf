
# ==================================================
# PATHNEX - ARGO CD INSTALLATION
# ==================================================

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "10.11.6"

  namespace        = "argocd"
  create_namespace = true

  wait            = true
  timeout         = 900
  atomic          = true
  cleanup_on_fail = true

  depends_on = [
    module.eks
  ]
}

# ==================================================
# ARGO CD OUTPUTS
# ==================================================

output "argocd_namespace" {
  description = "Kubernetes namespace where Argo CD is installed"
  value       = helm_release.argocd.namespace
}

output "argocd_release_status" {
  description = "Argo CD Helm release status"
  value       = helm_release.argocd.status
}

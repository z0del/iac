# Capítulo 4 - Terraform + ArgoCD + Helm (Enterprise Mode)
# Arquivo: cap4-argocd-gitops/main.tf

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}

################################################################################
# INFRAESTRUTURA (gerenciada pelo Terraform)
################################################################################

# Namespace para ArgoCD
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      managed-by = "terraform"
      purpose    = "gitops"
    }
  }
}

# Namespace para aplicações
resource "kubernetes_namespace" "ollama" {
  metadata {
    name = "ollama"
    labels = {
      managed-by = "terraform"
    }
  }
}

resource "kubernetes_namespace" "librechat" {
  metadata {
    name = "librechat"
    labels = {
      managed-by = "terraform"
    }
  }
}

# Secrets (infra-level, managed by Terraform)
resource "kubernetes_secret" "librechat_credentials" {
  metadata {
    name      = "librechat-credentials-env"
    namespace = kubernetes_namespace.librechat.metadata[0].name
  }

  data = {
    JWT_SECRET         = var.jwt_secret
    JWT_REFRESH_SECRET = var.jwt_refresh_secret
    CREDS_KEY          = var.creds_key
    CREDS_IV           = var.creds_iv
    MONGO_URI          = "mongodb://librechat-mongodb:27017/LibreChat"
    MEILI_HOST         = "http://librechat-meilisearch:7700"
    OLLAMA_BASE_URL    = "http://ollama.ollama.svc.cluster.local:11434"
  }

  type = "Opaque"
}

################################################################################
# ARGOCD (instalado pelo Terraform)
################################################################################

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "5.51.6"

  values = [
    file("${path.module}/values/argocd-values.yaml")
  ]

  timeout       = 600
  wait          = true
  wait_for_jobs = true

  depends_on = [
    kubernetes_namespace.argocd
  ]
}

# Senha inicial do ArgoCD (pegamos do secret)
data "kubernetes_secret" "argocd_initial_admin" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  depends_on = [
    helm_release.argocd
  ]
}

################################################################################
# ARGOCD APPLICATIONS (Apps gerenciadas pelo ArgoCD)
################################################################################

# Application: Ollama
resource "kubernetes_manifest" "argocd_app_ollama" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "ollama"
      namespace = kubernetes_namespace.argocd.metadata[0].name
      labels = {
        managed-by = "terraform"
      }
    }
    spec = {
      project = "default"
      
      source = {
        repoURL        = var.git_repo_url
        targetRevision = var.git_branch
        path           = "apps/ollama"
        helm = {
          valueFiles = ["values.yaml"]
        }
      }
      
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace.ollama.metadata[0].name
      }
      
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=false"
        ]
      }
    }
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.ollama
  ]
}

# Application: LibreChat
resource "kubernetes_manifest" "argocd_app_librechat" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "librechat"
      namespace = kubernetes_namespace.argocd.metadata[0].name
      labels = {
        managed-by = "terraform"
      }
    }
    spec = {
      project = "default"
      
      source = {
        repoURL        = var.git_repo_url
        targetRevision = var.git_branch
        path           = "apps/librechat"
        helm = {
          valueFiles = ["values.yaml"]
        }
      }
      
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace.librechat.metadata[0].name
      }
      
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=false"
        ]
      }
    }
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.librechat,
    kubernetes_secret.librechat_credentials
  ]
}

################################################################################
# OUTPUTS
################################################################################

output "argocd_url" {
  value = "http://argocd.glukas.space"
}

output "argocd_admin_password" {
  value     = try(data.kubernetes_secret.argocd_initial_admin.data["password"], "")
  sensitive = true
}

output "argocd_password_command" {
  value = "minikube kubectl -- -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "applications_managed" {
  value = {
    ollama = {
      namespace = kubernetes_namespace.ollama.metadata[0].name
      status    = "Managed by ArgoCD"
    }
    librechat = {
      namespace = kubernetes_namespace.librechat.metadata[0].name
      status    = "Managed by ArgoCD"
    }
  }
}

output "architecture_summary" {
  value = <<-EOT
    
    🏗️  Arquitetura Enterprise:
    
    ┌─────────────┐
    │   Git Repo  │ ← Source of Truth
    └──────┬──────┘
           │
           ↓
    ┌─────────────┐
    │   ArgoCD    │ ← Observa Git
    └──────┬──────┘
           │
           ↓
    ┌─────────────┐
    │  Kubernetes │ ← Deploys automáticos
    │  (Minikube) │
    └─────────────┘
    
    Terraform gerencia:
    • Namespaces
    • Secrets
    • RBAC
    • ArgoCD installation
    
    ArgoCD gerencia:
    • Ollama (via Helm)
    • LibreChat (via Helm)
    • Sync automático do Git
  EOT
}

# Capítulo 4 - Variáveis
# Arquivo: cap4-argocd-gitops/variables.tf

variable "jwt_secret" {
  description = "JWT Secret para LibreChat"
  type        = string
  sensitive   = true
}

variable "jwt_refresh_secret" {
  description = "JWT Refresh Secret para LibreChat"
  type        = string
  sensitive   = true
}

variable "creds_key" {
  description = "Credentials encryption key"
  type        = string
  sensitive   = true
}

variable "creds_iv" {
  description = "Credentials encryption IV"
  type        = string
  sensitive   = true
}

variable "git_repo_url" {
  description = "URL do repositório Git (para ArgoCD observar)"
  type        = string
  default     = "https://github.com/seu-usuario/librechat-k8s-apps.git"
}

variable "git_branch" {
  description = "Branch do Git para ArgoCD observar"
  type        = string
  default     = "main"
}

variable "argocd_version" {
  description = "Versão do chart Helm do ArgoCD"
  type        = string
  default     = "5.51.6"
}

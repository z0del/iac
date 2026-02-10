# Capítulo 4 - Terraform + ArgoCD + Helm (Enterprise Mode) 🏢

## 🎯 O Grande Click Mental

Neste capítulo você vai entender porque **Terraform não deve deployar aplicações diretamente** em ambientes enterprise.

### O Problema dos Capítulos Anteriores

```
Desenvolvedor → terraform apply → Kubernetes
                    ↑
              (processo manual)
```

❌ Sem auditoria clara
❌ Sem continuous deployment  
❌ Sem separação de responsabilidades
❌ Drift entre Git e cluster

### A Solução Enterprise

```
Desenvolvedor → Git push → ArgoCD observa → Kubernetes
                              ↑
                    (automático & auditado)
```

✅ Source of truth no Git
✅ Deploy automático
✅ Auditoria completa (quem, quando, o quê)
✅ Rollback visual

## 📐 Arquitetura Enterprise

```
┌─────────────────────────────────────────────────────────┐
│                    CAMADA 1: TERRAFORM                   │
│                    (Roda uma vez)                        │
├──────────────────────────────────────────────────────────┤
│  • Cria namespaces                                       │
│  • Cria secrets (infra-level)                            │
│  • Configura RBAC                                        │
│  • INSTALA ArgoCD                                        │
│  • Cria ArgoCD Applications (ponteiros para Git)        │
└────────────────┬─────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│                    CAMADA 2: GIT                        │
│                    (Source of Truth)                     │
├──────────────────────────────────────────────────────────┤
│  apps/                                                   │
│  ├── ollama/                                            │
│  │   ├── Chart.yaml                                    │
│  │   └── values.yaml                                   │
│  └── librechat/                                         │
│      ├── Chart.yaml                                    │
│      └── values.yaml                                   │
└────────────────┬─────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│                  CAMADA 3: ARGOCD                       │
│                  (Roda continuamente)                    │
├──────────────────────────────────────────────────────────┤
│  • Observa Git (a cada 3 minutos)                       │
│  • Detecta mudanças                                     │
│  • Aplica via Helm                                      │
│  • Self-healing (se alguém mudar manual, reverte)      │
└────────────────┬─────────────────────────────────────────┘
                 │
                 ↓
┌─────────────────────────────────────────────────────────┐
│                CAMADA 4: KUBERNETES                     │
│                (Estado desejado)                         │
├──────────────────────────────────────────────────────────┤
│  • Ollama rodando                                       │
│  • LibreChat rodando                                    │
│  • Sincronizado com Git                                 │
└──────────────────────────────────────────────────────────┘
```

## 🚀 Setup Completo

### Passo 1: Preparar o Repositório Git

```bash
# Criar um repositório no GitHub/GitLab
# Exemplo: librechat-k8s-apps

# Clonar localmente
git clone https://github.com/seu-usuario/librechat-k8s-apps.git
cd librechat-k8s-apps

# Copiar estrutura de exemplo
cp -r /path/to/cap4-argocd-gitops/git-repo-example/apps .

# Commit inicial
git add apps/
git commit -m "Initial commit: Ollama and LibreChat apps"
git push origin main
```

### Passo 2: Configurar Variáveis

```bash
cd cap4-argocd-gitops

# Copiar exemplo
cp terraform.tfvars.example terraform.tfvars

# Editar com seus valores
vim terraform.tfvars

# Adicionar:
git_repo_url = "https://github.com/seu-usuario/librechat-k8s-apps.git"
git_branch   = "main"

# Gerar secrets
jwt_secret         = "$(openssl rand -hex 32)"
jwt_refresh_secret = "$(openssl rand -hex 32)"
creds_key          = "$(openssl rand -hex 32)"
creds_iv           = "$(openssl rand -hex 16)"
```

### Passo 3: Adicionar ArgoCD ao /etc/hosts

```bash
# Pegar IP do Minikube
minikube ip

# Adicionar ao /etc/hosts
echo "192.168.49.2 argocd.glukas.space" | sudo tee -a /etc/hosts
```

### Passo 4: Deploy da Infraestrutura

```bash
# Inicializar Terraform
terraform init

# Ver o plano
terraform plan

# Aplicar
terraform apply
# Isso vai:
# - Criar namespaces
# - Criar secrets
# - Instalar ArgoCD
# - Criar Applications no ArgoCD
```

### Passo 5: Acessar ArgoCD

```bash
# Pegar senha do admin
terraform output argocd_admin_password

# OU
minikube kubectl -- -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# Acessar interface
open http://argocd.glukas.space

# Login:
# Username: admin
# Password: [o output acima]
```

### Passo 6: Verificar Sync

No ArgoCD UI, você verá:

```
┌─────────────────────────────────┐
│ ollama                          │
│ ✅ Synced | ✅ Healthy          │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│ librechat                       │
│ ✅ Synced | ✅ Healthy          │
└─────────────────────────────────┘
```

## 🎨 Workflow Dia-a-Dia

### Cenário 1: Adicionar um novo modelo ao Ollama

**Antes (Cap 3):**
```bash
# Editar values local
vim values/ollama-values.yaml

# Aplicar manualmente
terraform apply

# Esperar
```

**Agora (Cap 4):**
```bash
# Editar no Git
cd librechat-k8s-apps
vim apps/ollama/values.yaml

# Adicionar:
models:
  - llama2
  - llama3  # <-- novo!

# Commit e push
git add apps/ollama/values.yaml
git commit -m "Add llama3 model"
git push

# ArgoCD detecta em ~3 minutos e aplica automaticamente!
# Você vê o deploy acontecer na UI do ArgoCD
```

### Cenário 2: Atualizar versão do LibreChat

```bash
cd librechat-k8s-apps
vim apps/librechat/Chart.yaml

# Mudar version:
dependencies:
  - name: librechat
    version: "1.10.0"  # <-- bump!

git add apps/librechat/Chart.yaml
git commit -m "Upgrade LibreChat to 1.10.0"
git push

# ArgoCD faz rolling update automaticamente
```

### Cenário 3: Rollback

**Opção 1 - Via Git:**
```bash
git revert HEAD
git push
# ArgoCD aplica o revert automaticamente
```

**Opção 2 - Via ArgoCD UI:**
```
1. Abrir ArgoCD
2. Clicar na app
3. History tab
4. Selecionar versão anterior
5. Rollback
```

**Opção 3 - Via ArgoCD CLI:**
```bash
argocd app rollback librechat
```

## 🔍 Comparação Final

### Workflow nos 4 Capítulos

| Aspecto | Cap 1 | Cap 2 | Cap 3 | Cap 4 |
|---------|-------|-------|-------|-------|
| **Tool** | kubectl/helm | Terraform | Terraform + Helm | Terraform + ArgoCD + Helm |
| **Deploy** | Manual | Manual | Manual | Automático |
| **Source of Truth** | Memória | State | State + Values | Git |
| **Auditoria** | ❌ | Parcial | Parcial | ✅ Completa |
| **Rollback** | Difícil | Médio | Fácil | Visual |
| **CI/CD** | ❌ | ❌ | ❌ | ✅ |
| **Self-healing** | ❌ | ❌ | ❌ | ✅ |
| **Multi-env** | ❌ | Médio | Bom | ✅ Excelente |
| **Separação** | ❌ | ❌ | Parcial | ✅ Total |

### Deploy de uma mudança

**Cap 1:**
```bash
helm upgrade ...  # Manual
# Tempo: ~2 min
# Auditoria: nenhuma
```

**Cap 2:**
```bash
terraform apply  # Manual
# Tempo: ~5 min (state grande)
# Auditoria: Terraform logs
```

**Cap 3:**
```bash
terraform apply  # Manual
# Tempo: ~3 min
# Auditoria: Terraform logs
```

**Cap 4:**
```bash
git push  # Resto é automático!
# Tempo: ~3 min (depois do push)
# Auditoria: Git history + ArgoCD logs
```

## 🏆 Vantagens do Cap 4

### 1. GitOps Real

```
Git = Source of Truth
↓
Qualquer mudança passa por Pull Request
↓
Review + Approval
↓
Merge → Deploy automático
↓
Auditoria completa no Git
```

### 2. Self-Healing

```bash
# Alguém faz:
kubectl edit deployment ollama -n ollama

# ArgoCD detecta drift e reverte automaticamente!
# "Estado desejado está no Git, não no cluster"
```

### 3. Multi-Environment Natural

```
git-repo/
├── apps/
│   └── ollama/
│       ├── values-dev.yaml
│       ├── values-staging.yaml
│       └── values-prod.yaml
```

ArgoCD pode ter 3 Applications:
- `ollama-dev` → branch `dev`
- `ollama-staging` → branch `staging`
- `ollama-prod` → branch `main`

### 4. Visibility Total

ArgoCD UI mostra:
- ✅ O que está rodando
- 📊 Health de cada componente
- 📜 Histórico completo
- 🔄 Sync status
- 📦 Versões deployadas

### 5. Disaster Recovery

```bash
# Cluster explodiu?
# Reconstruir é trivial:

terraform apply  # Recria infra + ArgoCD
# ArgoCD sincroniza tudo do Git automaticamente
# Cluster volta ao estado desejado
```

## 📋 Responsabilidades Claramente Definidas

### Terraform é responsável por:

✅ Namespaces
✅ Secrets de infraestrutura
✅ RBAC / Service Accounts
✅ Instalação do ArgoCD
✅ Configuração de Applications (ponteiros)
✅ Recursos de cloud (se houver: VPC, RDS, etc)

### ArgoCD é responsável por:

✅ Observar Git
✅ Aplicar mudanças via Helm
✅ Garantir sync
✅ Self-healing
✅ Rollback

### Helm é responsável por:

✅ Empacotar aplicações
✅ Templates
✅ Lifecycle hooks

### Git é responsável por:

✅ Versionar tudo
✅ Ser o source of truth
✅ Auditoria (commits, PRs)

## 🎓 Lições Aprendidas

### 1. Terraform não deve deployar apps

```hcl
# ❌ MAL
resource "kubernetes_deployment" "app" { }

# ✅ BOM
resource "kubernetes_manifest" "argocd_app" {
  # Apenas cria o ponteiro, ArgoCD faz o deploy
}
```

### 2. Git é o source of truth

```
Estado no cluster ≠ verdade
Estado no Git = verdade
```

### 3. Separação de camadas

```
Layer 1: Terraform (infra que muda raramente)
Layer 2: Git (configs que mudam frequentemente)
Layer 3: ArgoCD (reconcilia Layer 1 + 2)
Layer 4: Kubernetes (estado atual)
```

## 🧹 Limpeza

```bash
# Destruir tudo
terraform destroy

# Confirmar com 'yes'
# Isso remove:
# - ArgoCD
# - Namespaces
# - Secrets
# (As apps serão deletadas pelo cascade delete)
```

## 🚀 Próximos Passos Reais

Agora que você entendeu a arquitetura enterprise, pode:

1. **Adicionar mais ambientes**
   - Dev, Staging, Prod
   - Branches diferentes no Git

2. **Integrar CI/CD**
   - GitHub Actions
   - Testes automatizados antes do merge

3. **Adicionar monitoramento**
   - Prometheus + Grafana
   - Alertas no Slack

4. **Configurar backups**
   - Velero para backup do cluster
   - Snapshots do Git

5. **Implementar políticas**
   - OPA / Gatekeeper
   - Network policies
   - Pod Security Standards

## 📚 Referências

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [GitOps Principles](https://opengitops.dev/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

---

## 🎯 Conclusão do Curso

Você passou por toda a jornada:

**Cap 1:** Aprendeu os conceitos (Minikube, Helm, kubectl)
**Cap 2:** Viu Terraform gerenciar K8s (mas percebeu as limitações)
**Cap 3:** Descobriu Terraform + Helm (muito melhor!)
**Cap 4:** Entendeu o padrão enterprise (GitOps!)

Agora você sabe **como** e **por que** as empresas estruturam infraestrutura desta forma.

**O click mental aconteceu? 💡**

> "Terraform gerencia a plataforma, não as aplicações."

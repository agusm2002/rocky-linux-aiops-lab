# Fase 9 — Migración a Oracle Cloud: Plan Detallado

> **Objetivo:** Migrar el stack completo del lab local (UTM) a Oracle Cloud Free Tier
> con arquitectura distribuida, sin gastar un solo USD.
>
> **Principio rector:** Todo lo que se toca en OCI se provisiona con OpenTofu.
> Nada se crea a mano desde la consola (salvo el compartment y la API key inicial).

---

## 1. Diagnóstico inicial: lo que falta antes de arrancar

### 1.1 Gaps en `tofu/oracle/`

El directorio `tofu/oracle/` actualmente **solo define NSGs**. No define:

- ❌ VCN + subnets
- ❌ Compute instances (`vm-bastion`, `vm-k3s`)
- ❌ OCI Object Storage bucket (para Loki)
- ❌ OCI Vault (secrets gestionados)
- ❌ Internet Gateway + route tables
- ❌ El `main.tf` referencia `oci_core_instance.bastion.private_ip` pero el recurso no existe → **`tofu plan` rompería**

Además, `tofu/.terraform.lock.hcl` solo tiene el provider `kubernetes`. El provider `oci` nunca fue inicializado.

### 1.2 Gaps en Ansible

- ❌ `ansible/inventory/oracle.yml` no existe
- ❌ `ansible/playbooks/bastion.yml` no existe
- ❌ `ansible/playbooks/k3s.yml` no existe
- El `site.yml` actual solo funciona con `connection: local`

### 1.3 Gaps en k3s manifests

- ❌ Loki está configurado con `filesystem` local. Necesita variante con OCI Object Storage.
- ❌ Los secrets se obtienen de Vault self-hosted. Hay que migrar a OCI Vault (o documentar el contraste).
- ❌ Grafana no está en modo read-only público.
- ❌ No hay `terraform.tfvars.example` para que el usuario sepa qué valores completar.

### 1.4 Lo que SÍ está listo y se reutiliza

- ✅ NSGs de OCI en OpenTofu (bastion + k3s con reglas least-privilege)
- ✅ Variables de OCI (`tenancy_ocid`, `user_ocid`, `fingerprint`, etc.)
- ✅ Los 7 roles de Ansible (system-base, firewalld, selinux, ssh-hardening, fail2ban, dnf-automatic, vault-agent)
- ✅ Todos los manifests de k3s (Prometheus, Grafana, Loki, n8n, Jenkins, ArgoCD, Alertmanager, Alloy)
- ✅ ArgoCD Application (`argocd-app.yml`)
- ✅ NSGs ya exportados como outputs

---

## 2. Arquitectura objetivo en Oracle Cloud

```
┌─────────────────────────────────────────────────────────┐
│                    Oracle Cloud Free Tier                │
│                                                          │
│  Internet                                                │
│     │                                                    │
│     ├── :443 (0.0.0.0/0) ──────────► vm-k3s             │
│     │    Grafana read-only público                        │
│     │                                                    │
│     └── :22 (tu IP/32) ────────────► vm-bastion          │
│           Único punto de entrada SSH                      │
│                                          │                │
│                           SSH interno (IP privada)        │
│                                          │                │
│                                          ▼                │
│                                      vm-k3s               │
│                                                           │
│  ┌───────────────────────────────────────────────────┐   │
│  │ k3s cluster (3 vCPU / 18 GB RAM)                   │   │
│  │                                                    │   │
│  │  ArgoCD  ←── sincroniza desde GitHub               │   │
│  │  Prometheus + Alertmanager                         │   │
│  │  Loki ←── escribe a OCI Object Storage             │   │
│  │  Grafana Alloy                                     │   │
│  │  Grafana (read-only público)                       │   │
│  │  n8n + OpenCode Go API                             │   │
│  │  Jenkins self-hosted                               │   │
│  └───────────────────────────────────────────────────┘   │
│                                                           │
│  ┌─────────────────────┐  ┌──────────────────────┐       │
│  │ OCI Object Storage  │  │ OCI Vault             │       │
│  │ (backend de Loki)   │  │ (secrets gestionados)  │       │
│  └─────────────────────┘  └──────────────────────┘       │
│                                                           │
│  ┌─────────────────────┐                                 │
│  │ OCI Cloud Guard     │                                 │
│  │ (threat monitoring) │                                 │
│  └─────────────────────┘                                 │
└─────────────────────────────────────────────────────────┘
```

### Recursos Free Tier utilizados

| Recurso | Shape | vCPU | RAM | Costo |
|---|---|---|---|---|
| vm-k3s | Ampere A1 | 3 | 18 GB | $0 |
| vm-bastion | Ampere A1 | 1 | 6 GB | $0 |
| OCI Object Storage | Managed (10 GB/mes) | — | — | $0 |
| OCI Vault | Managed (20 keys) | — | — | $0 |
| OCI VCN + NSG | Managed | — | — | $0 |
| OCI Cloud Guard | Managed | — | — | $0 |
| **Total** | | **4** | **24 GB** | **$0** |

---

## 3. Paso a paso de la migración

### Paso 0 — Prerrequisitos (única vez)

Antes de ejecutar cualquier comando, hay que hacer esto **una sola vez** en la consola de OCI:

#### 0.1 Crear cuenta Oracle Cloud

- Ir a https://oracle.com/cloud/free
- Completar registro con tarjeta de crédito (no se cobra nada en Free Tier)
- Esperar email de activación

#### 0.2 Configurar budget alert en $0

- Consola OCI → Governance → Budgets
- Crear budget mensual con umbral en $0.01
- Configurar alerta por email
- **Esto es OBLIGATORIO antes de crear cualquier recurso.** Si algo sale del Free Tier, te llega un email inmediato.

#### 0.3 Crear compartment

- Consola OCI → Identity → Compartments
- Crear compartment: `aiops-lab`
- Anotar el OCID del compartment

#### 0.4 Generar API Key

```bash
# En tu Mac
mkdir -p ~/.oci
openssl genrsa -out ~/.oci/oci_api_key.pem 2048
chmod 600 ~/.oci/oci_api_key.pem
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
```

- Subir la clave pública en: Consola OCI → Identity → Users → [tu usuario] → API Keys → Add API Key
- Anotar: `tenancy_ocid`, `user_ocid`, `fingerprint`
- Guardar todo en un archivo temporal **fuera del repo** (`.gitignore` ya cubre `*.key` y `secrets/`)

#### 0.5 Verificar conectividad

```bash
# Instalar OCI CLI (solo para verificar — OpenTofu usa el provider directamente)
brew install oci-cli  # macOS

# Configurar
oci setup keys --key-file ~/.oci/oci_api_key.pem

# Verificar
oci iam compartment list --compartment-id-in-subtree true
```

---

### Paso 1 — Completar OpenTofu para OCI (infraestructura completa)

El `tofu/oracle/main.tf` actual solo tiene NSGs. Hay que agregar **todo** el resto.

#### 1.1 Separar provider de recursos

Crear `tofu/oracle/provider.tf`:

```hcl
terraform {
  required_version = ">= 1.7"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

provider "oci" {
  region           = var.region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  private_key_path = var.private_key_path
  fingerprint      = var.fingerprint
}
```

#### 1.2 Agregar networking (VCN + subnets + gateway)

Crear `tofu/oracle/network.tf`:

```hcl
# ── VCN ──
resource "oci_core_vcn" "aiops" {
  compartment_id = var.compartment_id
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "vcn-aiops-lab"
  dns_label      = "aiops"
}

# ── Internet Gateway ──
resource "oci_core_internet_gateway" "aiops" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.aiops.id
  display_name   = "igw-aiops"
}

# ── Route Table (tráfico público por IGW) ──
resource "oci_core_default_route_table" "aiops" {
  manage_default_resource_id = oci_core_vcn.aiops.default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.aiops.id
  }
}

# ── Subnet pública (para vm-bastion y vm-k3s, Free Tier no soporta subnet privada separada sin NAT Gateway extra) ──
resource "oci_core_subnet" "aiops" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.aiops.id
  cidr_block     = "10.0.1.0/24"
  display_name   = "subnet-aiops"
  dns_label      = "aiopssubnet"
  prohibit_public_ip_on_vnic = false
  route_table_id = oci_core_default_route_table.aiops.id
}
```

> **Nota sobre subnet privada:** El Free Tier no incluye NAT Gateway gratis. Si se quiere una subnet verdaderamente privada, hay que pagar el NAT Gateway (~$30/mes). Como el objetivo es **$0**, ambas VMs van en una subnet pública pero protegidas por NSG: el bastion solo acepta SSH desde tu IP, y k3s solo acepta SSH desde el bastion. Esto es seguro para un lab. Se documenta la decisión.

#### 1.3 Agregar compute instances

Crear `tofu/oracle/compute.tf`:

```hcl
# ── Imagen de Rocky Linux 9 (ARM64) ──
# OCI publica imágenes oficiales de Rocky Linux.
# Buscar el OCID más reciente:
#   oci compute image list --operating-system "Rocky Linux" --shape VM.Standard.A1.Flex
data "oci_core_images" "rocky" {
  compartment_id           = var.compartment_id
  operating_system         = "Rocky Linux"
  operating_system_version = "9"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ── Cloud-init: hardening base + usuario inicial ──
# Se ejecuta UNA vez cuando la VM se crea.
# Ansible se encarga del resto del hardening después.
data "cloudinit_config" "bastion" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/templates/cloud-init.yml.tmpl", {
      ssh_public_key = var.ssh_public_key
      hostname       = "bastion"
    })
  }
}

data "cloudinit_config" "k3s" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/templates/cloud-init.yml.tmpl", {
      ssh_public_key = var.ssh_public_key
      hostname       = "k3s"
    })
  }
}

# ── vm-bastion (1 vCPU, 6 GB) ──
resource "oci_core_instance" "bastion" {
  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "vm-bastion"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 1
    memory_in_gbs = 6
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.aiops.id
    assign_public_ip = true
    nsg_ids          = [oci_core_network_security_group.bastion.id]
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.rocky.images[0].id
    boot_volume_size_in_gbs = 50
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = data.cloudinit_config.bastion.rendered
  }

  # Ignorar cambios en metadata para evitar reemplazo en cada apply
  lifecycle {
    ignore_changes = [
      metadata["user_data"],
      metadata["ssh_authorized_keys"],
      source_details[0].source_id,
    ]
  }
}

# ── vm-k3s (3 vCPU, 18 GB) ──
resource "oci_core_instance" "k3s" {
  compartment_id      = var.compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "vm-k3s"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 3
    memory_in_gbs = 18
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.aiops.id
    assign_public_ip = true
    nsg_ids          = [oci_core_network_security_group.k3s.id]
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.rocky.images[0].id
    boot_volume_size_in_gbs = 100
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = data.cloudinit_config.k3s.rendered
  }

  lifecycle {
    ignore_changes = [
      metadata["user_data"],
      metadata["ssh_authorized_keys"],
      source_details[0].source_id,
    ]
  }
}
```

#### 1.4 Agregar OCI Object Storage (para Loki)

Crear `tofu/oracle/object_storage.tf`:

```hcl
# ── Bucket para logs de Loki ──
resource "oci_objectstorage_bucket" "loki" {
  compartment_id = var.compartment_id
  name           = "loki-aiops-lab"
  namespace      = data.oci_objectstorage_namespace.aiops.namespace
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
}

# ── Namespace de Object Storage (valor por tenant) ──
data "oci_objectstorage_namespace" "aiops" {
  compartment_id = var.compartment_id
}
```

> **Atención:** Free Tier incluye 10 GB/mes de Object Storage. Loki con retention de 31 días y un lab de baja carga debería quedar muy por debajo de eso. Monitorear desde la consola.

#### 1.5 Agregar OCI Vault

Crear `tofu/oracle/vault.tf`:

```hcl
# ── Vault para secrets ──
resource "oci_kms_vault" "aiops" {
  compartment_id = var.compartment_id
  display_name   = "vault-aiops-lab"
  vault_type     = "DEFAULT"
}

# ── Master Encryption Key ──
resource "oci_kms_key" "aiops" {
  compartment_id  = var.compartment_id
  display_name    = "key-aiops-lab"
  management_endpoint = oci_kms_vault.aiops.management_endpoint
  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

# ── Secrets (se crean vacíos, se pueblan manualmente por consola o CLI) ──

resource "oci_vault_secret" "n8n_encryption_key" {
  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.aiops.id
  key_id         = oci_kms_key.aiops.id
  secret_name    = "n8n-encryption-key"
  secret_content {
    content_type = "BASE64"
    content      = "CHANGE_ME" # Se puebla manualmente post-apply
  }
}

resource "oci_vault_secret" "grafana_admin_password" {
  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.aiops.id
  key_id         = oci_kms_key.aiops.id
  secret_name    = "grafana-admin-password"
  secret_content {
    content_type = "BASE64"
    content      = "CHANGE_ME"
  }
}

resource "oci_vault_secret" "discord_webhook" {
  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.aiops.id
  key_id         = oci_kms_key.aiops.id
  secret_name    = "discord-webhook-url"
  secret_content {
    content_type = "BASE64"
    content      = "CHANGE_ME"
  }
}
```

> **Nota sobre OCI Vault vs Vault self-hosted:** El plan original dice "HashiCorp Vault se reemplaza por OCI Vault". En la práctica, esto implica:
> - Los manifests que usan `vault.hashicorp.com/agent-inject` dejan de funcionar
> - Hay que implementar OCI Instance Principal para que los pods autentiquen con OCI Vault
> - **Esto es complejo y no es trivial.** Ver sección 3.7 para la estrategia.

#### 1.6 Data sources adicionales

Agregar a `tofu/oracle/` o a un `data.tf`:

```hcl
# ── Availability Domains ──
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}
```

#### 1.7 Nuevas variables necesarias

Agregar a `tofu/oracle/variables.tf`:

```hcl
variable "ssh_public_key" {
  description = "Clave SSH pública para acceso a las VMs"
  type        = string
  # Ejemplo: "ssh-ed25519 AAAAC3..."
}

# Eliminar variable vcn_id (la VCN se crea, no se referencia)
# La variable compartment_id se mantiene
# NOTA: admin_cidr debe ser tu IP real con /32
```

#### 1.8 Template cloud-init

Crear `tofu/oracle/templates/cloud-init.yml.tmpl`:

```yaml
#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.aiops.local
manage_etc_hosts: true
users:
  - name: rocky
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: wheel
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_public_key}
package_update: true
package_upgrade: false
packages:
  - git
  - curl
  - wget
  - vim
  - python3
  - python3-pip
  - selinux-policy-targeted
  - firewalld
runcmd:
  - systemctl enable firewalld --now
  - setenforce 1
  - sed -i 's/SELINUX=disabled/SELINUX=enforcing/' /etc/selinux/config
```

---

### Paso 2 — Crear archivos de variables y .gitignore

#### 2.1 `tofu/oracle/terraform.tfvars.example`

```hcl
# ── Oracle Cloud — Variables de OpenTofu ──
# Copiar este archivo a terraform.tfvars y completar con tus valores.
# NO commitear terraform.tfvars — contiene datos sensibles.

region            = "us-ashburn-1"
tenancy_ocid      = "ocid1.tenancy.oc1..xxxxxxxxxxxxxxxxxxxx"
user_ocid         = "ocid1.user.oc1..xxxxxxxxxxxxxxxxxxxx"
fingerprint       = "xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx"
private_key_path  = "~/.oci/oci_api_key.pem"
compartment_id    = "ocid1.compartment.oc1..xxxxxxxxxxxxxxxxxxxx"
ssh_public_key    = "ssh-ed25519 AAAAC3..."
admin_cidr        = "203.0.113.45/32"  # Tu IP pública real con /32
```

#### 2.2 Actualizar `.gitignore`

```gitignore
# Ya existente — agregar:
*.tfvars
!*.tfvars.example
tofu/oracle/templates/cloud-init.yml  # Si se genera con valores reales
```

---

### Paso 3 — Crear inventario de Ansible para Oracle

Crear `ansible/inventory/oracle.yml`:

```yaml
---
# Inventario Ansible — Oracle Cloud
# Las IPs se completan después de tofu apply (outputs)

all:
  children:
    bastion:
      hosts:
        vm-bastion:
          ansible_host: "{{ lookup('env', 'BASTION_PUBLIC_IP') }}"
          ansible_user: rocky
          ansible_ssh_private_key_file: "~/.ssh/id_ed25519"
          ansible_python_interpreter: /usr/bin/python3

    k3s:
      hosts:
        vm-k3s:
          ansible_host: "{{ lookup('env', 'K3S_PRIVATE_IP') }}"
          ansible_user: rocky
          ansible_ssh_private_key_file: "~/.ssh/id_ed25519"
          ansible_python_interpreter: /usr/bin/python3
          ansible_ssh_common_args: '-o ProxyCommand="ssh -W %h:%p rocky@{{ lookup(''env'', ''BASTION_PUBLIC_IP'') }}"'
```

---

### Paso 4 — Crear playbooks específicos para OCI

#### 4.1 `ansible/playbooks/bastion.yml`

```yaml
---
# Playbook: Hardening del bastion
# Ejecutar: ansible-playbook -i ansible/inventory/oracle.yml ansible/playbooks/bastion.yml

- name: Hardening base del bastion
  hosts: bastion
  become: true
  roles:
    - system-base
    - firewalld
    - selinux
    - ssh-hardening
    - fail2ban
    - dnf-automatic

- name: Instalar herramientas de administración
  hosts: bastion
  become: true
  tasks:
    - name: Instalar kubectl
      get_url:
        url: https://dl.k8s.io/release/v1.29.0/bin/linux/arm64/kubectl
        dest: /usr/local/bin/kubectl
        mode: '0755'

    - name: Instalar tofu (OpenTofu)
      get_url:
        url: https://github.com/opentofu/opentofu/releases/download/v1.7.0/tofu_1.7.0_linux_arm64.zip
        dest: /tmp/tofu.zip
    - name: Extraer tofu
      unarchive:
        src: /tmp/tofu.zip
        dest: /usr/local/bin
        remote_src: true
        mode: '0755'

    - name: Instalar argocd CLI
      get_url:
        url: https://github.com/argoproj/argo-cd/releases/download/v2.12.0/argocd-linux-arm64
        dest: /usr/local/bin/argocd
        mode: '0755'

    - name: Clonar repo del proyecto
      git:
        repo: https://github.com/agusm2002/rocky-linux-aiops-lab.git
        dest: /home/rocky/rocky-linux-aiops-lab
        version: main
      become_user: rocky
```

#### 4.2 `ansible/playbooks/k3s.yml`

```yaml
---
# Playbook: Instalación de k3s en vm-k3s
# Ejecutar DESDE el bastion:
#   ansible-playbook -i ansible/inventory/oracle.yml ansible/playbooks/k3s.yml

- name: Hardening base de vm-k3s
  hosts: k3s
  become: true
  roles:
    - system-base
    - firewalld
    - selinux
    - ssh-hardening
    - fail2ban
    - dnf-automatic

- name: Instalar k3s
  hosts: k3s
  become: true
  tasks:
    - name: Instalar k3s (single-node)
      shell: |
        curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.29.0+k3s1 sh -s - \
          --write-kubeconfig-mode 644 \
          --disable traefik \
          --disable servicelb \
          --disable local-storage
      args:
        creates: /usr/local/bin/k3s

    - name: Esperar a que k3s esté listo
      command: k3s kubectl get nodes
      changed_when: false
      retries: 10
      delay: 10
      register: result
      until: result.rc == 0

    - name: Copiar kubeconfig al usuario rocky
      copy:
        src: /etc/rancher/k3s/k3s.yaml
        dest: /home/rocky/.kube/config
        owner: rocky
        group: rocky
        mode: '0600'
        remote_src: true

    - name: Instalar metrics-server
      command: k3s kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

### Paso 5 — Manifests específicos para OCI

#### 5.1 Loki con backend OCI Object Storage

Crear `k3s/manifests/loki/configmap-oci.yml`:

```yaml
---
# ConfigMap de Loki — Oracle Cloud (OCI Object Storage como backend)
# Usa S3-compatible API de OCI Object Storage.
# Auth via OCI Instance Principal — sin credenciales hardcodeadas.

apiVersion: v1
kind: ConfigMap
metadata:
  name: loki-config-oci
  namespace: aiops
data:
  loki.yml: |
    auth_enabled: false
    server:
      http_listen_port: 3100
      grpc_listen_port: 9096
    common:
      ring:
        instance_addr: 127.0.0.1
        kvstore:
          store: inmemory
      replication_factor: 1
    schema_config:
      configs:
        - from: 2024-04-01
          store: boltdb-shipper
          object_store: aws
          schema: v11
          index:
            prefix: index_
            period: 24h
    storage_config:
      boltdb_shipper:
        active_index_directory: /loki/boltdb-shipper-active
        cache_location: /loki/boltdb-shipper-cache
        shared_store: s3
      aws:
        # OCI Object Storage es compatible con S3 API
        s3: https://objectstorage.${REGION}.oraclecloud.com
        bucketnames: loki-aiops-lab
        region: ${REGION}
        # Sin access_key/secret_key: usa OCI Instance Principal
        # Requiere configurar Instance Principal en la VM
        s3forcepathstyle: true
    limits_config:
      reject_old_samples: true
      max_query_length: 721h
      allow_structured_metadata: false
      retention_period: 744h
    compactor:
      working_directory: /loki/compactor
      compaction_interval: 10m
      retention_enabled: true
      shared_store: s3
    ingester:
      wal:
        dir: /loki/storage/wal
    analytics:
      reporting_enabled: false
```

> **Nota sobre Instance Principal:** Para que Loki pueda escribir en OCI Object Storage sin credenciales hardcodeadas, la VM necesita una Dynamic Group policy que le otorgue permisos al bucket. Esto se configura en la consola OCI:
> ```
> # Dynamic Group
> Name: dg-k3s
> Rule: instance.compartment.id = '<compartment_ocid>'
>
> # Policy
> Allow dynamic-group dg-k3s to manage objects in compartment aiops-lab
> Allow dynamic-group dg-k3s to read secret-bundles in compartment aiops-lab
> ```

#### 5.2 Grafana en modo read-only público

Modificar `k3s/manifests/grafana/deployment.yml` (solo las líneas relevantes):

```yaml
env:
  - name: GF_SECURITY_ADMIN_USER
    value: admin
  - name: GF_SECURITY_ADMIN_PASSWORD
    value: admin  # Se cambia post-deploy via OCI Vault o se deja así para lab
  - name: GF_AUTH_ANONYMOUS_ENABLED
    value: "true"  # ← Cambiar de "false" a "true"
  - name: GF_AUTH_ANONYMOUS_ORG_ROLE
    value: "Viewer"  # ← Solo lectura para visitantes
  - name: GF_AUTH_BASIC_ENABLED
    value: "true"  # Admin sigue con login
  - name: GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH
    value: /var/lib/grafana/dashboards/cluster-overview.json
```

---

### Paso 6 — Flujo completo de ejecución

```bash
# ──────────────────────────────────────
# 1. PRERREQUISITOS (consola OCI, una vez)
# ──────────────────────────────────────
# - Crear cuenta, budget alert, compartment, API key
# - Anotar OCIDs y fingerprint

# ──────────────────────────────────────
# 2. PROVISIONAR INFRAESTRUCTURA
# ──────────────────────────────────────
cd tofu/oracle

# Copiar y completar variables
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars con tus valores reales
# ⚠️  admin_cidr debe ser tu IP real con /32 (buscar en: curl ifconfig.me)

# Inicializar providers
tofu init

# Ver qué se va a crear
tofu plan

# Crear todo
tofu apply

# ──────────────────────────────────────
# 3. EXTRAER IPs DE LOS OUTPUTS
# ──────────────────────────────────────
tofu output -json > /tmp/oci-outputs.json

export BASTION_PUBLIC_IP=$(jq -r '.bastion_public_ip.value' /tmp/oci-outputs.json)
export K3S_PRIVATE_IP=$(jq -r '.k3s_private_ip.value' /tmp/oci-outputs.json)
export K3S_PUBLIC_IP=$(jq -r '.k3s_public_ip.value' /tmp/oci-outputs.json)

echo "Bastion: $BASTION_PUBLIC_IP"
echo "k3s (privada): $K3S_PRIVATE_IP"
echo "k3s (pública): $K3S_PUBLIC_IP"

# ──────────────────────────────────────
# 4. ESPERAR QUE LAS VMs ESTÉN LISTAS
# ──────────────────────────────────────
# Esperar ~2 minutos a que cloud-init termine
sleep 120

# Verificar conectividad SSH al bastion
ssh rocky@$BASTION_PUBLIC_IP "echo 'SSH al bastion OK'"

# ──────────────────────────────────────
# 5. HARDENING DEL BASTION
# ──────────────────────────────────────
cd /home/agustinm/rocky-linux-aiops-lab
ansible-playbook -i ansible/inventory/oracle.yml ansible/playbooks/bastion.yml

# ──────────────────────────────────────
# 6. HARDENING + INSTALAR k3s EN VM-K3S
# ──────────────────────────────────────
ansible-playbook -i ansible/inventory/oracle.yml ansible/playbooks/k3s.yml

# ──────────────────────────────────────
# 7. COPIAR MANIFESTS AL BASTION
# ──────────────────────────────────────
# Copiar k3s manifests al bastion para aplicarlos desde ahí
scp -r k3s/manifests rocky@$BASTION_PUBLIC_IP:/home/rocky/rocky-linux-aiops-lab/k3s/
scp argocd/argocd-app.yml rocky@$BASTION_PUBLIC_IP:/home/rocky/rocky-linux-aiops-lab/argocd/

# ──────────────────────────────────────
# 8. INSTALAR ARGOCD EN k3s
# ──────────────────────────────────────
# Desde el bastion
ssh rocky@$BASTION_PUBLIC_IP << 'EOF'
# Copiar kubeconfig de k3s al bastion
scp rocky@$K3S_PRIVATE_IP:~/.kube/config ~/.kube/config

# Ajustar server en kubeconfig (apuntar a IP privada de k3s)
sed -i "s/127.0.0.1/$K3S_PRIVATE_IP/" ~/.kube/config

# Instalar ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.12.0/manifests/install.yaml

# Esperar a que ArgoCD esté listo
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Aplicar la Application de ArgoCD
kubectl apply -f ~/rocky-linux-aiops-lab/argocd/argocd-app.yml

# Verificar que ArgoCD sincronizó
kubectl get applications -n argocd
EOF

# ──────────────────────────────────────
# 9. CONFIGURAR OCI VAULT (MANUAL)
# ──────────────────────────────────────
# - Entrar a la consola OCI → Vault
# - Poblar los secrets: n8n_encryption_key, grafana_admin_password, discord_webhook
# - Configurar Dynamic Group + Policy para Instance Principal
# - Ver sección 3.7 para estrategia de migración de Vault

# ──────────────────────────────────────
# 10. ACTIVAR CLOUD GUARD
# ──────────────────────────────────────
# Consola OCI → Cloud Guard → Enable

# ──────────────────────────────────────
# 11. VERIFICAR DEMO PÚBLICA
# ──────────────────────────────────────
echo "Grafana (público, read-only): http://$K3S_PUBLIC_IP:3000"

# ──────────────────────────────────────
# 12. COMMIT DE FASE 9
# ──────────────────────────────────────
git add -A
git commit -m "feat: Fase 9 — Migración completa a Oracle Cloud Free Tier"
git push origin main
```

---

### Paso 7 — Estrategia de migración de Vault (self-hosted → OCI Vault)

Este es el punto **más complejo** de la migración. Hay tres enfoques posibles:

#### Opción A: Mantener Vault self-hosted (recomendado para el lab)

**Ventaja:** Cero cambios en los manifests. ArgoCD sincroniza exactamente lo mismo que en local. El contraste "lab vs cloud" se documenta diciendo: "En el lab local usé Vault self-hosted; en producción usaría OCI Vault o AWS Secrets Manager, pero mantuve Vault para demostrar que entiendo ambos modelos."

**Desventaja:** No se usa OCI Vault realmente.

**Impacto en el portfolio:** Mínimo — el argumento de entrevista sigue siendo válido: "Sé deployar Vault self-hosted y sé que en cloud se usa el servicio gestionado."

#### Opción B: OCI Vault con External Secrets Operator (ESO)

Usar [External Secrets Operator](https://external-secrets.io) para sincronizar secrets de OCI Vault → Kubernetes Secrets. Los pods leen Kubernetes Secrets normales, sin cambios.

**Complejidad:** Alta. Requiere desplegar ESO, configurar `SecretStore` con OCI, crear `ExternalSecret` por cada secret.

**Ventaja:** OCI Vault se usa de verdad.

#### Opción C: OCI Vault con CSI Driver

Usar el OCI Vault CSI Driver para montar secrets como volúmenes.

**Complejidad:** Muy alta. Requiere instalar el driver en el nodo.

#### Recomendación

**Opción A para la Fase 9.** El valor del proyecto no está en "usé OCI Vault", está en:
1. Arquitectura distribuida (bastion + k3s + managed services)
2. Infraestructura como código con OpenTofu
3. GitOps con ArgoCD sincronizando desde GitHub
4. NSG + firewalld + SELinux (seguridad en capas)
5. Loop end-to-end de incident response

La decisión se documenta en el README y en `docs/architecture.md`:

> "En el lab local, HashiCorp Vault corre self-hosted en k3s con Vault Agent Injector. En Oracle Cloud, el enfoque de producción sería usar OCI Vault (el servicio gestionado equivalente a AWS Secrets Manager). Para este lab mantuve Vault self-hosted en ambas arquitecturas para demostrar comprensión de ambos modelos: sé operar un Vault cluster manualmente y sé que en producción delego la disponibilidad al proveedor cloud. La migración a OCI Vault con External Secrets Operator está documentada como next step."

---

### Paso 8 — Configuración opcional: Cloudflare + Let's Encrypt

Esto convierte la demo en "producción-like" con HTTPS real:

```bash
# En vm-k3s
sudo dnf install -y certbot

# Obtener certificado (requiere que el dominio apunte a la IP pública de vm-k3s)
sudo certbot certonly --standalone -d grafana.aiops.tudominio.com

# Configurar Ingress de Grafana con TLS
# Ver k3s/manifests/grafana/ingress.yml
```

Si no tenés dominio, Grafana se expone en `http://<IP>:3000`. Es suficiente para la demo. Se documenta la limitación.

---

## 4. Checklist de verificación pre-migración

Antes de ejecutar `tofu apply`, verificar:

- [ ] Cuenta Oracle Cloud creada y activada
- [ ] Budget alert configurado en $0 con email
- [ ] Compartment `aiops-lab` creado y OCID anotado
- [ ] API key generada y fingerprint anotado
- [ ] `tenancy_ocid`, `user_ocid`, `compartment_id` anotados
- [ ] `terraform.tfvars` completado con valores reales
- [ ] `admin_cidr` seteado a tu IP real con /32 (verificar con `curl ifconfig.me`)
- [ ] Clave SSH pública lista (`~/.ssh/id_ed25519.pub`)
- [ ] `.gitignore` actualizado para no commitear `.tfvars`
- [ ] Todos los archivos nuevos de OpenTofu creados (`provider.tf`, `network.tf`, `compute.tf`, `object_storage.tf`, `vault.tf`)
- [ ] Template `cloud-init.yml.tmpl` creado
- [ ] Inventario `oracle.yml` creado
- [ ] Playbooks `bastion.yml` y `k3s.yml` creados
- [ ] ConfigMap de Loki para OCI creado
- [ ] Grafana configurado para read-only público
- [ ] `tofu init` ejecutado sin errores
- [ ] `tofu plan` muestra los recursos esperados sin errores

---

## 5. Checklist de verificación post-migración

Después de `tofu apply` y Ansible:

- [ ] SSH al bastion funciona: `ssh rocky@<BASTION_IP>`
- [ ] SSH del bastion a k3s funciona: `ssh rocky@<K3S_PRIVATE_IP>`
- [ ] `kubectl get nodes` muestra vm-k3s como Ready
- [ ] `kubectl get pods -n aiops` muestra todos los pods Running
- [ ] `kubectl get pods -n argocd` muestra argocd-server Running
- [ ] ArgoCD Application `aiops-lab` está Synced y Healthy
- [ ] Grafana accesible públicamente en `http://<K3S_PUBLIC_IP>:3000`
- [ ] Grafana muestra dashboards (anonymous Viewer)
- [ ] Login como admin posible con credenciales
- [ ] Loki recibe logs (verificar en Grafana → Explore → Loki)
- [ ] n8n accesible (via port-forward o ingress)
- [ ] Alertmanager configurado y enviando a n8n
- [ ] Budget alert de OCI sin disparos
- [ ] Cloud Guard activado
- [ ] NSGs bloquean tráfico no autorizado (verificar con nmap desde afuera)

---

## 6. Riesgos y mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| **Free Tier agotado en la región** | Media | Alto | Elegir región con disponibilidad (us-ashburn-1, sa-saopaulo-1). Verificar antes de crear. |
| **Ampere A1 sin capacidad** | Alta | Alto | Intentar en otra availability domain o región. Ser paciente (a veces liberan capacidad). Alternativa: usar shapes AMD (micro, pero solo 1 vCPU). |
| **Cargo accidental** | Baja | Crítico | Budget alert en $0 ANTES de crear recursos. Revisar consola diariamente la primera semana. |
| **Rocky Linux ARM64 no disponible como imagen** | Baja | Medio | OCI tiene imágenes oficiales de Rocky. Si no aparecen, usar Rocky Linux x86_64 con shape AMD. |
| **OCI Vault + Instance Principal complejo** | Alta | Medio | Usar Opción A (mantener Vault self-hosted) y documentar la decisión. |
| **Loki no autentica con OCI Object Storage** | Media | Medio | Documentar el approach con Instance Principal. Si falla, hacer rollback a filesystem por ahora. |
| **`tofu destroy` accidental** | Baja | Crítico | Agregar `prevent_destroy = true` en recursos críticos. Hacer backup de datos ANTES de cualquier destroy. |

---

## 7. Tiempo estimado

| Paso | Tiempo |
|---|---|
| Prerrequisitos OCI (cuenta, API key, compartment) | 30 min |
| Completar OpenTofu (VCN + compute + storage + vault) | 2–3 horas |
| Crear inventario y playbooks de Ansible | 1 hora |
| Crear manifests OCI (Loki, Grafana) | 30 min |
| `tofu plan` + debugging de errores | 1–2 horas |
| `tofu apply` (crear VMs tarda ~3–5 min) | 10 min |
| Esperar cloud-init | 2 min |
| Ejecutar Ansible (bastion hardening + k3s install) | 15 min |
| Instalar ArgoCD + aplicar Application | 10 min |
| Verificar sincronización de ArgoCD | 5 min |
| Debugging post-migración | 1–2 horas |
| Documentar y commit | 30 min |
| **Total estimado** | **6–10 horas (1–2 días)** |

---

## 8. Archivos a crear/modificar — resumen

### Archivos nuevos

| Archivo | Propósito |
|---|---|
| `tofu/oracle/provider.tf` | Provider OCI separado |
| `tofu/oracle/network.tf` | VCN + subnet + IGW + route table |
| `tofu/oracle/compute.tf` | vm-bastion + vm-k3s |
| `tofu/oracle/object_storage.tf` | Bucket de Loki |
| `tofu/oracle/vault.tf` | OCI Vault + secrets |
| `tofu/oracle/data.tf` | Data sources (ADs, namespace) |
| `tofu/oracle/templates/cloud-init.yml.tmpl` | Configuración inicial de VMs |
| `tofu/oracle/terraform.tfvars.example` | Template de variables |
| `tofu/oracle/outputs.tf` | **Modificar** — agregar IPs públicas/privadas |
| `ansible/inventory/oracle.yml` | Inventario para OCI |
| `ansible/playbooks/bastion.yml` | Hardening + tools del bastion |
| `ansible/playbooks/k3s.yml` | Hardening + k3s en vm-k3s |
| `k3s/manifests/loki/configmap-oci.yml` | Loki con backend OCI Object Storage |
| `docs/fase-9-migracion-oracle-cloud.md` | Este documento |

### Archivos a modificar

| Archivo | Cambio |
|---|---|
| `tofu/oracle/main.tf` | Eliminar provider block (movido a `provider.tf`), corregir referencia a `oci_core_instance` |
| `tofu/oracle/variables.tf` | Agregar `ssh_public_key`, eliminar `vcn_id` (se crea, no se referencia) |
| `tofu/oracle/outputs.tf` | Agregar `bastion_public_ip`, `k3s_public_ip`, `k3s_private_ip` |
| `k3s/manifests/grafana/deployment.yml` | `GF_AUTH_ANONYMOUS_ENABLED: "true"`, `GF_AUTH_ANONYMOUS_ORG_ROLE: "Viewer"` |
| `.gitignore` | Agregar `*.tfvars`, `!*.tfvars.example` |
| `README.md` | Agregar sección "Fase 9 — Migración a Oracle Cloud" |
| `docs/architecture.md` | Crear con diagrama de arquitectura Oracle Cloud |

---

## 9. ¿Qué NO hacer en esta fase?

- ❌ **NO** crear recursos desde la consola de OCI. Todo por OpenTofu.
- ❌ **NO** exponer puertos que no sean 443 y 22.
- ❌ **NO** commitear `terraform.tfvars` ni archivos con OCIDs reales.
- ❌ **NO** hacer `tofu destroy` sin antes verificar dos veces que es intencional.
- ❌ **NO** usar `admin_cidr = "0.0.0.0/0"` para SSH. Siempre tu IP real con /32.
- ❌ **NO** crear la VCN a mano. Que OpenTofu la cree.
- ❌ **NO** olvidar el budget alert. Es la única línea de defensa contra cargos.
- ❌ **NO** dejar la VM corriendo si no la estás usando. Aunque es $0, es buena práctica parar recursos que no se usan (Free Tier permite stop/start sin costo).

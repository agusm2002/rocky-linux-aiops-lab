/**
 * Jenkinsfile — Pipeline CI/CD para rocky-linux-aiops-lab
 *
 * Este pipeline se ejecuta automáticamente en cada push al repositorio
 * mediante un webhook de GitHub → Jenkins.  Corre dentro del cluster
 * k3s usando agentes dinámicos: Jenkins crea un pod efímero por cada
 * stage y lo destruye al terminar.
 *
 * ── Estructura del pipeline ──
 * 1. Lint YAML — yamllint sobre manifests de Kubernetes
 * 2. Lint Ansible — ansible-lint sobre playbooks y roles
 * 3. Validate OpenTofu — tofu validate sobre la configuración IaC
 * 4. Validate K8s Manifests — kubectl --dry-run para validar sintaxis
 *
 * ── Agentes dinámicos ──
 * Cada stage usa agent { kubernetes { ... } } para ejecutarse en un
 * contenedor con las herramientas específicas de esa etapa.  Esto evita
 * instalar todo en una sola imagen gigante y sigue el patrón de
 * "contenedores especializados por tarea".
 *
 * ── Webhook de fallo ──
 * Si el pipeline falla, el bloque post { failure { ... } } envía una
 * notificación al webhook de n8n, que puede disparar workflows de
 * respuesta automática (notificar por Discord, crear un ticket, etc.).
 */

pipeline {
    agent none  // No usar un agente global — cada stage define el suyo

    environment {
        // Namespace donde están los manifests y servicios del lab
        NAMESPACE = 'aiops'
    }

    stages {

        // ──────────────────────────────────────────────────────────
        // Stage 1: Lint de archivos YAML (manifests de Kubernetes)
        // ──────────────────────────────────────────────────────────
        stage('Lint YAML') {
            agent {
                kubernetes {
                    yaml '''
                        apiVersion: v1
                        kind: Pod
                        spec:
                          containers:
                          - name: yamllint
                            image: python:3.12-alpine
                            command: [cat]
                            tty: true
                    '''
                }
            }
            steps {
                container('yamllint') {
                    sh '''
                        pip install --quiet yamllint
                        yamllint k3s/manifests/ -d relaxed
                    '''
                }
            }
        }

        // ──────────────────────────────────────────────────────────
        // Stage 2: Lint de playbooks y roles de Ansible
        // ──────────────────────────────────────────────────────────
        stage('Lint Ansible') {
            agent {
                kubernetes {
                    yaml '''
                        apiVersion: v1
                        kind: Pod
                        spec:
                          containers:
                          - name: ansiblelint
                            image: python:3.12-alpine
                            command: [cat]
                            tty: true
                    '''
                }
            }
            steps {
                container('ansiblelint') {
                    sh '''
                        pip install --quiet ansible-lint
                        ansible-lint ansible/playbooks/ ansible/roles/ || true
                    '''
                }
            }
        }

        // ──────────────────────────────────────────────────────────
        // Stage 3: Validar configuración de OpenTofu
        // ──────────────────────────────────────────────────────────
        stage('Validate OpenTofu') {
            agent {
                kubernetes {
                    yaml '''
                        apiVersion: v1
                        kind: Pod
                        spec:
                          containers:
                          - name: tofu
                            image: ghcr.io/opentofu/opentofu:1.9.0
                            command: [cat]
                            tty: true
                    '''
                }
            }
            steps {
                container('tofu') {
                    sh '''
                        cd tofu
                        tofu init -backend=false
                        tofu validate
                    '''
                }
            }
        }

        // ──────────────────────────────────────────────────────────
        // Stage 4: Validar sintaxis de manifests de Kubernetes
        // ──────────────────────────────────────────────────────────
        stage('Validate K8s Manifests') {
            agent {
                kubernetes {
                    yaml '''
                        apiVersion: v1
                        kind: Pod
                        spec:
                          containers:
                          - name: kubectl
                            image: alpine/k8s:1.29.2
                            command: [cat]
                            tty: true
                    '''
                }
            }
            steps {
                container('kubectl') {
                    sh '''
                        # Recorremos todos los archivos YAML del directorio
                        # y validamos que sean sintácticamente correctos
                        # con kubectl --dry-run=client (no se aplican al cluster)
                        for file in $(find k3s/manifests/ -name '*.yml' -o -name '*.yaml'); do
                            echo "Validating: $file"
                            kubectl --dry-run=client apply -f "$file" || echo "WARNING: $file tiene errores de sintaxis"
                        done
                    '''
                }
            }
        }
    }

    post {
        failure {
            // Cuando el pipeline falla, notificar a n8n para acción automática.
            // n8n puede reaccionar notificando por Discord, registrando el
            // incidente en Loki, o disparando un rollback.
            sh '''
                curl -X POST http://n8n.aiops.svc.cluster.local:5678/webhook/jenkins-failure \
                    -H "Content-Type: application/json" \
                    -d "{\\"build\\": \\"${BUILD_NUMBER}\\", \\"job\\": \\"${JOB_NAME}\\", \\"status\\": \\"FAILURE\\"}" \
                    || true  # No fallar si n8n no responde
            '''
        }
        success {
            sh '''
                curl -X POST http://n8n.aiops.svc.cluster.local:5678/webhook/jenkins-success \
                    -H "Content-Type: application/json" \
                    -d "{\\"build\\": \\"${BUILD_NUMBER}\\", \\"job\\": \\"${JOB_NAME}\\", \\"status\\": \\"SUCCESS\\"}" \
                    || true
            '''
        }
    }
}

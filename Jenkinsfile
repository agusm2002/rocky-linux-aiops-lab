/**
 * Jenkinsfile — Pipeline CI/CD para rocky-linux-aiops-lab
 *
 * Este pipeline se ejecuta en el master (agent any) porque los stages
 * que usan agentes Kubernetes se ejecutan en pods efimeros dentro
 * del bloque node/podTemplate.  El post usa node para las
 * notificaciones a n8n.
 *
 * ── Estructura del pipeline ──
 * 1. Lint YAML — yamllint en pod efimero python:3.12-alpine
 * 2. Lint Ansible — ansible-lint en pod efimero
 * 3. Validate OpenTofu — tofu validate en pod efimero
 * 4. Validate K8s Manifests — kubectl --dry-run en pod efimero
 *
 * ── Webhook de fallo ──
 * Si el pipeline falla, notifica a n8n para respuesta automatica.
 */

pipeline {
    agent any  // Requerido para que los bloques post tengan contexto de nodo

    environment {
        NAMESPACE = 'aiops'
    }

    stages {

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
                        yamllint k3s/manifests/ -d relaxed || true
                    '''
                }
            }
        }

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
                        for file in $(find k3s/manifests/ -name "*.yml" -o -name "*.yaml"); do
                            echo "Validating: $file"
                            kubectl --dry-run=client apply -f "$file" 2>&1 | grep -v WARN | grep -v memcache | grep -v metrics || true
                        done
                    '''
                }
            }
        }
    }

    post {
        failure {
            node('built-in') {
                sh '''
                    curl -X POST http://n8n.aiops.svc.cluster.local:5678/webhook/jenkins-failure \
                        -H "Content-Type: application/json" \
                        -d "{\\"build\\": \\"${BUILD_NUMBER}\\", \\"job\\": \\"${JOB_NAME}\\"}" \
                        || true
                '''
            }
        }
        success {
            node('built-in') {
                sh '''
                    curl -X POST http://n8n.aiops.svc.cluster.local:5678/webhook/jenkins-success \
                        -H "Content-Type: application/json" \
                        -d "{\\"build\\": \\"${BUILD_NUMBER}\\", \\"job\\": \\"${JOB_NAME}\\"}" \
                        || true
                '''
            }
        }
    }
}

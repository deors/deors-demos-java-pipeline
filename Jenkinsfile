#!groovy
pipeline {
    agent {
        kubernetes {
            defaultContainer 'jdk'
            yaml '''
apiVersion: v1
kind: Pod
spec:
  securityContext:
    runAsUser: 1001
  containers:
    - name: jdk
      image: docker.io/eclipse-temurin:18.0.2.1_1-jdk
      command:
        - sleep
      args:
        - infinity
    - name: podman
      image: quay.io/containers/podman:v4.2.0
      command:
        - sleep
      args:
        - infinity
      securityContext:
        runAsUser: 0
        privileged: true
    - name: aks
      image: acrdvpsplatformdev.azurecr.io/devops-platform-image:v0.0.5
      command:
        - sleep
      args:
        - infinity
  imagePullSecrets:
    - name: master-acr-credentials
'''
        }
    }

    environment {
        APP_NAME = 'deors-demos-java-pipeline'
        APP_VERSION = '1.0-SNAPSHOT'
        APP_CONTEXT_ROOT = '/'
        APP_LISTENING_PORT = '8080'
        APP_JACOCO_PORT = '6300'
        CONTAINER_IMAGE_PREFIX = 'deors'
        TEST_CONTAINER_NAME = "ci-${APP_NAME}-${BUILD_NUMBER}"
        SELENIUM_HUB_HOST = 'selenium-hub'
        SELENIUM_HUB_PORT = '4444'
    }

    stages {
        stage('Prepare Environment') {
            steps {
                echo '-=- prepare environment -=-'
                sh './mvnw --version'
                container('podman') {
                    sh 'podman --version'
                }
                container('aks') {
                    withCredentials([
                            usernamePassword(
                                credentialsId: 'sp-terraform-credentials',
                                usernameVariable: 'AAD_SERVICE_PRINCIPAL_CLIENT_ID',
                                passwordVariable: 'AAD_SERVICE_PRINCIPAL_CLIENT_SECRET'),
                            string(credentialsId: 'aks-tenant', variable: 'AKS_TENANT'),
                            string(credentialsId: 'aks-resource-group', variable: 'AKS_RESOURCE_GROUP'),
                            string(credentialsId: 'aks-name', variable: 'AKS_NAME')]) {
                        sh "az login --service-principal --username ${AAD_SERVICE_PRINCIPAL_CLIENT_ID} --password ${AAD_SERVICE_PRINCIPAL_CLIENT_SECRET} --tenant ${AKS_TENANT}"
                        sh "az aks get-credentials --resource-group ${AKS_RESOURCE_GROUP} --name ${AKS_NAME}"
                        sh 'kubelogin convert-kubeconfig -l spn'
                        sh 'kubectl version'
                    }
                }
                script {
                    qualityGates = readYaml file: 'quality-gates.yaml'
                }
            }
        }

        stage('Compile') {
            steps {
                echo '-=- compiling project -=-'
                sh './mvnw compile'
            }
        }

        stage('Unit tests') {
            steps {
                echo '-=- execute unit tests -=-'
                sh './mvnw test org.jacoco:jacoco-maven-plugin:report'
                junit 'target/surefire-reports/*.xml'
                jacoco execPattern: 'target/jacoco.exec'
            }
        }

        stage('Mutation tests') {
            steps {
                echo '-=- execute mutation tests -=-'
                sh './mvnw org.pitest:pitest-maven:mutationCoverage'
            }
        }

        stage('Dependency vulnerability scan') {
            steps {
                echo '-=- run dependency vulnerability scan -=-'
                sh './mvnw dependency-check:check'
                dependencyCheckPublisher(
                    failedTotalCritical: qualityGates.security.dependencies.critical.failed,
                    unstableTotalCritical: qualityGates.security.dependencies.critical.unstable,
                    failedTotalHigh: qualityGates.security.dependencies.high.failed,
                    unstableTotalHigh: qualityGates.security.dependencies.high.unstable,
                    failedTotalMedium: qualityGates.security.dependencies.medium.failed,
                    unstableTotalMedium: qualityGates.security.dependencies.medium.unstable)
                script {
                    if (currentBuild.result == 'FAILURE') {
                        error('Dependency vulnerabilities exceed the configured threshold')
                    }
                }
            }
        }

        stage('Package') {
            steps {
                echo '-=- packaging project -=-'
                sh './mvnw package -DskipTests'
                archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
            }
        }

        stage('Build container image') {
            steps {
                echo '-=- build container image -=-'
                container('podman') {
                    sh "podman build -t ${CONTAINER_IMAGE_PREFIX}/${APP_NAME}:${APP_VERSION} ."
                }
            }
        }

        stage('Run container image') {
            steps {
                echo '-=- run container image -=-'
                container('aks') {
                    withCredentials([
                            usernamePassword(
                                credentialsId: 'sp-terraform-credentials',
                                usernameVariable: 'AAD_SERVICE_PRINCIPAL_CLIENT_ID',
                                passwordVariable: 'AAD_SERVICE_PRINCIPAL_CLIENT_SECRET')]) {
                        sh "kubectl run ${TEST_CONTAINER_NAME} --image=${CONTAINER_IMAGE_PREFIX}/${APP_NAME}:${APP_VERSION} --env=JAVA_OPTS=-javaagent:/jacocoagent.jar=output=tcpserver,address=*,port=${APP_JACOCO_PORT} --port=${APP_LISTENING_PORT}"
                        sh "kubectl expose pod ${TEST_CONTAINER_NAME} --port=${APP_LISTENING_PORT}"
                        sh "kubectl expose pod ${TEST_CONTAINER_NAME} --port=${APP_JACOCO_PORT} --name=${TEST_CONTAINER_NAME}-jacoco"
                    }
                }
            }
        }

        stage('Integration tests') {
            steps {
                echo '-=- execute integration tests -=-'
                sh "curl --retry 10 --retry-connrefused --connect-timeout 5 --max-time 5 http://${TEST_CONTAINER_NAME}:${APP_LISTENING_PORT}" + "${APP_CONTEXT_ROOT}/actuator/health".replace('//', '/')
                sh "./mvnw failsafe:integration-test failsafe:verify -DargLine=-Dtest.selenium.hub.url=http://${SELENIUM_HUB_HOST}:${SELENIUM_HUB_PORT}/wd/hub -Dtest.target.server.url=http://${TEST_CONTAINER_NAME}:${APP_LISTENING_PORT}" + "${APP_CONTEXT_ROOT}/".replace('//', '/')
                sh "java -jar target/dependency/jacococli.jar dump --address ${TEST_CONTAINER_NAME}-jacoco --port ${APP_JACOCO_PORT} --destfile target/jacoco-it.exec"
                sh 'mkdir target/site/jacoco-it'
                sh 'java -jar target/dependency/jacococli.jar report target/jacoco-it.exec --classfiles target/classes --xml target/site/jacoco-it/jacoco.xml'
                junit 'target/failsafe-reports/*.xml'
                jacoco execPattern: 'target/jacoco-it.exec'
            }
        }

        stage('Performance tests') {
            steps {
                echo '-=- execute performance tests -=-'
                sh "curl --retry 10 --retry-connrefused --connect-timeout 5 --max-time 5 http://${TEST_CONTAINER_NAME}:${APP_LISTENING_PORT}" + "${APP_CONTEXT_ROOT}/actuator/health".replace('//', '/')
                sh "./mvnw jmeter:configure@configuration jmeter:jmeter jmeter:results -Djmeter.target.host=${TEST_CONTAINER_NAME} -Djmeter.target.port=${APP_LISTENING_PORT} -Djmeter.target.root=${APP_CONTEXT_ROOT}"
                perfReport(
                    sourceDataFiles: 'target/jmeter/results/*.csv',
                    errorUnstableThreshold: qualityGates.performance.throughput.error.unstable,
                    errorFailedThreshold: qualityGates.performance.throughput.error.failed,
                    errorUnstableResponseTimeThreshold: qualityGates.performance.throughput.response.unstable)
            }
        }

        // stage('Web page performance analysis') {
        //     steps {
        //         echo '-=- execute web page performance analysis -=-'
        //         sh 'apt-get update'
        //         sh 'apt-get install -y gnupg'
        //         sh 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" | tee -a /etc/apt/sources.list.d/google.list'
        //         sh 'curl -sL https://dl.google.com/linux/linux_signing_key.pub | apt-key add -'
        //         sh 'curl -sL https://deb.nodesource.com/setup_10.x | bash -'
        //         sh 'apt-get install -y nodejs google-chrome-stable'
        //         sh 'npm install -g lighthouse@5.6.0'
        //         sh "lighthouse http://${TEST_CONTAINER_NAME}:${APP_LISTENING_PORT}/${APP_CONTEXT_ROOT}/hello --output=html --output=csv --chrome-flags=\"--headless --no-sandbox\""
        //         archiveArtifacts artifacts: '*.report.html'
        //         archiveArtifacts artifacts: '*.report.csv'
        //     }
        // }

        /*stage('Code inspection & quality gate') {
            steps {
                echo '-=- run code inspection & check quality gate -=-'
                withSonarQubeEnv('ci-sonarqube') {
                    sh './mvnw sonar:sonar'
                }
                timeout(time: 10, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }*/

        /*stage('Push Docker image') {
            steps {
                echo '-=- push Docker image -=-'
                withDockerRegistry([ credentialsId: "${ORG_NAME}-docker-hub", url: '' ]) {
                    sh "docker tag ${ORG_NAME}/${APP_NAME}:${APP_VERSION} ${ORG_NAME}/${APP_NAME}:latest"
                    sh "docker push ${ORG_NAME}/${APP_NAME}:${APP_VERSION}"
                    sh "docker push ${ORG_NAME}/${APP_NAME}:latest"
                }
            }
        }*/
    }

    post {
        always {
            echo '-=- stop test container and remove deployment -=-'
            container('aks') {
                withCredentials([
                        usernamePassword(
                            credentialsId: 'sp-terraform-credentials',
                            usernameVariable: 'AAD_SERVICE_PRINCIPAL_CLIENT_ID',
                            passwordVariable: 'AAD_SERVICE_PRINCIPAL_CLIENT_SECRET')]) {
                    sh "kubectl delete pod ${TEST_CONTAINER_NAME}"
                    sh "kubectl delete service ${TEST_CONTAINER_NAME}"
                    sh "kubectl delete service ${TEST_CONTAINER_NAME}-jacoco"
                }
            }
        }
    }
}

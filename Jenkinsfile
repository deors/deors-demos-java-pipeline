#!groovy
pipeline {
    agent {
        kubernetes {
            defaultContainer 'jdk'
            yaml '''
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: jdk
      image: docker.io/eclipse-temurin:20.0.1_9-jdk
      command:
        - cat
      tty: true
      volumeMounts:
        - name: m2-cache
          mountPath: /root/.m2
    - name: podman
      image: quay.io/containers/podman:v4.5.1
      command:
        - cat
      tty: true
      securityContext:
        runAsUser: 0
        privileged: true
    - name: kubectl
      image: docker.io/bitnami/kubectl:1.27.3
      command:
        - cat
      tty: true
      securityContext:
        runAsUser: 0
        privileged: true
  volumes:
    - name: m2-cache
      hostPath:
        path: /data/m2-cache
        type: DirectoryOrCreate
'''
        }
    }

    environment {
        APP_NAME = getPomArtifactId()
        APP_VERSION = getPomVersionNoQualifier()
        APP_CONTEXT_ROOT = '/'
        APP_LISTENING_PORT = '8080'
        APP_JACOCO_PORT = '6300'
        CONTAINER_REGISTRY_URL = 'docker.io'
        IMAGE_ORG = 'deors'
        IMAGE_NAME = "$IMAGE_ORG/$APP_NAME"
        IMAGE_SNAPSHOT = "$IMAGE_NAME:$APP_VERSION-snapshot-$BUILD_NUMBER" // tag for snapshot version
        IMAGE_SNAPSHOT_LATEST = "$IMAGE_NAME:latest-snapshot" // tag for latest snapshot version
        IMAGE_GA = "$IMAGE_NAME:$APP_VERSION" // tag for GA version
        IMAGE_GA_LATEST = "$IMAGE_NAME:latest" // tag for latest GA version
        EPHTEST_CONTAINER_NAME = "ephtest-$APP_NAME-snapshot-$BUILD_NUMBER"
        EPHTEST_BASE_URL = "http://$EPHTEST_CONTAINER_NAME:$APP_LISTENING_PORT" + "$APP_CONTEXT_ROOT/actuator/health".replace('//', '/')

        // credentials
        KUBERNETES_CLUSTER_CRED_ID = 'k8s-lima-vm-kubeconfig'
        CONTAINER_REGISTRY_CRED = credentials("$IMAGE_ORG-docker-hub")

        // external systems
        SELENIUM_GRID_HOST = 'ci-selenium-grid' //credentials('ci-selenium-grid-host')
        SELENIUM_GRID_PORT = '4444' //credentials('ci-selenium-grid-port')
        SELENIUM_URL = "http://$SELENIUM_GRID_HOST:$SELENIUM_GRID_PORT/wd/hub"
    }

    stages {
        stage('Prepare environment') {
            steps {
                echo '-=- prepare environment -=-'
                echo "APP_NAME: ${APP_NAME}\nAPP_VERSION: ${APP_VERSION}"
                sh 'java -version'
                sh './mvnw --version'
                container('podman') {
                    sh 'podman --version'
                    sh "podman login $CONTAINER_REGISTRY_URL -u $CONTAINER_REGISTRY_CRED_USR -p $CONTAINER_REGISTRY_CRED_PSW"
                }
                container('kubectl') {
                    withKubeConfig([credentialsId: "$KUBERNETES_CLUSTER_CRED_ID"]) {
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

        stage('Software composition analysis') {
            steps {
                echo '-=- run software composition analysis -=-'
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

        stage('Build & push container image') {
            steps {
                echo '-=- build & push container image -=-'
                container('podman') {
                    sh "podman build -t $IMAGE_SNAPSHOT ."
                    sh "podman tag $IMAGE_SNAPSHOT $CONTAINER_REGISTRY_URL/$IMAGE_SNAPSHOT"
                    sh "podman push $CONTAINER_REGISTRY_URL/$IMAGE_SNAPSHOT"
                    sh "podman tag $IMAGE_SNAPSHOT $CONTAINER_REGISTRY_URL/$IMAGE_SNAPSHOT_LATEST"
                    sh "podman push $CONTAINER_REGISTRY_URL/$IMAGE_SNAPSHOT_LATEST"
                }
            }
        }

        stage('Run container image') {
            steps {
                echo '-=- run container image -=-'
                container('kubectl') {
                    withKubeConfig([credentialsId: "$KUBERNETES_CLUSTER_CRED_ID"]) {
                        sh "kubectl run $EPHTEST_CONTAINER_NAME --image=$CONTAINER_REGISTRY_URL/$IMAGE_SNAPSHOT --env=JAVA_OPTS=-javaagent:/jacocoagent.jar=output=tcpserver,address=*,port=$APP_JACOCO_PORT --port=$APP_LISTENING_PORT"
                        sh "kubectl expose pod $EPHTEST_CONTAINER_NAME --port=$APP_LISTENING_PORT"
                        sh "kubectl expose pod $EPHTEST_CONTAINER_NAME --port=$APP_JACOCO_PORT --name=$EPHTEST_CONTAINER_NAME-jacoco"
                    }
                }
            }
        }

        stage('Integration tests') {
            steps {
                echo '-=- execute integration tests -=-'
                sh "curl --retry 10 --retry-connrefused --connect-timeout 5 --max-time 5 $EPHTEST_BASE_URL"
                sh "./mvnw failsafe:integration-test failsafe:verify -DargLine=-Dtest.selenium.hub.url=$SELENIUM_URL -Dtest.target.server.url=$EPHTEST_BASE_URL"
                sh "java -jar target/dependency/jacococli.jar dump --address $EPHTEST_CONTAINER_NAME-jacoco --port $APP_JACOCO_PORT --destfile target/jacoco-it.exec"
                sh 'mkdir target/site/jacoco-it'
                sh 'java -jar target/dependency/jacococli.jar report target/jacoco-it.exec --classfiles target/classes --xml target/site/jacoco-it/jacoco.xml'
                junit 'target/failsafe-reports/*.xml'
                jacoco execPattern: 'target/jacoco-it.exec'
            }
        }

        stage('Performance tests') {
            steps {
                echo '-=- execute performance tests -=-'
                sh "curl --retry 10 --retry-connrefused --connect-timeout 5 --max-time 5 $EPHTEST_BASE_URL"
                sh "./mvnw jmeter:configure@configuration jmeter:jmeter jmeter:results -Djmeter.target.host=$EPHTEST_CONTAINER_NAME -Djmeter.target.port=$APP_LISTENING_PORT -Djmeter.target.root=$APP_CONTEXT_ROOT"
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
        //         sh "lighthouse http://$EPHTEST_CONTAINER_NAME:$APP_LISTENING_PORT/$APP_CONTEXT_ROOT/hello --output=html --output=csv --chrome-flags=\"--headless --no-sandbox\""
        //         archiveArtifacts artifacts: '*.report.html'
        //         archiveArtifacts artifacts: '*.report.csv'
        //     }
        // }

        // stage('Code inspection & quality gate') {
        //     steps {
        //         echo '-=- run code inspection & check quality gate -=-'
        //         withSonarQubeEnv('ci-sonarqube') {
        //             sh './mvnw sonar:sonar'
        //         }
        //         timeout(time: 10, unit: 'MINUTES') {
        //             waitForQualityGate abortPipeline: true
        //         }
        //     }
        // }

        stage('Promote container image') {
            steps {
                echo '-=- promote container image -=-'
                container('podman') {
                    // when using latest or a non-snapshot tag to deploy GA version
                    // this tag push should trigger the change in staging/production environment
                    sh "podman tag $IMAGE_SNAPSHOT $CONTAINER_REGISTRY_URL/$IMAGE_GA"
                    sh "podman push $CONTAINER_REGISTRY_URL/$IMAGE_GA"
                    sh "podman tag $IMAGE_SNAPSHOT $CONTAINER_REGISTRY_URL/$IMAGE_GA_LATEST"
                    sh "podman push $CONTAINER_REGISTRY_URL/$IMAGE_GA_LATEST"
                }
            }
        }
    }

    post {
        always {
            echo '-=- stop test container and remove deployment -=-'
            container('kubectl') {
                withKubeConfig([credentialsId: "$KUBERNETES_CLUSTER_CRED_ID"]) {
                    sh "kubectl delete pod $EPHTEST_CONTAINER_NAME"
                    sh "kubectl delete service $EPHTEST_CONTAINER_NAME"
                    sh "kubectl delete service $EPHTEST_CONTAINER_NAME-jacoco"
                }
            }
        }
    }
}


def getPomVersion() {
    return readMavenPom().version
}

def getPomVersionNoQualifier() {
    return readMavenPom().version.split('-')[0]
}

def getPomArtifactId() {
    return readMavenPom().artifactId
}

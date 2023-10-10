# deors-demos-java-pipeline

An exemplar Jenkins CI/CD pipeline for Java + Maven + Spring Boot applications.

The main features for the reference pipeline are:

- Jenkins declarative pipeline.
- Build agent as a Kubernetes pod, tested to work with Rancher Desktop (K3s).
- Application packaged with Podman as a container image and published to Docker Hub (docker.io).
- Surefire configured to gather test coverage with JaCoCo.
- Mutation tests with Pitest.
- Integration tests with Selenium, which can be executed either manually or via Failsafe.
- Integration test coverage with JaCoCo.
- Load tests with JMeter.
- Dependency vulnerability scan with OWASP Dependency Check.
- Web performance analysis with Lighthouse.
- Quality analysis with SonarQube, including collating results from the other tools.

## Set up in Jenkins

To being with, a Jenkins CI server must be available. Besides the suggested plug-ins during Jenkins initial configuration, the following plug-ins must be installed:

- `Kubernetes`
- `Pipeline Utility Steps`
- `JaCoCo`
- `OWASP Dependency-Check`
- `Performance`
- `SonarQube Scanner`

To run the CI/CD pipeline in Jenkins, begin by configuring the Kubernetes cluster in the `Clouds` section under `System Configuration`. Three settings must be provided as the minimum:

- The URL to access Kubernetes API.
- The Jenkins URL to establish the connection with the JNLP agents.
- The `kubeconfig` file stored in the Jenkins credential vault.

Depending on the networking and ingress configuration, this might be tricky. For a typical local setup with Rancher Desktop and K3s, the Kubernetes API will be accessible from the host machine IP or cluster IP, and the Jenkins agent integration (typically port 50000) will be accessible from the IP/name internal to the cluster (e.g. pod IP or service name).

The CI/CD pipeline requires that a credential with id `docker-hub-deors` is configured in Jenkins. The `deors` suffix in the credential id refers to the `deors` org namespace which is the target when pushing container images to Docker Hub (the container registry used in this case).

If you want to use your own Docker Hub organization, edit the pipeline replacing the `ORG_NAME` variable with the chosen organization name, e.g., `YOUR_ORG_NAME`, and configure the credential in Jenkins with id `docker-hub-<YOUR_ORG_NAME>`, or use an entirely different id at both places.

The CI/CD pipeline also leverages the Jenkins credential vault to configure the URLs needed to access quality tools Selenium and Lighthouse. The credentials that must be configured in Jenkins are `ci-selenium-url` for the Selenium Grid Hub, and `ci-lighthouse-url` for the Lighthouse CI server.

To upload data into Lighthouse CI server, each project must be previously configured by running the `lhci wizard` command, and the generated token must be added as a credential in Jenkins. As a good practice, considering that there might be many projects configured in the same Jenkins master, configure the credential id in the form `ci-lighthouse-token-<YOUR_APP_NAME>`, e.g. `ci-lighthouse-token-deors-demos-java-pipeline`. This is just a recommendation, and of course you may choose an entirely different id for the Lighthouse tokens.

To configure integration with SonarQube, the following settings must be provided:

- On SonarQube, create a token to allow the scanner to publish the analysis data collected during Jenkins builds.
- On SonarQube, configure the Jenkins webhook to allow SonarQube to send a message to Jenkins when analysis results are available (e.g. to wait and check for the quality gate result).
- On Jenkins, add the scanner token as a secret in Jenkins credential vault.
- On Jenkins, configure SonarQube plug-in by adding an instance with name `ci-sonarqube` (the pipeline expects it to exist), the SonarQube URL, and the token previously added to the vault.

For a step-by-step guidance on how to configure Jenkins and SonarQube integration, as well as how to build up the entire CI/CD pipeline from scratch, you may refer to the instructions in the `workshop-pipelines` repository here: <https://github.com/deors/workshop-pipelines/blob/master/readme.md>

## Build and test locally

To build and launch the project, to ensure that everything works fine before commiting any change, just leverage the usual Maven commands:

    mvnw verify
    mvnw spring-boot:run

Once up and running, access the following URLs to get status information, a generic greeting message, and a personalized greeting message:

    http://localhost:8080/actuator/health
    http://localhost:8080/hello
    http://localhost:8080/hello/John

## Build and test locally with Rancher Desktop (K3s)

There are many ways to have a Kubernetes cluster available for development purposes, but possibly one of the simplest and fastest is to install Rancher Desktop in your workstation. With Rancher Desktop comes K3s, a lightweight Kubernetes distribution optimized to be used in a workstation and other resource-limited environments.

Once Rancher Desktop is installed and running, we can use `nerdctl` command line tool to build images and `kubectl` to run them.

To build the image, first build the project with Maven as usual and afterwards, execute the image build command:

    mvnw verify
    nerdctl --namespace k8s.io build -t deors-demos-java-pipeline:1.0-SNAPSHOT .

The namespace parameter is needed for the image to be available to the local Kubernetes cluster. Once ready, launch the service with this command:

    kubectl run javapipeline --image deors-demos-java-pipeline:1.0-SNAPSHOT

To simplify local testing, instead of exposing a service or configuring an ingress, let's simply enable port forwarding to the pod port:

    kubectl port-forward pods/javapipeline 8080:8080

Meanwhile the port forward is active the service will be available through `localhost` as if it was running as a local process:

    http://localhost:8080/actuator/health
    http://localhost:8080/hello
    http://localhost:8080/hello/John

Once the local tests have finished, finish the port forward session by pressing `Ctrl+C` in the terminal where the port forward command is running, and then terminate the Kubernetes service with the following command:

    kubectl delete pod javapipeline

Rancher Desktop can be configured to use the Docker client instead. In that case, the equivalent `docker` cli commands are:

    docker build -t deors-demos-java-pipeline:1.0-SNAPSHOT .
    docker run --name deors-demos-java-pipeline --detach --publish 8080:8080 deors-demos-java-pipeline:1.0-SNAPSHOT
    docker stop deors-demos-java-pipeline
    docker rm deors-demos-java-pipeline

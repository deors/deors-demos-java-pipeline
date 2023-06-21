# deors-demos-java-pipeline

An exemplar CI/CD pipeline for Java + Maven + Spring Boot powered by Jenkins, Docker and Kubernetes

This exemplar configuration includes:

- Pipeline as code with Jenkins.
- Build agent as a Kubernetes pod, suitable to be run with Rancher Desktop (K3s).
- Application packaged as a Docker image.
- Surefire configured to gather test coverage with JaCoCo.
- Mutation tests with Pitest.
- Integration tests with Selenium, which can be executed either manually or via Failsafe.
- Integration test coverage with JaCoCo.
- Load tests with JMeter.
- Dependency vulnerability scan with OWASP Dependency Check.
- Quality analysis with SonarQube, including collating results from the other tools.

## Set up in Jenkins

The CI/CD pipeline requires that a credential with id `deors-docker-hub` is configured in Jenkins. The `deors` prefix in the credential id refers to the `deors` org namespace which is the target when pushing Docker images to Docker Hub (the container registry used in this case).

If you want to use your own Docker Hub organization, edit the pipeline replacing the `ORG_NAME` variable with the chosen organization name, e.g., `YOUR_ORG_NAME`, and configure the credential in Jenkins with id `<YOUR_ORG_NAME-docker-hub>`.

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

To simplify local testing, instead of exposing a service or configuring an ingress, let's simply enable port forwarding:

    kubectl port-forward pods/javapipeline 8080:8080

Meanwhile the port forward is active (finish it pressing Ctrl+C in the terminal where the process is running), the service will be available through `localhost` as if it was running as a local process:

    http://localhost:8080/actuator/health
    http://localhost:8080/hello
    http://localhost:8080/hello/John

Once the local tests have finished, terminate the service with the following command:

    kubectl delete pod javapipeline

Rancher Desktop can be configured to use the Docker client instead. In that case, the equivalent `docker` cli commands are:

    docker built -t deors-demos-java-pipeline:1.0-SNAPSHOT .
    docker run --name deors-demos-java-pipeline --detach --publish 8080:8080 deors-demos-java-pipeline:1.0-SNAPSHOT
    docker stop deors-demos-java-pipeline
    docker rm deors-demos-java-pipeline

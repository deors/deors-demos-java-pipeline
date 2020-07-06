# deors-demos-java-pipeline

An exemplar Java + Maven + Spring Boot project with Jenkins pipeline using Maven lifecycle and Docker for packaging and running integration tests

This exemplar configuration includes:

- Packaging as a Docker image.
- Pipeline as code with Jenkins.
- Docker image lifecycle with Spotify Maven plug-in.
- Surefire configured to gather test coverage with JaCoCo.
- Mutation tests with Pitest.
- Integration tests with Selenium, which can be executed either manually or via Failsafe.
- Integration test coverage with JaCoCo.
- Load tests with JMeter.
- Dependency vulnerability scan with OWASP Dependency Check.
- Quality analysis with SonarQube, including gathering results from the other tools.

## Set up in Jenkins

The continuous integration pipeline requires that a credential with id `deors-docker-hub`
is configured in Jenkins. The `deors` prefix in the credential id refers to the `deors`
org namespace which is targeted to push Docker images to Docker Hub.

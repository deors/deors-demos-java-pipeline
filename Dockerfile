FROM eclipse-temurin:17.0.3_7-jdk
VOLUME /tmp
ADD target/dependency/jacocoagent.jar jacocoagent.jar
ADD target/deors-demos-java-pipeline.jar app.jar
ENTRYPOINT exec java $JAVA_OPTS -jar /app.jar

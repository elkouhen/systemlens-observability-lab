FROM maven:3.9.9-eclipse-temurin-21 AS build

WORKDIR /workspace
COPY pom.xml ./
COPY apm-demo-contracts/pom.xml apm-demo-contracts/pom.xml
COPY apm-demo/pom.xml apm-demo/pom.xml
COPY apm-demo-worker/pom.xml apm-demo-worker/pom.xml
RUN mvn --batch-mode --projects apm-demo,apm-demo-worker --also-make dependency:go-offline

COPY apm-demo-contracts/src apm-demo-contracts/src
COPY apm-demo/src apm-demo/src
COPY apm-demo-worker/src apm-demo-worker/src
RUN mvn --batch-mode --projects apm-demo,apm-demo-worker --also-make package -DskipTests

FROM eclipse-temurin:21-jre AS frontend

WORKDIR /app
COPY --from=build /workspace/apm-demo/target/apm-demo-1.0.0.jar application.jar
COPY --from=build /root/.m2/repository/co/elastic/apm/elastic-apm-agent/1.55.0/elastic-apm-agent-1.55.0.jar /opt/elastic-apm-agent.jar
USER 10001
EXPOSE 3000
ENTRYPOINT ["java", "-javaagent:/opt/elastic-apm-agent.jar", "-jar", "/app/application.jar"]

FROM eclipse-temurin:21-jre AS worker

WORKDIR /app
COPY --from=build /workspace/apm-demo-worker/target/apm-demo-worker-1.0.0.jar application.jar
COPY --from=build /root/.m2/repository/co/elastic/apm/elastic-apm-agent/1.55.0/elastic-apm-agent-1.55.0.jar /opt/elastic-apm-agent.jar
USER 10001
EXPOSE 3001
ENTRYPOINT ["java", "-javaagent:/opt/elastic-apm-agent.jar", "-jar", "/app/application.jar"]

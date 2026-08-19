FROM maven:3.9.9-eclipse-temurin-21 AS build

ARG OTEL_JAVA_AGENT_VERSION=2.20.1
# Certificat racine Zscaler (ou proxy TLS d'entreprise équivalent), encodé en
# base64. Laisser vide sur une machine sans interception TLS : aucune étape
# de confiance supplémentaire n'est alors exécutée.
ARG ZSCALER_CA_CERT_B64=""

WORKDIR /workspace

# Ajoute le certificat au magasin système (Maven, curl) et au truststore JVM
# (Maven/curl utilisent le magasin système, mais le JDK a son propre
# truststore cacerts). Ne s'exécute que si un certificat est fourni.
RUN if [ -n "$ZSCALER_CA_CERT_B64" ]; then \
      echo "$ZSCALER_CA_CERT_B64" | base64 -d > /usr/local/share/ca-certificates/zscaler-root-ca.crt && \
      update-ca-certificates && \
      keytool -importcert -noprompt -trustcacerts -alias zscaler-root-ca \
        -file /usr/local/share/ca-certificates/zscaler-root-ca.crt \
        -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit; \
    fi

COPY pom.xml ./
COPY apm-demo-contracts/pom.xml apm-demo-contracts/pom.xml
COPY apm-demo/pom.xml apm-demo/pom.xml
COPY apm-demo-worker/pom.xml apm-demo-worker/pom.xml
RUN mvn --batch-mode --projects apm-demo,apm-demo-worker --also-make dependency:go-offline

COPY apm-demo-contracts/src apm-demo-contracts/src
COPY apm-demo/src apm-demo/src
COPY apm-demo-worker/src apm-demo-worker/src
RUN mvn --batch-mode --projects apm-demo,apm-demo-worker --also-make package -DskipTests
RUN curl --fail --location --silent --show-error \
  "https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_JAVA_AGENT_VERSION}/opentelemetry-javaagent.jar" \
  -o /opt/opentelemetry-javaagent.jar

FROM eclipse-temurin:21.0.7_6-jre-noble AS frontend

WORKDIR /app
COPY --from=build /workspace/apm-demo/target/apm-demo-1.0.0.jar application.jar
COPY --from=build /opt/opentelemetry-javaagent.jar /opt/opentelemetry-javaagent.jar
USER 10001
EXPOSE 3000
ENTRYPOINT ["java", "-javaagent:/opt/opentelemetry-javaagent.jar", "-jar", "/app/application.jar"]

FROM eclipse-temurin:21.0.7_6-jre-noble AS worker

WORKDIR /app
COPY --from=build /workspace/apm-demo-worker/target/apm-demo-worker-1.0.0.jar application.jar
COPY --from=build /opt/opentelemetry-javaagent.jar /opt/opentelemetry-javaagent.jar
USER 10001
EXPOSE 3001
ENTRYPOINT ["java", "-javaagent:/opt/opentelemetry-javaagent.jar", "-jar", "/app/application.jar"]

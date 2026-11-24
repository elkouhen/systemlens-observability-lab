FROM maven:3.9.9-eclipse-temurin-21 AS build

# Certificat racine Zscaler (ou proxy TLS d'entreprise équivalent), encodé en
# base64. Laisser vide sur une machine sans interception TLS.
ARG ZSCALER_CA_CERT_B64=""

WORKDIR /workspace

RUN if [ -n "$ZSCALER_CA_CERT_B64" ]; then \
      echo "$ZSCALER_CA_CERT_B64" | base64 -d > /usr/local/share/ca-certificates/zscaler-root-ca.crt && \
      update-ca-certificates && \
      keytool -importcert -noprompt -trustcacerts -alias zscaler-root-ca \
        -file /usr/local/share/ca-certificates/zscaler-root-ca.crt \
        -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit; \
    fi

COPY pom.xml ./
RUN mvn --batch-mode dependency:go-offline
COPY src src
RUN mvn --batch-mode package -DskipTests

# L'image ne contient aucun agent : dans Kubernetes, l'opérateur
# OpenTelemetry injecte l'agent Java dans le pod annoté
# instrumentation.opentelemetry.io/inject-java (ADR-019).
FROM eclipse-temurin:21.0.7_6-jre-noble AS demo-api

WORKDIR /app
COPY --from=build /workspace/target/demo-api-1.2.0.jar application.jar
ENV OTEL_SERVICE_NAME=demo-api
USER 10001
EXPOSE 3010
ENTRYPOINT ["java", "-jar", "/app/application.jar"]

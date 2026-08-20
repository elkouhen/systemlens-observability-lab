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
COPY supermarket-contracts/pom.xml supermarket-contracts/pom.xml
COPY order-service/pom.xml order-service/pom.xml
COPY inventory-service/pom.xml inventory-service/pom.xml
RUN mvn --batch-mode --projects order-service,inventory-service --also-make dependency:go-offline

COPY supermarket-contracts/src supermarket-contracts/src
COPY order-service/src order-service/src
COPY inventory-service/src inventory-service/src
RUN mvn --batch-mode --projects order-service,inventory-service --also-make package -DskipTests
RUN curl --fail --location --silent --show-error \
  "https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_JAVA_AGENT_VERSION}/opentelemetry-javaagent.jar" \
  -o /opt/opentelemetry-javaagent.jar

FROM eclipse-temurin:21.0.7_6-jre-noble AS order-service

WORKDIR /app
COPY --from=build /workspace/order-service/target/order-service-1.0.0.jar application.jar
COPY --from=build /opt/opentelemetry-javaagent.jar /opt/opentelemetry-javaagent.jar
USER 10001
EXPOSE 3000
ENTRYPOINT ["java", "-javaagent:/opt/opentelemetry-javaagent.jar", "-jar", "/app/application.jar"]

FROM eclipse-temurin:21.0.7_6-jre-noble AS inventory-service

WORKDIR /app
COPY --from=build /workspace/inventory-service/target/inventory-service-1.0.0.jar application.jar
COPY --from=build /opt/opentelemetry-javaagent.jar /opt/opentelemetry-javaagent.jar
USER 10001
EXPOSE 3001
ENTRYPOINT ["java", "-javaagent:/opt/opentelemetry-javaagent.jar", "-jar", "/app/application.jar"]

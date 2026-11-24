package io.systemlens.demo;

import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.OpenTelemetry;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;

/**
 * API de démonstration minimale, instrumentée par l'agent Java OpenTelemetry
 * (traces, logs et métriques JVM) ; seule la métrique applicative
 * {@code demo_api.calls} est produite par le code, via l'API OTel.
 */
@SpringBootApplication
public class DemoApiApplication {

    public static void main(String[] args) {
        SpringApplication.run(DemoApiApplication.class, args);
    }

    /** OpenTelemetry de l'agent injecté ; no-op lorsque l'agent est absent. */
    @Bean
    OpenTelemetry openTelemetry() {
        return GlobalOpenTelemetry.get();
    }
}

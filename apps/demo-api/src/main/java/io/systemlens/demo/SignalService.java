package io.systemlens.demo;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

/**
 * Produit les trois signaux : des logs SLF4J (exportés par l'agent OTel avec
 * le contexte de trace), des métriques Micrometer (exportées en OTLP) et des
 * spans (créés par l'agent sur les requêtes HTTP entrantes et sortantes).
 */
@Service
public class SignalService {

    private static final Logger LOGGER = LoggerFactory.getLogger(SignalService.class);

    private final MeterRegistry registry;
    private final RestTemplate restTemplate;
    private final String selfUrl;
    private final Timer workTimer;

    public SignalService(
            MeterRegistry registry,
            RestTemplate restTemplate,
            @Value("${demo-api.self-url}") String selfUrl) {
        this.registry = registry;
        this.restTemplate = restTemplate;
        this.selfUrl = selfUrl;
        this.workTimer = Timer.builder("demo.work.duration")
            .description("Durée du travail simulé par /api/work")
            .publishPercentileHistogram()
            .register(registry);
    }

    public String greet(String name) {
        count("hello");
        // Les paires clé-valeur deviennent des attributs du log (demo.name).
        LOGGER.atInfo()
            .addKeyValue("demo.name", name)
            .addKeyValue("event.action", "greet")
            .log("Salutation demandée pour {}", name);
        return "Bonjour " + name;
    }

    public long work(long requestedMs) {
        count("work");
        long ms = Math.max(0, Math.min(requestedMs, 5_000));
        long started = System.nanoTime();
        workTimer.record(() -> simulate(ms));
        long elapsedMs = (System.nanoTime() - started) / 1_000_000;
        LOGGER.atInfo()
            .addKeyValue("demo.work.requested_ms", ms)
            .addKeyValue("demo.work.elapsed_ms", elapsedMs)
            .addKeyValue("event.action", "work")
            .log("Travail simulé terminé en {} ms", elapsedMs);
        return elapsedMs;
    }

    public String chain(String name) {
        count("chain");
        LOGGER.atInfo().addKeyValue("event.action", "chain").log("Appel sortant vers {}", selfUrl);
        Map<?, ?> response = restTemplate.getForObject(selfUrl + "/api/hello?name={name}", Map.class, name);
        return "Chaîne : " + (response == null ? "sans réponse" : response.get("message"));
    }

    public void fail(String reason) {
        count("fail");
        LOGGER.atError()
            .addKeyValue("demo.reason", reason)
            .addKeyValue("event.action", "fail")
            .log("Échec contrôlé demandé : {}", reason);
        throw new DemoFailureException("Échec contrôlé : " + reason);
    }

    /** Un compteur par point d'entrée, lisible dans metrics-demo.otel-*. */
    private void count(String endpoint) {
        Counter.builder("demo.requests")
            .description("Requêtes reçues par point d'entrée")
            .tag("endpoint", endpoint)
            .register(registry)
            .increment();
    }

    /** Alterne attente et calcul pour produire un span d'une durée visible. */
    private void simulate(long ms) {
        long deadline = System.nanoTime() + ms * 1_000_000;
        double accumulator = 0;
        while (System.nanoTime() < deadline) {
            accumulator += Math.sqrt(ThreadLocalRandom.current().nextDouble());
            if (accumulator > 1_000_000) {
                accumulator = 0;
                Thread.onSpinWait();
            }
        }
    }

    static class DemoFailureException extends RuntimeException {
        DemoFailureException(String message) {
            super(message);
        }
    }
}

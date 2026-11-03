package io.systemlens.demo;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import java.util.concurrent.atomic.AtomicLong;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Battement de cœur toutes les 30 secondes : un log et une jauge, pour que
 * les data streams de la plateforme restent alimentés sans trafic HTTP.
 */
@Component
public class HeartbeatScheduler {

    private static final Logger LOGGER = LoggerFactory.getLogger(HeartbeatScheduler.class);

    private final AtomicLong beats = new AtomicLong();

    public HeartbeatScheduler(MeterRegistry registry) {
        Gauge.builder("demo.heartbeat.count", beats, AtomicLong::get)
            .description("Battements de cœur émis depuis le démarrage")
            .register(registry);
    }

    @Scheduled(fixedRateString = "${demo-api.heartbeat-ms}")
    public void beat() {
        long count = beats.incrementAndGet();
        LOGGER.atInfo()
            .addKeyValue("demo.heartbeat", count)
            .addKeyValue("event.action", "heartbeat")
            .log("Battement de cœur {}", count);
    }
}

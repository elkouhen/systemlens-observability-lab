package io.systemlens.demo.frontend;

import io.systemlens.demo.contract.WorkRequested;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.UUID;

@Component
public class ScheduledWorkPublisher {

    private final KafkaTemplate<String, WorkRequested> kafkaTemplate;

    public ScheduledWorkPublisher(KafkaTemplate<String, WorkRequested> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    @Scheduled(cron = "${apm-demo.cron}")
    public void publishScheduledWork() {
        WorkRequested request = new WorkRequested(UUID.randomUUID().toString(), Instant.now());
        kafkaTemplate.send("apm-demo.work.requested", request.requestId(), request);
    }
}

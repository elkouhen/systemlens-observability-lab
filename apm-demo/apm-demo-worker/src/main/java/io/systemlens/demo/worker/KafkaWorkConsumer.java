package io.systemlens.demo.worker;

import io.systemlens.demo.contract.WorkRequested;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class KafkaWorkConsumer {

    private final WorkService workService;

    public KafkaWorkConsumer(WorkService workService) {
        this.workService = workService;
    }

    @KafkaListener(topics = "apm-demo.work.requested", groupId = "apm-demo-worker")
    public void consume(WorkRequested request) throws InterruptedException {
        workService.process("kafka", request.requestedAt());
    }
}

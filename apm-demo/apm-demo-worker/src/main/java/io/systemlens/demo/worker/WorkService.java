package io.systemlens.demo.worker;

import org.springframework.stereotype.Service;

import java.time.Instant;

@Service
public class WorkService {

    private final WorkItemRepository workItemRepository;

    public WorkService(WorkItemRepository workItemRepository) {
        this.workItemRepository = workItemRepository;
    }

    public WorkResult process(String trigger, Instant requestedAt) throws InterruptedException {
        Thread.sleep(150);
        long result = 499_500L;
        WorkItem saved = workItemRepository.save(
                new WorkItem(null, result, trigger, requestedAt, Instant.now())
        );
        return new WorkResult(saved.id(), result, trigger, 150L);
    }

    public record WorkResult(String id, long result, String trigger, long durationMs) {
    }
}

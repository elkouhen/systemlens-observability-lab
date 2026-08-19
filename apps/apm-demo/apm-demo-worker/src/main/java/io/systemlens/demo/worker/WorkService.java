package io.systemlens.demo.worker;

import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.UUID;

@Service
public class WorkService {

    private final WorkItemRepository workItemRepository;
    private final PostgresWorkItemRepository postgresWorkItemRepository;

    public WorkService(WorkItemRepository workItemRepository, PostgresWorkItemRepository postgresWorkItemRepository) {
        this.workItemRepository = workItemRepository;
        this.postgresWorkItemRepository = postgresWorkItemRepository;
    }

    public WorkResult process(String trigger, Instant requestedAt) throws InterruptedException {
        Thread.sleep(150);
        long result = 499_500L;
        String id = UUID.randomUUID().toString();
        Instant createdAt = Instant.now();
        WorkItem saved = workItemRepository.save(
                new WorkItem(id, result, trigger, requestedAt, createdAt)
        );
        try {
            postgresWorkItemRepository.save(new PostgresWorkItem(id, result, trigger, requestedAt, createdAt));
        } catch (RuntimeException exception) {
            // Il n'existe pas de transaction distribuée entre MongoDB et
            // PostgreSQL : compenser l'écriture MongoDB évite qu'un résultat
            // partiellement persisté soit présenté comme un succès.
            workItemRepository.deleteById(id);
            throw exception;
        }
        return new WorkResult(saved.id(), result, trigger, 150L);
    }

    public record WorkResult(String id, long result, String trigger, long durationMs) {
    }
}

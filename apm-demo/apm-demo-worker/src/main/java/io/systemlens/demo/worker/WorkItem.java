package io.systemlens.demo.worker;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.Instant;

@Document(collection = "apm_demo_work")
public record WorkItem(@Id String id, long result, String trigger, Instant requestedAt, Instant createdAt) {
}

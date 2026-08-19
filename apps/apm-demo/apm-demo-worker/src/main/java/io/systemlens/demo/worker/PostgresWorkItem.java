package io.systemlens.demo.worker;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "apm_demo_work")
public class PostgresWorkItem {

    @Id
    private String id;
    private long result;
    private String trigger;
    private Instant requestedAt;
    private Instant createdAt;

    protected PostgresWorkItem() {
    }

    public PostgresWorkItem(String id, long result, String trigger, Instant requestedAt, Instant createdAt) {
        this.id = id;
        this.result = result;
        this.trigger = trigger;
        this.requestedAt = requestedAt;
        this.createdAt = createdAt;
    }
}

package io.systemlens.demo.worker;

import org.springframework.data.jpa.repository.JpaRepository;

public interface PostgresWorkItemRepository extends JpaRepository<PostgresWorkItem, String> {
}

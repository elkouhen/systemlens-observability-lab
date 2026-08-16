package io.systemlens.demo.worker;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface WorkItemRepository extends MongoRepository<WorkItem, String> {
}

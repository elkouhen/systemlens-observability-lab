package io.systemlens.supermarket.inventory;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface OrderFulfillmentRepository extends MongoRepository<OrderFulfillment, String> {
}

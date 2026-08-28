package io.systemlens.supermarket.inventory.application.port.out;

import java.time.Instant;

public interface StockDepletedPort {
    void publish(String productId, Instant occurredAt);
}

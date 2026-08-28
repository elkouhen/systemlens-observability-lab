package io.systemlens.supermarket.inventory.application.port.in;

import java.time.Instant;

public interface InventoryUseCase {
    ReservationResult reserve(String orderId, String productId, int quantity, String channel, Instant requestedAt);
    void restock(String productId, int quantity);

    record ReservationResult(String orderId, String productId, String productName, int quantity,
                             int remainingStock, String channel, long durationMs) {}
}

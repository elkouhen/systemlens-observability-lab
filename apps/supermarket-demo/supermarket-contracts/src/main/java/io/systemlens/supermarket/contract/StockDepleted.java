package io.systemlens.supermarket.contract;

import java.time.Instant;

public record StockDepleted(String productId, Instant occurredAt) {
}

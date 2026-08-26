package io.systemlens.supermarket.contract;

import java.time.Instant;

public record StockRestockRequested(String productId, int quantity, Instant requestedAt) {
}

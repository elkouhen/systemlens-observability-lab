package io.systemlens.supermarket.contract;

import java.time.Instant;

/**
 * Commande client transportée entre order-service et inventory-service, soit
 * de façon asynchrone via Kafka (commandes en ligne traitées par lots), soit
 * de façon synchrone via REST (commande passée en caisse).
 */
public record OrderPlaced(String orderId, String productId, int quantity, Instant requestedAt) {
}

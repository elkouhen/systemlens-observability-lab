package io.systemlens.supermarket.inventory;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.Instant;

/**
 * Trace de traitement d'une commande, utilisée comme journal de lecture rapide
 * (audit) : produit livré, quantité, canal d'origine et stock restant après
 * réservation.
 */
@Document(collection = "order_fulfillments")
public record OrderFulfillment(@Id String orderId, String productId, String productName, int quantity,
                                int remainingStock, String channel, Instant requestedAt, Instant createdAt) {
}

package io.systemlens.supermarket.inventory;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

/** Ligne du grand livre transactionnel des mouvements de stock (décréments par commande). */
@Entity
@Table(name = "stock_movements")
public class StockMovement {

    @Id
    private String orderId;
    private String productId;
    private int quantity;
    private String channel;
    private Instant requestedAt;
    private Instant createdAt;

    protected StockMovement() {
    }

    public StockMovement(String orderId, String productId, int quantity, String channel,
                          Instant requestedAt, Instant createdAt) {
        this.orderId = orderId;
        this.productId = productId;
        this.quantity = quantity;
        this.channel = channel;
        this.requestedAt = requestedAt;
        this.createdAt = createdAt;
    }
}

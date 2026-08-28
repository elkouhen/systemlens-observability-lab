package io.systemlens.supermarket.inventory.adapter.in.messaging;

import io.systemlens.supermarket.contract.OrderPlaced;
import io.systemlens.supermarket.inventory.application.port.in.InventoryUseCase;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class KafkaOrderConsumer {
    private final InventoryUseCase inventory;
    public KafkaOrderConsumer(InventoryUseCase inventory) { this.inventory=inventory; }
    @KafkaListener(topics="supermarket.order.placed", groupId="inventory-service")
    public void consume(OrderPlaced order) { inventory.reserve(order.orderId(), order.productId(), order.quantity(), "kafka", order.requestedAt()); }
}

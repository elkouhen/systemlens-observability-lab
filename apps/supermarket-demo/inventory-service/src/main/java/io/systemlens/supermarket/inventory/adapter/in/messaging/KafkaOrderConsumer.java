package io.systemlens.supermarket.inventory.adapter.in.messaging;

import io.systemlens.supermarket.inventory.application.port.in.InventoryUseCase;
import io.systemlens.supermarket.contract.OrderPlaced;
import io.systemlens.supermarket.messaging.AbstractKafkaMessageProcessor;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class KafkaOrderConsumer extends AbstractKafkaMessageProcessor<OrderPlaced> {
    private final InventoryUseCase inventory;
    public KafkaOrderConsumer(InventoryUseCase inventory) { this(inventory, new io.micrometer.core.instrument.simple.SimpleMeterRegistry()); }
    @Autowired
    public KafkaOrderConsumer(InventoryUseCase inventory, MeterRegistry meterRegistry) { super(meterRegistry); this.inventory=inventory; }
    @KafkaListener(topics="supermarket.order.placed", groupId="inventory-service")
    public void consume(OrderPlaced order) {
        consumeMessage(order, "orders", "supermarket.order.placed");
    }

    @Override
    protected void processMessage(OrderPlaced order) {
        inventory.reserve(order.orderId(), order.productId(), order.quantity(), "kafka", order.requestedAt());
    }
}

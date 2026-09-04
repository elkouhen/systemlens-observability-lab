package io.systemlens.supermarket.inventory.adapter.in.messaging;

import io.systemlens.supermarket.contract.OrderPlaced;
import io.systemlens.supermarket.inventory.application.port.in.InventoryUseCase;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class KafkaOrderConsumer {
    private final InventoryUseCase inventory;
    private final MeterRegistry meterRegistry;
    public KafkaOrderConsumer(InventoryUseCase inventory) { this(inventory, new io.micrometer.core.instrument.simple.SimpleMeterRegistry()); }
    @Autowired
    public KafkaOrderConsumer(InventoryUseCase inventory, MeterRegistry meterRegistry) { this.inventory=inventory; this.meterRegistry=meterRegistry; }
    @KafkaListener(topics="supermarket.order.placed", groupId="inventory-service")
    public void consume(OrderPlaced order) {
        Timer.Sample sample = Timer.start(meterRegistry);
        try {
            inventory.reserve(order.orderId(), order.productId(), order.quantity(), "kafka", order.requestedAt());
        } finally {
            sample.stop(meterRegistry.timer("business.kafka.message.processing", "consumer", "orders", "topic", "supermarket.order.placed"));
        }
    }
}

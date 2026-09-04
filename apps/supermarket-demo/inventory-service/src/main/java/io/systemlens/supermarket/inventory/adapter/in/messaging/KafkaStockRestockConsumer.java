package io.systemlens.supermarket.inventory.adapter.in.messaging;

import io.systemlens.supermarket.contract.StockRestockRequested;
import io.systemlens.supermarket.inventory.application.port.in.InventoryUseCase;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class KafkaStockRestockConsumer {
    private final InventoryUseCase inventory;
    private final MeterRegistry meterRegistry;
    public KafkaStockRestockConsumer(InventoryUseCase inventory) { this(inventory, new io.micrometer.core.instrument.simple.SimpleMeterRegistry()); }
    @Autowired
    public KafkaStockRestockConsumer(InventoryUseCase inventory, MeterRegistry meterRegistry) { this.inventory=inventory; this.meterRegistry=meterRegistry; }
    @KafkaListener(topics="supermarket.stock.restock-requested", groupId="inventory-restock-service")
    public void consume(StockRestockRequested request) {
        Timer.Sample sample = Timer.start(meterRegistry);
        try {
            inventory.restock(request.productId(), request.quantity());
        } finally {
            sample.stop(meterRegistry.timer("business.kafka.message.processing", "consumer", "restock", "topic", "supermarket.stock.restock-requested"));
        }
    }
}

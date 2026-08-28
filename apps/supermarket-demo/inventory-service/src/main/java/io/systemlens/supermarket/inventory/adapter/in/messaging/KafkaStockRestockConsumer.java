package io.systemlens.supermarket.inventory.adapter.in.messaging;

import io.systemlens.supermarket.contract.StockRestockRequested;
import io.systemlens.supermarket.inventory.application.port.in.InventoryUseCase;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class KafkaStockRestockConsumer {
    private final InventoryUseCase inventory;
    public KafkaStockRestockConsumer(InventoryUseCase inventory) { this.inventory=inventory; }
    @KafkaListener(topics="supermarket.stock.restock-requested", groupId="inventory-restock-service")
    public void consume(StockRestockRequested request) { inventory.restock(request.productId(), request.quantity()); }
}

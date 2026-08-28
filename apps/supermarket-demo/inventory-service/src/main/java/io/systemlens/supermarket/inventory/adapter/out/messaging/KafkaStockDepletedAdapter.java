package io.systemlens.supermarket.inventory.adapter.out.messaging;

import io.systemlens.supermarket.contract.StockDepleted;
import io.systemlens.supermarket.inventory.application.port.out.StockDepletedPort;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;
import java.time.Instant;

@Component
class KafkaStockDepletedAdapter implements StockDepletedPort {
    private final KafkaTemplate<String, StockDepleted> kafkaTemplate;
    KafkaStockDepletedAdapter(KafkaTemplate<String, StockDepleted> kafkaTemplate) { this.kafkaTemplate=kafkaTemplate; }
    public void publish(String productId, Instant occurredAt) { kafkaTemplate.send("supermarket.stock.depleted", productId, new StockDepleted(productId, occurredAt)); }
}

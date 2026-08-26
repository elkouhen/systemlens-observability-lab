package io.systemlens.supermarket.restock;

import io.systemlens.supermarket.contract.StockDepleted;
import io.systemlens.supermarket.contract.StockRestockRequested;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

import java.time.Instant;

@Component
public class StockDepletedConsumer {

    private static final int RESTOCK_QUANTITY = 500;
    private static final Logger LOGGER = LoggerFactory.getLogger(StockDepletedConsumer.class);

    private final KafkaTemplate<String, StockRestockRequested> kafkaTemplate;

    public StockDepletedConsumer(KafkaTemplate<String, StockRestockRequested> kafkaTemplate) {
        this.kafkaTemplate = kafkaTemplate;
    }

    @KafkaListener(topics = "supermarket.stock.depleted", groupId = "restock-service")
    public void requestRestock(StockDepleted event) {
        StockRestockRequested request = new StockRestockRequested(
                event.productId(), RESTOCK_QUANTITY, Instant.now()
        );
        kafkaTemplate.send("supermarket.stock.restock-requested", request.productId(), request);
        LOGGER.info("Reassort demande: productId={}, quantity={}", request.productId(), request.quantity());
    }
}

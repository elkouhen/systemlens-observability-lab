package io.systemlens.supermarket.restock;

import io.systemlens.supermarket.contract.StockDepleted;
import io.systemlens.supermarket.contract.StockRestockRequested;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.springframework.beans.factory.annotation.Autowired;
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
    private final MeterRegistry meterRegistry;

    @Autowired
    public StockDepletedConsumer(KafkaTemplate<String, StockRestockRequested> kafkaTemplate,
                                MeterRegistry meterRegistry) {
        this.kafkaTemplate = kafkaTemplate;
        this.meterRegistry = meterRegistry;
    }

    public StockDepletedConsumer(KafkaTemplate<String, StockRestockRequested> kafkaTemplate) {
        this(kafkaTemplate, new SimpleMeterRegistry());
    }

    @KafkaListener(topics = "supermarket.stock.depleted", groupId = "restock-service")
    public void requestRestock(StockDepleted event) {
        StockRestockRequested request = new StockRestockRequested(
                event.productId(), RESTOCK_QUANTITY, Instant.now()
        );
        kafkaTemplate.send("supermarket.stock.restock-requested", request.productId(), request);
        meterRegistry.counter("business.stock.restock.requested").increment();
        LOGGER.info("Reassort demande: productId={}, quantity={}", request.productId(), request.quantity());
    }
}

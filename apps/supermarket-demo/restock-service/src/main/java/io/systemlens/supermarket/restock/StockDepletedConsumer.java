package io.systemlens.supermarket.restock;

import io.systemlens.supermarket.contract.generated.event.StockDepleted;
import io.systemlens.supermarket.contract.generated.event.StockRestockRequested;
import io.systemlens.supermarket.messaging.AbstractKafkaMessageProcessor;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Autowired;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Component;

import java.time.OffsetDateTime;

@Component
public class StockDepletedConsumer extends AbstractKafkaMessageProcessor<StockDepleted> {

    private static final int RESTOCK_QUANTITY = 500;
    private static final Logger LOGGER = LoggerFactory.getLogger(StockDepletedConsumer.class);

    private final KafkaTemplate<String, StockRestockRequested> kafkaTemplate;
    private final Counter restocksRequested;
    @Autowired
    public StockDepletedConsumer(KafkaTemplate<String, StockRestockRequested> kafkaTemplate,
                                MeterRegistry meterRegistry) {
        super(meterRegistry);
        this.kafkaTemplate = kafkaTemplate;
        this.restocksRequested = Counter.builder("business.stock.restock.requested").description("Réassorts demandés").register(meterRegistry);
    }

    public StockDepletedConsumer(KafkaTemplate<String, StockRestockRequested> kafkaTemplate) { this(kafkaTemplate, new io.micrometer.core.instrument.simple.SimpleMeterRegistry()); }

    @KafkaListener(topics = "supermarket.stock.depleted", groupId = "restock-service")
    public void requestRestock(StockDepleted event) {
        consumeMessage(event, "stock-depleted", "supermarket.stock.depleted");
    }

    @Override
    protected void processMessage(StockDepleted event) {
        StockRestockRequested request = new StockRestockRequested(
                event.getProductId(), RESTOCK_QUANTITY, OffsetDateTime.now()
        );
        kafkaTemplate.send("supermarket.stock.restock-requested", request.getProductId(), request);
        restocksRequested.increment();
        LOGGER.info("Reassort demande: productId={}, quantity={}", request.getProductId(), request.getQuantity());
    }
}

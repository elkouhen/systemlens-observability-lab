package io.systemlens.supermarket.restock;

import io.systemlens.supermarket.contract.StockDepleted;
import io.systemlens.supermarket.contract.StockRestockRequested;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.kafka.core.KafkaTemplate;

import java.time.Instant;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class StockDepletedConsumerTest {

    @SuppressWarnings("unchecked")
    private final KafkaTemplate<String, StockRestockRequested> kafkaTemplate = mock(KafkaTemplate.class);
    private final StockDepletedConsumer consumer = new StockDepletedConsumer(kafkaTemplate);

    @Test
    void requestsRestockForDepletedProduct() {
        consumer.requestRestock(new StockDepleted("PASTA-500G", Instant.parse("2026-08-26T10:00:00Z")));

        ArgumentCaptor<StockRestockRequested> request = ArgumentCaptor.forClass(StockRestockRequested.class);
        verify(kafkaTemplate).send(eq("supermarket.stock.restock-requested"), eq("PASTA-500G"), request.capture());
        assertEquals(500, request.getValue().quantity());
    }
}

package io.systemlens.supermarket.inventory;

import io.systemlens.supermarket.contract.StockRestockRequested;
import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class KafkaStockRestockConsumerTest {

    private final ReservationService reservationService = mock(ReservationService.class);
    private final KafkaStockRestockConsumer consumer = new KafkaStockRestockConsumer(reservationService);

    @Test
    void appliesRestockRequestToInventory() {
        consumer.consume(new StockRestockRequested("PASTA-500G", 500, Instant.now()));

        verify(reservationService).restock("PASTA-500G", 500);
    }
}

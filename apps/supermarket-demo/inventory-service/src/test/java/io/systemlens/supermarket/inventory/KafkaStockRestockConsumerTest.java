package io.systemlens.supermarket.inventory;

import io.systemlens.supermarket.contract.StockRestockRequested;
import io.systemlens.supermarket.inventory.adapter.in.messaging.KafkaStockRestockConsumer;
import io.systemlens.supermarket.inventory.application.port.in.InventoryUseCase;
import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

class KafkaStockRestockConsumerTest {

    private final InventoryUseCase reservationService = mock(InventoryUseCase.class);
    private final KafkaStockRestockConsumer consumer = new KafkaStockRestockConsumer(reservationService);

    @Test
    void appliesRestockRequestToInventory() {
        consumer.consume(new StockRestockRequested("PASTA-500G", 500, Instant.now()));

        verify(reservationService).restock("PASTA-500G", 500);
    }
}

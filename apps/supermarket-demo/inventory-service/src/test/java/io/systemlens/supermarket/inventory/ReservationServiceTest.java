package io.systemlens.supermarket.inventory;

import io.systemlens.supermarket.inventory.application.InventoryApplicationService;
import io.systemlens.supermarket.inventory.application.port.out.*;
import io.systemlens.supermarket.inventory.domain.Product;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class ReservationServiceTest {

    private final ProductPort productRepository = mock(ProductPort.class);
    private final OrderFulfillmentPort orderFulfillmentRepository = mock(OrderFulfillmentPort.class);
    private final StockMovementPort stockMovementRepository = mock(StockMovementPort.class);
    private final StockDepletedPort stockDepletedPort = mock(StockDepletedPort.class);
    private final InventoryApplicationService reservationService = new InventoryApplicationService(
            productRepository, orderFulfillmentRepository, stockMovementRepository, stockDepletedPort
    );

    @Test
    void rejectsNonPositiveQuantityBeforeAccessingStorage() {
        assertThrows(IllegalArgumentException.class, () -> reservationService.reserve(
                "order-1", "PASTA-500G", 0, "rest", Instant.now()
        ));

        verifyNoInteractions(productRepository, orderFulfillmentRepository, stockMovementRepository, stockDepletedPort);
    }

    @Test
    void publishesStockDepletedWhenReservationConsumesLastUnit() throws InterruptedException {
        Product product = new Product("PASTA-500G", "Pâtes penne 500g", 1);
        when(productRepository.findById("PASTA-500G")).thenReturn(Optional.of(product));

        reservationService.reserve("order-1", "PASTA-500G", 1, "rest", Instant.now());

        assertEquals(0, product.stockQuantity());
        verify(stockDepletedPort).publish(eq("PASTA-500G"), org.mockito.ArgumentMatchers.any());
    }
}

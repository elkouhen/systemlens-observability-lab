package io.systemlens.supermarket.inventory;

import org.junit.jupiter.api.Test;

import java.time.Instant;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;

class ReservationServiceTest {

    private final ProductRepository productRepository = mock(ProductRepository.class);
    private final OrderFulfillmentRepository orderFulfillmentRepository = mock(OrderFulfillmentRepository.class);
    private final StockMovementRepository stockMovementRepository = mock(StockMovementRepository.class);
    private final ReservationService reservationService = new ReservationService(
            productRepository, orderFulfillmentRepository, stockMovementRepository
    );

    @Test
    void rejectsNonPositiveQuantityBeforeAccessingStorage() {
        assertThrows(IllegalArgumentException.class, () -> reservationService.reserve(
                "order-1", "PASTA-500G", 0, "rest", Instant.now()
        ));

        verifyNoInteractions(productRepository, orderFulfillmentRepository, stockMovementRepository);
    }
}

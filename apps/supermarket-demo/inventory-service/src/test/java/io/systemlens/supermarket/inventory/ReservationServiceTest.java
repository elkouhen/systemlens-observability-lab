package io.systemlens.supermarket.inventory;

import io.systemlens.supermarket.contract.StockDepleted;
import org.junit.jupiter.api.Test;
import org.springframework.kafka.core.KafkaTemplate;

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

    private final ProductRepository productRepository = mock(ProductRepository.class);
    private final OrderFulfillmentRepository orderFulfillmentRepository = mock(OrderFulfillmentRepository.class);
    private final StockMovementRepository stockMovementRepository = mock(StockMovementRepository.class);
    @SuppressWarnings("unchecked")
    private final KafkaTemplate<String, StockDepleted> kafkaTemplate = mock(KafkaTemplate.class);
    private final ReservationService reservationService = new ReservationService(
            productRepository, orderFulfillmentRepository, stockMovementRepository, kafkaTemplate
    );

    @Test
    void rejectsNonPositiveQuantityBeforeAccessingStorage() {
        assertThrows(IllegalArgumentException.class, () -> reservationService.reserve(
                "order-1", "PASTA-500G", 0, "rest", Instant.now()
        ));

        verifyNoInteractions(productRepository, orderFulfillmentRepository, stockMovementRepository, kafkaTemplate);
    }

    @Test
    void publishesStockDepletedWhenReservationConsumesLastUnit() throws InterruptedException {
        Product product = new Product("PASTA-500G", "Pâtes penne 500g", 1);
        when(productRepository.findById("PASTA-500G")).thenReturn(Optional.of(product));

        reservationService.reserve("order-1", "PASTA-500G", 1, "rest", Instant.now());

        assertEquals(0, product.getStockQuantity());
        verify(kafkaTemplate).send(eq("supermarket.stock.depleted"), eq("PASTA-500G"), org.mockito.ArgumentMatchers.any(StockDepleted.class));
    }
}

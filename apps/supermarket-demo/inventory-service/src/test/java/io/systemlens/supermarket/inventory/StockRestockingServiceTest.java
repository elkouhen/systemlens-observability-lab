package io.systemlens.supermarket.inventory;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

class StockRestockingServiceTest {

    private final ProductRepository productRepository = mock(ProductRepository.class);
    private final StockRestockingService stockRestockingService = new StockRestockingService(productRepository);

    @Test
    void restocksAnEmptyProduct() {
        Product product = new Product("PASTA-500G", "Pâtes penne 500g", 0);

        stockRestockingService.restockWhenEmpty(product);

        verify(productRepository).save(product);
        assertEquals(500, product.getStockQuantity());
    }

    @Test
    void doesNotRestockProductWithRemainingStock() {
        Product product = new Product("PASTA-500G", "Pâtes penne 500g", 10);

        stockRestockingService.restockWhenEmpty(product);

        verifyNoInteractions(productRepository);
    }
}

package io.systemlens.supermarket.inventory;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

@Service
public class StockRestockingService {

    private static final int RESTOCK_QUANTITY = 500;
    private static final Logger LOGGER = LoggerFactory.getLogger(StockRestockingService.class);

    private final ProductRepository productRepository;

    public StockRestockingService(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    public void restockWhenEmpty(Product product) {
        if (product.getStockQuantity() != 0) {
            return;
        }

        product.setStockQuantity(RESTOCK_QUANTITY);
        productRepository.save(product);
        LOGGER.info("Reassort declenche: productId={}, quantity={}", product.getId(), RESTOCK_QUANTITY);
    }
}

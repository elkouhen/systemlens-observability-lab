package io.systemlens.supermarket.inventory.application;

import io.systemlens.supermarket.inventory.application.port.in.InventoryUseCase;
import io.systemlens.supermarket.inventory.application.port.out.OrderFulfillmentPort;
import io.systemlens.supermarket.inventory.application.port.out.ProductPort;
import io.systemlens.supermarket.inventory.application.port.out.StockDepletedPort;
import io.systemlens.supermarket.inventory.application.port.out.StockMovementPort;
import io.systemlens.supermarket.inventory.domain.Product;
import io.systemlens.supermarket.inventory.domain.ProductNotFoundException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;

@Service
public class InventoryApplicationService implements InventoryUseCase {
    private static final Logger LOGGER = LoggerFactory.getLogger(InventoryApplicationService.class);
    private static final long SIMULATED_PROCESSING_TIME_MS = 150L;
    private final ProductPort products;
    private final OrderFulfillmentPort fulfillments;
    private final StockMovementPort movements;
    private final StockDepletedPort stockDepleted;

    public InventoryApplicationService(ProductPort products, OrderFulfillmentPort fulfillments,
                                       StockMovementPort movements, StockDepletedPort stockDepleted) {
        this.products = products;
        this.fulfillments = fulfillments;
        this.movements = movements;
        this.stockDepleted = stockDepleted;
    }

    @Override
    @Transactional
    public ReservationResult reserve(String orderId, String productId, int quantity, String channel,
                                     Instant requestedAt) {
        if (quantity <= 0) {
            LOGGER.warn("Reservation refusee: orderId={}, productId={}, quantity={}, reason=invalid_quantity", orderId, productId, quantity);
            throw new IllegalArgumentException("La quantite doit etre strictement positive.");
        }
        try {
            Thread.sleep(SIMULATED_PROCESSING_TIME_MS);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("La reservation a ete interrompue.", exception);
        }
        Product product = products.findById(productId).orElseThrow(() -> {
            LOGGER.warn("Reservation refusee: orderId={}, productId={}, quantity={}, reason=product_not_found", orderId, productId, quantity);
            return new ProductNotFoundException(productId);
        });
        product.reserve(quantity);
        products.save(product);
        int remainingStock = product.stockQuantity();
        Instant createdAt = Instant.now();
        fulfillments.save(orderId, productId, product.name(), quantity, remainingStock, channel, requestedAt, createdAt);
        try {
            movements.save(orderId, productId, quantity, channel, requestedAt, createdAt);
        } catch (RuntimeException exception) {
            fulfillments.deleteById(orderId);
            throw exception;
        }
        LOGGER.info("Reservation effectuee: orderId={}, productId={}, quantity={}, remainingStock={}, channel={}", orderId, productId, quantity, remainingStock, channel);
        if (remainingStock == 0) {
            stockDepleted.publish(productId, createdAt);
            LOGGER.info("Stock epuise: productId={}", productId);
        }
        return new ReservationResult(orderId, productId, product.name(), quantity, remainingStock, channel,
                SIMULATED_PROCESSING_TIME_MS);
    }

    @Override
    @Transactional
    public void restock(String productId, int quantity) {
        Product product = products.findById(productId).orElseThrow(() -> new ProductNotFoundException(productId));
        product.restock(quantity);
        products.save(product);
        LOGGER.info("Reassort effectue: productId={}, quantity={}, stockQuantity={}", productId, quantity, product.stockQuantity());
    }
}

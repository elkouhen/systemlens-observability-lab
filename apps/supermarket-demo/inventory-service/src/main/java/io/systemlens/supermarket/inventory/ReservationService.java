package io.systemlens.supermarket.inventory;

import org.springframework.stereotype.Service;

import java.time.Instant;

@Service
public class ReservationService {

    private final ProductRepository productRepository;
    private final OrderFulfillmentRepository orderFulfillmentRepository;
    private final StockMovementRepository stockMovementRepository;

    public ReservationService(ProductRepository productRepository,
                               OrderFulfillmentRepository orderFulfillmentRepository,
                               StockMovementRepository stockMovementRepository) {
        this.productRepository = productRepository;
        this.orderFulfillmentRepository = orderFulfillmentRepository;
        this.stockMovementRepository = stockMovementRepository;
    }

    /**
     * Réserve la quantité demandée pour un produit et décrémente le stock.
     * Le canal (rest/kafka) distingue une commande passée en caisse d'une
     * commande en ligne traitée en tâche de fond.
     */
    public ReservationResult reserve(String orderId, String productId, int quantity, String channel,
                                      Instant requestedAt) throws InterruptedException {
        Thread.sleep(150);

        Product product = productRepository.findById(productId)
                .orElseThrow(() -> new ProductNotFoundException(productId));
        if (product.getStockQuantity() < quantity) {
            throw new OutOfStockException(productId, quantity, product.getStockQuantity());
        }

        product.setStockQuantity(product.getStockQuantity() - quantity);
        productRepository.save(product);
        int remainingStock = product.getStockQuantity();
        Instant createdAt = Instant.now();

        orderFulfillmentRepository.save(new OrderFulfillment(
                orderId, productId, product.getName(), quantity, remainingStock, channel, requestedAt, createdAt
        ));
        try {
            stockMovementRepository.save(
                    new StockMovement(orderId, productId, quantity, channel, requestedAt, createdAt)
            );
        } catch (RuntimeException exception) {
            // Il n'existe pas de transaction distribuée entre MongoDB et
            // PostgreSQL : compenser l'écriture MongoDB (et la décrémentation
            // de stock déjà appliquée) évite qu'une commande partiellement
            // persistée soit présentée comme un succès.
            orderFulfillmentRepository.deleteById(orderId);
            product.setStockQuantity(product.getStockQuantity() + quantity);
            productRepository.save(product);
            throw exception;
        }

        return new ReservationResult(orderId, productId, product.getName(), quantity, remainingStock, channel, 150L);
    }

    public record ReservationResult(String orderId, String productId, String productName, int quantity,
                                     int remainingStock, String channel, long durationMs) {
    }
}

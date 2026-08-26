package io.systemlens.supermarket.inventory;

import io.systemlens.supermarket.contract.StockDepleted;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;

@Service
public class ReservationService {

    private static final Logger LOGGER = LoggerFactory.getLogger(ReservationService.class);

    private final ProductRepository productRepository;
    private final OrderFulfillmentRepository orderFulfillmentRepository;
    private final StockMovementRepository stockMovementRepository;
    private final KafkaTemplate<String, StockDepleted> kafkaTemplate;

    public ReservationService(ProductRepository productRepository,
                               OrderFulfillmentRepository orderFulfillmentRepository,
                               StockMovementRepository stockMovementRepository,
                               KafkaTemplate<String, StockDepleted> kafkaTemplate) {
        this.productRepository = productRepository;
        this.orderFulfillmentRepository = orderFulfillmentRepository;
        this.stockMovementRepository = stockMovementRepository;
        this.kafkaTemplate = kafkaTemplate;
    }

    /**
     * Réserve la quantité demandée pour un produit et décrémente le stock.
     * Le canal (rest/kafka) distingue une commande passée en caisse d'une
     * commande en ligne traitée en tâche de fond.
     */
    @Transactional
    public ReservationResult reserve(String orderId, String productId, int quantity, String channel,
                                      Instant requestedAt) throws InterruptedException {
        if (quantity <= 0) {
            LOGGER.warn("Reservation refusee: orderId={}, productId={}, quantity={}, reason=invalid_quantity",
                    orderId, productId, quantity);
            throw new IllegalArgumentException("La quantite doit etre strictement positive.");
        }
        Thread.sleep(150);

        Product product = productRepository.findById(productId)
                .orElseThrow(() -> {
                    LOGGER.warn("Reservation refusee: orderId={}, productId={}, quantity={}, reason=product_not_found",
                            orderId, productId, quantity);
                    return new ProductNotFoundException(productId);
                });
        if (product.getStockQuantity() < quantity) {
            LOGGER.warn("Reservation refusee: orderId={}, productId={}, quantity={}, availableStock={}, reason=out_of_stock",
                    orderId, productId, quantity, product.getStockQuantity());
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
            stockMovementRepository.saveAndFlush(
                    new StockMovement(orderId, productId, quantity, channel, requestedAt, createdAt)
            );
        } catch (RuntimeException exception) {
            // Il n'existe pas de transaction distribuée entre MongoDB et
            // PostgreSQL : compenser l'écriture MongoDB (et la décrémentation
            // de stock déjà appliquée) évite qu'une commande partiellement
            // persistée soit présentée comme un succès.
            orderFulfillmentRepository.deleteById(orderId);
            throw exception;
        }

        LOGGER.info("Reservation effectuee: orderId={}, productId={}, quantity={}, remainingStock={}, channel={}",
                orderId, productId, quantity, remainingStock, channel);
        if (remainingStock == 0) {
            kafkaTemplate.send("supermarket.stock.depleted", productId, new StockDepleted(productId, createdAt));
            LOGGER.info("Stock epuise: productId={}", productId);
        }
        return new ReservationResult(orderId, productId, product.getName(), quantity, remainingStock, channel, 150L);
    }

    @Transactional
    public void restock(String productId, int quantity) {
        Product product = productRepository.findById(productId)
                .orElseThrow(() -> new ProductNotFoundException(productId));
        product.setStockQuantity(product.getStockQuantity() + quantity);
        productRepository.save(product);
        LOGGER.info("Reassort effectue: productId={}, quantity={}, stockQuantity={}",
                productId, quantity, product.getStockQuantity());
    }

    public record ReservationResult(String orderId, String productId, String productName, int quantity,
                                     int remainingStock, String channel, long durationMs) {
    }
}

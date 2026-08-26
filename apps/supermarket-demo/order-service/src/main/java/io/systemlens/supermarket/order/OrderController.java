package io.systemlens.supermarket.order;

import io.systemlens.supermarket.contract.OrderPlaced;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/** Commandes passées en caisse : réservation de stock synchrone auprès d'inventory-service. */
@RestController
@RequestMapping("/api")
public class OrderController {

    private static final Logger LOGGER = LoggerFactory.getLogger(OrderController.class);

    private final RestTemplate restTemplate;
    @Value("${order-service.inventory-service-url}")
    private String inventoryServiceUrl;

    public OrderController(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "ok");
    }

    @PostMapping("/orders")
    public ReservationResult placeOrder(@RequestBody OrderRequest request) {
        OrderPlaced order = new OrderPlaced(UUID.randomUUID().toString(), request.productId(), request.quantity(), Instant.now());
        LOGGER.info("Commande recue: orderId={}, productId={}, quantity={}",
            order.orderId(), order.productId(), order.quantity());
        ReservationResult reservation = restTemplate.postForObject(
            inventoryServiceUrl + "/api/reservations", order, ReservationResult.class);
        LOGGER.info("Commande reservee: orderId={}, productId={}, quantity={}, remainingStock={}",
            order.orderId(), order.productId(), order.quantity(), reservation.remainingStock());
        return reservation;
    }

    @GetMapping("/error")
    public void error() {
        // Quantité garantie supérieure au stock initial : démontre la
        // propagation d'une rupture de stock d'inventory-service vers
        // order-service (scénario d'erreur contrôlé pour l'observabilité).
        OrderPlaced order = new OrderPlaced(UUID.randomUUID().toString(), "PASTA-500G", 999_999, Instant.now());
        try {
            restTemplate.postForObject(inventoryServiceUrl + "/api/reservations", order, ReservationResult.class);
        } catch (HttpClientErrorException exception) {
            LOGGER.warn("Rupture de stock: orderId={}, productId={}, quantity={}",
                order.orderId(), order.productId(), order.quantity());
            throw new OutOfStockException("Rupture de stock signalée par inventory-service : " + exception.getMessage());
        }
    }

    @ExceptionHandler(OutOfStockException.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    Map<String, String> handleOutOfStock(OutOfStockException exception) {
        return Map.of("error", exception.getMessage());
    }

    record OrderRequest(String productId, int quantity) {
    }

    record ReservationResult(String orderId, String productId, String productName, int quantity,
                              int remainingStock, String channel, long durationMs) {
    }

    static class OutOfStockException extends RuntimeException {
        OutOfStockException(String message) {
            super(message);
        }
    }
}

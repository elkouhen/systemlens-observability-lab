package io.systemlens.supermarket.inventory;

import io.systemlens.supermarket.contract.OrderPlaced;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/** Réservation de stock en caisse : appelée de façon synchrone par order-service. */
@RestController
@RequestMapping("/api")
public class InventoryController {

    private final ReservationService reservationService;

    public InventoryController(ReservationService reservationService) {
        this.reservationService = reservationService;
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "ok");
    }

    @PostMapping("/reservations")
    public ReservationService.ReservationResult reserve(@RequestBody OrderPlaced order) throws InterruptedException {
        return reservationService.reserve(order.orderId(), order.productId(), order.quantity(), "rest", order.requestedAt());
    }

    @ExceptionHandler(OutOfStockException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    Map<String, String> handleOutOfStock(OutOfStockException exception) {
        return Map.of("error", exception.getMessage());
    }

    @ExceptionHandler(ProductNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    Map<String, String> handleProductNotFound(ProductNotFoundException exception) {
        return Map.of("error", exception.getMessage());
    }
}

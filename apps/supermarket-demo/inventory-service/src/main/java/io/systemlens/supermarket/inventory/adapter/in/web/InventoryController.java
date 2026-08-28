package io.systemlens.supermarket.inventory.adapter.in.web;

import io.systemlens.supermarket.contract.OrderPlaced;
import io.systemlens.supermarket.inventory.application.port.in.InventoryUseCase;
import io.systemlens.supermarket.inventory.domain.OutOfStockException;
import io.systemlens.supermarket.inventory.domain.ProductNotFoundException;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController @RequestMapping("/api")
public class InventoryController {
    private final InventoryUseCase inventory;
    public InventoryController(InventoryUseCase inventory) { this.inventory=inventory; }
    @GetMapping("/health") public Map<String,String> health() { return Map.of("status", "ok"); }
    @PostMapping("/reservations") public InventoryUseCase.ReservationResult reserve(@RequestBody OrderPlaced order) {
        return inventory.reserve(order.orderId(), order.productId(), order.quantity(), "rest", order.requestedAt());
    }
    @ExceptionHandler(OutOfStockException.class) @ResponseStatus(HttpStatus.CONFLICT)
    Map<String,String> handleOutOfStock(OutOfStockException e) { return Map.of("error", e.getMessage()); }
    @ExceptionHandler(ProductNotFoundException.class) @ResponseStatus(HttpStatus.NOT_FOUND)
    Map<String,String> handleNotFound(ProductNotFoundException e) { return Map.of("error", e.getMessage()); }
    @ExceptionHandler(IllegalArgumentException.class) @ResponseStatus(HttpStatus.BAD_REQUEST)
    Map<String,String> handleInvalid(IllegalArgumentException e) { return Map.of("error", e.getMessage()); }
}

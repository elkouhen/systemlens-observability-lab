package io.systemlens.supermarket.inventory;

import io.systemlens.supermarket.contract.StockRestockRequested;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class KafkaStockRestockConsumer {

    private final ReservationService reservationService;

    public KafkaStockRestockConsumer(ReservationService reservationService) {
        this.reservationService = reservationService;
    }

    @KafkaListener(topics = "supermarket.stock.restock-requested", groupId = "inventory-restock-service")
    public void consume(StockRestockRequested request) {
        reservationService.restock(request.productId(), request.quantity());
    }
}

package io.systemlens.supermarket.inventory;

import io.systemlens.supermarket.contract.OrderPlaced;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

/** Traite les commandes en ligne, publiées de façon asynchrone par order-service. */
@Component
public class KafkaOrderConsumer {

    private final ReservationService reservationService;

    public KafkaOrderConsumer(ReservationService reservationService) {
        this.reservationService = reservationService;
    }

    @KafkaListener(topics = "supermarket.order.placed", groupId = "inventory-service")
    public void consume(OrderPlaced order) throws InterruptedException {
        reservationService.reserve(order.orderId(), order.productId(), order.quantity(), "kafka", order.requestedAt());
    }
}

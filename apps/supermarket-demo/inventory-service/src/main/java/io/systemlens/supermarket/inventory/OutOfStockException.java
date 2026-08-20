package io.systemlens.supermarket.inventory;

/** Levée quand la quantité demandée dépasse le stock disponible pour un produit. */
public class OutOfStockException extends RuntimeException {

    public OutOfStockException(String productId, int requested, int available) {
        super("Rupture de stock pour %s : %d demandé(s), %d disponible(s)".formatted(productId, requested, available));
    }
}

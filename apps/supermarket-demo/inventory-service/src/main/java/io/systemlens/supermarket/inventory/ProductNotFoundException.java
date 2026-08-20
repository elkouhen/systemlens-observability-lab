package io.systemlens.supermarket.inventory;

/** Levée quand le produit référencé dans une commande n'existe pas au catalogue. */
public class ProductNotFoundException extends RuntimeException {

    public ProductNotFoundException(String productId) {
        super("Produit introuvable au catalogue : " + productId);
    }
}

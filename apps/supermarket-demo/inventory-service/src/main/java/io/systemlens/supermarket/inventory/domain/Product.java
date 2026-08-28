package io.systemlens.supermarket.inventory.domain;

/** Produit et règles de variation du stock, indépendants de Spring. */
public final class Product {
    private final String id;
    private final String name;
    private int stockQuantity;

    public Product(String id, String name, int stockQuantity) {
        this.id = id;
        this.name = name;
        this.stockQuantity = stockQuantity;
    }

    public void reserve(int quantity) {
        if (stockQuantity < quantity) {
            throw new OutOfStockException(id, quantity, stockQuantity);
        }
        stockQuantity -= quantity;
    }

    public void restock(int quantity) {
        stockQuantity += quantity;
    }

    public String id() { return id; }
    public String name() { return name; }
    public int stockQuantity() { return stockQuantity; }
}

package io.systemlens.supermarket.inventory;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/** Article du catalogue du supermarché, avec son stock disponible en rayon/entrepôt. */
@Entity
@Table(name = "products")
public class Product {

    @Id
    private String id;
    private String name;
    private int stockQuantity;

    protected Product() {
    }

    public Product(String id, String name, int stockQuantity) {
        this.id = id;
        this.name = name;
        this.stockQuantity = stockQuantity;
    }

    public String getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public int getStockQuantity() {
        return stockQuantity;
    }

    public void setStockQuantity(int stockQuantity) {
        this.stockQuantity = stockQuantity;
    }
}

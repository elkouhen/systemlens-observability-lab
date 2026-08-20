package io.systemlens.supermarket.inventory;

import org.springframework.boot.CommandLineRunner;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Initialise le catalogue au démarrage si la base est vide, afin que la
 * démonstration dispose immédiatement de références en stock.
 */
@Component
public class CatalogSeeder implements CommandLineRunner {

    static final List<Product> CATALOG = List.of(
            new Product("PASTA-500G", "Pâtes penne 500g", 500),
            new Product("BREAD-WHOLE", "Pain de mie complet", 500),
            new Product("MILK-1L", "Lait demi-écrémé 1L", 500),
            new Product("COFFEE-250G", "Café moulu 250g", 500),
            new Product("EGGS-12", "Œufs plein air x12", 500)
    );

    private final ProductRepository productRepository;

    public CatalogSeeder(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    @Override
    public void run(String... args) {
        if (productRepository.count() == 0) {
            productRepository.saveAll(CATALOG);
        }
    }
}

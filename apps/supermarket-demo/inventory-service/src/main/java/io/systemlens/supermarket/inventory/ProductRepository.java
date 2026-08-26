package io.systemlens.supermarket.inventory;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;

import java.util.Optional;

public interface ProductRepository extends JpaRepository<Product, String> {

    @Override
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<Product> findById(String id);
}

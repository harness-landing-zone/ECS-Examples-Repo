package com.example.inventory;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@RestController
public class InventoryController {

    private static final List<Map<String, Object>> ITEMS = List.of(
            Map.of("id", 1, "name", "Widget", "quantity", 42),
            Map.of("id", 2, "name", "Gadget", "quantity", 17),
            Map.of("id", 3, "name", "Doohickey", "quantity", 5)
    );

    @GetMapping("/")
    public Map<String, String> root() {
        return Map.of("service", "inventory-service", "status", "running");
    }

    @GetMapping("/items")
    public List<Map<String, Object>> listItems() {
        return ITEMS;
    }

    @GetMapping("/items/{id}")
    public Map<String, Object> getItem(@PathVariable int id) {
        return ITEMS.stream()
                .filter(item -> (int) item.get("id") == id)
                .findFirst()
                .orElse(Map.of("error", "Item not found"));
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "UP");
    }
}

package io.systemlens.demo.frontend;

import co.elastic.apm.api.ElasticApm;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

@RestController
@RequestMapping("/api")
public class WorkController {

    private final RestTemplate restTemplate;
    @Value("${apm-demo.worker-url}")
    private String workerUrl;

    public WorkController(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "ok");
    }

    @GetMapping("/work")
    public WorkerResult work() {
        return restTemplate.getForObject(workerUrl + "/api/work", WorkerResult.class);
    }

    @GetMapping("/error")
    public void error() {
        throw new DemoException("Erreur contrôlée générée par apm-demo");
    }

    @ExceptionHandler(DemoException.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    Map<String, String> handleDemoException(DemoException exception) {
        ElasticApm.currentTransaction().captureException(exception);
        return Map.of("error", exception.getMessage());
    }

    record WorkerResult(String id, long result, String trigger, long durationMs) {
    }

    static class DemoException extends RuntimeException {
        DemoException(String message) {
            super(message);
        }
    }
}

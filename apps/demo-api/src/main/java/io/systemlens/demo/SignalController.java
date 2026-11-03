package io.systemlens.demo;

import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.StatusCode;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * Points d'entrée HTTP, un par type de signal à démontrer. La logique est
 * dans {@link SignalService} ; ce contrôleur reste fin.
 */
@RestController
public class SignalController {

    private final SignalService service;

    public SignalController(SignalService service) {
        this.service = service;
    }

    /** Sonde de santé des probes Kubernetes. */
    @GetMapping("/api/health")
    public Map<String, String> health() {
        return Map.of("status", "ok");
    }

    /** Transaction simple : une trace, un log INFO avec attributs, un compteur. */
    @GetMapping("/api/hello")
    public Map<String, String> hello(@RequestParam(defaultValue = "lab") String name) {
        return Map.of("message", service.greet(name));
    }

    /** Travail simulé : un timer Micrometer et un span interne dont la durée varie. */
    @GetMapping("/api/work")
    public Map<String, Object> work(@RequestParam(defaultValue = "200") long ms) {
        return Map.of("durationMs", service.work(ms));
    }

    /** Appel sortant vers sa propre API : une trace distribuée sur deux transactions. */
    @GetMapping("/api/chain")
    public Map<String, String> chain(@RequestParam(defaultValue = "lab") String name) {
        return Map.of("message", service.chain(name));
    }

    /** Erreur contrôlée : log ERROR avec pile, transaction en échec et erreur APM. */
    @GetMapping("/api/fail")
    public Map<String, String> fail(@RequestParam(defaultValue = "demo") String reason) {
        service.fail(reason);
        return Map.of("message", "unreachable");
    }

    /**
     * L'exception étant traitée ici, elle n'atteint pas l'instrumentation
     * servlet de l'agent : elle est enregistrée sur le span courant pour
     * produire l'erreur APM et marquer la transaction en échec.
     */
    @ExceptionHandler(SignalService.DemoFailureException.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    Map<String, String> handleFailure(SignalService.DemoFailureException exception) {
        Span span = Span.current();
        span.recordException(exception);
        span.setStatus(StatusCode.ERROR, exception.getMessage());
        return Map.of("error", exception.getMessage());
    }
}

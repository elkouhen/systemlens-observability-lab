package io.systemlens.demo;

import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.metrics.LongCounter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.servlet.HandlerMapping;

/**
 * Métrique applicative {@code demo_api.calls} : nombre d'appels de l'API,
 * par {@code outcome} ({@code ok} si le statut HTTP est inférieur à 400 et
 * qu'aucune exception ne remonte, {@code ko} sinon) et par {@code http.route}.
 * L'agent Java OTel exporte le compteur avec les métriques JVM.
 */
@Component
public class CallMetricsFilter extends OncePerRequestFilter {

    private static final AttributeKey<String> OUTCOME = AttributeKey.stringKey("outcome");
    private static final AttributeKey<String> ROUTE = AttributeKey.stringKey("http.route");

    private final LongCounter calls;

    public CallMetricsFilter(OpenTelemetry openTelemetry) {
        this.calls = openTelemetry.getMeter("io.systemlens.demo")
            .counterBuilder("demo_api.calls")
            .setDescription("Appels de demo-api par résultat (ok, ko)")
            .setUnit("{call}")
            .build();
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/api/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
            FilterChain chain) throws ServletException, IOException {
        boolean ok = false;
        try {
            chain.doFilter(request, response);
            ok = response.getStatus() < 400;
        } finally {
            Object route = request.getAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE);
            calls.add(1, Attributes.of(
                OUTCOME, ok ? "ok" : "ko",
                ROUTE, route != null ? route.toString() : "unmatched"));
        }
    }
}

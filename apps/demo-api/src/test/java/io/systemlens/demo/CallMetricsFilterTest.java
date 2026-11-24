package io.systemlens.demo;

import static io.opentelemetry.sdk.testing.assertj.OpenTelemetryAssertions.assertThat;
import static io.opentelemetry.sdk.testing.assertj.OpenTelemetryAssertions.equalTo;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.metrics.SdkMeterProvider;
import io.opentelemetry.sdk.metrics.data.MetricData;
import io.opentelemetry.sdk.testing.exporter.InMemoryMetricReader;
import java.util.Collection;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(HelloController.class)
@Import({CallMetricsFilter.class, CallMetricsFilterTest.InMemoryOpenTelemetry.class})
class CallMetricsFilterTest {

    private static final AttributeKey<String> OUTCOME = AttributeKey.stringKey("outcome");
    private static final AttributeKey<String> ROUTE = AttributeKey.stringKey("http.route");

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private InMemoryMetricReader metricReader;

    @Test
    void countsSuccessfulAndFailedCalls() throws Exception {
        mockMvc.perform(get("/api/hello").param("name", "lab")).andExpect(status().isOk());
        mockMvc.perform(get("/api/hello")).andExpect(status().isOk());
        assertThatThrownBy(() -> mockMvc.perform(get("/api/fail")))
            .hasRootCauseInstanceOf(HelloController.DemoFailureException.class);

        Collection<MetricData> metrics = metricReader.collectAllMetrics();
        assertThat(metrics).anySatisfy(metric -> assertThat(metric)
            .hasName("demo_api.calls")
            .hasUnit("{call}")
            .hasLongSumSatisfying(sum -> sum.isMonotonic().hasPointsSatisfying(
                point -> point.hasValue(2).hasAttributesSatisfyingExactly(
                    equalTo(OUTCOME, "ok"),
                    equalTo(ROUTE, "/api/hello")),
                point -> point.hasValue(1).hasAttributesSatisfyingExactly(
                    equalTo(OUTCOME, "ko"),
                    equalTo(ROUTE, "/api/fail")))));
    }

    @TestConfiguration
    static class InMemoryOpenTelemetry {

        @Bean
        InMemoryMetricReader metricReader() {
            return InMemoryMetricReader.create();
        }

        @Bean
        @Primary
        OpenTelemetry inMemoryOpenTelemetry(InMemoryMetricReader metricReader) {
            return OpenTelemetrySdk.builder()
                .setMeterProvider(SdkMeterProvider.builder().registerMetricReader(metricReader).build())
                .build();
        }
    }
}

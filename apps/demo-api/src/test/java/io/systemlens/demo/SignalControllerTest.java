package io.systemlens.demo;

import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import io.micrometer.core.instrument.MeterRegistry;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest(properties = "demo-api.heartbeat-ms=3600000")
@AutoConfigureMockMvc
class SignalControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private MeterRegistry registry;

    @Test
    void helloAnswersAndCounts() throws Exception {
        mockMvc.perform(get("/api/hello").param("name", "test"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.message").value("Bonjour test"));
        org.assertj.core.api.Assertions.assertThat(
                registry.get("demo.requests").tag("endpoint", "hello").counter().count())
            .isGreaterThanOrEqualTo(1);
    }

    @Test
    void workRecordsTimer() throws Exception {
        mockMvc.perform(get("/api/work").param("ms", "20"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.durationMs").isNumber());
        org.assertj.core.api.Assertions.assertThat(registry.get("demo.work.duration").timer().count())
            .isGreaterThanOrEqualTo(1);
    }

    @Test
    void failReturnsControlledError() throws Exception {
        mockMvc.perform(get("/api/fail").param("reason", "test"))
            .andExpect(status().isInternalServerError())
            .andExpect(jsonPath("$.error").value(containsString("test")));
    }

    @Test
    void healthIsOk() throws Exception {
        mockMvc.perform(get("/api/health"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.status").value("ok"));
    }
}

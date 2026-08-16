package io.systemlens.demo.contract;

import java.time.Instant;

/** Message publié par le déclencheur planifié de la façade. */
public record WorkRequested(String requestId, Instant requestedAt) {
}

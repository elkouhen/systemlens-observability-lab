# Microservices architecture audit

## Audit scope

This review applies the `microservices-architect` checks to the persisted
SystemLens model of the supermarket-demo lab. It does not replace the indexed
facts with inferred runtime behavior.

SystemLens reports:

- 3 services: `order-service`, `inventory-service`, and `restock-service`;
- 3 Kafka Topics and 10 persisted topology edges;
- 5 potential call flows, with 3 medium-confidence and 2 low-confidence flows;
- 3 root flows, no persisted cycle flows, and complete endpoint reconciliation;
- 5 Maven dependency edges, including shared `supermarket-contracts` and
  `kafka-processing` modules.

## Architecture model

```text
order-service
  ├─ REST POST /api/reservations ───────────────> inventory-service
  └─ Kafka supermarket.order.placed
       ├────────────────────────────────────────> inventory-service
       └────────────────────────────────────────> restock-service (observer)

inventory-service
  ├─ Kafka supermarket.stock.depleted ─────────> restock-service
  ├─ JPA: Product and StockMovement
  └─ Mongo: OrderFulfillment

restock-service
  └─ Kafka supermarket.stock.restock-requested ─> inventory-service
```

The model has clear business capabilities, but the stock lifecycle crosses the
inventory and restock boundaries in both directions. The shared contracts are
technical integration dependencies, not proof of shared business data.

## Findings

### High: resilience controls are not visible on the synchronous service call

The indexed REST edge is `order-service -> inventory-service` through
`POST /api/reservations`. `OrderServiceApplication` creates a plain
`RestTemplate` from `RestTemplateBuilder`, and the lab configuration does not
declare a connect timeout, read timeout, retry budget, circuit breaker, or
fallback for this call.

Evidence:

- `order-service/src/main/java/io/systemlens/supermarket/order/OrderServiceApplication.java:17-20`
- `order-service/src/main/java/io/systemlens/supermarket/order/OrderController.java:41-70`
- `order-service/src/main/resources/application.yml:4-7`
- SystemLens topology edge `order-service -> inventory-service`,
  `POST /api/reservations`.

Impact: an unavailable or slow inventory service can block the order request
and propagate failure to the caller. The current `OutOfStockException` handler
is a business-error mapping, not a network-failure resilience strategy.

Recommendation: define an explicit timeout budget first, then choose a bounded
retry policy for safe failures and a circuit breaker or graceful degradation
behavior. Do not retry a reservation without an idempotency decision.

**Confidence:** high for the visible configuration gap; runtime defaults and
external infrastructure policies were not inspected.

### High: the data strategy uses polyglot persistence inside one use case

`inventory-service` owns the stock state in JPA and stores fulfillment data in
MongoDB. `InventoryApplicationService.reserve` updates the product, writes the
fulfillment document, writes the stock movement, and may publish a Kafka event
inside one `@Transactional` application method.

Evidence:

- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/application/InventoryApplicationService.java:72-118`
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/out/persistence/jpa/ProductPersistenceAdapter.java:10-19`
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/out/persistence/mongodb/OrderFulfillmentPersistenceAdapter.java:8-14`
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/out/messaging/KafkaStockDepletedAdapter.java:8-14`
- `inventory-service/src/main/resources/application.yml:4-18`

Impact: the service has a coherent ownership boundary, but the consistency
boundary spans JPA, MongoDB, and Kafka. The lab does not show an outbox or an
explicit cross-resource transaction coordinator. A partial failure can require
reconciliation between stock, fulfillment history, movement history, and the
depletion event.

Recommendation: document the consistency model and choose one mechanism for
recovery, such as an outbox plus reconciliation, or an explicitly accepted
eventual-consistency workflow with idempotent consumers.

**Confidence:** high for the multi-resource path; medium for the failure mode
because transaction-manager behavior is not represented in the model.

### High: the stock bounded context has a bidirectional protocol

SystemLens shows `inventory-service -> restock-service` through
`supermarket.stock.depleted` and the reverse edge through
`supermarket.stock.restock-requested`. This is a business protocol across two
services, not just a technical dependency.

Evidence:

- SystemLens JSON export: 10 topology edges, including both Kafka directions.
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/out/messaging/KafkaStockDepletedAdapter.java:12-13`
- `restock-service/src/main/java/io/systemlens/supermarket/restock/StockDepletedConsumer.java:35-46`
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/in/messaging/KafkaStockRestockConsumer.java:17-25`

Impact: the services cannot evolve their stock lifecycle independently without
coordinating message schemas, retries, duplicate handling, and terminal states.
The topology is not a persisted call-graph cycle, but it is a bidirectional
coupling that can become a distributed monolith if more state transitions are
added to both sides.

Recommendation: assign ownership for each stock state, document the protocol as
a state machine, and keep restock commands or events idempotent. Add a test for
duplicate depletion and restock messages.

**Confidence:** high for the topology and source declarations.

### Medium: the communication model mixes command, event, and observation roles

The same `supermarket.order.placed` Topic is consumed by `inventory-service` to
reserve stock and by `restock-service` to record an observation metric. The
scheduled publisher in `order-service` therefore fans out to two consumers with
different responsibilities.

Evidence:

- `order-service/src/main/java/io/systemlens/supermarket/order/ScheduledOrderPublisher.java:33-40`
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/in/messaging/KafkaOrderConsumer.java:17-25`
- `restock-service/src/main/java/io/systemlens/supermarket/restock/OrderPlacedConsumer.java:27-38`
- SystemLens topology edge list for `supermarket.order.placed`.

Impact: schema evolution and retention decisions have different consequences
for a business consumer and an observability consumer. The event name describes
something that happened, but the inventory consumer treats it as a command to
reserve stock.

Recommendation: document the event as an integration contract and separate
business-trigger semantics from observation semantics. Consider distinct
events if their ownership, retention, or compatibility requirements diverge.

**Confidence:** high.

### Medium: call-flow coverage is insufficient for end-to-end validation

SystemLens persists five local potential flows but reports zero global flows in
the flow diagnostic. The model can connect local entry points to local effects
and render topology edges, but it cannot yet prove the complete order-to-stock-
depletion-to-restock path in one call graph.

Evidence:

- `systemlens flows list --json`
- `systemlens analyze flows-diagnostic --json`
- `systemlens analyze indexing-audit --json`

Impact: service-boundary and resilience recommendations can be made from the
topology, but end-to-end change impact remains partly inferred. The two
low-confidence flows also pass through generic Kafka processing and interface
dispatch.

Recommendation: repair the global flow composition before treating the HTML
call graph as a complete execution model. Keep potential, confidence, and
reconciliation status visible in the export.

**Confidence:** high for the diagnostic result.

### Medium: observability is strong on metrics but incomplete for distributed tracing

The three services expose health, Prometheus, HTTP latency percentiles, and
Kafka processing metrics. The indexed application code does not expose a
correlation ID or trace-context propagation across the REST call and Kafka
messages.

Evidence:

- `order-service/src/main/resources/application.yml:24-46`
- `inventory-service/src/main/resources/application.yml:25-48`
- `restock-service/src/main/resources/application.yml:17-40`
- `inventory-service/src/main/java/io/systemlens/supermarket/messaging/AbstractKafkaMessageProcessor.java:23-34`

Impact: the lab can measure service and consumer behavior, but one order may be
hard to follow across REST, Kafka, and persistence logs without infrastructure-
level tracing not represented in the application model.

Recommendation: propagate a correlation or trace identifier in HTTP headers and
Kafka headers, and include it in structured logs and business metrics.

**Confidence:** medium because external OpenTelemetry configuration may provide
part of this behavior outside the application source.

## Validation matrix

| Skill checkpoint | Result | Evidence or gap |
|---|---|---|
| Clear service capabilities | Partial pass | Order, inventory, and restock responsibilities are recognizable |
| Independent data ownership | Pass with caution | Inventory owns JPA and Mongo stores; cross-store consistency needs a decision |
| Explicit communication choice | Partial pass | REST and Kafka are visible, but timeout and retry policies are not |
| Failure and graceful degradation | Gap | No application-level timeout, circuit breaker, retry budget, or fallback is visible |
| End-to-end observability | Partial pass | Metrics and health are visible; correlation propagation is not visible |
| Complete call-graph validation | Gap | 5 local flows, 0 global flows |
| Independent service evolution | Partial pass | Shared contracts and bidirectional stock protocol require coordination |

## Priority actions

1. Define timeout, retry, circuit-breaker, and idempotency policies for
   `order-service -> inventory-service`.
2. Choose the consistency and recovery mechanism for JPA, MongoDB, and Kafka
   effects in `reserve`.
3. Document and test the bidirectional stock state machine, including duplicate
   messages and consumer recovery.
4. Complete global SystemLens flow composition for the order and restock paths.
5. Add correlation propagation across HTTP and Kafka, then verify one order can
   be traced end to end.

## Limits

This audit is based on the persisted SystemLens model and the source evidence
needed to interpret its edges. It does not establish runtime traffic, latency,
deployment scaling, Kafka delivery guarantees, broker retry behavior, or
transaction-manager semantics. Recommendations from the
`microservices-architect` skill are review criteria, not facts about the
running system.

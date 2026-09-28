# Architecture complexity audit

## Executive summary

The most important complexity in this POC is not the number of services. It is
the way one stock reservation crosses several execution and consistency
boundaries. `InventoryApplicationService.reserve` is called through REST and
Kafka, updates JPA and Mongo persistence, records metrics, and can publish a
Kafka event before the surrounding transaction completes. The restock loop
then sends another Kafka message back to `inventory-service`.

This creates three architecture questions worth resolving: how the database
changes and Kafka publication remain consistent, how duplicate messages are
handled, and which service owns the stock lifecycle. The indexed call graph
supports the local paths, but it currently does not compose them into complete
cross-service flows.

## The critical scenario

The POC has two entry paths into the same reservation operation:

```text
POST /api/orders
  order-service.OrderController.placeOrder
    -> POST /api/reservations
      inventory-service.InventoryController.reserve
        -> InventoryApplicationService.reserve

scheduled order
  -> supermarket.order.placed
       -> inventory-service.KafkaOrderConsumer
         -> InventoryApplicationService.reserve
       -> restock-service.OrderPlacedConsumer
```

Inside `reserve`, the application service performs this sequence:

```text
ProductRepository.findById
  -> Product.reserve
  -> ProductRepository.save                 [JPA]
  -> OrderFulfillmentPort.save              [Mongo]
  -> StockMovementPort.save                 [JPA]
  -> metrics
  -> StockDepletedPort.publish, when stock reaches zero [Kafka]
```

The depletion path continues as follows:

```text
supermarket.stock.depleted
  -> restock-service.StockDepletedConsumer
    -> supermarket.stock.restock-requested
      -> inventory-service.KafkaStockRestockConsumer
        -> InventoryApplicationService.restock
          -> ProductRepository.save             [JPA]
```

These paths are source-backed potential paths. They are not runtime traces.

## Findings

### HIGH: One transaction boundary covers several independent effects

`InventoryApplicationService.reserve` is annotated `@Transactional`, then
updates a JPA product, writes Mongo fulfillment data, writes a JPA stock
movement, and publishes Kafka when the stock reaches zero.

Evidence:

- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/application/InventoryApplicationService.java:72-118`
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/out/persistence/jpa/ProductPersistenceAdapter.java:10-19`
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/out/persistence/jpa/StockMovementPersistenceAdapter.java:8-13`
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/out/persistence/mongodb/OrderFulfillmentPersistenceAdapter.java:8-14`
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/out/messaging/KafkaStockDepletedAdapter.java:8-14`

The code shows the effects inside one application operation, but the indexed
repository does not show an outbox or an explicit transaction coordinator for
JPA, Mongo, and Kafka. A failure or retry can therefore leave the business
state, audit documents, stock movements, and emitted event with different
outcomes unless the runtime configuration supplies guarantees not visible in
this POC.

Decision to clarify: choose and document the consistency model. The options
are an outbox for Kafka publication, an explicit distributed transaction
strategy, or an accepted eventual-consistency model with reconciliation.

**Confidence:** high for the observed multi-effect operation; medium for the
failure consequence because runtime transaction configuration was not present
in the indexed source.

### HIGH: The stock lifecycle is split across two services with a return edge

`inventory-service` publishes `supermarket.stock.depleted` to
`restock-service`. `restock-service` publishes
`supermarket.stock.restock-requested` back to `inventory-service`.

Evidence:

- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/out/messaging/KafkaStockDepletedAdapter.java:12-13`
- `restock-service/src/main/java/io/systemlens/supermarket/restock/StockDepletedConsumer.java:35-46`
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/in/messaging/KafkaStockRestockConsumer.java:17-25`
- `inventory-service/src/main/resources/static/asyncapi.yaml:36-81`

This is not a materialized call-graph cycle, because the restock operation does
not publish another depletion event in the indexed flow. It is nevertheless a
bidirectional business protocol. A change to stock state, event schema,
consumer retry, or restock quantity crosses both services.

Decision to clarify: identify the owner of the stock lifecycle and define the
protocol states, duplicate handling, retry policy, and expected terminal state.
The current source creates a new restock request for each depletion message and
does not expose an idempotency check in the consumer.

**Confidence:** high for the two Kafka directions; medium for duplicate-message
risk until the broker delivery and consumer configuration are reviewed.

### HIGH: `reserve` hides two business channels behind one use case

The HTTP adapter calls `reserve(..., "rest", ...)`, while the Kafka consumer
calls `reserve(..., "kafka", ...)`. The same method then writes fulfillment and
movement records, changes stock, emits metrics, and may publish depletion.

Evidence:

- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/in/web/InventoryController.java:28-34`
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/in/messaging/KafkaOrderConsumer.java:22-25`
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/application/InventoryApplicationService.java:73-118`

This is a useful shared business invariant, but it also means that a change
made for synchronous checkout can alter asynchronous order processing. The
`channel` value changes metrics and persisted movement data, so the two paths
are not merely transport variants.

Decision to clarify: keep one reservation policy or split channel-specific
orchestration around a shared domain operation. In either case, test the REST
and Kafka paths independently and verify that their transaction and failure
semantics are intentional.

**Confidence:** high.

### MEDIUM: The order event has two different meanings for two consumers

`supermarket.order.placed` is consumed by `inventory-service` to reserve stock
and by `restock-service` only to record an observation metric.

Evidence:

- `order-service/src/main/java/io/systemlens/supermarket/order/ScheduledOrderPublisher.java:33-40`
- `inventory-service/src/main/java/io/systemlens/supermarket/inventory/adapter/in/messaging/KafkaOrderConsumer.java:17-25`
- `restock-service/src/main/java/io/systemlens/supermarket/restock/OrderPlacedConsumer.java:27-38`
- `systemlens export microservices --json`

The event is therefore both a business trigger and an observability input. Its
retention, schema, and delivery changes have different consequences for each
consumer. The observer must not accidentally become a business dependency.

Decision to clarify: document the event intent and consumer roles separately,
or split the business command from the observation event if their lifecycles
diverge.

**Confidence:** high.

### MEDIUM: The error endpoint is a deliberate cross-service test path

`GET /api/error` constructs an intentionally impossible reservation and calls
`inventory-service`. A downstream client error is then converted into a 500
response by `order-service`.

Evidence:

- `order-service/src/main/java/io/systemlens/supermarket/order/OrderController.java:55-75`
- `systemlens flows show be313b1390914440 --json`

This endpoint is useful for observability demonstrations, but it introduces a
diagnostic path into the public API model and couples the test scenario to the
inventory error contract. It also makes the topology look like a normal order
flow unless the endpoint is explicitly classified.

Decision to clarify: keep the endpoint as a documented demo probe, or move it
behind a test profile and exclude it from the production API contract.

**Confidence:** high.

### MEDIUM: The current graph cannot yet prove the end-to-end scenario

SystemLens persists five local potential flows, all with complete endpoint
reconciliation, but the flow diagnostic reports zero global flows. Four entries
are classified as `global_composition_gap`, including the REST order path and
the Kafka continuations.

Evidence:

- `systemlens flows list --json`
- `systemlens analyze flows-diagnostic --json`
- `systemlens analyze indexing-audit --json`

This is primarily an analysis coverage problem, not an application defect. It
means the HTML graph can show the individual paths and topology edges, but it
cannot currently prove one complete path from order creation to stock
depletion and restock.

Decision to clarify: repair the global flow join before using the graph for
end-to-end change-impact claims. Keep the current potential flows qualified.

**Confidence:** high for the diagnostic result.

## Change-impact hotspots

| Change | Directly affected | Hidden propagation |
|---|---|---|
| Change `OrderPlaced` | `order-service`, `inventory-service`, `restock-service`, shared contracts | Reservation and observation consumers can diverge |
| Change reservation rules | REST checkout and scheduled Kafka orders | JPA stock, Mongo fulfillment, JPA movement, metrics, depletion event |
| Change stock-depletion event | `inventory-service`, `restock-service` | Restock request and inventory state recovery |
| Change restock quantity or policy | `restock-service`, inventory consumer | Product JPA state and future depletion behavior |
| Change Mongo or JPA persistence | inventory-service | Reservation success can disagree with audit or movement state |

## Priority actions

1. Add a test that exercises the complete depletion and restock protocol,
   including duplicate delivery of each Kafka message.
2. Decide whether Kafka publication is protected by an outbox or explicitly
   accepted as eventual consistency with reconciliation.
3. Document the stock state machine and ownership between inventory and
   restock services.
4. Repair the SystemLens global-flow composition so the HTML view can represent
   the complete order-to-restock scenario.
5. Classify `GET /api/error` as a demo-only diagnostic endpoint.

## Limits

This audit cannot establish runtime traffic, latency, deployment scaling,
feature-flag routing, Kafka delivery guarantees, retry configuration,
transaction-manager behavior, or actual duplicate delivery. The source-backed
paths remain potential flows. The persistence consistency finding is a design
question to validate, not a claim that production data corruption occurs.

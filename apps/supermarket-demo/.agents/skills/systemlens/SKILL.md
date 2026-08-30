---
name: systemlens
description: "Guide architecture-first exploration of a repository with SystemLens. Use when asked to index code, inspect or enrich services, HTTP APIs, data schemas, message channels, build modules, dependencies, unresolved facts, or architecture exports."
---

# systemlens Architecture Explorer

Use `systemlens` to query a local, persisted Java/Spring architecture inventory.
Start with the inventory before inspecting implementation files. It describes
services, modules, HTTP APIs, data schemas, message channels and their
evidenced relationships. MongoDB collections and Kafka topics are concrete
technology views of the generic schema/channel vocabulary.

## Documentation language

Write user-facing documentation, generated report text, architecture labels
and examples in French, and correct spelling, grammar and accents before
delivering them. Preserve exact CLI output, source snippets and user-provided
text when quoting them.

## Ownership

Work from the target repository root. Own the `systemlens` lifecycle for that
project.

- Run `systemlens doctor` before drawing broad architectural conclusions.
- If configuration is missing, run `systemlens init`; never overwrite an existing
  `.systemlens/config.yml`.
- If the index is absent or source/configuration changed, run `systemlens index`
  before querying. Use `systemlens index --full` after a broad refactor or an
  extractor upgrade.
- Treat `systemlens` as static, source-evidenced analysis. Keep dynamic,
  ambiguous and unresolved integrations explicit; do not infer a dependency from
  a coincidental route or a topic name.

## Setup

For a fresh project:

```bash
systemlens init
systemlens doctor
systemlens index
```

The configuration controls the indexed source perimeter. See
[settings.md](references/settings.md) only when the perimeter must change.

## Architecture workflow

Start with the indexed architecture and retrieve source evidence only when needed:

1. `systemlens microservices` — discover services and main integrations.
2. `systemlens microservices show <name>` — inspect one service.
3. `systemlens microservices topics <name>`, `apis <name>` or `mongodb <name>` —
   follow linked objects.
4. `systemlens topics`, `systemlens apis`, `systemlens dtos` or
   `systemlens mongodb` — inspect a shared object from the other direction.
5. `systemlens analyze coverage` and `systemlens analyze indexing-issues` —
   identify inventory limits before relying on a conclusion.
6. `systemlens analyze audit` — assess static topology risks.
7. `systemlens analyze microservices impact <name>` or `path <source> <target>` —
   inspect dependencies and impact paths.

```bash
systemlens microservices show order-service
systemlens topics consumers orders.created
systemlens apis consumers 'POST /payments'
systemlens mongodb services orders
systemlens modules show shared-domain
systemlens analyze coverage
systemlens analyze indexing-issues
systemlens analyze audit
```

Kafka message types are shown only when explicit in the source. A missing type
is unknown, not an invitation to infer it from a topic name or serializer.

## Simple AI-assisted graph workflow

Use this path when the goal is simply to analyse one directory and obtain a
graph, including repositories whose conventions are not covered by the
deterministic extractors:

1. Set `PROJECT_ROOT` to the repository being analysed and run the normal
   SystemLens baseline (`doctor`, `init` if needed, then `index`). Keep
   Strategy1 opt-in; do not enable it unless the repository follows the rules
   in [analysis-rules.md](references/analysis-rules.md).
2. Inspect the repository source, configuration and manifests as an analysis
   agent. Produce `PROJECT_ROOT/architecture.ai-graph.json` using the
   `systemlens-ai-graph-v1` contract. Use relative evidence paths, stable IDs,
   and keep uncertain convention matches as `ambiguous` or `unresolved`.
3. Prefer the MCP enrichment workflow after indexing: call
   `graph_fact_exists` before every proposed node or edge, then call
   `add_graph_fact` only when `exists` is false. Use `confidence`, relative
   `evidence_path` and `note`, review with `list_graph_facts`, and remove only
   MCP assertions with `remove_graph_fact`.
   Use `kind=data_schema` or `kind=message_channel` plus `technology` for
   middleware not covered by the built-in extractors (for example SQL, Redis,
   RabbitMQ or SQS); keep provider-specific details in `metadata`.
4. Read the merged result with `architecture_graph`. A later
   `index_repository` refresh preserves the enrichment layer.
5. For a portable file-based handoff, import the analysis artifact into
   SystemLens's HTML renderer:

   ```bash
   cd "$PROJECT_ROOT"
   systemlens export microservices \
     --graph architecture.ai-graph.json \
     --html architecture.html \
     --root-path "$PROJECT_ROOT"
   ```

6. Open `architecture.html`. Confirmed and proposed relations are drawn;
   ambiguous and unresolved claims are available in the Quality panel. This
   import is read-only: it does not merge AI claims into `.systemlens/` or
   replace the deterministic inventory.

An agent can use this prompt as a bounded starting point:

> Analyse the code and configuration under this directory. First identify
> services, external systems, event topics, HTTP routes and data stores. Then
> write `architecture.ai-graph.json` in `systemlens-ai-graph-v1` format. Keep
> all evidence paths relative to the directory, include short reasons for
> ambiguous or unresolved relationships, and do not guess dynamic targets.
> Finally run `systemlens export microservices --graph architecture.ai-graph.json
> --html architecture.html --root-path .`.

Use `--json` when a downstream step needs structured results. The current MCP
surface is intentionally focused on the index/enrich workflow: call
`index_repository`, then `architecture_graph` for the complete dependency
graph. The returned graph includes legacy API, MongoDB collection and Kafka
associations as well as generic schema/channel facts.

For the complete extraction contract, including supported Java/Spring forms,
dynamic-value handling, exact REST target resolution, Kafka matching,
module/OpenAPI attribution, MongoDB evidence and Strategy1 conventions, read
[analysis-rules.md](references/analysis-rules.md). Never enable Strategy1 just
to force an expected edge; verify the repository convention first.

When the repository follows the documented `getTopics()` and
`${kafka.topics.*.name}` conventions, use the explicit strategy:

```bash
systemlens index --topic-strategy strategy1
```

It may derive convention-based Kafka and configured HTTP dependencies. Treat
these as convention-derived facts and inspect their source evidence. Do not
enable this strategy solely to make an expected relation appear.

For the Strategy1 OpenAPI publication convention, a declaration at
`src/main/resources/openapi/xxx.rest` can publish valid same-named contracts
anywhere in the repository. It also publishes every valid YAML or JSON OpenAPI
contract under `model-xxx/src/main/resources/openapi/`; contract file names do
not need to match `xxx`. Reindex with `--full --topic-strategy strategy1` after
adding or moving a declaration or shared contract.

Every build module independently inventories all valid YAML or JSON OpenAPI
documents under its own `src/main/resources/openapi/` directory. Contract file
names do not need to be `openapi.*` or `swagger.*`.

## Runtime APM investigation

When read-only Elasticsearch access is configured and the user needs observed
runtime service dependencies, errors, or latency, export a bounded APM digest:

```bash
systemlens apm doctor --json
systemlens apm export --since 1h --environment production --out apm-digest.json
```

Configure `SYSTEMLENS_ELASTICSEARCH_URL` and
`SYSTEMLENS_ELASTICSEARCH_API_KEY` in the shell; do not put credentials in a
command, report, or prompt. The digest contains `service_destination` metric
aggregates only, never raw spans or request data. It is a one-shot observed
dataset: it is not persisted in the SystemLens index, surfaced through MCP, or
evidence for a static source relationship. Check `coverage` before treating an
absent relation as conclusive, because the aggregation and export are bounded.

For a human performance investigation, produce the explicit runtime report
instead of asking an agent to interpret raw APM events:

```bash
systemlens apm report --since 1h --environment production --html apm-runtime.html
```

The report ranks service and transaction tail latency with average and P95 and
provides an interactive directed service map. Circle nodes are observed
services; diamond nodes are observed messaging targets. Arrows go from source
service to target, are labelled HTTP or `send`, and carry volume and aggregate
risk styling. A messaging target is not claimed to be a confirmed broker topic.
Selecting a service reveals its HTTP (`request` or `http`), messaging
(`messaging`), and other transaction aggregates plus inbound and outbound
dependencies. The map does not claim that a transaction called a dependency;
that would require a separately approved sampled-span aggregate. Dependency P95
is intentionally unavailable in this first pass.
The report contains aggregates and a bounded Timeline projection of recorded
transaction fields. It never includes `_source`, trace IDs, request data,
headers, bodies, logs, or error messages. It is observed runtime context, not
evidence of a static source relationship; review its window and coverage before
drawing conclusions.
Its interactive graph reuses the Graphology/Sigma.js CDN assets of the
architecture export and retains an embedded SVG fallback when they are offline.

## Exports and MCP

```bash
systemlens export microservices --html architecture.html
systemlens export microservices --c4 likec4-project
systemlens export modules --html module-dependencies.html
systemlens mcp
```

When deterministic extraction cannot resolve repository-specific conventions,
have the analysis agent produce a `systemlens-ai-graph-v1` manifest and render
it without changing the persisted index:

```bash
systemlens export microservices --graph architecture.ai-graph.json --html architecture.html --root-path /path/to/checkout
```

The manifest must keep source evidence relative, include confidence and
`confirmed`/`proposed`/`ambiguous`/`unresolved` status on every claim, and give
an explicit reason for unresolved claims. SystemLens draws confirmed and
proposed claims and puts ambiguous or unresolved claims in the Quality panel;
it never turns an AI guess into persisted source topology. See
[ai-graph.md](references/ai-graph.md) for the full contract and example.

Exports consume the persisted snapshot; refresh the index deliberately when
source changes must be reflected. Use `--root-path` only to resolve local source
links at HTML export time.

The MCP server is intentionally a control surface for the two-phase workflow:
call `index_repository` first, then call `graph_fact_exists` before enriching
with `add_graph_fact` using `fact_type=node` or `fact_type=edge`. The add
operation rejects semantic duplicates atomically, so this remains safe when
multiple agents work on the same repository. Use `architecture_graph` for the
merged generic graph. `remove_graph_fact` never deletes source-derived facts;
it only removes an assertion previously added through MCP.

For a data resource, use `kind=data_schema` and set `technology` to
`mongodb`, `postgresql`, `redis`, `s3`, or another provider. For messaging,
use `kind=message_channel` and set `technology` to `kafka`, `rabbitmq`, `sqs`,
or another provider. Put provider-specific identifiers in `metadata`, for
example `{database, schema, table}` or `{exchange, queue}`. Use edge kinds
such as `provides`, `calls`, `reads`, `writes`, `publishes`, and `consumes`.

## References

- [settings.md](references/settings.md): project configuration.
- [analysis-rules.md](references/analysis-rules.md): deterministic extraction,
  conservative resolution and Strategy1 rules.
- [ai-graph.md](references/ai-graph.md): versioned AI-produced graph manifests.
- [management.md](references/management.md): installation, refresh and
  troubleshooting.

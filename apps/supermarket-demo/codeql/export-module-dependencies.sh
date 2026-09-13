#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="$(mktemp -d "${TMPDIR:-/tmp}/systemlens-codeql.XXXXXX")"
trap 'rm -rf "$workspace"' EXIT

database="$workspace/database"
results="$workspace/module-dependencies.bqrs"
decoded="$workspace/module-dependencies.json"
graph="$project_root/architecture.codeql-module-dependencies.json"
inventory="$project_root/architecture.application-inventory.json"

codeql database create "$database" --language=java --build-mode=none --source-root="$project_root"
codeql query run "$project_root/codeql/ModuleDependencies.ql" --database "$database" --output "$results"
codeql bqrs decode "$results" --format=json --output "$decoded"

jq --arg revision "$(git -C "$project_root" rev-parse HEAD)" '
  def module_name: split("/")[0];
  {
    format: "codeql-module-dependencies-v1",
    project: "supermarket-demo",
    generated_by: {
      tool: "CodeQL",
      analysis: "Imports Java résolus vers le module Maven partagé supermarket-contracts.",
      source_revision: $revision
    },
    nodes: [
      {id: "order-service", kind: "module", name: "order-service"},
      {id: "inventory-service", kind: "module", name: "inventory-service"},
      {id: "restock-service", kind: "module", name: "restock-service"},
      {id: "supermarket-contracts", kind: "module", name: "supermarket-contracts"}
    ],
    edges: [
      .["#select"].tuples
      | group_by(.[0] | module_name)[]
      | {
          id: ((.[0][0] | module_name) + "-depends-on-supermarket-contracts"),
          source: (.[0][0] | module_name),
          target: "supermarket-contracts",
          kind: "compile_time",
          status: "confirmed",
          confidence: "high",
          reason: "Dépendance Maven corroborée par des imports Java résolus par CodeQL.",
          evidence: map({
            path: .[0],
            start_line: .[1],
            end_line: .[1],
            contract: .[2],
            contract_path: .[3]
          })
        }
    ]
  }
' "$decoded" > "$graph"

edges="$(jq -c '.edges' "$graph")"
CODEQL_EDGES="$edges" perl -0pi -e '
  s{\n  "module_to_module_compile_time":.*?(?=\n  "module_to_topic_to_module")}{"\n  \"module_to_module_compile_time\": " . $ENV{CODEQL_EDGES} . ","}se
' "$inventory"

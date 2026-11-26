#!/usr/bin/env bash
# Experiment lifecycle through the Flagsmith CLI's authenticated API access.
#
#   scripts/experiment.sh create    create the experiment (not started)
#   scripts/experiment.sh start     start it (locks the flag, turns on the 50/50 split)
#   scripts/experiment.sh status    show status, exposures per variant
#   scripts/experiment.sh results   refresh (max once per 5 min) and print results
#   scripts/experiment.sh ship control|sample_data [--dry]   end it, serve the winner (asks to confirm)
#
# Run scripts/setup.sh first. The experiment id is stored in .experiment-id.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"

FLAG=first_screen
VARIANT=sample_data
NAME="First screen: empty board vs sample data"
HYPOTHESIS="Showing new visitors a pre-filled sample board will increase the share who create their first card in their first session, because they see what a finished board looks like instead of having to imagine it."

ENV_KEY=$(sed -n 's/.*"environment": *"\([^"]*\)".*/\1/p' flagsmith.json)
API="api/v1/environments/$ENV_KEY"
ID_FILE=.experiment-id

# Pull a numeric "id" for an object whose "name"/"key" matches, from compact JSON.
json_id_where() { # json field value
  python -I -c 'import json,sys
d=json.loads(sys.argv[1]); d=d.get("results",d) if isinstance(d,dict) else d
print(next(str(x["id"]) for x in d if str(x.get(sys.argv[2]))==sys.argv[3]))' "$@"
}

exp_id() {
  [[ -f $ID_FILE ]] || { echo "No $ID_FILE: run '$0 create' first" >&2; exit 1; }
  cat "$ID_FILE"
}

case "${1:-}" in
create)
  if [[ -f $ID_FILE ]]; then echo "✓ experiment $(cat $ID_FILE) already created"; exit 0; fi
  feature_id=$(flagsmith feature get "$FLAG" --json --jq '.id')
  variant_id=$(json_id_where "$(flagsmith feature variant list "$FLAG" --json)" key "$VARIANT")
  metrics=$(flagsmith api "$API/experiment-metrics/")
  m_primary=$(json_id_where "$metrics" name first_card_created)
  m_secondary=$(json_id_where "$metrics" name card_created)
  m_guardrail=$(json_id_where "$metrics" name help_opened)

  body=$(cat <<JSON
{
  "feature": $feature_id,
  "name": "$NAME",
  "hypothesis": "$HYPOTHESIS",
  "metrics": [
    {"metric": $m_primary,   "expected_direction": "increase"},
    {"metric": $m_secondary, "expected_direction": "increase"},
    {"metric": $m_guardrail, "expected_direction": "not_increase"}
  ],
  "experiment_rollout": {
    "enabled": true,
    "rollout_percentage": 100,
    "feature_state_value": {"type": "string", "value": "control"},
    "multivariate_feature_state_values": [
      {"multivariate_feature_option": $variant_id, "percentage_allocation": 50}
    ]
  }
}
JSON
)
  resp=$(flagsmith api "$API/experiments/" --input - <<<"$body")
  id=$(python -I -c 'import json,sys; print(json.loads(sys.argv[1])["id"])' "$resp")
  echo "$id" > "$ID_FILE"
  echo "+ created experiment $id (status: draft). Run '$0 start' to launch it."
  ;;
start)
  id=$(exp_id)
  flagsmith api "$API/experiments/$id/start/" -X POST >/dev/null
  status=$(flagsmith api "$API/experiments/$id/" | python -I -c 'import json,sys; print(json.load(sys.stdin)["status"])')
  echo "== experiment $id: $status"
  ;;
status)
  id=$(exp_id)
  flagsmith api "$API/experiments/$id/" | python -I -c 'import json,sys
e=json.load(sys.stdin)
print("experiment %s: %s" % (e["id"], e["name"]))
print("status: %s  started: %s" % (e["status"], e.get("started_at")))
for m in e.get("metrics",[]):
    print("  metric %-20s %-11s expected %s" % (m["metric_name"], m["aggregation"], m["expected_direction"]))'
  flagsmith api "$API/experiments/$id/exposures/refresh/" -X POST >/dev/null 2>&1 || true
  echo "exposures:"; flagsmith api "$API/experiments/$id/exposures/"; echo
  ;;
results)
  id=$(exp_id)
  flagsmith api "$API/experiments/$id/results/refresh/" -X POST >/dev/null 2>&1 \
    || echo "(refresh skipped: allowed at most once per 5 minutes)"
  flagsmith api "$API/experiments/$id/results/"; echo
  ;;
ship)
  # Ends the experiment and serves the chosen version to everyone.
  # IRREVERSIBLE: an ended experiment cannot be restarted. Requires typing the id.
  choice=${2:-}
  [[ $choice == control || $choice == "$VARIANT" ]] || { echo "usage: $0 ship control|$VARIANT [--dry]" >&2; exit 1; }
  id=$(exp_id)
  if [[ $choice == control ]]; then
    body='{"rollout_decision":"control"}'
  else
    variant_id=$(json_id_where "$(flagsmith feature variant list "$FLAG" --json)" key "$VARIANT")
    body="{\"rollout_decision\":\"variant\",\"rollout_variant\":$variant_id}"
  fi
  echo "== latest results (check them against the decision rule in EXPERIMENT.md):"
  flagsmith api "$API/experiments/$id/results/"; echo
  echo "== will POST $API/experiments/$id/complete/ $body"
  if [[ ${3:-} == --dry ]]; then echo "(dry run: nothing sent)"; exit 0; fi
  read -r -p "This ends experiment $id for good and serves '$choice' to everyone. Type the experiment id to confirm: " confirm
  [[ $confirm == "$id" ]] || { echo "Not confirmed, nothing changed."; exit 1; }
  flagsmith api "$API/experiments/$id/complete/" --input - <<<"$body" >/dev/null
  echo "== experiment $id: $(flagsmith api "$API/experiments/$id/" | python -I -c 'import json,sys; print(json.load(sys.stdin)["status"])')"
  echo "== what new visitors get now:"
  for i in 1 2 3 4 5 6; do
    flagsmith api --sdk "api/v1/identities/?identifier=post_ship_check_$i" \
      | python -I -c 'import json,sys
d=json.load(sys.stdin); f=[x for x in d["flags"] if x["feature"]["name"]==sys.argv[1]][0]
print("  ", d["identifier"], "->", f["feature_state_value"])' "$FLAG"
  done
  ;;
*)
  sed -n '2,10p' "$0"; exit 1 ;;
esac

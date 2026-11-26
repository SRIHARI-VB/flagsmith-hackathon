#!/usr/bin/env bash
# Creates everything the experiment needs in Flagsmith. Safe to re-run: each
# step is skipped if it already exists.
#
#   1. multivariate flag `first_screen` (value `control`) + variant `sample_data`
#   2. metrics: first_card_created (primary), card_created, help_opened (guardrail)
#
# Prereqs: Flagsmith CLI v2 logged in (`flagsmith login`) and this repo bound
# with `flagsmith init` (flagsmith.json). Names must match app/src/experiment.ts.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.local/bin:$PATH"

FLAG=first_screen
VARIANT=sample_data
ENV_KEY=$(flagsmith config --json --jq '.environment.value' 2>/dev/null || true)
ENV_KEY=${ENV_KEY:-$(sed -n 's/.*"environment": *"\([^"]*\)".*/\1/p' flagsmith.json)}
API="api/v1/environments/$ENV_KEY"

echo "== environment $ENV_KEY"

# --- 1. flag + variant -------------------------------------------------------
if flagsmith feature get "$FLAG" >/dev/null 2>&1; then
  echo "✓ flag $FLAG exists"
else
  flagsmith feature create "$FLAG" --value control --enabled \
    --description "Experiment: empty board (control) vs sample-data board (sample_data)"
  echo "+ created flag $FLAG"
fi

# Every variant needs a key, or its exposures are not counted.
if flagsmith feature variant list "$FLAG" --json | grep -q "\"$VARIANT\""; then
  echo "✓ variant $VARIANT exists"
else
  flagsmith feature variant add "$FLAG" --value "$VARIANT" --key "$VARIANT" --weight 0
  echo "+ added variant $VARIANT"
fi

# --- 2. metrics --------------------------------------------------------------
existing_metrics=$(flagsmith api "$API/experiment-metrics/")

create_metric() { # name aggregation direction
  local name=$1 agg=$2 dir=$3
  if grep -q "\"name\":\"$name\"" <<<"$existing_metrics"; then
    echo "✓ metric $name exists"
    return
  fi
  flagsmith api "$API/experiment-metrics/" --input - >/dev/null <<JSON
{"name":"$name","aggregation":"$agg","direction":"$dir","definition":{"version":1,"event":"$name"}}
JSON
  echo "+ created metric $name ($agg, $dir)"
}

create_metric first_card_created occurrence up   # primary
create_metric card_created       count      up   # secondary
create_metric help_opened        occurrence down # guardrail: confusion signal

# --- 3. warehouse status -----------------------------------------------------
status=$(flagsmith api "$API/warehouse-connections/" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
echo "== warehouse: ${status:-none}"
if [[ "$status" != "connected" ]]; then
  echo "   The experiment can be created once the warehouse is 'connected'."
fi

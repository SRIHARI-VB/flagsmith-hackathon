#!/usr/bin/env bash
# fx.sh: Flagsmith experiment-then-rollout helper. Needs only the Flagsmith CLI v2
# (logged in, repo bound with `flagsmith init`). Output is deliberately terse.
#
#   fx.sh preflight
#   fx.sh flag    <flag> <control_value> <variant_key>...
#   fx.sh metric  <event> <occurrence|count|sum|mean> <up|down>
#   fx.sh create  <flag> <name> <hypothesis> <rollout_pct> <event>:<increase|decrease|not_increase|not_decrease>...
#   fx.sh start   <exp_id> --confirm <exp_id> [--confirm-production]
#   fx.sh results <exp_id>
#   fx.sh ship    <exp_id> <control|variant_key> --confirm <exp_id> [--confirm-production]
#   fx.sh list
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
fs() { flagsmith "$@"; }
die() { echo "ERROR: $*" >&2; exit 1; }

ENV_KEY=$(fs config --json --jq '.environment.value') || die "run 'flagsmith login' and 'flagsmith init' first"
[[ -n $ENV_KEY && $ENV_KEY != null ]] || die "no environment bound: run 'flagsmith init'"
ENV_NAME=$(fs config --json --jq '.environment.name // ""')
API="api/v1/environments/$ENV_KEY"
esc() { sed 's/\\/\\\\/g; s/"/\\"/g' <<<"$1"; } # JSON string escape

# Changes that go live (start, ship) need the id typed back, and more for production.
guard() { # exp_id args...
  local id=$1; shift
  [[ " $* " == *" --confirm $id "* ]] || die "refusing: pass --confirm $id after a human approves this change"
  if [[ ${ENV_NAME,,} == *prod* && " $* " != *" --confirm-production "* ]]; then
    die "environment '$ENV_NAME' looks like production: also pass --confirm-production"
  fi
}

cmd=${1:-}; shift || true
case "$cmd" in
preflight)
  fs auth status >/dev/null 2>&1 || die "not logged in: run 'flagsmith login'"
  echo "project:   $(fs config --json --jq '.project.value')  environment: $ENV_NAME ($ENV_KEY)"
  [[ ${ENV_NAME,,} == *prod* ]] && echo "WARNING:   production environment: start/ship need --confirm-production"
  w=$(fs api "$API/warehouse-connections/" --jq '.[0].status // "none"')
  echo "warehouse: $w"
  [[ $w == connected ]] || echo "BLOCKER:   experiments need a connected warehouse (Environment Settings > Warehouse)"
  echo "running:   $(fs api "$API/experiments/" --jq '[.results[] | select(.status=="running") | "\(.id):\(.feature.name)"] | join(", ") | if .=="" then "none" else . end')"
  ;;

flag)
  [[ $# -ge 3 ]] || die "usage: flag <flag> <control_value> <variant_key>..."
  f=$1 control=$2; shift 2
  if fs feature get "$f" >/dev/null 2>&1; then echo "= flag $f exists"
  else fs feature create "$f" --value "$control" --enabled >/dev/null && echo "+ flag $f (control=$control)"; fi
  have=$(fs feature variant list "$f" --json --jq '[.[].key] | join(" ")')
  for k in "$@"; do
    # Variants MUST have a key, or their exposures are not counted.
    if [[ " $have " == *" $k "* ]]; then echo "= variant $k exists"
    else fs feature variant add "$f" --value "$k" --key "$k" --weight 0 >/dev/null && echo "+ variant $k"; fi
  done
  ;;

metric)
  [[ $# -eq 3 ]] || die "usage: metric <event> <occurrence|count|sum|mean> <up|down>"
  if [[ -n $(fs api "$API/experiment-metrics/" --jq ".results[] | select(.name==\"$1\") | .id") ]]; then
    echo "= metric $1 exists"
  else
    fs api "$API/experiment-metrics/" --input - >/dev/null <<<"{\"name\":\"$(esc "$1")\",\"aggregation\":\"$2\",\"direction\":\"$3\",\"definition\":{\"version\":1,\"event\":\"$(esc "$1")\"}}"
    echo "+ metric $1 ($2, $3)"
  fi
  ;;

create)
  [[ $# -ge 5 ]] || die "usage: create <flag> <name> <hypothesis> <rollout_pct> <event>:<direction>..."
  f=$1 name=$2 hyp=$3 rollout=$4; shift 4
  fid=$(fs feature get "$f" --json --jq '.id')
  control=$(fs feature get "$f" --json --jq '.initial_value // .default_value // "control"' 2>/dev/null || echo control)
  vids=($(fs feature variant list "$f" --json --jq '.[] | select(.key != null and .key != "") | .id'))
  [[ ${#vids[@]} -ge 1 ]] || die "flag $f has no keyed variants: run 'fx.sh flag' first"
  share=$((100 / (${#vids[@]} + 1))) # even split; control gets the remainder
  mv=$(for v in "${vids[@]}"; do printf '{"multivariate_feature_option":%s,"percentage_allocation":%s},' "$v" "$share"; done)
  ms=""
  for pair in "$@"; do
    ev=${pair%%:*} dir=${pair#*:}
    mid=$(fs api "$API/experiment-metrics/" --jq ".results[] | select(.name==\"$ev\") | .id")
    [[ -n $mid ]] || die "metric $ev not found: run 'fx.sh metric' first"
    ms+="{\"metric\":$mid,\"expected_direction\":\"$dir\"},"
  done
  body="{\"feature\":$fid,\"name\":\"$(esc "$name")\",\"hypothesis\":\"$(esc "$hyp")\",\"metrics\":[${ms%,}],\"experiment_rollout\":{\"enabled\":true,\"rollout_percentage\":$rollout,\"feature_state_value\":{\"type\":\"string\",\"value\":\"$(esc "$control")\"},\"multivariate_feature_state_values\":[${mv%,}]}}"
  id=$(fs api "$API/experiments/" --input - --jq '.id' <<<"$body")
  echo "+ experiment $id (draft, NOT started): $f, rollout ${rollout}%, each variant ${share}%, control the rest"
  ;;

start)
  id=${1:?exp_id}; guard "$@"
  fs api "$API/experiments/$id/start/" -X POST >/dev/null
  echo "experiment $id: $(fs api "$API/experiments/$id/" --jq '.status')"
  ;;

results)
  id=${1:?exp_id}
  fs api "$API/experiments/$id/results/refresh/" -X POST >/dev/null 2>&1 || true # max once per 5 min
  meta=$(fs api "$API/experiments/$id/" --jq '"\(.status) \(.feature.name)", (.metrics[] | "\(.metric) \(.metric_name) \(.expected_direction)")')
  read -r status flagname <<<"$(head -1 <<<"$meta")"
  res=$(fs api "$API/experiments/$id/results/" --jq '
    .results // {} | .payload // {} |
    "asof \(.as_of // "-") srm \(.srm_p_value // "-")",
    (.metrics // [] | .[] | .metric_id as $m | (.variants | to_entries | map(select(.key=="control")) | .[0].value) as $c |
      .inference // {} | to_entries[] | select(.value != null) |
      "m \($m) \(.key) \(.value.chance_to_win) \(.value.lift) \(.value.ci_low) \(.value.ci_high) \($c.n) \($c.sum)"),
    (.metrics // [] | .[] | .variants | to_entries[] | "n \(.key) \(.value.n) \(.value.sum)")')
  if [[ -z $(grep '^m ' <<<"$res") ]]; then
    echo "experiment $id ($status) flag $flagname: no statistics yet (each arm needs >=50 identities)"
    grep '^n ' <<<"$res" | awk '!s[$2]++ {printf "  %s n=%s primary=%s\n", $2, $3, $4}'
    exit 0
  fi
  echo "experiment $id ($status) flag $flagname"
  grep '^n ' <<<"$res" | awk '!s[$2]++ {printf "  %s n=%s\n", $2, $3}'
  srm=$(sed -n 's/^asof .* srm //p' <<<"$res")
  low_n=$(grep '^n ' <<<"$res" | awk '$3 < 50' | head -1)
  primary=""; guard_bad=0
  while read -r mid mname mdir; do
    while read -r _ m v ctw lift lo hi cn cs; do
      [[ $m == "$mid" ]] || continue
      vs=$(grep "^n $v " <<<"$res" | head -1 | awk '{print $4}')
      verdict=$(awk -v p="$ctw" 'BEGIN{print (p>=0.95)?"WINNING":(p<=0.05)?"LOSING":"inconclusive"}')
      printf "  %-22s %-12s %-14s chance=%.0f%% lift=%+.1f%% ci=[%+.1f%%,%+.1f%%] %s\n" "$mname" "$v" "$mdir" \
        "$(awk -v x="$ctw" 'BEGIN{print x*100}')" "$(awk -v x="$lift" 'BEGIN{print x*100}')" \
        "$(awk -v x="$lo" 'BEGIN{print x*100}')" "$(awk -v x="$hi" 'BEGIN{print x*100}')" "$verdict"
      [[ -z $primary ]] && primary="$v $verdict"
      [[ $mdir == not_* && $verdict == LOSING ]] && guard_bad=1
    done < <(grep '^m ' <<<"$res")
  done < <(tail -n +2 <<<"$meta")
  echo "  srm_p=$srm (fail if < 0.001)"
  read -r pv pverdict <<<"$primary"
  if [[ -n $low_n ]]; then rec="keep running: an arm has < 50 identities"
  elif [[ $srm != "-" ]] && awk -v p="$srm" 'BEGIN{exit !(p<0.001)}'; then rec="STOP: sample ratio mismatch, fix assignment before trusting results"
  elif [[ $pverdict == WINNING && $guard_bad == 0 ]]; then rec="ship $pv (primary winning, guardrails ok)"
  elif [[ $pverdict == WINNING ]]; then rec="do not ship: primary wins but a guardrail is losing"
  elif [[ $pverdict == LOSING ]]; then rec="ship control (primary losing)"
  else rec="inconclusive: keep running or end and keep control"; fi
  echo "RECOMMEND: $rec (default rule: primary = first metric, >=95% to win; a human decides)"
  ;;

ship)
  id=${1:?exp_id} choice=${2:?control|variant_key}; shift 2; guard "$id" "$@"
  flagname=$(fs api "$API/experiments/$id/" --jq '.feature.name')
  if [[ $choice == control ]]; then body='{"rollout_decision":"control"}'
  else
    vid=$(fs feature variant list "$flagname" --json --jq ".[] | select(.key==\"$choice\") | .id")
    [[ -n $vid ]] || die "no variant with key $choice on $flagname"
    body="{\"rollout_decision\":\"variant\",\"rollout_variant\":$vid}"
  fi
  fs api "$API/experiments/$id/complete/" --input - >/dev/null <<<"$body"
  echo "experiment $id: $(fs api "$API/experiments/$id/" --jq '.status') -> serving '$choice'"
  # Edge caches take a few seconds to pick up the change: poll fresh identities.
  served=$( [[ $choice == control ]] && fs feature get "$flagname" --json --jq '.default_value' || echo "$choice")
  for attempt in $(seq 1 12); do
    got=$(for i in 1 2 3 4 5; do fs api --sdk "api/v1/identities/?identifier=fx_verify_${attempt}_$i" --jq ".flags[] | select(.feature.name==\"$flagname\") | .feature_state_value"; done | sort -u | tr '\n' ' ')
    if [[ $got == "$served " ]]; then echo "verified: 5/5 new identities get '$served' (after ~$(( (attempt - 1) * 5 ))s)"; exit 0; fi
    sleep 5
  done
  echo "WARNING: new identities still get: $got(expected '$served'); check the flag in the dashboard"
  ;;

list)
  fs api "$API/experiments/" --jq '.results[] | "\(.id)\t\(.status)\t\(.feature.name)\t\(.name)"'
  ;;

*) sed -n '2,13p' "$0"; exit 1 ;;
esac

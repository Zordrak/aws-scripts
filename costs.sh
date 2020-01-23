#!/usr/bin/env bash

set -uo pipefail;

declare period="${1-""}";
declare what from to;

case "${period}" in
  'mtd')
    what="Month to Date";
    from="$(date +%Y-%m-01)";
    to="$(date +%Y-%m-%d)";
    ;;
  'month')
    what="One Month";
    from="$(date +%Y-%m-%d --date "last month")";
    to="$(date +%Y-%m-%d)";
    ;;
  *)
    echo "ERROR: invalid argument. Specify mtd or month" >&2 && exit 1;
    ;;
esac

echo -e "###\n# AWS Blended Costs by Service: ${what} (${from} => ${to})\n###\n";

aws ce get-cost-and-usage \
  --time-period "Start=${from},End=${to}" \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output json \
  | jq -r '.ResultsByTime[].Groups[]|(.Keys|join(",")) + "%" + .Metrics.BlendedCost.Amount + "%" + .Metrics.BlendedCost.Unit' \
  | awk 'BEGIN { FS = "%"; printf("%-50s %-5s %s\n", "Service", "Unit", "Blended Cost")};{printf("%-50s %-5s %s\n", $1, $3, $2)}';

exit 0;

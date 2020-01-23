#!/bin/bash

set -eo pipefail

key_arn="${1:-${default_key_arn}}"

# Declare Associative Arrays
declare -A grants_latest;
declare -A grants_delete;

# Declare primary input array
declare -a grants_list

# Get the list of grants for the key ARN
# Presume all grants are for Lambda as we don't create them manually
echo -en "Getting all grants for Key ${key_arn}, this might take a moment...";
grants_list=($(aws kms list-grants \
  --key-id "${key_arn}" \
  --o json \
  | jq -r '.Grants[] | (.CreationDate|tostring) + "," + .GrantId + "," + .Constraints.EncryptionContextEquals."aws:lambda:FunctionArn"' \
  | sort -t"," -k1));

[ ${?} -eq 0 ] && echo -e "  Done." || exit 1;

# For debug
#echo -e "Grants List:\n";
#for grant in ${grants_list[@]}; do
#  echo ${grant};
#done;
#exit 0

# Since we time-sorted the list, keep pushing the creation dates
# of each grant as the "latest" into the associative array
# when complete it will only contain the latest timestamp_id for each function
for grant in ${grants_list[@]}; do
  grants_latest["${grant##*,}"]="${grant%,*}";
done;

# For debug
#echo -e "Grants Latest:\n";
#for grant in ${!grants_latest[@]}; do
#  echo "Function: ${grant} timestamp_id: ${grants_latest[${grant}]}";
#done;

# For every grant in the primary input array, if it's not the latest
# grant for the given function ARN, then add it to the delete list
for grant in ${grants_list[@]}; do
  function_arn="${grant##*,}";
  timestamp_id="${grant%,*}";
  if [[ ${timestamp_id%,*} -lt ${grants_latest[${function_arn}]%,*} ]]; then
    # If the timestamp_id is older delete it
    grants_delete[${function_arn}]+="${timestamp_id}:";
  elif [[ ${timestamp_id%,*} -ne ${grants_latest[${function_arn}]%,*} ]]; then
    # If the timestamp_id isn't the same (therefore skipped) or older (therefore deleted)
    # then this script has failed to work correctly as sorting shouldn't allow this.
    echo "AWOOGA AWOOGA AWOOGA AWOOGA AWOOGA AWOOGA AWOOGA AWOOGA AWOOGA PROCESS FAILURE";
    exit 1;
  fi;
done;

# For each of the function_arns (the grants_latest hash keyset is the easiest list of them all)
# Print out the function arn, the one we're keeping and the ones we are deleting.
# And use stupid printf because stupid macs don't have GNU Date.
for function_arn in ${!grants_latest[@]}; do
  timestamp_ids=()
  echo -e "\e[1mFunction: ${function_arn}\e[0m";
  echo -e "\e[32m\tKeeping:\t$(printf '%(%c)T\n' ${grants_latest[${function_arn}]%,*})\e[0m";
  IFS=: read -a timestamp_ids <<<${grants_delete[${function_arn}]}
  for timestamp_id in ${timestamp_ids[@]}; do
    echo -e "\e[31m\tDeleting:\t$(printf '%(%c)T\n' ${timestamp_id%,*}) (Grant ID: ${timestamp_id##*,}\e[0m"
    aws kms revoke-grant --key-id ${key_arn} --grant-id ${timestamp_id##*,}
  done;
done;

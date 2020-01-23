#!/bin/bash
# set -x

# ebs_volume_mean_iops.sh
# 
# Get the mean Input/Output Operations per Second (IOPS) for an AWS EBS volume.


# If you want to mess around with the dates on invocation, try this:
#
# START=$(date -d "<some parseable date string>" +%FT%T) END=$(date -d "<some parseable date string>" +%FT%T) VOLUME=<A vol-id> ./iops.sh


# Assuming you use aws profiles, specify the profile name
AWS_PROFILE=${AWS_PROFILE:-"mot"};

# Default to past 24 hours unless START/END specified
now="$(date +%s)";
START=${START:-"$(date -d @$(( ${now} - 86400 )) +%FT%T)"};
END=${END:-"$(date -d @${now} +%FT%T)"};

# Default to /var/lib/prometheus on monitoring-1.prd.mot.aws.dvsa
VOLUME=${VOLUME-"vol-9b345c54"};

# Period is entire time range.
# This script is not set up to handle multiple response values from CloudWatch.
period="$(( $(date -d ${END} +%s) - $(date -d ${START} +%s) ))";

# Query Read IOPS
readiop=$(aws \
            --profile ${AWS_PROFILE} \
            cloudwatch get-metric-statistics \
            --metric-name VolumeReadOps \
            --start-time ${START} \
            --end-time ${END} \
            --period ${period} \
            --namespace AWS/EBS \
            --statistics Sum \
            --dimensions Name=VolumeId,Value=${VOLUME} \
            --region eu-west-1 \
            | awk '/^DATAPOINTS/{print $2}' \
            | cut -d. -f1
         );

# Query Write IOPS
writeiop=$(aws \
             --profile ${AWS_PROFILE} \
             cloudwatch get-metric-statistics \
             --metric-name VolumeWriteOps \
             --start-time ${START} \
             --end-time ${END} \
             --period ${period} \
             --namespace AWS/EBS \
             --statistics Sum \
             --dimensions Name=VolumeId,Value=${VOLUME} \
             --region eu-west-1 \
             | awk '/^DATAPOINTS/{print $2}' \
             | cut -d. -f1
         );

totaliop=$(( ${readiop} + ${writeiop} ));
iops=$(( ${totaliop} / ${period} ));
echo -e "Volume:\t\t${VOLUME}\nStart:\t\t${START}\nEnd:\t\t${END}\nPeriod (s):\t${period}\n\nAverage IOPS:\t${iops}"

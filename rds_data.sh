#!/bin/bash
# set -x

# ebs_volume_mean_iops.sh
# 
# Get the mean Input/Output Operations per Second (IOPS) for an AWS EBS volume.


# If you want to mess around with the dates on invocation, try this:
#
# START=$(date -d "<some parseable date string>" +%FT%T) END=$(date -d "<some parseable date string>" +%FT%T) VOLUME=<A vol-id> ./iops.sh


# Default to past 24 hours unless START/END specified
now="$(date +%s)";
START=${START:-"$(date -d @$(( ${now} - 2592000 )) +%FT%T)"};
END=${END:-"$(date -d @${now} +%FT%T)"};

DB_INSTANCE=${1};

# Period is entire time range.
# This script is not set up to handle multiple response values from CloudWatch.
period="$(( $(date -d ${END} +%s) - $(date -d ${START} +%s) ))";

# Query Read IOPS
receivebps=$(aws \
            --profile ${AWS_PROFILE} \
            cloudwatch get-metric-statistics \
            --metric-name NetworkReceiveThroughput \
            --start-time ${START} \
            --end-time ${END} \
            --period ${period} \
            --namespace AWS/RDS \
            --statistics Average \
            --dimensions Name=DBInstanceIdentifier,Value=${DB_INSTANCE} \
            --region eu-west-1 \
            | awk '/^DATAPOINTS/{print $2}' \
            | cut -d. -f1
         );

# Query Write IOPS
transmitbps=$(aws \
             --profile ${AWS_PROFILE} \
             cloudwatch get-metric-statistics \
             --metric-name NetworkTransmitThroughput \
             --start-time ${START} \
             --end-time ${END} \
             --period ${period} \
             --namespace AWS/RDS \
             --statistics Average \
             --dimensions Name=DBInstanceIdentifier,Value=${DB_INSTANCE} \
             --region eu-west-1 \
             | awk '/^DATAPOINTS/{print $2}' \
             | cut -d. -f1
         );

# Presuming about equal write as replicate
totalbps=$(( ${transmitbps} + ${receivebps} ));
bytes=$(( ${totalbps} * ${period} ));
echo -e "DB Instance:\t\t${DB_INSTANCE}\nStart:\t\t${START}\nEnd:\t\t${END}\nPeriod (s):\t${period}\n\nAverage BPS * Period (GiB):\t$(( ${bytes} / 1073741824 ))"

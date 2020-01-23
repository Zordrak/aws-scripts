#!/bin/bash

# ec2_get_root_volume_sizes

# [AWS_PROFILE=<aws cli profile name>] ./ec2_get_root_volume_sizes <environment> <project>

environment="${1}";
project="${2}";

echo -e "
EBS Root Volume Sizes

##############################################################
| Name                        | Instance | Volume Id  | Size |
##############################################################";
while read line;
do
  echo -e "$line $(aws --profile ${AWS_PROFILE} \
                     ec2 \
                     describe-volumes \
                     --volume-id \
                     "$(echo $line \
                          | cut -f3 -d" "
                     )" \
                     --query "Volumes[*].Size"
                   )";
done<<<"$(aws --profile ${AWS_PROFILE} \
            ec2 describe-instances \
            --filters "Name=tag:environment,Values=${environment}" \
                      "Name=tag:project,Values=${project}" \
            --query "Reservations[*]
                       .Instances[*]
                         .[
                           BlockDeviceMappings[?DeviceName=='/dev/sda1'].Ebs.VolumeId, 
                           InstanceId,
                           Tags[?Key=='Name'].Value[]
                         ]" \
            | sed 'N;N;s/\n/ /g' \
            | awk '{printf "%-30s %-10s %s\n",$3, $1, $2}' \
            | sort -t- -k1,1 -k2,2n
         )";

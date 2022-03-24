#!/bin/bash
function check_node_exists {
  set -e 
  num="0"
  ec2_node_name=$1
  flag_node_found=false
  alertid=1
  host_names=$(aws ec2 describe-vpc-attribute --vpc-id=${vpc_id} --region=${region} --attribute=enableDnsHostnames --output=text | grep ENABLEDNSHOSTNAMES | awk '{print $2}')
  if [[ "$host_names" == "True" ]]; then
      if [[ "${inventory_env}" == "stg" ]]; then
          name=$(aws ec2 describe-instances --filter Name=instance-state-name,Values=running Name=tag:Name,Values=stg_aerospike_* --output=text --region=${region} | grep Name | awk '{print $3;}' )
      elif [[ "${inventory_env}" == "databases" ]]; then
          name=$(aws ec2 describe-instances --filter Name=instance-state-name,Values=running Name=tag:Name,Values=extendtv_east_vpc1_aerospike_* --output=text --region=${region} | grep Name | awk '{print $3;}' )
      else 
          echo "Wrong Inventory Type"
          exit 1
      fi 
      for node_name in $name; do 
          if [[ "$node_name" = "$ec2_node_name" ]]; then 
              flag_node_found=true
              break
          fi
      done
  else
      if [[ "${inventory_env}" == "stg" ]]; then
          name=$(aws ec2 describe-instances --filter Name=instance-state-name,Values=running Name=tag:Name,Values=stg_aerospike_* --output=text --region=${region} | grep Name | awk '{print $3;}' )
      elif [[ "${inventory_env}" == "databases" ]]; then
          name=$(aws ec2 describe-instances --filter Name=instance-state-name,Values=running Name=tag:Name,Values=extendtv_east_vpc1_aerospike_* --output=text --region=${region} | grep Name | awk '{print $3;}' )
      else 
          echo "Wrong Inventory Type"
          exit 1
      fi 
      for node_name in $name; do 
          if [[ "$node_name" = "$ec2_node_name" ]]; then  
              flag_node_found=true
              break
          fi
      done
  fi
  if $flag_node_found  
  then
      exit 1 
  else
      exit 0
  fi
}

function add_new_node_in_ansible_inventory {
  set -e   
  list_of_resource=$(cat ./ansible/inventories/$inventory_env/hosts.yaml)
  echo $list_of_resource
  echo "&************************"
  for item in ${list_of_resource[@]}; do
    if [[ ${item} =~ aerospike-[0-9]{0,2}.$inventory_env.$hosted_zone: ]]; then
      echo "**$item**"
      line_number=$(awk -v x=${item} '$0~x {print NR}' ./ansible/inventories/$inventory_env/hosts.yaml)
      echo "**$line_number**"

    fi
  done
  hostname=$1
  node_number=$(echo ${hostname} | sed 's/[^0-9]//g')
  echo "param node name: $hostname Node Number :$node_number"
  new_line_number=`expr $line_number + 1`
  new_dns_recordname=aerospike-${node_number}.$inventory_env.$hosted_zone
  new_inventory=aerospike-${node_number}.$inventory_env.$hosted_zone:
  new_hostname=$hostname.$inventory_env

  echo "new_line_number $new_line_number"
  echo "New Host Name $new_dns_recordname"
  echo "new_inventory $new_inventory"
  echo "new_hostname $new_hostname"

  sed -i './script/aerospike_route_53_dns_record.json' -e "s/%RECORDNAME%/${new_dns_recordname}/" ./script/aerospike_route_53_dns_record.json # Adding the Name of recod set in json file 
  sed -i ./ansible/inventories/${inventory_env}/hosts.yaml -e "${new_line_number}s/^[[:space:]]*$/        ${new_inventory}\n/" ./ansible/inventories/$inventory_env/hosts.yaml #adding new entry in the inventry file
  rm -rf userdata.txt
  cat './script/aerospike_route_53_dns_record.json'
  echo  "*********** host.yaml"
  cat ./ansible/inventories/${inventory_env}/hosts.yaml
  echo "*******"
  # Userdata to update the host name 
cat <<EOF >> userdata.txt
#!/bin/bash
new_hostname=${new_hostname}
new_host_name="PS1='\[\033[01m\]\${new_hostname}\[\033[00m\]:\[\033[01;34m\]\W \[\033[00m\]\u\$ '"  
sed -i '$ d' /etc/profile.d/default_prompt.sh
sed -i '$ d' /etc/hosts
test=$new_dns_recordname
privateip=\$(curl http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.privateIp')
echo "\$privateip  \$test" >>/etc/hosts
echo "\$new_host_name">>/etc/profile.d/default_prompt.sh
EOF
  echo ${new_dns_recordname}
}

function add_node_in_ansible_inventory {
  set -e   
  list_of_resource=$(cat ./ansible/inventories/$inventory_env/hosts.yaml)
  for item in ${list_of_resource[@]}; do
    if [[ ${item} =~ aerospike-[0-9]{0,2}.$inventory_env.$hosted_zone: ]]; then
      line_number=$(awk -v x=${item} '$0~x {print NR}' ./ansible/inventories/$inventory_env/hosts.yaml)
      node_number=$(echo ${item} | sed 's/[^0-9]//g')
    fi
  done
  
  new_node_number=`expr $node_number + 1`
  new_line_number=`expr $line_number + 1`
  new_dns_recordname=aerospike-${new_node_number}.$inventory_env.$hosted_zone
  new_inventory=aerospike-${new_node_number}.$inventory_env.$hosted_zone:
  new_hostname=aerospike-${new_node_number}.$inventory_env

  sed -i './script/aerospike_route_53_dns_record.json' -e "s/%RECORDNAME%/${new_dns_recordname}/" ./script/aerospike_route_53_dns_record.json # Adding the Name of recod set in json file 
  sed -i ./ansible/inventories/${inventory_env}/hosts.yaml -e "${new_line_number}s/^[[:space:]]*$/        ${new_inventory}\n/" ./ansible/inventories/$inventory_env/hosts.yaml #adding new entry in the inventry file
  rm -rf userdata.txt
  # Userdata to update the host name 
cat <<EOF >> userdata.txt
#!/bin/bash
new_hostname=${new_hostname}
new_host_name="PS1='\[\033[01m\]\${new_hostname}\[\033[00m\]:\[\033[01;34m\]\W \[\033[00m\]\u\$ '"  
sed -i '$ d' /etc/profile.d/default_prompt.sh
sed -i '$ d' /etc/hosts
test=$new_dns_recordname
privateip=\$(curl http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.privateIp')
echo "\$privateip  \$test" >>/etc/hosts
echo "\$new_host_name">>/etc/profile.d/default_prompt.sh
EOF
  echo ${new_dns_recordname}
}

function create_instance_and_dns_record {
  set -e   
  
  finalvalue=""
  nslookup_output=""
  count=0
  new_dns_recordname=$1
  new_node_number=$(echo $new_dns_recordname | sed 's/[^0-9]//g')
  new_node_name=$(echo ${node_name_template} | sed "s/%NUMBER%/$new_node_number/g")
  tags=[{Key=Name,Value=$new_node_name},$cluster_tag]


  meta_data=$(aws ec2 run-instances \
  --image-id $ami_id \
  --instance-type $instance_type \
  --count 1 \
  --subnet-id $subnet_id \
  --key-name $key_name \
  --security-group-ids $sg_ids \
  --iam-instance-profile Arn=$instanceprofile \
  --user-data file://userdata.txt \
  --tag-specifications "ResourceType=instance,Tags=$tags" | grep InstanceId)

  instance_id=$(echo $meta_data | sed -r 's/^[^:]*:(.*)$/\1/' | sed 's/"//g'| sed 's/,//g')
  
  while [[ "$finalvalue" != "running" ]]; do
      sleep 10s
      finalvalue=$(aws ec2 describe-instances --instance-ids $instance_id  --query 'Reservations[].Instances[].State.Name' --output text)
      if [[ "$finalvalue" == "running" ]]; then
          echo "Instance is now in  $finalvalue state"
      fi
  done

  if [[ "${inventory_env}" == "stg" ]] || [[ "${inventory_env}" == "databases" ]]; then
  
    dns_record_ip=$(aws ec2 describe-instances --instance-ids $instance_id  --query 'Reservations[].Instances[].PrivateIpAddress' --output text)
    sed -i './script/aerospike_route_53_dns_record.json' -e "s/%SAMPLEIP%/$dns_record_ip/" ./script/aerospike_route_53_dns_record.json
    aws route53 change-resource-record-sets --hosted-zone-id $hostedzone_id --change-batch file://script/aerospike_route_53_dns_record.json
    sed -i './script/aerospike_route_53_dns_record.json' -e "s/$dns_record_ip/%SAMPLEIP%/" ./script/aerospike_route_53_dns_record.json
    sed -i './script/aerospike_route_53_dns_record.json' -e "s/${new_dns_recordname}/%RECORDNAME%/" ./script/aerospike_route_53_dns_record.json
    
    echo "Waiting for DNS to propagate"
    sleep 2m

    if [[ "${inventory_env}" == "stg" ]]; then
      
      while [[ $count != 1 ]]; do
          nslookup_output=$(nslookup ${new_dns_recordname} | awk '/Address/&&!/#/{print $2}')
          sleep 10s
          if [[ $nslookup_output =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "DNS is Getting resolved"
            count=`expr $count + 1`
          else
              echo "DNS is not resolved yet"
          fi
      done 

    elif [[ "${inventory_env}" == "databases" ]]; then
  
      while [[ $count != 1 ]]; do
          nslookup_output=$(nslookup ${new_dns_recordname} | awk '/Address/&&!/#/{print $2}')
          sleep 10s
          if [[ $nslookup_output =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "DNS is Getting resolved"
            count=`expr $count + 1`
          else
              echo "DNS is not resolved yet"
          fi
      done  
    fi
  else
    echo "Wrong Inventory Variable / Unable to Create Find DNS"
    echo "Terminating Launch Instance"
    aws ec2 terminate-instances --instance-ids $instance_id
    exit 1  
  fi 
  echo $instance_id
  
}
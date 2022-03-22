#!/bin/bash

function get_last_node_metadata {
    set -e
    num="0"
    largest_number=0
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
            node_number=$(echo $node_name | sed 's/[^0-9]//g')
            if [[ "${node_number}" -gt "${largest_number}" ]]; then
                largest_number=${node_number}
                last_node_name=$node_name
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
            node_number=$(echo $node_name | sed 's/[^0-9]//g')
            if [[ "${node_number}" -gt "${largest_number}" ]]; then
                largest_number=${node_number}
                last_node_name=$node_name
            fi
        done
    fi
    echo ${last_node_name}
}

function get_node_name {
    set -e
    num="0"
    ec2_node_name=$1
    flag_node_found=0
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
            echo "${node_name}"
            if [[ "${node_name}" == "${ec2_node_name}" ]]; then 
                echo "found instance"
                flag_node_found=1
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
            echo "${node_name}"
            if [[ "${node_name}" == "${ec2_node_name}" ]]; then 
                echo "found instance"
                break
            fi
        done
    fi
    echo "Flag Status : ${flag_node_found}"
    if $flag_node_found 
    then
        echo ${ec2_node_name}
    else
        echo "Wrong Inventory Type1"
        exit 1
    fi
}

function extract_ip_of_last_node {
    set -e
    last_node_name=$1
    node_ip=$(aws ec2 describe-instances --filter Name=tag:Name,Values=${last_node_name} --region=${region} --query 'Reservations[].Instances[].PrivateIpAddress' --output=text)
    echo ${node_ip}
}

function quiesce_last_node {
    set -x
    node_ip=$1
    docker run --name aerospike-asinfo --rm aerospike/aerospike-tools asadm -e "enable; asinfo -v 'quiesce:' with ${node_ip}" -h ${master_node_ip} --no-config-file
}

function nodes_which_got_quiesced {
    set -e
    nodes_name_displayed=()
    node_ip=$1
    node_to_quiece="ip-$(echo ${node_ip} | sed 's/\./-/g').ec2.internal:3000"
    cluster_node_ips=$(docker run --name aerospike-asinfo --rm aerospike/aerospike-tools asadm -e "show statistics like pending_quiesce --enable" -j  -h ${master_node_ip} | sed -n '/^{$/,$p' | jq '.groups[].records[].Node.raw' | sed 's/"//g')
    quiece_node_status=$(docker run --name aerospike-asinfo --rm aerospike/aerospike-tools asadm -e "show statistics like pending_quiesce --enable" -j  -h ${master_node_ip} | sed -n '/^{$/,$p' | jq '.groups[].records[].pending_quiesce.raw' | sed 's/"//g')
    status=($quiece_node_status)
    cluster_node_ips=($cluster_node_ips)
    length=${#cluster_node_ips[@]} 
    header="\n%-35s %-15s\n"
    format="\n%-28s %-15s"
    echo "******************** Nodes Which  Got Quieced ********************"
    printf "${header}" "Node Name" "Status" 
    for (( j=0; j<${length}; j++ ));
    do
        if [[ ! "${nodes_name_displayed[*]}" =~ "${cluster_node_ips[$j]}" ]]; then
            if [[ ${status[$j]} == "true" ]]; then
                printf "${format}" "${cluster_node_ips[$j]}" "${status[$j]}"
            fi
        fi       
        nodes_name_displayed+=("${cluster_node_ips[$j]}")    
    done

}

function undo_quiesce_on_unwanted_quiesced_nodes {
    set -e
    node_ip=$1
    node_to_quiece="ip-$(echo ${node_ip} | sed 's/\./-/g').ec2.internal:3000"
    cluster_node_ips=$(docker run --name aerospike-asinfo --rm aerospike/aerospike-tools asadm -e "show statistics like pending_quiesce --enable" -j  -h ${master_node_ip} | sed -n '/^{$/,$p' | jq '.groups[].records[].Node.raw' | sed 's/"//g')
    quiece_node_status=$(docker run --name aerospike-asinfo --rm aerospike/aerospike-tools asadm -e "show statistics like pending_quiesce --enable" -j  -h ${master_node_ip} | sed -n '/^{$/,$p' | jq '.groups[].records[].pending_quiesce.raw' | sed 's/"//g')
    status=($quiece_node_status)
    cluster_node_ips=($cluster_node_ips)
    length=${#status[@]}  
    for (( j=0; j<${length}; j++ ));
    do
        if [[ ${status[$j]} == "true" ]]; then
            if [[ ${cluster_node_ips[$j]} == ${node_to_quiece} ]]; then
                echo "Right Node Got Quieced"
                echo "Node IP : ${cluster_node_ips[$j]} Status ${status[$j]}"
            elif [[ ${cluster_node_ips[$j]} != ${node_to_quiece} ]]; then
                echo "Wrong Node Got Quieced"
                echo "Node IP : ${cluster_node_ips[$j]} Status ${status[$j]}"
                echo "Undo the quiece"
                quieced_node_ip=$(echo ${cluster_node_ips[$j]} | sed 's/:3000//g')
                docker run --name aerospike-asinfo --rm aerospike/aerospike-tools asadm -e "enable; manage quiesce undo with ${quieced_node_ip}" -h ${master_node_ip} --no-config-file
            fi 
        elif [[ ${status[$j]} == "false" ]]; then
            echo "Node IP : ${cluster_node_ips[$j]} Status ${status[$j]}"
        fi
    done
    echo "Final Status of Cluster Node Having pending_quiesce status true"
    docker run --name aerospike-asinfo --rm aerospike/aerospike-tools asadm -e "show statistics like pending_quiesce --enable" -h ${master_node_ip}
}
function run_recluster_node {
    set -x
    docker run --name aerospike-asinfo --rm aerospike/aerospike-tools asadm -e "enable;asinfo -v 'recluster:'" -h ${master_node_ip} --no-config-file
}

function check_migration_before_delete_node_process { 
    set -e
    migration=$(curl -fs --data-urlencode 'query=sum(aerospike_namespace_migrate_rx_partitions_remaining{job="aerospike", cluster_name=~".*", service=~".*", ns=~".*"}) + sum(aerospike_namespace_migrate_tx_partitions_remaining{job="aerospike", cluster_name=~".*", service=~".*", ns=~".*"})' http://prometheus-1.infra.zm.private/api/v1/query | jq -r '.data.result[].value[1]')
    if [ $migration -ne 0 ]; then
        echo "Migration is Running"
        exit 1
    else 
        echo "Cluster is Stable"
        exit 0
    fi        

}

function check_migration { 
    set -e
    migration=$(curl -fs --data-urlencode 'query=sum(aerospike_namespace_migrate_rx_partitions_remaining{job="aerospike", cluster_name=~".*", service=~".*", ns=~".*"}) + sum(aerospike_namespace_migrate_tx_partitions_remaining{job="aerospike", cluster_name=~".*", service=~".*", ns=~".*"})' http://prometheus-1.infra.zm.private/api/v1/query | jq -r '.data.result[].value[1]')
    echo "Checking Migration Now"
    while [ $migration -ne 0 ]
    do
        echo "Migration is Still Running"
        sleep 5m
        migration=$(curl -fs --data-urlencode 'query=sum(aerospike_namespace_migrate_rx_partitions_remaining{job="aerospike", cluster_name=~".*", service=~".*", ns=~".*"}) + sum(aerospike_namespace_migrate_tx_partitions_remaining{job="aerospike", cluster_name=~".*", service=~".*", ns=~".*"})' http://prometheus-1.infra.zm.private/api/v1/query | jq -r '.data.result[].value[1]')
    done
    echo "Migration Completed "
    sleep 2m
}

function stop_container_and_delete_node {
    set -e
    node_ip=$1
    node_name=$2

    if [[ "${inventory_env}" == "stg" ]]; then
        node_number=$(echo $node_name | sed 's/[^0-9]//g')
    elif [[ "${inventory_env}" == "databases" ]]; then
        node_name=$(echo $node_name | sed 's/extendtv_east_vpc1_//g' | sed 's/[^0-9]//g')
    else
        echo "Wrong Inventory Type"
        exit 1
    fi 

    node_dns_name="aerospike-${node_number}.${inventory_env}.${hosted_zone}"

    instance_id=$(aws ec2 describe-instances --filter Name=tag-key,Values=Name Name=tag-value,Values=${node_name} --region=${region} --query Reservations[*].Instances[*].[InstanceId] --output text)
    echo "Stopping the container"
    ssh_output=$(ssh -o StrictHostKeyChecking=No ec2-user@${node_dns_name} "sudo docker stop \$(sudo docker ps -q)")
    echo $ssh_output
    echo "Tip clearing the DNS NAME"
    docker run  --name aerospike-asinfo --rm aerospike/aerospike-tools asadm -e "enable;asinfo -v 'tip-clear:host-port-list=${node_dns_name}:3002'" -h ${master_node_ip} --no-config-file
    sleep 15s
    docker run  --name aerospike-asinfo --rm aerospike/aerospike-tools asadm -e "enable;asinfo -v 'tip-clear:host-port-list=${node_dns_name}:3002'" -h ${master_node_ip} --no-config-file
    # ALUMINICLEAR
    docker run  --name aerospike-asinfo --rm aerospike/aerospike-tools asadm -e "enable;asinfo -v 'services-alumni-reset'" -h ${master_node_ip} --no-config-file
    sleep 15s
    docker run  --name aerospike-asinfo --rm aerospike/aerospike-tools asadm -e "enable;asinfo -v 'services-alumni-reset'" -h ${master_node_ip} --no-config-file
    # Terminate INSTANCE
    aws ec2 terminate-instances --instance-ids ${instance_id}
}
function delete_dns_record_update_inventory_file {
    set -e
    node_ip=$1
    node_name=$2
    
    if [[ "${inventory_env}" == "stg" ]]; then
        node_number=$(echo $node_name | sed 's/[^0-9]//g')
    elif [[ "${inventory_env}" == "databases" ]]; then
        node_name=$(echo $node_name | sed 's/extendtv_east_vpc1_//g' | sed 's/[^0-9]//g')
    else
        echo "Wrong Inventory Type"
        exit 1
    fi 

    node_dns_name="aerospike-${node_number}.${inventory_env}.${hosted_zone}"

    sed -i './script/aerospike_route_53_dns_record.json' -e "s/%RECORDNAME%/${node_dns_name}/" ./script/aerospike_route_53_dns_record.json
    sed -i './script/aerospike_route_53_dns_record.json' -e "s/%SAMPLEIP%/${node_ip}/" ./script/aerospike_route_53_dns_record.json
    sed -i './script/aerospike_route_53_dns_record.json' -e "s/CREATE/DELETE/" ./script/aerospike_route_53_dns_record.json
    aws route53 change-resource-record-sets --hosted-zone-id ${hostedzone_id} --change-batch file://script/aerospike_route_53_dns_record.json
    sed -i './script/aerospike_route_53_dns_record.json' -e "s/${node_dns_name}/%RECORDNAME%/" ./script/aerospike_route_53_dns_record.json
    sed -i './script/aerospike_route_53_dns_record.json' -e "s/${node_ip}/%SAMPLEIP%/" ./script/aerospike_route_53_dns_record.json
    # Remove inventory entry
    sed -i ./ansible/inventories/${inventory_env}/hosts.yaml -e "/${node_dns_name}/d" ./ansible/inventories/$inventory_env/hosts.yaml
}
#!/bin/bash
if [ ! $# -ge 2 ]; then
  echo "Usage: ./gen_hostfiles.sh <ospd_ip_address> <ssh_config_file> "
  echo "Generates ssh config file to use OSP undercloud host as a jumpbox and creates ansible inventory file."
  exit
fi
ospd_ip_address=$1
ansible_inventory_file='hosts'
ssh_config_file=$2

# "Hackish" copy ssh key to self if we are on directly on the undercloud machine:
if [[ "${ospd_ip_address}" == "localhost" ]]; then
 cat ~stack/.ssh/id_rsa.pub >> ~stack/.ssh/authorized_keys
 chmod 0600 ~stack/.ssh/authorized_keys
 sudo bash -c "cat ~stack/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys"
 sudo bash -c "chmod 0600 /root/.ssh/authorized_keys"
fi

nodes=$(ssh -t -o "StrictHostKeyChecking no" stack@${ospd_ip_address} ". ~/stackrc; nova list | grep -i -E 'active|running'")
if [ ${#nodes} -lt 1 ]; then
    echo "ERROR: nova list failed to execute properly, please check the openstack-nova-api on the undercloud."
    exit 1
fi
controller_id=$(ssh -t -o "StrictHostKeyChecking no" stack@${ospd_ip_address} ". ~/stackrc; heat resource-show overcloud Controller | grep physical_resource_id" | awk '{print $4}')
if [ ${#controller_id} -lt 1 ]; then
   echo "Error: Controller ID is not reporting correctly. Please see check the openstack-heat-api on the undercloud."
   exit 1
fi
compute_id=$(ssh -t -o "StrictHostKeyChecking no" stack@${ospd_ip_address} ". ~/stackrc; heat resource-show overcloud Compute | grep physical_resource_id" | awk '{print $4}')
if [ ${#controller_id} -lt 1 ]; then
   echo "Error: Compute ID is not reporting correctly. Please see check the openstack-heat-api on the undercloud."
   exit 1
fi
controller_ids=$(ssh -t -o "StrictHostKeyChecking no" stack@${ospd_ip_address} ". ~/stackrc; heat resource-list ${controller_id} | grep -i controller" | awk '{print $2}')
if [ ${#controller_id} -lt 1 ]; then
   echo "Error: Controller IDs is not reporting correctly. Please see check the openstack-heat-api on the undercloud."
   exit 1
fi
compute_ids=$(ssh -t -o "StrictHostKeyChecking no" stack@${ospd_ip_address} ". ~/stackrc; heat resource-list ${compute_id} | grep -i compute" | awk '{print $2}')
if [ ${#controller_id} -lt 1 ]; then
   echo "Error: Compute IDs is not reporting correctly. Please see check the openstack-heat-api on the undercloud."
   exit 1
fi


controller_uuids=()
for controller in ${controller_ids}
do
 controller_uuids+=$(ssh -t -o "StrictHostKeyChecking no" stack@${ospd_ip_address} ". ~/stackrc; heat resource-show ${controller_id} ${controller} | grep -i nova_server_resource" | awk '{print $4}')
done
compute_uuids=()
for compute in ${compute_ids}
do
 compute_uuids+=$(ssh -t -o "StrictHostKeyChecking no" stack@${ospd_ip_address} ". ~/stackrc; heat resource-show ${compute_id} ${compute} | grep -i nova_server_resource" | awk '{print $4}')
done

echo ""
echo "---------------------------"
echo "Creating ssh config file:"
echo "---------------------------"
echo ""

echo "# Generated by gen_hostfile.sh from browbeat" | tee ${ssh_config_file}
echo "" | tee -a ${ssh_config_file}
echo "Host undercloud" | tee -a ${ssh_config_file}
echo "    Hostname ${ospd_ip_address}" | tee -a ${ssh_config_file}
echo "    IdentityFile ~/.ssh/id_rsa" | tee -a ${ssh_config_file}
echo "    StrictHostKeyChecking no" | tee -a ${ssh_config_file}
echo "    UserKnownHostsFile=/dev/null" | tee -a ${ssh_config_file}
echo "" | tee -a ${ssh_config_file}
echo "Host undercloud-root" | tee -a ${ssh_config_file}
echo "    Hostname ${ospd_ip_address}" | tee -a ${ssh_config_file}
echo "    User root" | tee -a ${ssh_config_file}
echo "    IdentityFile ~/.ssh/id_rsa" | tee -a ${ssh_config_file}
echo "    StrictHostKeyChecking no" | tee -a ${ssh_config_file}
echo "    UserKnownHostsFile=/dev/null" | tee -a ${ssh_config_file}
echo "" | tee -a ${ssh_config_file}
echo "Host undercloud-stack" | tee -a ${ssh_config_file}
echo "    Hostname ${ospd_ip_address}" | tee -a ${ssh_config_file}
echo "    User stack" | tee -a ${ssh_config_file}
echo "    IdentityFile ~/.ssh/id_rsa" | tee -a ${ssh_config_file}
echo "    StrictHostKeyChecking no" | tee -a ${ssh_config_file}
echo "    UserKnownHostsFile=/dev/null" | tee -a ${ssh_config_file}

compute_hn=()
controller_hn=()
ceph_hn=()
IFS=$'\n'
for line in $nodes; do
 uuid=$(echo $line | awk '{print $2}')
 host=$(echo $line | awk '{print $4}')
 IP=$(echo $line | awk '{print $12}' | cut -d "=" -f2)
 if grep -q $uuid <<< {$controller_uuids}; then
  controller_hn+=("$host")
 elif grep -q $uuid <<< {$compute_uuids}; then
  compute_hn+=("$host")
 else
  ceph_hn+=("$host")
 fi
 echo "" | tee -a ${ssh_config_file}
 echo "Host ${host}" | tee -a ${ssh_config_file}
 echo "    ProxyCommand ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o ConnectTimeout=60 -i ~/.ssh/id_rsa undercloud-stack -W ${IP}:22" | tee -a ${ssh_config_file}
 echo "    User heat-admin" | tee -a ${ssh_config_file}
 echo "    IdentityFile ~/.ssh/heat-admin-id_rsa" | tee -a ${ssh_config_file}
 echo "    StrictHostKeyChecking no" | tee -a ${ssh_config_file}
 echo "    UserKnownHostsFile=/dev/null" | tee -a ${ssh_config_file}
done

echo ""
echo "---------------------------"
echo "Creating ansible inventory file:"
echo "---------------------------"
echo ""
echo "[undercloud]" | tee ${ansible_inventory_file}
echo "undercloud" | tee -a ${ansible_inventory_file}
if [[ ${#controller_hn} -gt 0 ]]; then
 echo "" | tee -a ${ansible_inventory_file}
 echo "[controller]" | tee -a ${ansible_inventory_file}
 for ct in ${controller_hn[@]}; do
  echo "${ct}" | tee -a ${ansible_inventory_file}
 done
fi
if [[ ${#compute_hn} -gt 0 ]]; then
 echo "" | tee -a ${ansible_inventory_file}
 echo "[compute]" | tee -a ${ansible_inventory_file}
 for c in ${compute_hn[@]}; do
  echo "${c}" | tee -a ${ansible_inventory_file}
 done
fi
if [[ ${#ceph_hn} -gt 0 ]]; then
 echo "" | tee -a ${ansible_inventory_file}
 echo "[ceph]" | tee -a ${ansible_inventory_file}
 for ceph in ${ceph_hn[@]}; do
  echo "${ceph}" | tee -a ${ansible_inventory_file}
 done
fi
echo "" | tee -a ${ansible_inventory_file}
echo "[graphite]" | tee -a ${ansible_inventory_file}
echo "## example host entry." | tee -a ${ansible_inventory_file}
echo "#host-01" | tee -a ${ansible_inventory_file}
echo "" | tee -a ${ansible_inventory_file}
echo "[grafana]" | tee -a ${ansible_inventory_file}
echo "## example host entry." | tee -a ${ansible_inventory_file}
echo "#host-02" | tee -a ${ansible_inventory_file}

echo "---------------------------"
echo "IMPORTANT: If you plan on deploying graphite and grafana, update hosts and make sure"
echo "           the [graphite] and [grafana] hosts entries are updated with valid hosts."
echo "           You will need to have passwordless access to root on these hosts."
echo "---------------------------"
echo "" | tee -a ${ansible_inventory_file}
echo "[elk]" | tee -a ${ansible_inventory_file}
echo "## example host entry." | tee -a ${ansible_inventory_file}
echo "#host-01" | tee -a ${ansible_inventory_file}
echo "" | tee -a ${ansible_inventory_file}
echo "[elk-client]" | tee -a ${ansible_inventory_file}
echo "## example host entry." | tee -a ${ansible_inventory_file}
echo "#host-02" | tee -a ${ansible_inventory_file}

echo "---------------------------"
echo "IMPORTANT: If you plan on deploying ELK and ELK clients, update hosts and make sure"
echo "           the [elk] and [elk-client] hosts entries are updated with valid hosts."
echo "           You will need to have passwordless access to root on these hosts."
echo "---------------------------"

# Before referencing a host in ~/.ssh/config, ensure correct permissions on ssh config file
chmod 0600 ${ssh_config_file}

# Copy heat-admin key so we can use jumpbox
echo ""
echo "---------------------------"
echo "Copying heat-admin key to local machine(~/.ssh/heat-admin-id_rsa) to for use with ssh config file"
echo "---------------------------"
echo ""
scp "stack@${ospd_ip_address}":/home/stack/.ssh/id_rsa ~/.ssh/heat-admin-id_rsa

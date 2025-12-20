#!/bin/bash

# Stop on error
set -e

# --- SETTINGS ---
RESOURCE_GROUP="VPN_RG"
LOCATION="germanywestcentral"     # One of the cheapest/closest regions
VM_NAME="VPN-VM"
VM_IMAGE="Ubuntu2404"      # Ubuntu 24.04 LTS
VM_SIZE="Standard_B1s"     # Recommended size
ADMIN_USER="azureuser"
CLOUD_INIT_FILE="final_cloud_init.yaml"

# Colored Outputs
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}[1/5] Checking Cloud-Init file...${NC}"
if [ ! -f "$CLOUD_INIT_FILE" ]; then
    echo "ERROR: $CLOUD_INIT_FILE not found! Please run 'pwsh -File automation/generate_cloud_init.ps1' first."
    exit 1
fi

echo -e "${GREEN}[2/5] Creating Resource Group ($RESOURCE_GROUP)...${NC}"
az group create --name $RESOURCE_GROUP --location $LOCATION --output none

echo -e "${GREEN}[3/5] Creating VM (with Static IP)...${NC}"
# --public-ip-address-allocation static : Ensures IP doesn't change
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --image $VM_IMAGE \
  --size $VM_SIZE \
  --admin-username $ADMIN_USER \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --public-ip-address-allocation static \
  --custom-data @$CLOUD_INIT_FILE \
  --output none

echo -e "${GREEN}[4/5] Opening Ports (NSG)...${NC}"
# WireGuard UDP
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name ${VM_NAME}NSG --name AllowWireGuardUDP --priority 1010 --protocol Udp --destination-port-ranges 51820 --access Allow --direction Inbound --output none
# WireGuard Web UI
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name ${VM_NAME}NSG --name AllowWireGuardWeb --priority 1020 --protocol Tcp --destination-port-ranges 51821 --access Allow --direction Inbound --output none
# AdGuard Web UI
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name ${VM_NAME}NSG --name AllowAdGuardWeb --priority 1030 --protocol Tcp --destination-port-ranges 8080 --access Allow --direction Inbound --output none
# SSH (Already open but ensuring)
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name ${VM_NAME}NSG --name AllowSSH --priority 1000 --protocol Tcp --destination-port-ranges 22 --access Allow --direction Inbound --output none

echo -e "${GREEN}[5/5] Installation Complete! Retrieving info...${NC}"
IP_ADDRESS=$(az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --show-details --query publicIps --output tsv)

echo "--------------------------------------------------"
echo -e "Server IP Address (Static): ${GREEN}$IP_ADDRESS${NC}"
echo "--------------------------------------------------"
echo "Please update 'automation/config.yaml' -> 'server: ip' with this IP."
echo "Then run 'pwsh -File automation/verify_deployment.ps1' to verify installation."
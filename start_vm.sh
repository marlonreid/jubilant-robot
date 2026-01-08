#!/bin/bash
echo "Starting VM..."
az vm start --resource-group ollama-poc --name ollama-test

echo "Waiting for VM to be ready..."
sleep 20

VM_IP=$(az vm show -d --resource-group ollama-poc --name ollama-test --query publicIps -o tsv)
echo ""
echo "✓ VM started!"
echo "Open WebUI: http://$VM_IP:3000"
echo "SSH: ssh azureuser@$VM_IP"

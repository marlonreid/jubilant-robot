#!/bin/bash
echo "Checking VM status..."
echo ""

STATUS=$(az vm get-instance-view \
  --resource-group ollama-poc \
  --name ollama-test \
  --query instanceView.statuses[1].displayStatus -o tsv)

echo "Status: $STATUS"

if [ "$STATUS" == "VM running" ]; then
    echo ""
    echo "⚠️  VM is RUNNING - costing ~£0.42/hour"
    VM_IP=$(az vm show -d --resource-group ollama-poc --name ollama-test --query publicIps -o tsv)
    echo "Open WebUI: http://$VM_IP:3000"
    echo ""
    echo "To stop: ./stop-vm.sh"
else
    echo ""
    echo "✓ VM is stopped - only storage costs (~£0.40/day)"
    echo ""
    echo "To start: ./start-vm.sh"
fi

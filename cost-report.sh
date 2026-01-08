#!/bin/bash
echo "VM Cost Report (Last 7 Days)"
echo "=============================="
echo ""

az consumption usage list \
  --start-date $(date -d '7 days ago' +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --query "[?contains(instanceName, 'ollama-test')].{Date:usageStart, Service:meterName, Quantity:quantity, Cost:pretaxCost}" \
  -o table

echo ""
echo "Current VM Status:"
./check-vm.sh

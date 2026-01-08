#!/bin/bash

echo "⚠️  This will delete EVERYTHING:"
echo "  - VM (ollama-test)"
echo "  - All data"
echo "  - Resource group"
echo ""
read -p "Are you absolutely sure? Type 'yes' to confirm: " -r
echo

if [[ $REPLY == "yes" ]]; then
    echo "Deleting resource group and all resources..."
    az group delete --name ollama-poc --yes --no-wait
    echo ""
    echo "✓ Deletion started (runs in background)"
    echo "✓ All resources will be removed in 5-10 minutes"
    echo "✓ No more costs will be incurred"
else
    echo "Cancelled. Nothing deleted."
fi

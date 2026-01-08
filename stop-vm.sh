#!/bin/bash
echo "Stopping VM..."
az vm deallocate --resource-group ollama-poc --name ollama-test
echo "✓ VM stopped. Cost now: ~£0.40/day (storage only)"

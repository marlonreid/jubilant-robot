#!/bin/bash
# check-network-status.sh
# Shows current network lock status

set -e

VM_IP="YOUR_VM_IP"
ADMIN_USER="azureuser"

if [ ! -z "$1" ]; then
    VM_IP=$1
fi

if [ -z "$VM_IP" ]; then
    echo "Usage: ./check-network-status.sh <VM_IP>"
    exit 1
fi

echo "Checking network status on VM..."
echo ""

ssh -o StrictHostKeyChecking=no ${ADMIN_USER}@${VM_IP} << 'CHECKSCRIPT'
if [ -f ~/.network-status ]; then
    cat ~/.network-status
    echo ""
    
    STATUS=$(head -1 ~/.network-status)
    if [ "$STATUS" == "LOCKED" ]; then
        echo "🔒 Network is LOCKED (offline mode)"
        echo ""
        echo "Testing connectivity:"
        
        # Test external
        if curl -s --max-time 3 https://google.com &>/dev/null; then
            echo "  ⚠ External: Accessible (unexpected!)"
        else
            echo "  ✓ External: Blocked (as expected)"
        fi
        
        # Test Ollama
        if curl -s --max-time 3 http://localhost:11434/api/tags &>/dev/null; then
            echo "  ✓ Ollama: Working locally"
        else
            echo "  ✗ Ollama: Not responding"
        fi
        
    else
        echo "🔓 Network is UNLOCKED (online mode)"
        echo ""
        echo "Testing connectivity:"
        
        if curl -s --max-time 3 https://google.com &>/dev/null; then
            echo "  ✓ External: Accessible"
        else
            echo "  ✗ External: Blocked (unexpected!)"
        fi
        
        if curl -s --max-time 3 http://localhost:11434/api/tags &>/dev/null; then
            echo "  ✓ Ollama: Working"
        else
            echo "  ✗ Ollama: Not responding"
        fi
    fi
else
    echo "No network status file found (likely unlocked by default)"
fi

echo ""
echo "Active iptables rules:"
sudo iptables -L LOCKDOWN -n 2>/dev/null || echo "  No LOCKDOWN chain (network is open)"
CHECKSCRIPT

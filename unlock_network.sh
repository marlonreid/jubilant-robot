#!/bin/bash
# unlock-network.sh
# Restores internet access for updates and model downloads

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VM_IP="YOUR_VM_IP"  # Replace with actual IP or pass as argument
ADMIN_USER="azureuser"

if [ ! -z "$1" ]; then
    VM_IP=$1
fi

if [ -z "$VM_IP" ]; then
    echo -e "${RED}Error: VM IP not specified${NC}"
    echo "Usage: ./unlock-network.sh <VM_IP>"
    exit 1
fi

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔓 Unlocking Network - Restoring Internet${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cat > /tmp/unlock-network.sh << 'UNLOCKSCRIPT'
#!/bin/bash
set -e

echo "Removing network lockdown rules..."

# Check if backup exists
if [ ! -f ~/iptables-backup.rules ]; then
    echo "⚠ No backup found, flushing all rules"
    sudo iptables -F
    sudo iptables -X
    sudo iptables -t nat -F
    sudo iptables -t nat -X
    sudo iptables -t mangle -F
    sudo iptables -t mangle -X
    sudo iptables -P INPUT ACCEPT
    sudo iptables -P FORWARD ACCEPT
    sudo iptables -P OUTPUT ACCEPT
else
    echo "Restoring from backup..."
    sudo iptables-restore < ~/iptables-backup.rules
fi

# Remove LOCKDOWN chain if it exists
sudo iptables -D OUTPUT -j LOCKDOWN 2>/dev/null || true
sudo iptables -D INPUT -j LOCKDOWN 2>/dev/null || true
sudo iptables -F LOCKDOWN 2>/dev/null || true
sudo iptables -X LOCKDOWN 2>/dev/null || true

# Update status file
echo "UNLOCKED" > ~/.network-status
echo "Unlocked at: $(date)" >> ~/.network-status

echo ""
echo "✓ Network lockdown removed"
echo ""

# Test that external access works
echo "Testing internet connectivity..."
if curl -s --max-time 5 https://google.com &>/dev/null; then
    echo "✓ External internet accessible (google.com reachable)"
else
    echo "⚠ Warning: External internet still blocked or connectivity issue"
fi

# Test local services still work
if curl -s --max-time 3 http://localhost:11434/api/tags &>/dev/null; then
    echo "✓ Ollama API still accessible"
else
    echo "⚠ Warning: Ollama API not responding"
fi

echo ""
echo "Network is now fully open for:"
echo "  ✓ Model downloads (ollama pull)"
echo "  ✓ Package updates (apt update)"
echo "  ✓ Software installation"
echo "  ✓ All internet access"
echo ""
echo "Network status saved to ~/.network-status"
UNLOCKSCRIPT

echo "Connecting to VM and unlocking network..."
scp -o StrictHostKeyChecking=no /tmp/unlock-network.sh ${ADMIN_USER}@${VM_IP}:/tmp/
ssh -o StrictHostKeyChecking=no ${ADMIN_USER}@${VM_IP} 'bash /tmp/unlock-network.sh'

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Network Unlocked Successfully${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}You can now:${NC}"
echo "  - Download new models: ssh $ADMIN_USER@$VM_IP 'ollama pull phi4'"
echo "  - Update packages: ssh $ADMIN_USER@$VM_IP 'sudo apt update'"
echo "  - Install software"
echo ""
echo -e "${YELLOW}To lock again: ./lock-network.sh $VM_IP${NC}"
echo ""

#!/bin/bash
# lock-network.sh
# Blocks all outgoing internet while keeping local access to Open WebUI

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
    echo "Usage: ./lock-network.sh <VM_IP>"
    exit 1
fi

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}🔒 Locking Down Network - Proving Offline Mode${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

cat > /tmp/lock-network.sh << 'LOCKSCRIPT'
#!/bin/bash
set -e

echo "Creating network lockdown rules..."

# Backup existing iptables rules
sudo iptables-save > ~/iptables-backup.rules

# Create new chain for lockdown
sudo iptables -N LOCKDOWN 2>/dev/null || sudo iptables -F LOCKDOWN

# Allow all local traffic (loopback)
sudo iptables -A LOCKDOWN -i lo -j ACCEPT
sudo iptables -A LOCKDOWN -o lo -j ACCEPT

# Allow established connections (keeps existing SSH alive)
sudo iptables -A LOCKDOWN -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow incoming SSH (so you can still manage)
sudo iptables -A LOCKDOWN -p tcp --dport 22 -j ACCEPT

# Allow incoming HTTP/HTTPS to Open WebUI (port 3000)
sudo iptables -A LOCKDOWN -p tcp --dport 3000 -j ACCEPT

# Allow Docker internal networking
sudo iptables -A LOCKDOWN -s 172.17.0.0/16 -d 172.17.0.0/16 -j ACCEPT
sudo iptables -A LOCKDOWN -s 172.18.0.0/16 -d 172.18.0.0/16 -j ACCEPT

# Allow Ollama to talk to Open WebUI (local)
sudo iptables -A LOCKDOWN -p tcp --dport 11434 -j ACCEPT

# BLOCK all other outgoing traffic
sudo iptables -A LOCKDOWN -j REJECT --reject-with icmp-host-unreachable

# Apply the chain
sudo iptables -I OUTPUT 1 -j LOCKDOWN
sudo iptables -I INPUT 1 -j LOCKDOWN

# Make persistent across reboots
sudo mkdir -p /etc/iptables
sudo iptables-save > /etc/iptables/rules.v4

# Create status file
echo "LOCKED" > ~/.network-status
echo "Locked at: $(date)" >> ~/.network-status

echo ""
echo "✓ Network locked down"
echo ""
echo "What's allowed:"
echo "  ✓ Local SSH access (port 22)"
echo "  ✓ Open WebUI access (port 3000)"
echo "  ✓ Docker internal networking"
echo "  ✓ Ollama ↔ Open WebUI communication"
echo ""
echo "What's blocked:"
echo "  ✗ All outgoing internet traffic"
echo "  ✗ Package updates (apt, pip, etc.)"
echo "  ✗ Model downloads"
echo "  ✗ External API calls"
echo ""

# Test that external access is blocked
echo "Testing network lockdown..."
if ! curl -s --max-time 3 https://google.com &>/dev/null; then
    echo "✓ External internet blocked (google.com unreachable)"
else
    echo "⚠ Warning: External internet still accessible!"
fi

# Test that local services work
if curl -s --max-time 3 http://localhost:11434/api/tags &>/dev/null; then
    echo "✓ Ollama API accessible locally"
else
    echo "⚠ Warning: Ollama API not responding"
fi

echo ""
echo "Network status saved to ~/.network-status"
LOCKSCRIPT

echo "Connecting to VM and applying network lockdown..."
scp -o StrictHostKeyChecking=no /tmp/lock-network.sh ${ADMIN_USER}@${VM_IP}:/tmp/
ssh -o StrictHostKeyChecking=no ${ADMIN_USER}@${VM_IP} 'bash /tmp/lock-network.sh'

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Network Locked Down Successfully${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Demo Points for C-Level:${NC}"
echo ""
echo "  1. Open WebUI still works: http://$VM_IP:3000"
echo "  2. AI models still respond (all data is local)"
echo "  3. Try pinging google.com from VM (will fail)"
echo "  4. Try apt update (will fail)"
echo "  5. Generate tests - everything works!"
echo ""
echo -e "${RED}⚠️  Remember: While locked, you CANNOT:${NC}"
echo "  - Download new models"
echo "  - Install packages"
echo "  - Update software"
echo ""
echo -e "${YELLOW}To unlock: ./unlock-network.sh $VM_IP${NC}"
echo ""

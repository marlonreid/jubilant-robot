#!/bin/bash
set -e  # Exit on any error

echo "=================================================="
echo "AI Test Generation POC - Complete Setup"
echo "UK South Region with Auto-Shutdown"
echo "=================================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RESOURCE_GROUP="ollama-poc"
VM_NAME="ollama-test"
LOCATION="uksouth"
VM_SIZE="Standard_NC4as_T4_v3"
MAX_PRICE="0.20"  # Spot instance max price
ADMIN_USER="azureuser"
SHUTDOWN_TIME="1800"  # 6 PM (24-hour format: HHMM)
TIMEZONE="GMT Standard Time"

echo -e "${BLUE}Configuration:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  VM Name: $VM_NAME"
echo "  Location: $LOCATION"
echo "  VM Size: $VM_SIZE"
echo "  Auto-shutdown: ${SHUTDOWN_TIME:0:2}:${SHUTDOWN_TIME:2:2} $TIMEZONE"
echo ""

echo -e "${YELLOW}Step 1: Creating Resource Group${NC}"
az group create --name $RESOURCE_GROUP --location $LOCATION
echo -e "${GREEN}✓ Resource group created${NC}"

echo ""
echo -e "${YELLOW}Step 2: Creating Spot VM with GPU${NC}"
echo "This will create a $VM_SIZE instance in UK South..."
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --size $VM_SIZE \
  --priority Spot \
  --max-price $MAX_PRICE \
  --eviction-policy Deallocate \
  --image Ubuntu2204 \
  --admin-username $ADMIN_USER \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --location $LOCATION

echo -e "${GREEN}✓ VM created${NC}"

echo ""
echo -e "${YELLOW}Step 3: Opening Firewall Ports${NC}"
# SSH (22)
az vm open-port \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --port 22 \
  --priority 1000

# Open WebUI (3000)
az vm open-port \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --port 3000 \
  --priority 1001

echo -e "${GREEN}✓ Ports opened (22, 3000)${NC}"

echo ""
echo -e "${YELLOW}Step 4: Configuring Azure Auto-Shutdown${NC}"
az vm auto-shutdown \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --time $SHUTDOWN_TIME \
  --time-zone "$TIMEZONE"

echo -e "${GREEN}✓ Auto-shutdown configured for ${SHUTDOWN_TIME:0:2}:${SHUTDOWN_TIME:2:2} GMT daily${NC}"

echo ""
echo -e "${YELLOW}Step 5: Getting VM Public IP${NC}"
VM_IP=$(az vm show -d \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --query publicIps -o tsv)

echo -e "${GREEN}✓ VM IP Address: $VM_IP${NC}"

echo ""
echo -e "${YELLOW}Step 6: Waiting for VM to be ready (30 seconds)...${NC}"
sleep 30

echo ""
echo -e "${YELLOW}Step 7: Installing software on VM${NC}"
echo "This will take 5-10 minutes..."

# Create the remote setup script
cat > /tmp/remote-setup.sh << 'REMOTESCRIPT'
#!/bin/bash
set -e

echo "=== Installing System Updates ==="
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

echo ""
echo "=== Installing NVIDIA Drivers ==="
sudo apt-get install -y -qq ubuntu-drivers-common
sudo ubuntu-drivers autoinstall || echo "Driver install attempted"

echo ""
echo "=== Installing Docker ==="
sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -qq
sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER

echo ""
echo "=== Installing Ollama ==="
curl -fsSL https://ollama.com/install.sh | sh

echo ""
echo "=== Starting Ollama Service ==="
sudo systemctl start ollama
sudo systemctl enable ollama
sleep 5

echo ""
echo "=== Pulling AI Models ==="
echo "This may take 5-10 minutes depending on connection speed..."
echo "Pulling Phi-3.5 (4GB model for code generation)..."
ollama pull phi3.5 &
PID1=$!

echo "Pulling DeepSeek Coder (4GB alternative)..."
ollama pull deepseek-coder:6.7b &
PID2=$!

# Wait for both downloads
wait $PID1
wait $PID2

echo ""
echo "=== Installing NVIDIA Container Toolkit ==="
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update -qq
sudo apt-get install -y -qq nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

echo ""
echo "=== Starting Open WebUI ==="
docker run -d \
  --gpus all \
  -p 3000:8080 \
  --add-host=host.docker.internal:host-gateway \
  -v open-webui:/app/backend/data \
  --name open-webui \
  --restart always \
  ghcr.io/open-webui/open-webui:main

echo ""
echo "=== Cloning Test Projects ==="
cd ~
echo "Cloning WordPress (PHP)..."
git clone --depth 1 https://github.com/WordPress/wordpress-develop.git &
PID1=$!

echo "Cloning eShopOnWeb (C# .NET 8)..."
git clone --depth 1 https://github.com/dotnet-architecture/eShopOnWeb.git &
PID2=$!

wait $PID1
wait $PID2

echo ""
echo "=== Installing .NET SDK 8.0 ==="
wget -q https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh
chmod +x dotnet-install.sh
./dotnet-install.sh --channel 8.0 --install-dir ~/.dotnet
echo 'export DOTNET_ROOT=$HOME/.dotnet' >> ~/.bashrc
echo 'export PATH=$PATH:$HOME/.dotnet:$HOME/.dotnet/tools' >> ~/.bashrc

echo ""
echo "=== Creating Custom Ollama Models ==="

# PHP Test Expert
cat > /tmp/PHPModelfile << 'EOF'
FROM phi3.5

PARAMETER temperature 0.3
PARAMETER top_p 0.9
PARAMETER num_ctx 4096

SYSTEM """
You are an expert PHP developer specializing in writing PHPUnit tests.

When generating tests, always:
1. First explain what needs to be tested and why
2. List edge cases to cover
3. Then write the complete PHPUnit test
4. Use appropriate mocking (PHPUnit's mock builder or Mockery)
5. Follow PSR-12 coding standards
6. Use data providers for multiple test cases where appropriate

Format your response as:
## Analysis
[What needs testing and why]

## Edge Cases
[List of test scenarios]

## Test Code
```php
<?php
[Complete PHPUnit test class with namespace, use statements, etc.]
```

Be thorough but concise. Focus on practical, maintainable tests that follow best practices.
"""
EOF

ollama create php-test-expert -f /tmp/PHPModelfile

# C# Test Expert
cat > /tmp/CSharpModelfile << 'EOF'
FROM phi3.5

PARAMETER temperature 0.3
PARAMETER top_p 0.9
PARAMETER num_ctx 4096

SYSTEM """
You are an expert C# developer specializing in .NET 8+ and xUnit test generation.

When generating tests, always:
1. Use xUnit as the testing framework
2. Use Moq for mocking dependencies
3. Use FluentAssertions for readable assertions
4. Follow AAA pattern (Arrange, Act, Assert)
5. Use [Theory] with [InlineData] for parameterized tests where appropriate
6. Handle async/await properly
7. Follow modern C# conventions (nullable reference types, latest syntax)
8. Include proper using statements and namespaces

Format your response as:
## Testing Strategy
[What needs testing and why]

## Edge Cases
[List of test scenarios]

## Test Code
```csharp
using Xunit;
using Moq;
using FluentAssertions;
[Complete xUnit test class with proper structure]
```

Write maintainable, professional tests that follow .NET best practices and modern C# conventions.
"""
EOF

ollama create csharp-test-expert -f /tmp/CSharpModelfile

echo ""
echo "=== Creating Audit Log Directory ==="
mkdir -p ~/ai-audit-logs
cat > ~/ai-audit-logs/README.txt << 'EOF'
AI Test Generation Audit Logs

This directory will contain logs of all AI interactions:
- Prompts sent to the model
- Generated responses
- Timestamps and user information
- Context used (RAG retrievals)

Format: JSON Lines (.jsonl)
Each line is a complete JSON object representing one interaction.

Example:
{"timestamp": "2026-01-08T14:30:00Z", "user": "dev1", "model": "php-test-expert", "prompt": "...", "response": "..."}
EOF

echo ""
echo "=== Configuring VM-Level Auto-Shutdown (Backup) ==="
cat > ~/auto-shutdown-backup.sh << 'EOF'
#!/bin/bash
# Backup auto-shutdown script (in case Azure auto-shutdown fails)
# Runs hourly via cron

CURRENT_HOUR=$(date +%H)
CURRENT_DAY=$(date +%u)  # 1=Monday, 7=Sunday

# Weekdays after 6 PM
if [ $CURRENT_DAY -le 5 ] && [ $CURRENT_HOUR -ge 18 ]; then
    logger "Auto-shutdown: After hours (weekday 6PM+)"
    echo "$(date): Auto-shutdown triggered (weekday evening)" >> ~/ai-audit-logs/shutdown.log
    sudo shutdown -h +5 "Auto-shutdown: After hours (5 minute warning)"
fi

# Weekends after 2 PM
if [ $CURRENT_DAY -gt 5 ] && [ $CURRENT_HOUR -ge 14 ]; then
    logger "Auto-shutdown: Weekend after 2PM"
    echo "$(date): Auto-shutdown triggered (weekend)" >> ~/ai-audit-logs/shutdown.log
    sudo shutdown -h +5 "Auto-shutdown: Weekend (5 minute warning)"
fi
EOF

chmod +x ~/auto-shutdown-backup.sh

# Add to crontab (runs every hour at :00)
(crontab -l 2>/dev/null; echo "0 * * * * /home/azureuser/auto-shutdown-backup.sh") | crontab -

echo ""
echo "=== Adding Cost Reminder to Login Banner ==="
cat >> ~/.bashrc << 'EOF'

# Cost Reminder
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║    💰 VM COST REMINDER 💰                 ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "  Running: ~£0.42/hour (~£10/day if left on)"
echo "  Azure Auto-shutdown: 6 PM GMT daily"
echo ""
echo "  Manual stop: sudo shutdown -h now"
echo "  Or from Azure: az vm deallocate --name ollama-test"
echo ""
EOF

echo ""
echo "=== Verifying Installation ==="
echo "Available Ollama models:"
ollama list

echo ""
echo "Docker containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "Test projects:"
ls -lh ~ | grep -E "wordpress|eShop"

echo ""
echo "=== Setup Complete! ==="
REMOTESCRIPT

# Copy script to VM and execute
echo "Connecting to VM at $VM_IP and running setup..."
echo "(This will take 5-10 minutes)"
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null /tmp/remote-setup.sh ${ADMIN_USER}@${VM_IP}:/tmp/
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${ADMIN_USER}@${VM_IP} 'bash /tmp/remote-setup.sh'

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                ║${NC}"
echo -e "${GREEN}║           🎉 SETUP COMPLETE! 🎉                ║${NC}"
echo -e "${GREEN}║                                                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Access Information:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  🌐 Open WebUI:  ${GREEN}http://$VM_IP:3000${NC}"
echo -e "  🔐 SSH Access:  ${YELLOW}ssh $ADMIN_USER@$VM_IP${NC}"
echo -e "  📍 Region:      ${BLUE}UK South${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Available AI Models:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  📦 phi3.5              - General purpose (4GB)"
echo "  📦 deepseek-coder:6.7b - Code specialist (4GB)"
echo "  🎯 php-test-expert     - Custom PHP testing"
echo "  🎯 csharp-test-expert  - Custom C# testing"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Test Projects Available:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  📁 ~/wordpress-develop  - PHP (WordPress core)"
echo "  📁 ~/eShopOnWeb         - C# .NET 8 (Microsoft reference app)"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}💰 Cost Management:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${GREEN}✓ Azure Auto-Shutdown:${NC} Enabled (6 PM GMT daily)"
echo -e "  ${GREEN}✓ Backup Shutdown:${NC}     Configured (cron)"
echo ""
echo -e "  Running:  ${RED}~£0.42/hour${NC} (~£10/day if left on)"
echo -e "  Stopped:  ${GREEN}~£0.40/day${NC} (storage only)"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Useful Commands:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Stop VM (save money):"
echo -e "    ${YELLOW}az vm deallocate --resource-group $RESOURCE_GROUP --name $VM_NAME${NC}"
echo ""
echo "  Start VM:"
echo -e "    ${YELLOW}az vm start --resource-group $RESOURCE_GROUP --name $VM_NAME${NC}"
echo ""
echo "  Check VM status:"
echo -e "    ${YELLOW}az vm get-instance-view --resource-group $RESOURCE_GROUP --name $VM_NAME --query instanceView.statuses[1].displayStatus${NC}"
echo ""
echo "  Delete everything:"
echo -e "    ${YELLOW}az group delete --name $RESOURCE_GROUP --yes --no-wait${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  1. Open http://$VM_IP:3000 in your browser"
echo "  2. Create an account (first user becomes admin)"
echo "  3. Select a model: 'php-test-expert' or 'csharp-test-expert'"
echo "  4. Start generating tests!"
echo ""
echo -e "${RED}⚠️  IMPORTANT REMINDERS:${NC}"
echo ""
echo -e "  • VM will ${RED}auto-shutdown at 6 PM GMT${NC} daily"
echo -e "  • ${RED}Manually stop when done${NC} to save costs"
echo -e "  • Weekend left running = ${RED}~£24 wasted!${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

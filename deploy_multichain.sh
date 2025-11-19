#!/bin/bash

# Multi-Chain Deployment Script for GeniusSwapRouter
# Compatible with macOS default bash (3.x)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check required environment variables
if [ -z "$SWAPROUTER_DEPLOYER_PRIVATE_KEY" ]; then
    echo -e "${RED}Error: SWAPROUTER_DEPLOYER_PRIVATE_KEY not set${NC}"
    exit 1
fi

if [ -z "$SWAPROUTER_FEE_COLLECTOR_ADDRESS" ]; then
    echo -e "${RED}Error: SWAPROUTER_FEE_COLLECTOR_ADDRESS not set${NC}"
    exit 1
fi

if [ -z "$SWAPROUTER_ADMIN_ADDRESS" ]; then
    echo -e "${RED}Error: SWAPROUTER_ADMIN_ADDRESS not set${NC}"
    exit 1
fi

# Create a temporary file to store deployment results
RESULTS_FILE=$(mktemp)

echo -e "${BLUE}==========================================="
echo "Multi-Chain GeniusSwapRouter Deployment"
echo -e "===========================================${NC}\n"

# Function to get RPC URL for a chain
get_rpc_url() {
    case $1 in
        avalanche) echo "$AVALANCHE_RPC_URL" ;;
        base) echo "$BASE_RPC_URL" ;;
        arbitrum) echo "$ARBITRUM_RPC_URL" ;;
        optimism) echo "$OPTIMISM_RPC_URL" ;;
        bsc) echo "$BSC_RPC_URL" ;;
        polygon) echo "$POLYGON_RPC_URL" ;;
        *) echo "" ;;
    esac
}

# Define chains (excluding ethereum, sonic, hyper)
CHAINS="avalanche base arbitrum optimism bsc polygon"

# Deploy to each chain
for chain in $CHAINS; do
    echo -e "${YELLOW}Deploying to ${chain}...${NC}"
    
    rpc_url=$(get_rpc_url "$chain")
    
    if [ -z "$rpc_url" ]; then
        echo -e "${RED}Error: RPC URL not found for ${chain}${NC}\n"
        echo "${chain}|FAILED|N/A" >> "$RESULTS_FILE"
        continue
    fi
    
    # Run deployment
    output=$(forge script script/deployment/DeployGeniusSwapRouter.s.sol \
        --rpc-url "$rpc_url" \
        --private-key "$SWAPROUTER_DEPLOYER_PRIVATE_KEY" \
        --broadcast \
        --legacy 2>&1) || {
        echo -e "${RED}Failed to deploy on ${chain}${NC}\n"
        echo "${chain}|FAILED|N/A" >> "$RESULTS_FILE"
        continue
    }
    
    # Extract deployed address from output
    address=$(echo "$output" | grep -oE "GeniusSwapRouter deployed at: 0x[a-fA-F0-9]{40}" | grep -oE "0x[a-fA-F0-9]{40}" | head -1)
    
    if [ -n "$address" ]; then
        echo -e "${GREEN}✓ Successfully deployed on ${chain}${NC}"
        echo -e "  Address: ${address}\n"
        echo "${chain}|SUCCESS|${address}" >> "$RESULTS_FILE"
    else
        echo -e "${RED}✗ Deployment failed on ${chain}${NC}\n"
        echo "${chain}|FAILED|N/A" >> "$RESULTS_FILE"
    fi
done

# Print summary
echo -e "\n${BLUE}==========================================="
echo "        DEPLOYMENT SUMMARY"
echo -e "===========================================${NC}\n"

success_count=0
fail_count=0
total_count=0

while IFS='|' read -r chain status address; do
    total_count=$((total_count + 1))
    if [ "$status" = "SUCCESS" ]; then
        echo -e "${GREEN}[✓] ${chain}${NC}"
        echo -e "    Address: ${address}"
        success_count=$((success_count + 1))
    else
        echo -e "${RED}[✗] ${chain}${NC}"
        echo -e "    Status: Deployment Failed"
        fail_count=$((fail_count + 1))
    fi
    echo ""
done < "$RESULTS_FILE"

echo -e "${BLUE}==========================================="
echo "Total Chains: ${total_count}"
echo -e "${GREEN}Successful: ${success_count}${NC}"
echo -e "${RED}Failed: ${fail_count}${NC}"
echo -e "${BLUE}===========================================${NC}"

# Clean up
rm "$RESULTS_FILE"

# Exit with error if any deployment failed
if [ $fail_count -gt 0 ]; then
    exit 1
fi
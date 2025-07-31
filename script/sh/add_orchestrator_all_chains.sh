#!/bin/bash

# Script to run AddOrchestrator on all supported chains
# Usage: ./script/sh/add_orchestrator_all_chains.sh

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if .env file exists
if [ ! -f ".env" ]; then
    print_error ".env file not found. Please make sure you have a .env file with the required environment variables."
    exit 1
fi

# Source environment variables
source .env

# Set deployment environment
export DEPLOY_ENV=PROD

print_status "Starting AddOrchestrator deployment on all chains with DEPLOY_ENV=PROD"

# Array of chains with their RPC URL environment variables
declare -A chains=(
    ["AVALANCHE"]="AVALANCHE_RPC_URL"
    ["BASE"]="BASE_RPC_URL"
    ["ARBITRUM"]="ARBITRUM_RPC_URL"
    ["OPTIMISM"]="OPTIMISM_RPC_URL"
    ["SONIC"]="SONIC_RPC_URL"
    ["POLYGON"]="POLYGON_RPC_URL"
    ["BSC"]="BSC_RPC_URL"
    ["ETHEREUM"]="ETHEREUM_RPC_URL"
)

# Function to run the script on a specific chain
run_on_chain() {
    local chain_name=$1
    local rpc_env_var=$2
    
    print_status "Running AddOrchestrator on $chain_name..."
    
    # Check if RPC URL is set
    if [ -z "${!rpc_env_var}" ]; then
        print_warning "RPC URL for $chain_name not found (${rpc_env_var} not set). Skipping..."
        return 1
    fi
    
    # Run the forge script
    if forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator \
        --rpc-url "${!rpc_env_var}" \
        --broadcast \
        -vvvv \
        --via-ir; then
        print_success "AddOrchestrator completed successfully on $chain_name"
        return 0
    else
        print_error "AddOrchestrator failed on $chain_name"
        return 1
    fi
}

# Track results
successful_chains=()
failed_chains=()

# Run on each chain
for chain_name in "${!chains[@]}"; do
    rpc_env_var="${chains[$chain_name]}"
    
    if run_on_chain "$chain_name" "$rpc_env_var"; then
        successful_chains+=("$chain_name")
    else
        failed_chains+=("$chain_name")
    fi
    
    echo ""  # Add spacing between chains
done

# Print summary
echo "=========================================="
print_status "Deployment Summary:"
echo "=========================================="

if [ ${#successful_chains[@]} -gt 0 ]; then
    print_success "Successfully deployed on: ${successful_chains[*]}"
fi

if [ ${#failed_chains[@]} -gt 0 ]; then
    print_error "Failed to deploy on: ${failed_chains[*]}"
fi

echo "=========================================="

# Exit with error if any chain failed
if [ ${#failed_chains[@]} -gt 0 ]; then
    print_error "Some chains failed to deploy. Please check the logs above."
    exit 1
else
    print_success "All chains deployed successfully!"
    exit 0
fi 
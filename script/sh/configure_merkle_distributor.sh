#!/bin/bash

# Set environment variable to mute Foundry nightly warning
export FOUNDRY_DISABLE_NIGHTLY_WARNING=true

# Arrays for chain names and their corresponding chain identifiers for Foundry
chains=("BASE" "OPTIMISM" "AVAX" "ARBITRUM" "BSC" "ETHEREUM" "POLYGON" "SONIC")

# Map chain names to their Foundry chain identifiers
declare -A chain_ids=(
  ["BASE"]="base"
  ["OPTIMISM"]="optimism"
  ["AVAX"]="avalanche"
  ["ARBITRUM"]="arbitrum"
  ["BSC"]="bsc"
  ["ETHEREUM"]="mainnet"
  ["POLYGON"]="polygon"
  ["SONIC"]="sonic"
)

# Check if environment is provided as argument
if [ $# -eq 0 ]; then
  echo "Usage: $0 <ENVIRONMENT>"
  echo "ENVIRONMENT: DEV or STAGING"
  echo "Example: $0 DEV"
  echo "Example: $0 STAGING"
  exit 1
fi

DEPLOY_ENV=$1

# Validate environment
if [ "$DEPLOY_ENV" != "DEV" ] && [ "$DEPLOY_ENV" != "STAGING" ]; then
  echo "Error: Environment must be either DEV or STAGING"
  echo "Usage: $0 <ENVIRONMENT>"
  exit 1
fi

echo "Configuring MerkleDistributor for environment: $DEPLOY_ENV"

# Source .env file to load environment variables
if [ -f .env ]; then
  echo "Loading environment variables from .env file..."
  source .env
else
  echo "Error: .env file not found!"
  exit 1
fi

# Make logs directory if it doesn't exist
mkdir -p deployment_logs

# Debug: Show which RPC URLs are loaded
echo "Checking RPC URLs..."
for chain in "${chains[@]}"; do
  rpc_var="${chain}_RPC_URL"
  rpc_url=$(eval echo \$rpc_var)
  echo "$rpc_var = $rpc_url"
done
echo "--------------------------------------------------------------"

for chain in "${chains[@]}"; do
  echo "Starting configuration for $chain..."
  
  # Get the chain ID for Foundry
  chain_id=${chain_ids[$chain]}
  
  # Get the actual RPC URL value from environment
  rpc_var="${chain}_RPC_URL"
  rpc_url=$(eval echo \$$rpc_var)
  
  echo "Using chain ID: $chain_id"
  echo "Using RPC URL: $rpc_url"
  
  if [ -z "$rpc_url" ]; then
    echo "RPC URL not found for $chain (variable: $rpc_var). Skipping..."
    continue
  fi
  
  # Configure MerkleDistributor
  echo "Configuring MerkleDistributor for $chain..."
  
  # Capture logs to temporary file
  DEPLOY_ENV=$DEPLOY_ENV forge script script/ConfigureMerkleDistributor.s.sol --chain $chain_id --rpc-url "$rpc_url" --broadcast --via-ir > temp_logs.txt 2>&1
  
  # Check if the script executed successfully
  if grep -q "Configuration completed successfully!" temp_logs.txt; then
    echo "Configuration for $chain completed successfully!"
    
    # Extract key information from logs
    fee_collector_address=$(grep "FeeCollector address:" temp_logs.txt | awk '{print $NF}')
    merkle_distributor_address=$(grep "MerkleDistributor address:" temp_logs.txt | awk '{print $NF}')
    
    echo "FeeCollector address: $fee_collector_address"
    echo "MerkleDistributor address: $merkle_distributor_address"
    echo "FeeCollector DISTRIBUTOR_ROLE granted to: 0xbeef84d2fCef62c5834FcBf38B700E5203679197"
    echo "MerkleDistributor DISTRIBUTOR_ROLE granted to: $fee_collector_address"
  else
    echo "Configuration failed for $chain. Check logs for errors."
    cat temp_logs.txt
  fi
  
  # Add configuration logs to chain log file
  cat temp_logs.txt >> "deployment_logs/${chain}_merkle_distributor_configuration.log"
  
  echo "Configuration for $chain completed!"
  echo "--------------------------------------------------------------"
  
  # Extract and format the logs for summary
  grep -A 100 "== Logs ==" "deployment_logs/${chain}_merkle_distributor_configuration.log" | grep -B 100 "## Setting up 1 EVM" | grep -v "== Logs ==" | grep -v "## Setting up 1 EVM" > "deployment_logs/${chain}_merkle_distributor_configuration_summary.log"
  
  # Create summary file
  cat > "deployment_logs/${chain}_merkle_distributor_configuration_summary.txt" << EOF
$chain MerkleDistributor Configuration ($DEPLOY_ENV)

\`\`\`jsx
$(cat "deployment_logs/${chain}_merkle_distributor_configuration_summary.log")
\`\`\`

EOF

  # Clean up temp file
  rm temp_logs.txt
done

# Combine all summaries into one file
echo "Creating combined summary..."
if ls deployment_logs/*_merkle_distributor_configuration_summary.txt 1> /dev/null 2>&1; then
  cat deployment_logs/*_merkle_distributor_configuration_summary.txt > merkle_distributor_configuration_summary.txt
else
  echo "No successful configurations found." > merkle_distributor_configuration_summary.txt
fi

echo "MerkleDistributor configuration completed for all chains. See deployment_logs directory for detailed logs."
echo "Summary available in merkle_distributor_configuration_summary.txt" 
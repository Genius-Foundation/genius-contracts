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

# Environments to process
environments=("PROD")

# Source .env file to load environment variables
if [ -f .env ]; then
  echo "Loading environment variables from .env file..."
  source .env
else
  echo "Error: .env file not found!"
  exit 1
fi

# Debug: Show which RPC URLs are loaded
echo "Checking RPC URLs..."
for chain in "${chains[@]}"; do
  rpc_var="${chain}_RPC_URL"
  rpc_url=$(eval echo \$rpc_var)
  echo "$rpc_var = $rpc_url"
done

# Check if required admin addresses are set
if [ -z "$NEW_ADMIN_ADDRESS" ]; then
  echo "Error: NEW_ADMIN_ADDRESS not set in .env file!"
  exit 1
fi

if [ -z "$PREVIOUS_ADMIN_ADDRESS" ]; then
  echo "Error: PREVIOUS_ADMIN_ADDRESS not set in .env file!"
  exit 1
fi

echo "========================================"
echo "Admin Ownership Change Configuration"
echo "========================================"
echo "New Admin: $NEW_ADMIN_ADDRESS"
echo "Previous Admin: $PREVIOUS_ADMIN_ADDRESS"
echo
echo "This will process:"
echo "  - Environments: ${environments[*]}"
echo "  - Chains: ${chains[*]}"
echo "  - Total operations: $((${#environments[@]} * ${#chains[@]})) (${#environments[@]} environments × ${#chains[@]} chains)"
echo "========================================"
echo

# Confirm with user
read -p "Are you sure you want to proceed with changing admin ownership across ALL chains and environments? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Operation cancelled."
  exit 0
fi

# Make logs directory if it doesn't exist
mkdir -p admin_change_logs

# Create timestamp for this run
timestamp=$(date +"%Y%m%d_%H%M%S")

# Summary file
summary_file="admin_change_logs/admin_change_summary_${timestamp}.txt"
echo "Admin Ownership Change Summary - $(date)" > "$summary_file"
echo "New Admin: $NEW_ADMIN_ADDRESS" >> "$summary_file"
echo "Previous Admin: $PREVIOUS_ADMIN_ADDRESS" >> "$summary_file"
echo "======================================" >> "$summary_file"
echo >> "$summary_file"

# Initialize counters
total_operations=$((${#environments[@]} * ${#chains[@]}))
current_operation=0
successful_operations=0
failed_operations=0
skipped_operations=0

# Process each environment
for env in "${environments[@]}"; do
  echo "========================================="
  echo "Processing environment: $env"
  echo "========================================="
  echo >> "$summary_file"
  echo "Environment: $env" >> "$summary_file"
  echo "-------------------" >> "$summary_file"
  
  # Process each chain
  for chain in "${chains[@]}"; do
    ((current_operation++))
    echo "  [$current_operation/$total_operations] Processing $chain ($env)..."
    
    # Get the chain ID for Foundry
    chain_id=${chain_ids[$chain]}
    
    # Get the actual RPC URL value from environment
    rpc_var="${chain}_RPC_URL"
    rpc_url=$(eval echo \$$rpc_var)

    echo "Using chain ID: $chain_id"
    echo "Using RPC URL: $rpc_url"
    
    if [ -z "$rpc_url" ]; then
      echo "    RPC URL not found for $chain (variable: $rpc_var). Skipping..."
      echo "$chain: SKIPPED - No RPC URL" >> "$summary_file"
      ((skipped_operations++))
      continue
    fi
    
    # Create log file for this chain and environment
    log_file="admin_change_logs/${chain}_${env}_admin_change_${timestamp}.log"
    
    echo "    Running admin change script..."
    echo "    Chain ID: $chain_id"
    echo "    RPC URL: $rpc_url"
    
    # Run the script with appropriate environment
    if DEPLOY_ENV=$env forge script script/utility/TransferOwnership.s.sol \
      --chain $chain_id \
      --rpc-url "$rpc_url" \
      --broadcast \
      --via-ir \
      -vvvv > "$log_file" 2>&1; then
      
      echo "    ✓ Admin change completed for $chain ($env)"
      echo "$chain: SUCCESS" >> "$summary_file"
      ((successful_operations++))
      
      # Extract key information from logs
      echo "    Contract status:" >> "$summary_file"
      grep -E "(Processing|Granted|Revoked|already has|does not have)" "$log_file" | grep -v "Compiling" | sed 's/^/      /' >> "$summary_file"
      
    else
      echo "    ✗ Admin change failed for $chain ($env)"
      echo "$chain: FAILED" >> "$summary_file"
      ((failed_operations++))
      
      # Show error details
      echo "    Error details:" >> "$summary_file"
      tail -n 20 "$log_file" | grep -E "(Error|revert|fail)" | sed 's/^/      /' >> "$summary_file"
    fi
    
    echo >> "$summary_file"
  done
  
  echo "  Environment $env processing complete."
  echo
done

echo "========================================"
echo "Admin ownership change process complete!"
echo "========================================"
echo
echo "Final Results:"
echo "  Total operations: $total_operations"
echo "  ✓ Successful: $successful_operations"
echo "  ✗ Failed: $failed_operations"
echo "  - Skipped: $skipped_operations"
echo
echo "Summary saved to: $summary_file"
echo "Detailed logs available in: admin_change_logs/"
echo

# Display summary
echo "Quick Summary by Chain/Environment:"
echo "-----------------------------------"
cat "$summary_file" | grep -E "^(BASE|OPTIMISM|AVAX|ARBITRUM|BSC|ETHEREUM|POLYGON|SONIC):"

# Create a simplified summary with just success/failure
simple_summary="admin_change_logs/admin_change_results_${timestamp}.txt"
{
  echo "Admin Change Results - $(date)"
  echo
  echo "New Admin: $NEW_ADMIN_ADDRESS"
  echo "Previous Admin: $PREVIOUS_ADMIN_ADDRESS"
  echo
  echo "Final Statistics:"
  echo "  Total: $total_operations"
  echo "  Success: $successful_operations"
  echo "  Failed: $failed_operations"
  echo "  Skipped: $skipped_operations"
  echo
  echo "Details by Chain/Environment:"
  echo "-----------------------------"
  grep -E "(SUCCESS|FAILED|SKIPPED)" "$summary_file"
} > "$simple_summary"

echo
echo "Results summary saved to: $simple_summary"

# Display a formatted table of results
echo
echo "========================================="
echo "OPERATION RESULTS BY CHAIN AND ENVIRONMENT"
echo "========================================="
printf "%-12s %-10s %s\n" "CHAIN" "DEV" "STAGING"
echo "-----------------------------------------"

for chain in "${chains[@]}"; do
  dev_result=$(grep -E "^$chain: (SUCCESS|FAILED|SKIPPED)" "$summary_file" | grep -A1 "Environment: DEV" | grep "$chain:" | awk '{print $2}' | head -1)
  staging_result=$(grep -E "^$chain: (SUCCESS|FAILED|SKIPPED)" "$summary_file" | grep -A1 "Environment: STAGING" | grep "$chain:" | awk '{print $2}' | head -1)
  
  # Set default if not found
  [ -z "$dev_result" ] && dev_result="-"
  [ -z "$staging_result" ] && staging_result="-"
  
  # Color code the results
  dev_display="$dev_result"
  staging_display="$staging_result"
  
  printf "%-12s %-10s %s\n" "$chain" "$dev_display" "$staging_display"
done

echo "========================================="

# Final check
if [ $failed_operations -eq 0 ] && [ $successful_operations -gt 0 ]; then
  echo
  echo "✅ ALL OPERATIONS COMPLETED SUCCESSFULLY!"
  echo
else
  echo
  echo "⚠️  Some operations failed or were skipped. Please check the logs."
  echo
fi
#!/bin/bash

# Azure Infrastructure Performance Testing Suite
# Phase 3: Azure VM and Storage Performance Analysis

set -e

# Configuration
RESOURCE_GROUP="your-nifi-rg"
VM_NAME="nifi-cluster-vm"
STORAGE_ACCOUNT="yourstorageaccount"
SUBSCRIPTION_ID="your-subscription-id"
LOG_DIR="./azure_tests_$(date +%Y%m%d_%H%M%S)"
TEST_DURATION=300

mkdir -p $LOG_DIR

# Function: Check Azure CLI and Login
check_azure_cli() {
    echo "Checking Azure CLI setup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        echo "Azure CLI not found. Please install Azure CLI."
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        echo "Please log in to Azure CLI: az login"
        exit 1
    fi
    
    # Set subscription
    az account set --subscription "$SUBSCRIPTION_ID"
    echo "Using subscription: $SUBSCRIPTION_ID"
}

# Function: Test VM Performance
test_vm_performance() {
    echo "Testing Azure VM performance..."
    
    # Get VM information
    az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --output json > $LOG_DIR/vm_info.json
    
    # Get VM size details
    vm_size=$(jq -r '.hardwareProfile.vmSize' $LOG_DIR/vm_info.json)
    echo "VM Size: $vm_size" > $LOG_DIR/vm_performance_summary.txt
    
    # Get VM metrics (CPU, Memory, Network, Disk)
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    start_time=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
    
    # CPU utilization
    az monitor metrics list \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$VM_NAME" \
        --metric "Percentage CPU" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --interval PT1M \
        --output json > $LOG_DIR/vm_cpu_metrics.json
    
    # Network metrics
    az monitor metrics list \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$VM_NAME" \
        --metric "Network In Total,Network Out Total" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --interval PT1M \
        --output json > $LOG_DIR/vm_network_metrics.json
    
    # Disk metrics
    az monitor metrics list \
        --resource "/subscriptions/$SUBSCRIPTION_GROUP/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$VM_NAME" \
        --metric "Disk Read Bytes/sec,Disk Write Bytes/sec,Disk Read Operations/Sec,Disk Write Operations/Sec" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --interval PT1M \
        --output json > $LOG_DIR/vm_disk_metrics.json
    
    echo "VM performance metrics collected."
}

# Function: Test Storage Performance
test_storage_performance() {
    echo "Testing Azure Storage performance..."
    
    # Get storage account information
    az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --output json > $LOG_DIR/storage_info.json
    
    # Storage account metrics
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    start_time=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
    
    # Transaction metrics
    az monitor metrics list \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
        --metric "Transactions,Ingress,Egress,SuccessE2ELatency,SuccessServerLatency" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --interval PT1M \
        --output json > $LOG_DIR/storage_metrics.json
    
    # Blob storage specific metrics
    az monitor metrics list \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT/blobServices/default" \
        --metric "BlobCount,BlobCapacity,ContainerCount" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --interval PT1H \
        --output json > $LOG_DIR/blob_metrics.json
    
    echo "Storage performance metrics collected."
}

# Function: Network Performance Testing within Azure
test_azure_network() {
    echo "Testing Azure network performance..."
    
    # Get network interface information
    vm_info=$(cat $LOG_DIR/vm_info.json)
    nic_id=$(echo $vm_info | jq -r '.networkProfile.networkInterfaces[0].id')
    nic_name=$(basename "$nic_id")
    
    # Network interface metrics
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    start_time=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
    
    az monitor metrics list \
        --resource "$nic_id" \
        --metric "BytesSentRate,BytesReceivedRate,PacketsSentRate,PacketsReceivedRate" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --interval PT1M \
        --output json > $LOG_DIR/nic_metrics.json
    
    # Test network connectivity to Azure services
    test_azure_connectivity
    
    echo "Azure network performance testing completed."
}

# Function: Test Azure Service Connectivity
test_azure_connectivity() {
    echo "Testing connectivity to Azure services..."
    
    # Test connectivity to various Azure endpoints
    endpoints=(
        "management.azure.com:443"
        "$STORAGE_ACCOUNT.blob.core.windows.net:443"
        "$STORAGE_ACCOUNT.dfs.core.windows.net:443"
        "login.microsoftonline.com:443"
    )
    
    for endpoint in "${endpoints[@]}"; do
        echo "Testing connectivity to $endpoint..."
        host=$(echo $endpoint | cut -d':' -f1)
        port=$(echo $endpoint | cut -d':' -f2)
        
        # Test connection time
        start_time=$(date +%s.%N)
        if nc -z -w 5 "$host" "$port" 2>/dev/null; then
            end_time=$(date +%s.%N)
            duration=$(echo "$end_time - $start_time" | bc)
            echo "$endpoint: Connected in ${duration}s" >> $LOG_DIR/azure_connectivity.log
        else
            echo "$endpoint: Connection failed" >> $LOG_DIR/azure_connectivity.log
        fi
        
        # DNS resolution time
        dig_output=$(dig +stats "$host" | grep "Query time:")
        echo "$endpoint DNS: $dig_output" >> $LOG_DIR/azure_dns_times.log
    done
}

# Function: Storage Performance Benchmarking
benchmark_storage_performance() {
    echo "Running storage performance benchmark..."
    
    # Create test container if not exists
    container_name="nifi-performance-test"
    
    # Get storage account key
    storage_key=$(az storage account keys list --account-name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query '[0].value' -o tsv)
    
    # Test file upload performance
    test_file="test_data_$(date +%s).txt"
    
    # Create test files of different sizes
    sizes=(1M 10M 100M 500M)
    
    for size in "${sizes[@]}"; do
        echo "Testing upload performance for ${size} file..."
        
        # Create test file
        dd if=/dev/zero of="$test_file" bs=$size count=1 2>/dev/null
        
        # Upload test - measure time
        start_time=$(date +%s.%N)
        az storage blob upload \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$storage_key" \
            --container-name "$container_name" \
            --name "$test_file" \
            --file "$test_file" \
            --output none 2>/dev/null
        end_time=$(date +%s.%N)
        
        upload_duration=$(echo "$end_time - $start_time" | bc)
        throughput=$(echo "scale=2; $size / $upload_duration" | bc | sed 's/M//')
        
        echo "Size: $size, Duration: ${upload_duration}s, Throughput: ${throughput} MB/s" >> $LOG_DIR/storage_upload_performance.log
        
        # Download test - measure time
        start_time=$(date +%s.%N)
        az storage blob download \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$storage_key" \
            --container-name "$container_name" \
            --name "$test_file" \
            --file "downloaded_$test_file" \
            --output none 2>/dev/null
        end_time=$(date +%s.%N)
        
        download_duration=$(echo "$end_time - $start_time" | bc)
        download_throughput=$(echo "scale=2; $size / $download_duration" | bc | sed 's/M//')
        
        echo "Size: $size, Duration: ${download_duration}s, Throughput: ${download_throughput} MB/s" >> $LOG_DIR/storage_download_performance.log
        
        # Cleanup
        rm -f "$test_file" "downloaded_$test_file"
        az storage blob delete \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$storage_key" \
            --container-name "$container_name" \
            --name "$test_file" \
            --output none 2>/dev/null
    done
    
    echo "Storage benchmark completed."
}

# Function: Test Azure Data Lake Performance
test_data_lake_performance() {
    echo "Testing Azure Data Lake performance..."
    
    # Data Lake specific tests
    filesystem_name="nifi-test-fs"
    
    # Create filesystem if it doesn't exist
    az storage fs create \
        --name "$filesystem_name" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --output none 2>/dev/null || true
    
    # Test directory operations
    start_time=$(date +%s.%N)
    az storage fs directory create \
        --name "test-directory" \
        --file-system "$filesystem_name" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --output none 2>/dev/null
    end_time=$(date +%s.%N)
    
    dir_create_time=$(echo "$end_time - $start_time" | bc)
    echo "Directory creation time: ${dir_create_time}s" >> $LOG_DIR/data_lake_performance.log
    
    # Test file operations
    test_content="This is test content for Data Lake performance testing. $(date)"
    echo "$test_content" > temp_test_file.txt
    
    # Upload file to Data Lake
    start_time=$(date +%s.%N)
    az storage fs file upload \
        --path "test-directory/test-file.txt" \
        --file-system "$filesystem_name" \
        --source "temp_test_file.txt" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --output none 2>/dev/null
    end_time=$(date +%s.%N)
    
    file_upload_time=$(echo "$end_time - $start_time" | bc)
    echo "File upload time: ${file_upload_time}s" >> $LOG_DIR/data_lake_performance.log
    
    # Cleanup
    rm -f temp_test_file.txt
    az storage fs directory delete \
        --name "test-directory" \
        --file-system "$filesystem_name" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --yes \
        --output none 2>/dev/null || true
}

# Function: Analyze VM Sizing and Recommendations
analyze_vm_sizing() {
    echo "Analyzing VM sizing and generating recommendations..."
    
    # Get available VM sizes in the region
    vm_info=$(cat $LOG_DIR/vm_info.json)
    location=$(echo $vm_info | jq -r '.location')
    current_size=$(echo $vm_info | jq -r '.hardwareProfile.vmSize')
    
    # List available VM sizes
    az vm list-sizes --location "$location" --output json > $LOG_DIR/available_vm_sizes.json
    
    # Get current VM size specifications
    current_vm_specs=$(jq ".[] | select(.name == \"$current_size\")" $LOG_DIR/available_vm_sizes.json)
    
    cat > $LOG_DIR/vm_sizing_analysis.txt << EOF
VM Sizing Analysis
==================

Current VM: $current_size
Location: $location

Current Specifications:
- vCPUs: $(echo $current_vm_specs | jq -r '.numberOfCores')
- Memory: $(echo $current_vm_specs | jq -r '.memoryInMB') MB
- Max Data Disks: $(echo $current_vm_specs | jq -r '.maxDataDiskCount')
- OS Disk Size: $(echo $current_vm_specs | jq -r '.osDiskSizeInMB') MB
- Resource Disk Size: $(echo $current_vm_specs | jq -r '.resourceDiskSizeInMB') MB

Recommended VM Sizes for NiFi Workloads:
========================================

For CPU-Intensive Workloads:
$(jq -r '.[] | select(.name | startswith("Standard_F")) | select(.numberOfCores >= 4) | .name + " - " + (.numberOfCores|tostring) + " vCPUs, " + (.memoryInMB|tostring) + " MB RAM"' $LOG_DIR/available_vm_sizes.json | head -5)

For Memory-Intensive Workloads:
$(jq -r '.[] | select(.name | startswith("Standard_E")) | select(.numberOfCores >= 4) | .name + " - " + (.numberOfCores|tostring) + " vCPUs, " + (.memoryInMB|tostring) + " MB RAM"' $LOG_DIR/available_vm_sizes.json | head -5)

For Balanced Workloads:
$(jq -r '.[] | select(.name | startswith("Standard_D")) | select(.numberOfCores >= 4) | .name + " - " + (.numberOfCores|tostring) + " vCPUs, " + (.memoryInMB|tostring) + " MB RAM"' $LOG_DIR/available_vm_sizes.json | head -5)
EOF
}

# Function: Generate Azure Performance Report
generate_azure_report() {
    echo "Generating Azure performance report..."
    
    # Calculate storage performance averages
    if [ -f "$LOG_DIR/storage_upload_performance.log" ]; then
        avg_upload_throughput=$(awk '{sum+=$NF} END {print sum/NR}' $LOG_DIR/storage_upload_performance.log)
        avg_download_throughput=$(awk '{sum+=$NF} END {print sum/NR}' $LOG_DIR/storage_download_performance.log)
    else
        avg_upload_throughput="N/A"
        avg_download_throughput="N/A"
    fi
    
    cat > $LOG_DIR/azure_performance_report.md << EOF
# Azure Infrastructure Performance Report

**Test Date:** $(date)
**Resource Group:** $RESOURCE_GROUP
**VM Name:** $VM_NAME
**Storage Account:** $STORAGE_ACCOUNT

## Executive Summary

This report analyzes the performance characteristics of the Azure infrastructure supporting the NiFi cluster, including VM performance, storage throughput, and network connectivity.

## VM Performance Analysis

### Current Configuration
$(cat $LOG_DIR/vm_sizing_analysis.txt | grep -A 10 "Current Specifications:")

### Performance Metrics
- **CPU Utilization:** Based on Azure Monitor metrics
- **Network Throughput:** Measured via Azure Monitor
- **Disk I/O Performance:** Read/Write operations per second

## Storage Performance Analysis

### Blob Storage Performance
- **Average Upload Throughput:** $avg_upload_throughput MB/s
- **Average Download Throughput:** $avg_download_throughput MB/s

### Data Lake Performance
$(cat $LOG_DIR/data_lake_performance.log)

### Storage Metrics Summary
- **Transaction Rate:** Based on Azure Monitor metrics
- **End-to-End Latency:** Response time for storage operations
- **Server Latency:** Storage service processing time

## Network Performance Analysis

### Azure Service Connectivity
$(cat $LOG_DIR/azure_connectivity.log)

### DNS Resolution Performance
$(cat $LOG_DIR/azure_dns_times.log | head -10)

## Recommendations

### VM Optimization
1. **CPU Performance:** 
   - Monitor CPU utilization during peak NiFi processing
   - Consider F-series VMs for CPU-intensive workloads
   - Upgrade to higher core count if CPU > 80%

2. **Memory Optimization:**
   - Ensure sufficient RAM for NiFi heap and OS
   - Consider E-series VMs for memory-intensive operations
   - Monitor memory pressure indicators

3. **Network Performance:**
   - Enable Accelerated Networking if not already enabled
   - Consider proximity placement groups for multi-VM clusters
   - Monitor network utilization against VM limits

### Storage Optimization
1. **Storage Tier Selection:**
   - Use Hot tier for frequently accessed data
   - Consider Cool/Archive tiers for long-term retention
   - Implement lifecycle management policies

2. **Performance Improvements:**
   - Use Premium storage for NiFi repositories
   - Implement parallel uploads for large files
   - Consider read-access geo-redundant storage for DR

3. **Cost Optimization:**
   - Monitor storage usage and optimize retention policies
   - Use storage analytics to identify access patterns
   - Implement automated cleanup for temporary data

### Network Optimization
1. **Connectivity:**
   - Implement ExpressRoute for predictable performance
   - Use private endpoints for storage access
   - Configure optimal routing for data flows

2. **Security:**
   - Enable network security groups with minimal required access
   - Use managed identities instead of storage keys
   - Implement network monitoring and alerting

## Action Items

1. **Immediate (1-2 weeks):**
   - Review and adjust VM sizing based on utilization metrics
   - Enable Accelerated Networking if not configured
   - Optimize storage access patterns

2. **Medium-term (1 month):**
   - Implement monitoring dashboards for key metrics
   - Test performance improvements from recommendations
   - Establish baseline performance benchmarks

3. **Long-term (3 months):**
   - Consider architecture improvements (ExpressRoute, etc.)
   - Implement automated scaling based on workload
   - Review and optimize costs based on usage patterns

## Monitoring Setup

### Key Metrics to Monitor
- VM CPU, Memory, Disk, and Network utilization
- Storage transaction rates and latency
- Network connectivity and DNS resolution times
- NiFi-specific performance counters

### Alerting Thresholds
- CPU utilization > 85%
- Memory utilization > 90%
- Storage latency > 100ms
- Network errors or connectivity failures

### Dashboard Components
- Real-time performance metrics
- Historical trend analysis
- Cost monitoring and optimization
- Capacity planning projections

EOF

    echo "Azure performance report generated: $LOG_DIR/azure_performance_report.md"
}

# Function: Test Azure Monitor Integration
test_azure_monitor() {
    echo "Testing Azure Monitor integration..."
    
    # Create diagnostic settings if they don't exist
    diagnostic_name="nifi-diagnostics"
    
    # Enable diagnostics for VM
    az monitor diagnostic-settings create \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$VM_NAME" \
        --name "$diagnostic_name" \
        --storage-account "$STORAGE_ACCOUNT" \
        --metrics '[{"category": "AllMetrics","enabled": true,"retentionPolicy": {"days": 30,"enabled": true}}]' \
        --output none 2>/dev/null || echo "Diagnostic settings may already exist"
    
    # Test custom metrics (example)
    az monitor metrics list \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$VM_NAME" \
        --metric "Percentage CPU" \
        --output table > $LOG_DIR/monitor_test_output.log
    
    echo "Azure Monitor integration test completed."
}

# Main execution
main() {
    echo "Starting Azure infrastructure performance analysis..."
    
    # Check dependencies
    command -v az >/dev/null 2>&1 || { echo "Azure CLI required but not installed."; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "jq required but not installed."; exit 1; }
    command -v bc >/dev/null 2>&1 || { echo "bc required but not installed."; exit 1; }
    
    # Setup Azure CLI
    check_azure_cli
    
    # Run all tests
    test_vm_performance
    test_storage_performance
    test_azure_network
    benchmark_storage_performance
    test_data_lake_performance
    analyze_vm_sizing
    test_azure_monitor
    
    # Generate comprehensive report
    generate_azure_report
    
    echo "Azure infrastructure performance analysis completed."
    echo "Results available in: $LOG_DIR"
    echo "Key files:"
    echo "  - azure_performance_report.md: Comprehensive performance analysis"
    echo "  - vm_sizing_analysis.txt: VM sizing recommendations"
    echo "  - storage_*_performance.log: Storage benchmark results"
    echo "  - azure_connectivity.log: Network connectivity test results"
}

# Execute main function
main "$@"

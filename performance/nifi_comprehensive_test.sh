#!/bin/bash

# Comprehensive Testing and Tuning Execution Guide
# Oracle to Azure Data Lake Migration Performance Optimization

set -e

# Configuration
PROJECT_NAME="Oracle-Azure-Migration"
BASE_DIR="./performance_testing_$(date +%Y%m%d_%H%M%S)"
NIFI_HOST="your-nifi-vm.azure.com"
ORACLE_HOST="your-oracle-server.com"
AZURE_STORAGE_ACCOUNT="yourstorageaccount"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function: Print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date +'%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

# Function: Create directory structure
setup_test_environment() {
    print_status $BLUE "Setting up test environment..."
    
    mkdir -p "$BASE_DIR"/{network,nifi,azure,reports,configs}
    mkdir -p "$BASE_DIR"/logs/{network,nifi,azure,system}
    
    # Create configuration files
    cat > "$BASE_DIR/configs/test_config.env" << EOF
# Test Configuration
PROJECT_NAME="$PROJECT_NAME"
NIFI_HOST="$NIFI_HOST"
ORACLE_HOST="$ORACLE_HOST"
AZURE_STORAGE_ACCOUNT="$AZURE_STORAGE_ACCOUNT"

# Test Parameters
TEST_DURATION=300
NETWORK_TEST_CYCLES=5
NIFI_MONITORING_INTERVAL=10
AZURE_BENCHMARK_SIZES="1M 10M 100M 500M"

# Performance Thresholds
CPU_THRESHOLD=85
MEMORY_THRESHOLD=90
NETWORK_LATENCY_THRESHOLD=100
STORAGE_LATENCY_THRESHOLD=100

# Email Notifications (optional)
NOTIFICATION_EMAIL=""
SLACK_WEBHOOK=""
EOF

    source "$BASE_DIR/configs/test_config.env"
    
    print_status $GREEN "Test environment setup completed at: $BASE_DIR"
}

# Function: Check prerequisites
check_prerequisites() {
    print_status $BLUE "Checking prerequisites..."
    
    local missing_tools=()
    
    # Required tools
    tools=("curl" "jq" "ping" "mtr" "iperf3" "nc" "az" "dig" "bc" "awk")
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_status $RED "Missing required tools: ${missing_tools[*]}"
        print_status $YELLOW "Please install missing tools and run again."
        exit 1
    fi
    
    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        print_status $RED "Azure CLI not logged in. Please run: az login"
        exit 1
    fi
    
    # Check NiFi API accessibility
    if ! curl -s "$NIFI_HOST:8080/nifi-api/system-diagnostics" &> /dev/null; then
        print_status $YELLOW "Warning: NiFi API not accessible at $NIFI_HOST:8080"
        print_status $YELLOW "Network tests will continue, but NiFi tests may fail"
    fi
    
    print_status $GREEN "Prerequisites check completed"
}

# Function: Run Phase 1 - Network Testing
run_network_tests() {
    print_status $BLUE "Starting Phase 1: Network Performance Testing..."
    
    cd "$BASE_DIR/network"
    
    # Download and run network testing script
    curl -s -o network_test.sh https://raw.githubusercontent.com/example/scripts/network_test.sh || {
        print_status $YELLOW "Could not download network test script. Using local version..."
        
        # Create inline network test script
        cat > network_test.sh << 'EOF'
#!/bin/bash
# Basic network testing implementation
echo "Running basic network connectivity tests..."

# Test Oracle connectivity
if ping -c 5 "$ORACLE_HOST" > ping_oracle.log 2>&1; then
    echo "Oracle connectivity: PASS"
else
    echo "Oracle connectivity: FAIL"
fi

# Test Azure VM connectivity
if ping -c 5 "$NIFI_HOST" > ping_azure.log 2>&1; then
    echo "Azure VM connectivity: PASS"
else
    echo "Azure VM connectivity: FAIL"
fi

# Test Azure Storage connectivity
if dig "$AZURE_STORAGE_ACCOUNT.blob.core.windows.net" > azure_dns.log 2>&1; then
    echo "Azure Storage DNS: PASS"
else
    echo "Azure Storage DNS: FAIL"
fi

# Basic bandwidth test (requires iperf3 server on target)
echo "Note: For bandwidth testing, start iperf3 server on target hosts"
echo "Command: iperf3 -s -p 5201"
EOF
        chmod +x network_test.sh
    }
    
    # Run network tests
    bash network_test.sh > "$BASE_DIR/logs/network/network_test_output.log" 2>&1
    
    # Network latency testing
    print_status $BLUE "Testing network latency..."
    for host in "$ORACLE_HOST" "$NIFI_HOST"; do
        if ping -c 100 "$host" > "$BASE_DIR/logs/network/latency_${host//\./_}.log" 2>&1; then
            avg_latency=$(grep "rtt min/avg/max/mdev" "$BASE_DIR/logs/network/latency_${host//\./_}.log" | awk -F'/' '{print $5}')
            print_status $GREEN "Average latency to $host: ${avg_latency}ms"
        else
            print_status $RED "Latency test failed for $host"
        fi
    done
    
    cd - > /dev/null
    print_status $GREEN "Phase 1: Network testing completed"
}

# Function: Run Phase 2 - NiFi Performance Testing
run_nifi_tests() {
    print_status $BLUE "Starting Phase 2: NiFi Performance Testing..."
    
    cd "$BASE_DIR/nifi"
    
    # Create NiFi monitoring script
    cat > nifi_monitor.sh << 'EOF'
#!/bin/bash

NIFI_HOST="$1"
DURATION="$2"
INTERVAL="$3"
LOG_FILE="$4"

if [ -z "$NIFI_HOST" ] || [ -z "$DURATION" ] || [ -z "$INTERVAL" ] || [ -z "$LOG_FILE" ]; then
    echo "Usage: $0 <nifi_host> <duration_seconds> <interval_seconds> <log_file>"
    exit 1
fi

NIFI_API="http://$NIFI_HOST:8080/nifi-api"
end_time=$(($(date +%s) + DURATION))
counter=0

# Create CSV header
echo "timestamp,heap_used,heap_max,heap_utilization,cpu_load,active_threads,queued_count,flowfiles_in,flowfiles_out" > "$LOG_FILE"

while [ $(date +%s) -lt $end_time ]; do
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Get system diagnostics
    if system_data=$(curl -s "$NIFI_API/system-diagnostics" 2>/dev/null); then
        heap_used=$(echo "$system_data" | jq -r '.systemDiagnostics.aggregateSnapshot.totalHeapBytes // "0"')
        heap_max=$(echo "$system_data" | jq -r '.systemDiagnostics.aggregateSnapshot.maxHeapBytes // "0"')
        heap_util=$(echo "$system_data" | jq -r '.systemDiagnostics.aggregateSnapshot.heapUtilization // "0%"')
        cpu_load=$(echo "$system_data" | jq -r '.systemDiagnostics.aggregateSnapshot.processorLoadAverage // "0"')
        
        # Get flow statistics
        if flow_data=$(curl -s "$NIFI_API/flow/process-groups/root" 2>/dev/null); then
            active_threads=$(echo "$flow_data" | jq -r '.processGroupFlow.breadcrumb.breadcrumb.activeRemotePortCount // "0"')
            queued_count=$(echo "$flow_data" | jq -r '.processGroupFlow.breadcrumb.breadcrumb.queuedCount // "0"')
            flowfiles_in=$(echo "$flow_data" | jq -r '.processGroupFlow.breadcrumb.breadcrumb.inputPortCount // "0"')
            flowfiles_out=$(echo "$flow_data" | jq -r '.processGroupFlow.breadcrumb.breadcrumb.outputPortCount // "0"')
        else
            active_threads=0
            queued_count=0
            flowfiles_in=0
            flowfiles_out=0
        fi
        
        echo "$timestamp,$heap_used,$heap_max,$heap_util,$cpu_load,$active_threads,$queued_count,$flowfiles_in,$flowfiles_out" >> "$LOG_FILE"
    else
        echo "$timestamp,ERROR,ERROR,ERROR,ERROR,ERROR,ERROR,ERROR,ERROR" >> "$LOG_FILE"
    fi
    
    counter=$((counter + 1))
    sleep "$INTERVAL"
done

echo "NiFi monitoring completed. Data points collected: $counter"
EOF
    
    chmod +x nifi_monitor.sh
    
    # Run NiFi monitoring
    print_status $BLUE "Monitoring NiFi performance for $TEST_DURATION seconds..."
    bash nifi_monitor.sh "$NIFI_HOST" "$TEST_DURATION" 10 "$BASE_DIR/logs/nifi/nifi_performance.csv" &
    
    # Get NiFi configuration analysis
    print_status $BLUE "Analyzing NiFi configuration..."
    if curl -s "http://$NIFI_HOST:8080/nifi-api/system-diagnostics" | jq '.' > "$BASE_DIR/logs/nifi/system_diagnostics.json" 2>/dev/null; then
        print_status $GREEN "NiFi system diagnostics captured"
    else
        print_status $RED "Failed to capture NiFi system diagnostics"
    fi
    
    # Wait for monitoring to complete
    wait
    
    cd - > /dev/null
    print_status $GREEN "Phase 2: NiFi testing completed"
}

# Function: Run Phase 3 - Azure Infrastructure Testing
run_azure_tests() {
    print_status $BLUE "Starting Phase 3: Azure Infrastructure Testing..."
    
    cd "$BASE_DIR/azure"
    
    # Azure resource information
    print_status $BLUE "Gathering Azure resource information..."
    
    # Get subscription and resource group info
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    
    # Find NiFi VM resource group (assuming VM name contains 'nifi')
    RESOURCE_GROUP=$(az vm list --query "[?contains(name, 'nifi')].resourceGroup" -o tsv | head -1)
    VM_NAME=$(az vm list --query "[?contains(name, 'nifi')].name" -o tsv | head -1)
    
    if [ -z "$RESOURCE_GROUP" ] || [ -z "$VM_NAME" ]; then
        print_status $YELLOW "Could not auto-detect NiFi VM. Please provide details:"
        read -p "Resource Group: " RESOURCE_GROUP
        read -p "VM Name: " VM_NAME
    fi
    
    print_status $GREEN "Using Resource Group: $RESOURCE_GROUP, VM: $VM_NAME"
    
    # VM Performance metrics
    print_status $BLUE "Collecting Azure VM metrics..."
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    start_time=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%SZ")
    
    # CPU metrics
    az monitor metrics list \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$VM_NAME" \
        --metric "Percentage CPU" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --interval PT1M \
        --output json > "$BASE_DIR/logs/azure/vm_cpu_metrics.json" 2>/dev/null || \
        print_status $YELLOW "Could not collect VM CPU metrics"
    
    # Network metrics
    az monitor metrics list \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachines/$VM_NAME" \
        --metric "Network In Total,Network Out Total" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --interval PT1M \
        --output json > "$BASE_DIR/logs/azure/vm_network_metrics.json" 2>/dev/null || \
        print_status $YELLOW "Could not collect VM network metrics"
    
    # Storage account metrics
    if [ -n "$AZURE_STORAGE_ACCOUNT" ]; then
        print_status $BLUE "Collecting Azure Storage metrics..."
        STORAGE_RG=$(az storage account list --query "[?name=='$AZURE_STORAGE_ACCOUNT'].resourceGroup" -o tsv)
        
        if [ -n "$STORAGE_RG" ]; then
            az monitor metrics list \
                --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$STORAGE_RG/providers/Microsoft.Storage/storageAccounts/$AZURE_STORAGE_ACCOUNT" \
                --metric "Transactions,Ingress,Egress,SuccessE2ELatency" \
                --start-time "$start_time" \
                --end-time "$end_time" \
                --interval PT1M \
                --output json > "$BASE_DIR/logs/azure/storage_metrics.json" 2>/dev/null || \
                print_status $YELLOW "Could not collect storage metrics"
        fi
    fi
    
    cd - > /dev/null
    print_status $GREEN "Phase 3: Azure testing completed"
}

# Function: Analyze results and generate recommendations
analyze_results() {
    print_status $BLUE "Analyzing test results and generating recommendations..."
    
    cd "$BASE_DIR/reports"
    
    # Create comprehensive analysis report
    cat > performance_analysis_report.md << EOF
# Performance Analysis Report - $PROJECT_NAME

**Test Date:** $(date)
**Test Duration:** $TEST_DURATION seconds

## Executive Summary

This report provides a comprehensive analysis of the Oracle to Azure Data Lake migration performance, including network, NiFi, and Azure infrastructure metrics.

## Test Environment
- **Oracle Host:** $ORACLE_HOST
- **NiFi Host:** $NIFI_HOST
- **Azure Storage Account:** $AZURE_STORAGE_ACCOUNT
- **Test Base Directory:** $BASE_DIR

## Network Performance Analysis

### Connectivity Tests
EOF

    # Analyze network results
    if [ -f "$BASE_DIR/logs/network/network_test_output.log" ]; then
        echo "### Network Test Results" >> performance_analysis_report.md
        echo '```' >> performance_analysis_report.md
        cat "$BASE_DIR/logs/network/network_test_output.log" >> performance_analysis_report.md
        echo '```' >> performance_analysis_report.md
    fi
    
    # Analyze latency results
    echo "" >> performance_analysis_report.md
    echo "### Latency Analysis" >> performance_analysis_report.md
    
    for latency_file in "$BASE_DIR/logs/network/latency_"*.log; do
        if [ -f "$latency_file" ]; then
            host=$(basename "$latency_file" .log | sed 's/latency_//' | sed 's/_/\./g')
            if grep -q "rtt min/avg/max/mdev" "$latency_file"; then
                avg_latency=$(grep "rtt min/avg/max/mdev" "$latency_file" | awk -F'/' '{print $5}')
                packet_loss=$(grep "packet loss" "$latency_file" | awk '{print $6}' | sed 's/,//')
                
                echo "- **$host:** Average latency: ${avg_latency}ms, Packet loss: $packet_loss" >> performance_analysis_report.md
                
                # Performance assessment
                latency_value=$(echo "$avg_latency" | cut -d'.' -f1)
                if [ "$latency_value" -gt "$NETWORK_LATENCY_THRESHOLD" ]; then
                    echo "  - ⚠️  **Warning:** High latency detected" >> performance_analysis_report.md
                else
                    echo "  - ✅ **Good:** Latency within acceptable range" >> performance_analysis_report.md
                fi
            fi
        fi
    done
    
    # Analyze NiFi performance
    echo "" >> performance_analysis_report.md
    echo "## NiFi Performance Analysis" >> performance_analysis_report.md
    
    if [ -f "$BASE_DIR/logs/nifi/nifi_performance.csv" ]; then
        # Calculate averages
        total_lines=$(wc -l < "$BASE_DIR/logs/nifi/nifi_performance.csv")
        if [ "$total_lines" -gt 1 ]; then
            avg_heap_used=$(tail -n +2 "$BASE_DIR/logs/nifi/nifi_performance.csv" | awk -F',' '{sum+=$2; count++} END {if(count>0) print sum/count/1024/1024; else print "N/A"}')
            avg_cpu_load=$(tail -n +2 "$BASE_DIR/logs/nifi/nifi_performance.csv" | awk -F',' '{sum+=$5; count++} END {if(count>0) print sum/count; else print "N/A"}')
            max_queued=$(tail -n +2 "$BASE_DIR/logs/nifi/nifi_performance.csv" | awk -F',' 'BEGIN{max=0} {if($7>max && $7!="ERROR") max=$7} END {print max}')
            
            cat >> performance_analysis_report.md << EOF

### Resource Utilization Summary
- **Average Heap Used:** ${avg_heap_used} MB
- **Average CPU Load:** ${avg_cpu_load}
- **Maximum Queue Depth:** ${max_queued}
- **Data Points Collected:** $((total_lines - 1))

### Performance Assessment
EOF
            
            # CPU assessment
            cpu_int=$(echo "$avg_cpu_load" | cut -d'.' -f1)
            if [ "$cpu_int" -gt "$CPU_THRESHOLD" ]; then
                echo "- ⚠️  **CPU:** High utilization detected ($avg_cpu_load)" >> performance_analysis_report.md
            else
                echo "- ✅ **CPU:** Utilization within normal range ($avg_cpu_load)" >> performance_analysis_report.md
            fi
            
            # Queue depth assessment
            if [ "$max_queued" -gt 10000 ]; then
                echo "- ⚠️  **Queuing:** High queue depth detected ($max_queued)" >> performance_analysis_report.md
            else
                echo "- ✅ **Queuing:** Queue depths acceptable ($max_queued)" >> performance_analysis_report.md
            fi
        fi
    fi
    
    # Azure metrics analysis
    echo "" >> performance_analysis_report.md
    echo "## Azure Infrastructure Analysis" >> performance_analysis_report.md
    
    if [ -f "$BASE_DIR/logs/azure/vm_cpu_metrics.json" ]; then
        if jq -e '.value[0].timeseries[0].data[0]' "$BASE_DIR/logs/azure/vm_cpu_metrics.json" > /dev/null 2>&1; then
            avg_cpu=$(jq -r '.value[0].timeseries[0].data | map(.average) | add / length' "$BASE_DIR/logs/azure/vm_cpu_metrics.json" 2>/dev/null || echo "N/A")
            echo "- **VM Average CPU:** $avg_cpu%" >> performance_analysis_report.md
        fi
    fi
    
    # Generate recommendations
    cat >> performance_analysis_report.md << EOF

## Recommendations

### Network Optimization
1. **Latency Improvements:**
   - Consider ExpressRoute for predictable performance if latency > 100ms
   - Implement connection pooling and keep-alive settings
   - Use compression for data transfer

2. **Bandwidth Optimization:**
   - Test parallel connections for large data transfers
   - Implement data compression before network transfer
   - Consider regional proximity for better performance

### NiFi Configuration Tuning
1. **Memory Management:**
   - Monitor heap usage trends and adjust JVM settings if needed
   - Implement proper garbage collection tuning
   - Use off-heap storage for large datasets

2. **Processing Optimization:**
   - Tune concurrent task settings based on CPU cores
   - Implement appropriate backpressure thresholds
   - Optimize processor scheduling strategies

3. **Repository Configuration:**
   - Use SSD storage for repositories
   - Distribute repositories across multiple disks
   - Implement appropriate retention policies

### Azure Infrastructure Optimization
1. **VM Sizing:**
   - Right-size VM based on actual usage patterns
   - Enable Accelerated Networking for better performance
   - Consider premium storage for better I/O performance

2. **Storage Optimization:**
   - Use appropriate storage tiers based on access patterns
   - Implement parallel uploads for large files
   - Optimize block sizes for different file sizes

3. **Networking:**
   - Use private endpoints for storage access
   - Implement network security groups optimally
   - Consider proximity placement groups for multi-VM clusters

## Implementation Priority

### Phase 1 (Immediate - 1-2 weeks)
- Address any critical performance bottlenecks identified
- Implement basic NiFi tuning parameters
- Optimize network connectivity issues

### Phase 2 (Medium-term - 1 month)
- Advanced NiFi configuration tuning
- Azure infrastructure optimization
- Implement monitoring and alerting

### Phase 3 (Long-term - 3 months)
- Architecture improvements (ExpressRoute, etc.)
- Advanced features implementation
- Cost optimization initiatives

## Monitoring Setup

### Key Metrics to Track
- Network latency and throughput
- NiFi heap usage and CPU utilization
- Azure VM and storage performance
- End-to-end processing times

### Alerting Thresholds
- Network latency > ${NETWORK_LATENCY_THRESHOLD}ms
- CPU utilization > ${CPU_THRESHOLD}%
- Memory usage > ${MEMORY_THRESHOLD}%
- Queue depths > 50,000 FlowFiles

## Next Steps
1. Review this report with technical teams
2. Prioritize recommendations based on impact and effort
3. Implement changes in development environment first
4. Monitor improvements and iterate
5. Schedule regular performance reviews

---
**Report Generated:** $(date)
**Test Environment:** $BASE_DIR
**Contact:** Performance Engineering Team
EOF

    # Generate CSV summary for trending
    cat > performance_summary.csv << EOF
timestamp,test_duration,network_latency_oracle,network_latency_nifi,nifi_avg_cpu,nifi_avg_heap_mb,nifi_max_queue,azure_avg_cpu
$(date '+%Y-%m-%d %H:%M:%S'),$TEST_DURATION,$avg_oracle_latency,$avg_nifi_latency,$avg_cpu_load,$avg_heap_used,$max_queued,$avg_cpu
EOF

    cd - > /dev/null
    print_status $GREEN "Analysis completed. Reports generated in $BASE_DIR/reports/"
}

# Function: Send notifications
send_notifications() {
    if [ -n "$NOTIFICATION_EMAIL" ] && command -v mail &> /dev/null; then
        print_status $BLUE "Sending email notification..."
        mail -s "Performance Test Completed - $PROJECT_NAME" "$NOTIFICATION_EMAIL" < "$BASE_DIR/reports/performance_analysis_report.md"
    fi
    
    if [ -n "$SLACK_WEBHOOK" ] && command -v curl &> /dev/null; then
        print_status $BLUE "Sending Slack notification..."
        curl -X POST -H 'Content-type: application/json' \
            --data '{"text":"Performance testing completed for '"$PROJECT_NAME"'. Results available at '"$BASE_DIR"'"}' \
            "$SLACK_WEBHOOK" > /dev/null 2>&1
    fi
}

# Function: Cleanup
cleanup() {
    print_status $BLUE "Cleaning up temporary files..."
    
    # Kill any background processes
    jobs -p | xargs -r kill > /dev/null 2>&1
    
    # Compress logs for storage
    if command -v tar &> /dev/null; then
        tar -czf "$BASE_DIR/logs/all_logs_$(date +%Y%m%d_%H%M%S).tar.gz" -C "$BASE_DIR/logs" . 2>/dev/null
        print_status $GREEN "Logs compressed for archival"
    fi
    
    print_status $GREEN "Cleanup completed"
}

# Function: Display summary
display_summary() {
    print_status $GREEN "====================================================="
    print_status $GREEN "Performance Testing Summary"
    print_status $GREEN "====================================================="
    echo -e "${GREEN}Project:${NC} $PROJECT_NAME"
    echo -e "${GREEN}Test Duration:${NC} $TEST_DURATION seconds"
    echo -e "${GREEN}Results Directory:${NC} $BASE_DIR"
    echo -e "${GREEN}Key Reports:${NC}"
    echo -e "  - Network: $BASE_DIR/logs/network/"
    echo -e "  - NiFi: $BASE_DIR/logs/nifi/"
    echo -e "  - Azure: $BASE_DIR/logs/azure/"
    echo -e "  - Analysis: $BASE_DIR/reports/performance_analysis_report.md"
    print_status $GREEN "====================================================="
}

# Main execution function
main() {
    print_status $BLUE "Starting Comprehensive Performance Testing Suite"
    print_status $BLUE "Project: $PROJECT_NAME"
    
    # Setup and checks
    setup_test_environment
    check_prerequisites
    
    # Execute test phases
    run_network_tests
    run_nifi_tests
    run_azure_tests
    
    # Analysis and reporting
    analyze_results
    send_notifications
    
    # Cleanup and summary
    cleanup
    display_summary
    
    print_status $GREEN "Performance testing completed successfully!"
    print_status $BLUE "Review the analysis report for detailed recommendations."
}

# Trap for cleanup on exit
trap cleanup EXIT

# Execute main function with all arguments
main "$@"

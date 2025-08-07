#!/bin/bash

# NiFi Performance Testing and Monitoring Suite
# Phase 2: NiFi Cluster Performance Analysis

set -e

# Configuration
NIFI_HOST="your-nifi-vm.azure.com"
NIFI_PORT="8080"
NIFI_API_BASE="http://${NIFI_HOST}:${NIFI_PORT}/nifi-api"
LOG_DIR="./nifi_tests_$(date +%Y%m%d_%H%M%S)"
MONITOR_DURATION=300  # 5 minutes

mkdir -p $LOG_DIR

# Function: Check NiFi API Health
check_nifi_health() {
    echo "Checking NiFi cluster health..."
    
    # System diagnostics
    curl -s "${NIFI_API_BASE}/system-diagnostics" | jq '.' > $LOG_DIR/system_diagnostics.json
    
    # Cluster summary
    curl -s "${NIFI_API_BASE}/flow/cluster/summary" | jq '.' > $LOG_DIR/cluster_summary.json
    
    # Controller services status
    curl -s "${NIFI_API_BASE}/flow/controller/controller-services" | jq '.' > $LOG_DIR/controller_services.json
    
    echo "NiFi health check completed."
}

# Function: Monitor NiFi Performance Metrics
monitor_nifi_metrics() {
    echo "Starting NiFi performance monitoring for $MONITOR_DURATION seconds..."
    
    local end_time=$(($(date +%s) + MONITOR_DURATION))
    local counter=0
    
    while [ $(date +%s) -lt $end_time ]; do
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        # System metrics
        system_metrics=$(curl -s "${NIFI_API_BASE}/system-diagnostics")
        
        # Extract key metrics
        heap_used=$(echo $system_metrics | jq -r '.systemDiagnostics.aggregateSnapshot.totalHeapBytes')
        heap_max=$(echo $system_metrics | jq -r '.systemDiagnostics.aggregateSnapshot.maxHeapBytes')
        cpu_utilization=$(echo $system_metrics | jq -r '.systemDiagnostics.aggregateSnapshot.processorLoadAverage')
        
        # Flow metrics
        flow_metrics=$(curl -s "${NIFI_API_BASE}/flow/process-groups/root")
        
        # Extract flow metrics
        active_threads=$(echo $flow_metrics | jq -r '.processGroupFlow.breadcrumb.breadcrumb.activeRemotePortCount // 0')
        queued_count=$(echo $flow_metrics | jq -r '.processGroupFlow.breadcrumb.breadcrumb.queuedCount // "0"')
        queued_size=$(echo $flow_metrics | jq -r '.processGroupFlow.breadcrumb.breadcrumb.queuedSize // "0 bytes"')
        
        # Write metrics to CSV
        if [ $counter -eq 0 ]; then
            echo "timestamp,heap_used,heap_max,cpu_load,active_threads,queued_count,queued_size" > $LOG_DIR/nifi_metrics.csv
        fi
        
        echo "$timestamp,$heap_used,$heap_max,$cpu_utilization,$active_threads,$queued_count,$queued_size" >> $LOG_DIR/nifi_metrics.csv
        
        counter=$((counter + 1))
        sleep 10
    done
    
    echo "NiFi monitoring completed. Data saved to $LOG_DIR/nifi_metrics.csv"
}

# Function: Analyze Repository Performance
analyze_repositories() {
    echo "Analyzing NiFi repository performance..."
    
    # Get repository usage
    repo_metrics=$(curl -s "${NIFI_API_BASE}/system-diagnostics")
    
    # Content repository metrics
    echo $repo_metrics | jq '.systemDiagnostics.aggregateSnapshot.contentRepositoryStorageUsage[]' > $LOG_DIR/content_repo_usage.json
    
    # FlowFile repository metrics  
    echo $repo_metrics | jq '.systemDiagnostics.aggregateSnapshot.flowFileRepositoryStorageUsage[]' > $LOG_DIR/flowfile_repo_usage.json
    
    # Provenance repository metrics
    echo $repo_metrics | jq '.systemDiagnostics.aggregateSnapshot.provenanceRepositoryStorageUsage[]' > $LOG_DIR/provenance_repo_usage.json
    
    # Generate repository report
    cat > $LOG_DIR/repository_analysis.txt << EOF
Repository Performance Analysis
==============================

Content Repository Usage:
$(jq -r '.identifier + ": " + .utilization + " (" + .freeSpace + " free)"' $LOG_DIR/content_repo_usage.json)

FlowFile Repository Usage:
$(jq -r '.identifier + ": " + .utilization + " (" + .freeSpace + " free)"' $LOG_DIR/flowfile_repo_usage.json)

Provenance Repository Usage:
$(jq -r '.identifier + ": " + .utilization + " (" + .freeSpace + " free)"' $LOG_DIR/provenance_repo_usage.json)
EOF
}

# Function: Test Connection Pools
test_connection_pools() {
    echo "Testing database connection pool performance..."
    
    # This would need to be customized based on your specific DBCPConnectionPool service
    # Get controller services
    controller_services=$(curl -s "${NIFI_API_BASE}/flow/controller/controller-services")
    
    # Find DBCP services
    echo $controller_services | jq '.controllerServices[] | select(.component.type == "org.apache.nifi.dbcp.DBCPConnectionPool")' > $LOG_DIR/dbcp_services.json
    
    # Extract connection pool metrics for each service
    while IFS= read -r service; do
        service_id=$(echo $service | jq -r '.id')
        service_name=$(echo $service | jq -r '.component.name')
        
        # Get detailed metrics for this service
        curl -s "${NIFI_API_BASE}/controller-services/${service_id}" > $LOG_DIR/dbcp_${service_name}_details.json
        
    done < <(echo $controller_services | jq -c '.controllerServices[] | select(.component.type == "org.apache.nifi.dbcp.DBCPConnectionPool")')
}

# Function: Generate NiFi Performance Report
generate_nifi_report() {
    echo "Generating NiFi performance report..."
    
    # Calculate averages from metrics
    if [ -f "$LOG_DIR/nifi_metrics.csv" ]; then
        avg_heap_used=$(tail -n +2 $LOG_DIR/nifi_metrics.csv | awk -F',' '{sum+=$2; count++} END {print sum/count}')
        avg_cpu_load=$(tail -n +2 $LOG_DIR/nifi_metrics.csv | awk -F',' '{sum+=$4; count++} END {print sum/count}')
        max_queued=$(tail -n +2 $LOG_DIR/nifi_metrics.csv | awk -F',' 'BEGIN{max=0} {if($5>max) max=$5} END {print max}')
    else
        avg_heap_used="N/A"
        avg_cpu_load="N/A" 
        max_queued="N/A"
    fi
    
    cat > $LOG_DIR/nifi_performance_report.md << EOF
# NiFi Performance Analysis Report

**Test Date:** $(date)
**Monitoring Duration:** $MONITOR_DURATION seconds
**NiFi Cluster:** $NIFI_HOST:$NIFI_PORT

## Performance Metrics Summary

### Resource Utilization
- **Average Heap Used:** $avg_heap_used bytes
- **Average CPU Load:** $avg_cpu_load
- **Maximum Queue Depth:** $max_queued

### Repository Analysis
$(cat $LOG_DIR/repository_analysis.txt)

## Key Performance Indicators

### Memory Usage
- Monitor heap usage trends for memory leaks
- Ensure sufficient heap space for peak loads
- Consider increasing heap size if usage > 80%

### CPU Utilization
- Target CPU utilization: 60-80% under load
- High CPU may indicate inefficient processors or transforms

### Queue Depths
- Monitor for backpressure conditions
- High queue depths may indicate downstream bottlenecks

## Recommendations

1. **Memory Optimization:**
   - Increase heap size if average usage > 70%
   - Tune garbage collection settings
   - Monitor FlowFile repository growth

2. **Processing Optimization:**
   - Review processor configurations for efficiency
   - Implement appropriate backpressure thresholds
   - Consider processor scheduling optimization

3. **Repository Tuning:**
   - Ensure sufficient disk space for repositories
   - Consider SSD storage for better I/O performance
   - Implement repository maintenance schedules

## Next Steps
1. Review detailed metrics in CSV files
2. Implement recommended optimizations
3. Test with production-like data volumes
4. Monitor impact of configuration changes
EOF

    echo "NiFi performance report generated: $LOG_DIR/nifi_performance_report.md"
}

# Function: NiFi JVM Analysis
analyze_jvm_performance() {
    echo "Analyzing NiFi JVM performance..."
    
    # Get JVM metrics
    jvm_metrics=$(curl -s "${NIFI_API_BASE}/system-diagnostics")
    
    # Extract JVM statistics
    echo $jvm_metrics | jq '.systemDiagnostics.aggregateSnapshot' > $LOG_DIR/jvm_snapshot.json
    
    # Garbage collection analysis
    echo $jvm_metrics | jq '.systemDiagnostics.aggregateSnapshot.garbageCollection[]' > $LOG_DIR/gc_metrics.json
    
    # Generate JVM report
    cat > $LOG_DIR/jvm_analysis.txt << EOF
JVM Performance Analysis
=======================

Heap Memory:
- Used: $(echo $jvm_metrics | jq -r '.systemDiagnostics.aggregateSnapshot.totalHeap')
- Max: $(echo $jvm_metrics | jq -r '.systemDiagnostics.aggregateSnapshot.maxHeap')
- Utilization: $(echo $jvm_metrics | jq -r '.systemDiagnostics.aggregateSnapshot.heapUtilization')

Non-Heap Memory:
- Used: $(echo $jvm_metrics | jq -r '.systemDiagnostics.aggregateSnapshot.totalNonHeap')
- Max: $(echo $jvm_metrics | jq -r '.systemDiagnostics.aggregateSnapshot.maxNonHeap')

Garbage Collection:
$(jq -r '.name + " - Collections: " + (.collectionCount|tostring) + ", Time: " + .collectionTime' $LOG_DIR/gc_metrics.json)
EOF
}

# Function: Test Processor Performance
test_processor_performance() {
    echo "Testing individual processor performance..."
    
    # Get all processors in the root process group
    root_pg=$(curl -s "${NIFI_API_BASE}/flow/process-groups/root")
    
    # Extract processor information
    echo $root_pg | jq '.processGroupFlow.flow.processors[]' > $LOG_DIR/processors_info.json
    
    # Create processor performance summary
    cat > $LOG_DIR/processor_performance.txt << EOF
Processor Performance Summary
============================

$(jq -r '.component.name + " (" + .component.type + "):" + 
        "\n  - Input Count: " + (.status.aggregateSnapshot.input // "0") + 
        "\n  - Output Count: " + (.status.aggregateSnapshot.output // "0") + 
        "\n  - Processing Time: " + (.status.aggregateSnapshot.processingNanos // "0") + " ns" +
        "\n  - Active Threads: " + (.status.aggregateSnapshot.activeThreadCount // "0") + "\n"' $LOG_DIR/processors_info.json)
EOF
}

# Main execution
main() {
    echo "Starting NiFi performance analysis..."
    
    # Check dependencies
    command -v curl >/dev/null 2>&1 || { echo "curl required but not installed."; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "jq required but not installed."; exit 1; }
    
    # Test NiFi connectivity
    if ! curl -s "$NIFI_API_BASE/system-diagnostics" > /dev/null; then
        echo "Error: Cannot connect to NiFi API at $NIFI_API_BASE"
        echo "Please check the NIFI_HOST and NIFI_PORT settings"
        exit 1
    fi
    
    # Run all tests
    check_nifi_health
    analyze_repositories
    analyze_jvm_performance
    test_connection_pools
    test_processor_performance
    
    # Start monitoring (this will run for MONITOR_DURATION)
    monitor_nifi_metrics
    
    # Generate comprehensive report
    generate_nifi_report
    
    echo "NiFi performance analysis completed. Results available in: $LOG_DIR"
    echo "Key files:"
    echo "  - nifi_performance_report.md: Main performance report"
    echo "  - nifi_metrics.csv: Time-series performance data"
    echo "  - jvm_analysis.txt: JVM and garbage collection analysis"
    echo "  - processor_performance.txt: Individual processor statistics"
}

# Execute main function
main "$@"

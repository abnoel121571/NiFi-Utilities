#!/bin/bash

# Network Performance Testing Suite for NiFi Azure Migration
# Phase 1: Network Assessment Scripts

echo "=== Network Performance Testing Suite ==="
echo "Testing Date: $(date)"
echo "=========================================="

# Configuration Variables
AZURE_VM_IP="10.0.1.100"  # Replace with actual Azure NiFi VM IP
ORACLE_HOST="192.168.1.100"  # Replace with Oracle server IP
TEST_DURATION=300  # 5 minutes
LOG_DIR="./network_tests_$(date +%Y%m%d_%H%M%S)"

# Create log directory
mkdir -p $LOG_DIR

# Function: Network Latency Testing
test_network_latency() {
    echo "Testing network latency to Azure VM..."
    
    # Basic ping test
    ping -c 100 $AZURE_VM_IP > $LOG_DIR/ping_azure_vm.log 2>&1
    
    # MTR (My TraceRoute) for detailed path analysis
    mtr --report --report-cycles 50 $AZURE_VM_IP > $LOG_DIR/mtr_azure_vm.log 2>&1
    
    # Traceroute for path discovery
    traceroute $AZURE_VM_IP > $LOG_DIR/traceroute_azure_vm.log 2>&1
    
    echo "Latency tests completed. Results in $LOG_DIR/"
}

# Function: Bandwidth Testing
test_bandwidth() {
    echo "Testing bandwidth between on-prem and Azure..."
    
    # iPerf3 bandwidth test (requires iPerf3 server on Azure VM)
    # Run this on Azure VM first: iperf3 -s -p 5201
    
    # TCP bandwidth test
    iperf3 -c $AZURE_VM_IP -t $TEST_DURATION -P 4 -f M > $LOG_DIR/iperf3_tcp.log 2>&1
    
    # UDP bandwidth test
    iperf3 -c $AZURE_VM_IP -u -b 100M -t 60 > $LOG_DIR/iperf3_udp.log 2>&1
    
    echo "Bandwidth tests completed."
}

# Function: Network Quality Assessment
test_network_quality() {
    echo "Testing network quality metrics..."
    
    # Extended ping for packet loss analysis
    ping -c 1000 -i 0.1 $AZURE_VM_IP | tee $LOG_DIR/extended_ping.log
    
    # Calculate statistics
    packet_loss=$(grep "packet loss" $LOG_DIR/extended_ping.log | awk '{print $6}')
    avg_rtt=$(grep "rtt min/avg/max/mdev" $LOG_DIR/extended_ping.log | awk -F'/' '{print $5}')
    
    echo "Packet Loss: $packet_loss" >> $LOG_DIR/network_summary.txt
    echo "Average RTT: ${avg_rtt}ms" >> $LOG_DIR/network_summary.txt
}

# Function: TCP Window Scaling Test
test_tcp_optimization() {
    echo "Testing TCP optimization parameters..."
    
    # Check current TCP settings
    echo "=== Current TCP Settings ===" > $LOG_DIR/tcp_settings.log
    sysctl net.core.rmem_max >> $LOG_DIR/tcp_settings.log
    sysctl net.core.wmem_max >> $LOG_DIR/tcp_settings.log
    sysctl net.ipv4.tcp_window_scaling >> $LOG_DIR/tcp_settings.log
    sysctl net.ipv4.tcp_timestamps >> $LOG_DIR/tcp_settings.log
    
    # Test different TCP window sizes with curl
    for window_size in 64k 128k 256k 512k 1M; do
        echo "Testing TCP window size: $window_size"
        curl -w "@curl-format.txt" -o /dev/null -s "http://$AZURE_VM_IP:8080/nifi" \
             --tcp-nodelay --tcp-fastopen \
             >> $LOG_DIR/tcp_window_test_${window_size}.log 2>&1
    done
}

# Function: DNS Resolution Testing
test_dns_performance() {
    echo "Testing DNS resolution performance..."
    
    # DNS lookup time for Azure VM
    for i in {1..50}; do
        dig +stats $AZURE_VM_IP | grep "Query time:" >> $LOG_DIR/dns_lookup_times.log
        sleep 1
    done
    
    # Calculate average DNS lookup time
    avg_dns_time=$(awk '{sum+=$4} END {print sum/NR}' $LOG_DIR/dns_lookup_times.log)
    echo "Average DNS lookup time: ${avg_dns_time}ms" >> $LOG_DIR/network_summary.txt
}

# Function: Firewall and Port Testing
test_ports_connectivity() {
    echo "Testing port connectivity..."
    
    # Common NiFi ports
    NIFI_PORTS=(8080 8443 8082 8083 10000 10001)
    
    for port in "${NIFI_PORTS[@]}"; do
        echo "Testing port $port..."
        nc -zv $AZURE_VM_IP $port >> $LOG_DIR/port_connectivity.log 2>&1
        
        # Measure connection time
        time_output=$(time nc -z $AZURE_VM_IP $port 2>&1)
        echo "Port $port connection time: $time_output" >> $LOG_DIR/port_timing.log
    done
}

# Function: Azure-specific Network Tests
test_azure_network() {
    echo "Running Azure-specific network tests..."
    
    # Test Azure Storage endpoint connectivity
    AZURE_STORAGE_ENDPOINT="yourstorageaccount.dfs.core.windows.net"
    
    # DNS resolution for Azure Storage
    nslookup $AZURE_STORAGE_ENDPOINT >> $LOG_DIR/azure_storage_dns.log
    
    # Connectivity test to Azure Storage
    curl -I "https://$AZURE_STORAGE_ENDPOINT" >> $LOG_DIR/azure_storage_connectivity.log 2>&1
    
    # Test Azure Service endpoints
    curl -w "@curl-format.txt" -o /dev/null -s "https://management.azure.com/" \
         >> $LOG_DIR/azure_management_endpoint.log 2>&1
}

# Create curl format file for detailed timing
cat > curl-format.txt << 'EOF'
     time_namelookup:  %{time_namelookup}\n
        time_connect:  %{time_connect}\n
     time_appconnect:  %{time_appconnect}\n
    time_pretransfer:  %{time_pretransfer}\n
       time_redirect:  %{time_redirect}\n
  time_starttransfer:  %{time_starttransfer}\n
                     ----------\n
          time_total:  %{time_total}\n
EOF

# Function: Generate Network Report
generate_network_report() {
    echo "Generating network performance report..."
    
    cat > $LOG_DIR/network_performance_report.md << EOF
# Network Performance Test Report

**Test Date:** $(date)
**Test Duration:** $TEST_DURATION seconds
**Target:** $AZURE_VM_IP

## Summary
$(cat $LOG_DIR/network_summary.txt)

## Recommendations
Based on the test results:

1. **Latency Optimization:**
   - If RTT > 100ms, consider ExpressRoute
   - If packet loss > 1%, investigate network path

2. **Bandwidth Optimization:**
   - Compare iPerf3 results with expected throughput
   - Consider multiple parallel connections if single connection is limited

3. **TCP Optimization:**
   - Tune TCP window scaling based on bandwidth-delay product
   - Enable TCP timestamps if not already enabled

## Next Steps
1. Review detailed logs in this directory
2. Implement recommended network optimizations
3. Re-run tests after optimizations
4. Proceed to NiFi performance testing phase
EOF

    echo "Network performance report generated: $LOG_DIR/network_performance_report.md"
}

# Main execution
main() {
    echo "Starting comprehensive network performance testing..."
    
    # Check dependencies
    command -v ping >/dev/null 2>&1 || { echo "ping required but not installed."; exit 1; }
    command -v mtr >/dev/null 2>&1 || { echo "mtr required but not installed. Install: apt-get install mtr"; exit 1; }
    command -v iperf3 >/dev/null 2>&1 || { echo "iperf3 required but not installed. Install: apt-get install iperf3"; exit 1; }
    command -v nc >/dev/null 2>&1 || { echo "netcat required but not installed."; exit 1; }
    
    # Run all tests
    test_network_latency
    test_bandwidth  # Note: Requires iperf3 server running on Azure VM
    test_network_quality
    test_tcp_optimization
    test_dns_performance
    test_ports_connectivity
    test_azure_network
    
    # Generate report
    generate_network_report
    
    echo "All network tests completed. Results available in: $LOG_DIR"
}

# Execute main function
main "$@"

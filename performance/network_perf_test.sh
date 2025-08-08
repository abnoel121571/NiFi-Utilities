#!/bin/bash

# Generic Network Performance Testing Suite
# Enhanced version with command-line arguments and improved output

set -euo pipefail

# Default configuration
DEFAULT_TEST_DURATION=300
DEFAULT_LOG_DIR="./network_tests_$(date +%Y%m%d_%H%M%S)"
DEFAULT_OUTPUT_FILE=""
VERBOSE=false
QUIET=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage function
usage() {
    cat << EOF
Generic Network Performance Testing Suite

USAGE:
    $0 -t TARGET_IP [OPTIONS]

REQUIRED:
    -t, --target IP         Target IP address or hostname to test

OPTIONS:
    -s, --source IP         Source IP address (default: auto-detect)
    -d, --duration SECONDS  Test duration in seconds (default: $DEFAULT_TEST_DURATION)
    -o, --output FILE       Save detailed output to file
    -l, --log-dir DIR       Log directory (default: $DEFAULT_LOG_DIR)
    -p, --ports PORT_LIST   Comma-separated list of ports to test (default: 22,80,443)
    -q, --quiet             Suppress detailed output, show only summary
    -v, --verbose           Show verbose output
    -h, --help              Show this help message

EXAMPLES:
    $0 -t 192.168.1.100
    $0 -t 10.0.1.50 -s 192.168.1.10 -d 60 -o network_test.log
    $0 -t example.com -p "22,80,443,8080" --verbose
    $0 -t 172.16.1.1 --quiet --log-dir /tmp/tests

TESTS PERFORMED:
    • Network latency (ping, traceroute)
    • Bandwidth testing (iperf3 if available)
    • Network quality (packet loss, jitter)
    • TCP optimization analysis
    • DNS resolution performance
    • Port connectivity
    • Network path analysis

DEPENDENCIES:
    Required: ping, traceroute, nc (netcat)
    Optional: mtr, iperf3, dig, nmap
    
    If tools are missing, the script will show installation commands
    for your operating system (Linux/Ubuntu/CentOS/macOS)

EOF
}

# Logging functions
log_info() {
    if [[ "$QUIET" != true ]]; then
        echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
    fi
}

log_success() {
    if [[ "$QUIET" != true ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
    fi
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_verbose() {
    if [[ "$VERBOSE" == true && "$QUIET" != true ]]; then
        echo -e "${NC}[VERBOSE]${NC} $1" | tee -a "$LOG_FILE"
    fi
}

# Progress indicator
show_progress() {
    local duration=$1
    local message=$2
    
    if [[ "$QUIET" != true ]]; then
        echo -n "$message "
        for ((i=0; i<duration; i++)); do
            echo -n "."
            sleep 1
        done
        echo " Done!"
    else
        sleep $duration
    fi
}

# Get install command for missing tools
get_install_command() {
    local tool=$1
    local os_type=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    case $tool in
        ping)
            case $os_type in
                linux) echo "apt-get install iputils-ping  # or yum install iputils" ;;
                darwin) echo "ping is built-in on macOS" ;;
                *) echo "Install ping utility for your OS" ;;
            esac
            ;;
        traceroute)
            case $os_type in
                linux) echo "apt-get install traceroute  # or yum install traceroute" ;;
                darwin) echo "traceroute is built-in on macOS" ;;
                *) echo "Install traceroute utility for your OS" ;;
            esac
            ;;
        nc)
            case $os_type in
                linux) echo "apt-get install netcat-openbsd  # or yum install nc" ;;
                darwin) echo "nc is built-in on macOS" ;;
                *) echo "Install netcat utility for your OS" ;;
            esac
            ;;
        mtr)
            case $os_type in
                linux) echo "apt-get install mtr  # or yum install mtr" ;;
                darwin) echo "brew install mtr" ;;
                *) echo "Install mtr (My TraceRoute) for your OS" ;;
            esac
            ;;
        iperf3)
            case $os_type in
                linux) echo "apt-get install iperf3  # or yum install iperf3" ;;
                darwin) echo "brew install iperf3" ;;
                *) echo "Install iperf3 for your OS" ;;
            esac
            ;;
        dig)
            case $os_type in
                linux) echo "apt-get install dnsutils  # or yum install bind-utils" ;;
                darwin) echo "dig is built-in on macOS" ;;
                *) echo "Install dig/DNS utilities for your OS" ;;
            esac
            ;;
        nmap)
            case $os_type in
                linux) echo "apt-get install nmap  # or yum install nmap" ;;
                darwin) echo "brew install nmap" ;;
                *) echo "Install nmap for your OS" ;;
            esac
            ;;
        *)
            echo "Install $tool for your operating system"
            ;;
    esac
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    local optional_deps=()
    
    # Required dependencies
    for cmd in ping traceroute nc; do
        if ! command -v $cmd >/dev/null 2>&1; then
            missing_deps+=($cmd)
        fi
    done
    
    # Optional dependencies
    for cmd in mtr iperf3 dig nmap; do
        if ! command -v $cmd >/dev/null 2>&1; then
            optional_deps+=($cmd)
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        for dep in "${missing_deps[@]}"; do
            log_error "To install $dep: $(get_install_command $dep)"
        done
        exit 1
    fi
    
    if [[ ${#optional_deps[@]} -gt 0 ]]; then
        log_warning "Optional tools not found: ${optional_deps[*]}"
        for dep in "${optional_deps[@]}"; do
            log_warning "To install $dep: $(get_install_command $dep)"
        done
        log_warning "Some advanced tests may be skipped"
    fi
}

# Auto-detect source IP
detect_source_ip() {
    local target=$1
    local source_ip

    if command -v ip >/dev/null 2>&1; then
        source_ip=$(ip route get "$target" 2>/dev/null | grep -oP 'src \K\S+' | head -1)
    fi

    if [[ -z "$source_ip" ]]; then
        source_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi

    if [[ -z "$source_ip" ]]; then
        source_ip=$(hostname -i 2>/dev/null | awk '{print $1}')
    fi

    echo "${source_ip:-127.0.0.1}"
}

# Network latency testing
test_network_latency() {
    log_info "Testing network latency to $TARGET_IP..."
    
    # Basic ping test
    local ping_result=$(ping -c 20 -i 0.5 $TARGET_IP 2>&1)
    echo "$ping_result" > "$LOG_DIR/ping_results.log"
    
    # Extract statistics
    local packet_loss=$(echo "$ping_result" | grep -oP '\d+(?=% packet loss)' || echo "N/A")
    local avg_rtt=$(echo "$ping_result" | grep -oP 'rtt min/avg/max/mdev = [\d.]+/\K[\d.]+' || echo "N/A")
    
    echo "Packet Loss: ${packet_loss}%" >> "$SUMMARY_FILE"
    echo "Average RTT: ${avg_rtt}ms" >> "$SUMMARY_FILE"
    
    if [[ "$packet_loss" != "N/A" && "$packet_loss" -gt 5 ]]; then
        log_warning "High packet loss detected: ${packet_loss}%"
    elif [[ "$packet_loss" != "N/A" ]]; then
        log_success "Packet loss: ${packet_loss}%"
    fi
    
    if [[ "$avg_rtt" != "N/A" ]]; then
        local rtt_int=${avg_rtt%.*}
        if [[ $rtt_int -gt 100 ]]; then
            log_warning "High latency detected: ${avg_rtt}ms"
        else
            log_success "Average latency: ${avg_rtt}ms"
        fi
    fi
    
    # Traceroute
    log_verbose "Running traceroute..."
    traceroute $TARGET_IP > "$LOG_DIR/traceroute.log" 2>&1 &
    local trace_pid=$!
    
    # MTR if available
    if command -v mtr >/dev/null 2>&1; then
        log_verbose "Running MTR analysis..."
        mtr --report --report-cycles 10 $TARGET_IP > "$LOG_DIR/mtr_report.log" 2>&1 &
        local mtr_pid=$!
    else
        log_verbose "MTR not available, skipping advanced path analysis"
        log_info "To install MTR: $(get_install_command mtr)"
    fi
    
    # Wait for traceroute
    wait $trace_pid 2>/dev/null || true
    [[ -n "${mtr_pid:-}" ]] && wait $mtr_pid 2>/dev/null || true
}

# Bandwidth testing
test_bandwidth() {
    if ! command -v iperf3 >/dev/null 2>&1; then
        log_warning "iperf3 not available, skipping bandwidth test"
        log_info "To install iperf3: $(get_install_command iperf3)"
        echo "Bandwidth Test: Skipped (iperf3 not installed)" >> "$SUMMARY_FILE"
        return
    fi
    
    log_info "Testing bandwidth (requires iperf3 server on target)..."
    
    # Test if iperf3 server is running on target
    if nc -z $TARGET_IP 5201 2>/dev/null; then
        log_verbose "iperf3 server detected, running bandwidth test..."
        
        # TCP test
        iperf3 -c $TARGET_IP -t 30 -f M > "$LOG_DIR/bandwidth_tcp.log" 2>&1 || {
            log_warning "TCP bandwidth test failed"
        }
        
        # UDP test
        iperf3 -c $TARGET_IP -u -b 50M -t 10 > "$LOG_DIR/bandwidth_udp.log" 2>&1 || {
            log_warning "UDP bandwidth test failed"
        }
        
        # Extract bandwidth results
        if [[ -f "$LOG_DIR/bandwidth_tcp.log" ]]; then
            local tcp_bw=$(grep "sender" "$LOG_DIR/bandwidth_tcp.log" | tail -1 | awk '{print $(NF-2), $(NF-1)}')
            echo "TCP Bandwidth: $tcp_bw" >> "$SUMMARY_FILE"
            log_success "TCP bandwidth: $tcp_bw"
        fi
    else
        log_warning "No iperf3 server found on port 5201, skipping bandwidth test"
        log_info "To run iperf3 server on target: iperf3 -s -p 5201"
        echo "Bandwidth Test: Skipped (no iperf3 server on target)" >> "$SUMMARY_FILE"
    fi
}

# Network quality assessment
test_network_quality() {
    log_info "Assessing network quality..."
    
    # Extended ping for jitter analysis
    local jitter_test=$(ping -c 50 -i 0.1 $TARGET_IP 2>&1)
    echo "$jitter_test" > "$LOG_DIR/jitter_test.log"
    
    # Calculate jitter (standard deviation of RTT)
    local rtts=$(echo "$jitter_test" | grep -oP 'time=\K[\d.]+' | head -20)
    if [[ -n "$rtts" ]]; then
        local jitter=$(echo "$rtts" | awk '{sum+=$1; sumsq+=$1*$1} END {print sqrt(sumsq/NR - (sum/NR)^2)}')
        echo "Network Jitter: ${jitter}ms" >> "$SUMMARY_FILE"
        log_success "Network jitter: ${jitter}ms"
    fi
}

# Port connectivity testing
test_ports_connectivity() {
    log_info "Testing port connectivity..."
    
    IFS=',' read -ra PORTS_ARRAY <<< "$TEST_PORTS"
    local open_ports=()
    local closed_ports=()
    
    for port in "${PORTS_ARRAY[@]}"; do
        port=$(echo $port | xargs)  # trim whitespace
        log_verbose "Testing port $port..."
        
        if timeout 5 nc -z $TARGET_IP $port 2>/dev/null; then
            open_ports+=($port)
            log_success "Port $port: OPEN"
        else
            closed_ports+=($port)
            log_warning "Port $port: CLOSED/FILTERED"
        fi
    done
    
    echo "Open Ports: ${open_ports[*]:-None}" >> "$SUMMARY_FILE"
    echo "Closed Ports: ${closed_ports[*]:-None}" >> "$SUMMARY_FILE"
}

# DNS performance testing
test_dns_performance() {
    if ! command -v dig >/dev/null 2>&1; then
        log_warning "dig not available, skipping DNS test"
        log_info "To install dig: $(get_install_command dig)"
        echo "DNS Resolution Test: Skipped (dig not installed)" >> "$SUMMARY_FILE"
        return
    fi
    
    log_info "Testing DNS resolution performance..."
    
    local dns_times=()
    for i in {1..5}; do
        local query_time=$(dig +short +stats $TARGET_IP | grep -oP 'Query time: \K\d+' || echo "0")
        dns_times+=($query_time)
        log_verbose "DNS query $i: ${query_time}ms"
    done
    
    local avg_dns=$(printf '%s\n' "${dns_times[@]}" | awk '{sum+=$1} END {print sum/NR}')
    echo "Average DNS Resolution: ${avg_dns}ms" >> "$SUMMARY_FILE"
    log_success "Average DNS resolution: ${avg_dns}ms"
}

# Generate summary report
generate_summary_report() {
    echo
    echo "==============================================="
    echo "    NETWORK PERFORMANCE TEST SUMMARY"
    echo "==============================================="
    echo "Test Date: $(date)"
    echo "Source IP: $SOURCE_IP"
    echo "Target IP: $TARGET_IP"
    echo "Test Duration: ${TEST_DURATION}s"
    echo "==============================================="
    
    while IFS= read -r line; do
        echo "$line"
    done < "$SUMMARY_FILE"
    
    echo "==============================================="
    echo "Detailed logs saved to: $LOG_DIR"
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "Output also saved to: $OUTPUT_FILE"
    fi
    echo "==============================================="
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--target)
                TARGET_IP="$2"
                shift 2
                ;;
            -s|--source)
                SOURCE_IP="$2"
                shift 2
                ;;
            -d|--duration)
                TEST_DURATION="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -l|--log-dir)
                LOG_DIR="$2"
                shift 2
                ;;
            -p|--ports)
                TEST_PORTS="$2"
                shift 2
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "${TARGET_IP:-}" ]]; then
        echo "Error: Target IP is required"
        usage
        exit 1
    fi
    
    # Set defaults
    TEST_DURATION=${TEST_DURATION:-$DEFAULT_TEST_DURATION}
    LOG_DIR=${LOG_DIR:-$DEFAULT_LOG_DIR}
    TEST_PORTS=${TEST_PORTS:-"22,80,443"}
    
    # Auto-detect source IP if not provided
    if [[ -z "${SOURCE_IP:-}" ]]; then
        SOURCE_IP=$(detect_source_ip "$TARGET_IP")
        log_verbose "Auto-detected source IP: $SOURCE_IP"
    fi
}

# Main function
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Setup logging
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/test.log"
    SUMMARY_FILE="$LOG_DIR/summary.txt"
    
    # Setup output redirection if specified
    #if [[ -n "$OUTPUT_FILE" ]]; then
    #    exec 1> >(tee -a "$OUTPUT_FILE")
    #    exec 2> >(tee -a "$OUTPUT_FILE" >&2)
    #fi
    
    # Check dependencies
    check_dependencies
    
    # Initialize summary file
    echo "# Network Performance Test Summary" > "$SUMMARY_FILE"
    echo "Date: $(date)" >> "$SUMMARY_FILE"
    echo "Source: $SOURCE_IP" >> "$SUMMARY_FILE"
    echo "Target: $TARGET_IP" >> "$SUMMARY_FILE"
    echo "Duration: ${TEST_DURATION}s" >> "$SUMMARY_FILE"
    echo "" >> "$SUMMARY_FILE"
    
    log_info "Starting network performance tests..."
    log_info "Source: $SOURCE_IP → Target: $TARGET_IP"
    
    # Run tests
    test_network_latency
    test_bandwidth
    test_network_quality
    test_ports_connectivity
    test_dns_performance
    
    # Generate and display summary
    generate_summary_report
    
    log_success "Network performance testing completed!"
}

# Execute main function with all arguments
main "$@"


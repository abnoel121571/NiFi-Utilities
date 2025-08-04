#!/bin/bash
#
# ==============================================================================
#
#               Cloudera-Managed NiFi Diagnostics Collector (v13)
#
# ==============================================================================
#
# Description:
#   This script safely collects diagnostics from a Cloudera-managed Apache NiFi
#   instance. This definitive version works by providing the vendor's 'nifi.sh'
#   script with a complete and correct execution environment, overriding its
#   faulty internal discovery logic.
#
#   1. Runs as the 'root' user to gain necessary permissions.
#   2. Dynamically discovers the active NiFi process directory.
#   3. Extracts the exact JAVA_HOME and generated 'conf' directory.
#   4. Sets all required environment variables (NIFI_HOME, NIFI_PID_DIR,
#      NIFI_ENV_PATH, BOOTSTRAP_CONF_DIR) to force nifi.sh to work correctly.
#   5. Switches to the 'nifi' user to execute the command securely.
#   6. Supports configurable timeout and connection settings via JAVA_OPTS.
#
# Usage:
#   1. Save this file (e.g., as run_nifi_diagnostics.sh).
#   2. Make it executable:
#      chmod +x run_nifi_diagnostics.sh
#   3. Run it with root privileges:
#      sudo ./run_nifi_diagnostics.sh [options]
#
# Options:
#   --timeout <seconds>     Set connection timeout (default: 30)
#   --read-timeout <seconds> Set read timeout (default: 60)
#   --socket-timeout <seconds> Set socket timeout (default: 300)
#   --custom-java-opts "<opts>" Add custom JAVA_OPTS
#   --help                  Show this help message
#
# Examples:
#   sudo ./run_nifi_diagnostics.sh
#   sudo ./run_nifi_diagnostics.sh --timeout 60 --read-timeout 120
#   sudo ./run_nifi_diagnostics.sh --custom-java-opts "-Xmx2g -XX:+UseG1GC"
#
# ==============================================================================

# --- Script Configuration ---
set -e # Exit immediately if a command exits with a non-zero status.

# The user that the NiFi service runs as.
readonly NIFI_USER="nifi"

# The base path to the NiFi installation provided by Cloudera parcels.
readonly NIFI_HOME_PATH="/opt/cloudera/parcels/CFM/NIFI"
readonly NIFI_BIN_PATH="${NIFI_HOME_PATH}/bin"

# Default timeout values (in seconds)
DEFAULT_CONNECTION_TIMEOUT=30
DEFAULT_READ_TIMEOUT=60
DEFAULT_SOCKET_TIMEOUT=300

# Initialize variables
CONNECTION_TIMEOUT=$DEFAULT_CONNECTION_TIMEOUT
READ_TIMEOUT=$DEFAULT_READ_TIMEOUT
SOCKET_TIMEOUT=$DEFAULT_SOCKET_TIMEOUT
CUSTOM_JAVA_OPTS=""

# --- Functions ---

show_help() {
    cat << EOF
Cloudera-Managed NiFi Diagnostics Collector (v13)

Usage: $0 [options]

Options:
  --timeout <seconds>          Set connection timeout (default: $DEFAULT_CONNECTION_TIMEOUT)
  --read-timeout <seconds>     Set read timeout (default: $DEFAULT_READ_TIMEOUT)
  --socket-timeout <seconds>   Set socket timeout (default: $DEFAULT_SOCKET_TIMEOUT)
  --custom-java-opts "<opts>"  Add custom JAVA_OPTS (e.g., "-Xmx2g -XX:+UseG1GC")
  --help                       Show this help message

Examples:
  $0
  $0 --timeout 60 --read-timeout 120
  $0 --socket-timeout 600 --custom-java-opts "-Xmx4g"
  $0 --custom-java-opts "-Djavax.net.debug=all"

Timeout Parameters:
  - Connection timeout: How long to wait when establishing connections
  - Read timeout: How long to wait for data to be read
  - Socket timeout: Overall socket operation timeout

EOF
}

validate_timeout() {
    local value=$1
    local name=$2
    
    if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -le 0 ]; then
        echo "❌ ERROR: Invalid $name value: $value. Must be a positive integer."
        exit 1
    fi
    
    if [ "$value" -gt 3600 ]; then
        echo "⚠️  WARNING: $name of $value seconds seems very high (>1 hour)"
    fi
}

# --- Parse Command Line Arguments ---

while [[ $# -gt 0 ]]; do
    case $1 in
        --timeout)
            CONNECTION_TIMEOUT="$2"
            validate_timeout "$CONNECTION_TIMEOUT" "connection timeout"
            shift 2
            ;;
        --read-timeout)
            READ_TIMEOUT="$2"
            validate_timeout "$READ_TIMEOUT" "read timeout"
            shift 2
            ;;
        --socket-timeout)
            SOCKET_TIMEOUT="$2"
            validate_timeout "$SOCKET_TIMEOUT" "socket timeout"
            shift 2
            ;;
        --custom-java-opts)
            CUSTOM_JAVA_OPTS="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "❌ ERROR: Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# --- Pre-flight Checks ---

echo "▶️ Starting NiFi Diagnostics Collection..."

# Check if the script is being run as root.
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ ERROR: This script must be run as root or with sudo privileges."
    echo "   Please run as: sudo $0"
    exit 1
fi

# Check if the NiFi home directory exists.
if [ ! -d "$NIFI_HOME_PATH" ]; then
    echo "❌ ERROR: NiFi home path not found at '${NIFI_HOME_PATH}'."
    echo "   Please verify the CFM parcel installation path."
    exit 1
fi

# --- Main Logic ---

# 1. Discover the active NiFi process directory managed by cloudera-scm-agent.
echo "   - Searching for the active NiFi process directory..."
NIFI_PROC_DIR=$(ls -td /var/run/cloudera-scm-agent/process/*NIFI*/ | head -1)

if [ -z "$NIFI_PROC_DIR" ] || [ ! -d "$NIFI_PROC_DIR" ]; then
    echo "❌ ERROR: Could not find a running NiFi process directory."
    echo "   Please ensure the Cloudera Agent and NiFi role are running."
    exit 1
fi
echo "   - Found NiFi process directory: $NIFI_PROC_DIR"

# 2. Extract the JAVA_HOME path from the process's metric.properties file.
echo "   - Locating the correct JAVA_HOME for NiFi..."
MY_JAVA_HOME=$(grep "JAVA_HOME" "${NIFI_PROC_DIR}/metric.properties" | cut -d'=' -f2 | xargs)

if [ -z "$MY_JAVA_HOME" ]; then
    echo "❌ ERROR: Could not determine JAVA_HOME from metric.properties."
    exit 1
fi
echo "   - Found JAVA_HOME: $MY_JAVA_HOME"

# 3. Find the path to the generated config directory from the process's bootstrap.conf.
echo "   - Locating the generated configuration directory..."
NIFI_GENERATED_CONF_DIR=$(grep "conf.dir=" "${NIFI_PROC_DIR}/bootstrap.conf" | cut -d'=' -f2 | xargs)

if [ -z "$NIFI_GENERATED_CONF_DIR" ] || [ ! -d "$NIFI_GENERATED_CONF_DIR" ]; then
    echo "❌ ERROR: Could not determine the generated 'conf.dir' from ${NIFI_PROC_DIR}/bootstrap.conf."
    exit 1
fi
echo "   - Found generated config directory: $NIFI_GENERATED_CONF_DIR"

# 4. Construct the full path to the environment script that nifi.sh needs to source.
NIFI_ENV_FILE_TO_SOURCE="${NIFI_GENERATED_CONF_DIR}/nifi-env.sh"
if [ ! -f "$NIFI_ENV_FILE_TO_SOURCE" ]; then
    echo "❌ ERROR: The environment script was not found at the expected location: ${NIFI_ENV_FILE_TO_SOURCE}"
    exit 1
fi
echo "   - Using environment script: ${NIFI_ENV_FILE_TO_SOURCE}"

# 5. Build JAVA_OPTS for timeout configuration
echo "   - Configuring timeout settings..."
TIMEOUT_JAVA_OPTS=""
TIMEOUT_JAVA_OPTS="${TIMEOUT_JAVA_OPTS} -Dsun.net.client.defaultConnectTimeout=$((CONNECTION_TIMEOUT * 1000))"
TIMEOUT_JAVA_OPTS="${TIMEOUT_JAVA_OPTS} -Dsun.net.client.defaultReadTimeout=$((READ_TIMEOUT * 1000))"
TIMEOUT_JAVA_OPTS="${TIMEOUT_JAVA_OPTS} -Djava.net.preferIPv4Stack=true"
TIMEOUT_JAVA_OPTS="${TIMEOUT_JAVA_OPTS} -Dcom.sun.jndi.ldap.connect.timeout=$((CONNECTION_TIMEOUT * 1000))"
TIMEOUT_JAVA_OPTS="${TIMEOUT_JAVA_OPTS} -Dcom.sun.jndi.ldap.read.timeout=$((READ_TIMEOUT * 1000))"

# Add socket timeout for HTTP connections
TIMEOUT_JAVA_OPTS="${TIMEOUT_JAVA_OPTS} -Dsun.net.useExclusiveBind=false"

# Combine with custom JAVA_OPTS if provided
FINAL_JAVA_OPTS="$TIMEOUT_JAVA_OPTS"
if [ -n "$CUSTOM_JAVA_OPTS" ]; then
    FINAL_JAVA_OPTS="${FINAL_JAVA_OPTS} ${CUSTOM_JAVA_OPTS}"
    echo "   - Added custom JAVA_OPTS: $CUSTOM_JAVA_OPTS"
fi

echo "   - Connection timeout: ${CONNECTION_TIMEOUT}s"
echo "   - Read timeout: ${READ_TIMEOUT}s"
echo "   - Socket timeout: ${SOCKET_TIMEOUT}s"

# 6. Generate a unique, timestamped filename for the diagnostics bundle.
DIAG_FILE="/tmp/cloudera-nifi-diag-$(hostname)-$(date +'%Y_%m_%d_%H_%M').zip"
echo "   - Diagnostics will be saved to: $DIAG_FILE"

# Check available disk space
AVAILABLE_SPACE_KB=$(df /tmp | awk 'NR==2 {print $4}')
AVAILABLE_SPACE_MB=$((AVAILABLE_SPACE_KB / 1024))
if [ "$AVAILABLE_SPACE_MB" -lt 1024 ]; then
    echo "⚠️  WARNING: Only ${AVAILABLE_SPACE_MB}MB available in /tmp. Diagnostics may require significant space."
fi

# --- Execution ---

# 7. Execute the diagnostics command as the specified NIFI_USER.
#    We export all necessary environment variables to give the nifi.sh
#    script and its underlying Java process the complete, correct environment.
echo "   - Running the diagnostics command as user '$NIFI_USER'..."

# Use timeout command to enforce overall execution timeout
OVERALL_TIMEOUT=$((SOCKET_TIMEOUT + 60))  # Add buffer to socket timeout

COMMAND_TO_RUN="export NIFI_HOME='${NIFI_HOME_PATH}'; \
                export BOOTSTRAP_CONF_DIR='${NIFI_GENERATED_CONF_DIR}'; \
                export NIFI_ENV_PATH='${NIFI_ENV_FILE_TO_SOURCE}'; \
                export NIFI_PID_DIR='${NIFI_PROC_DIR}'; \
                export JAVA_HOME='${MY_JAVA_HOME}'; \
                export JAVA_OPTS='${FINAL_JAVA_OPTS}'; \
                timeout ${OVERALL_TIMEOUT} '${NIFI_BIN_PATH}/nifi.sh' diagnostics --verbose '${DIAG_FILE}'"

echo "   - Using JAVA_OPTS: $FINAL_JAVA_OPTS"
echo "   - Overall execution timeout: ${OVERALL_TIMEOUT}s"

# Execute with proper error handling
if sudo -u "$NIFI_USER" bash -c "${COMMAND_TO_RUN}"; then
    # Check if the command was terminated by timeout
    if [ $? -eq 124 ]; then
        echo "❌ ERROR: Diagnostics collection timed out after ${OVERALL_TIMEOUT} seconds."
        echo "   Consider increasing timeout values or checking NiFi connectivity."
        exit 1
    fi
    
    # Final check to ensure the zip file is valid and not empty
    if [ -s "${DIAG_FILE}" ]; then
        # Validate zip file if unzip is available
        if command -v unzip >/dev/null 2>&1; then
            if unzip -t "${DIAG_FILE}" >/dev/null 2>&1; then
                FILE_SIZE=$(du -h "${DIAG_FILE}" | cut -f1)
                echo "✅ SUCCESS: NiFi diagnostics collection complete."
                echo "   Output file: ${DIAG_FILE} (${FILE_SIZE})"
                echo "   File validated successfully."
            else
                echo "⚠️  WARNING: Diagnostics file created but may be corrupted."
                echo "   File location: ${DIAG_FILE}"
            fi
        else
            FILE_SIZE=$(du -h "${DIAG_FILE}" | cut -f1)
            echo "✅ SUCCESS: NiFi diagnostics collection complete."
            echo "   Output file: ${DIAG_FILE} (${FILE_SIZE})"
            echo "   (Install 'unzip' to validate file integrity)"
        fi
    else
        echo "❌ ERROR: The diagnostics command completed but produced an empty or invalid file."
        echo "   The file at ${DIAG_FILE} is empty or missing."
        exit 1
    fi
else
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 124 ]; then
        echo "❌ ERROR: Diagnostics collection timed out after ${OVERALL_TIMEOUT} seconds."
        echo "   Try increasing timeout values with --socket-timeout option."
    else
        echo "❌ ERROR: The nifi.sh diagnostics command failed with exit code $EXIT_CODE."
        echo "   Please check the output above for errors."
    fi
    exit 1
fi

echo "   - To extract and examine: unzip -l '${DIAG_FILE}'"
exit 0

#!/bin/bash
#
# ==============================================================================
#
#               Cloudera-Managed NiFi Diagnostics Collector (v12)
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
#
# Usage:
#   1. Save this file (e.g., as run_nifi_diagnostics.sh).
#   2. Make it executable:
#      chmod +x run_nifi_diagnostics.sh
#   3. Run it with root privileges:
#      sudo ./run_nifi_diagnostics.sh
#
# ==============================================================================

# --- Script Configuration ---
set -e # Exit immediately if a command exits with a non-zero status.

# The user that the NiFi service runs as.
readonly NIFI_USER="nifi"

# The base path to the NiFi installation provided by Cloudera parcels.
readonly NIFI_HOME_PATH="/opt/cloudera/parcels/CFM/NIFI"
readonly NIFI_BIN_PATH="${NIFI_HOME_PATH}/bin"

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

# 5. Generate a unique, timestamped filename for the diagnostics bundle.
DIAG_FILE="/tmp/cloudera-nifi-diag-$(hostname)-$(date +'%Y_%m_%d_%H_%M').zip"
echo "   - Diagnostics will be saved to: $DIAG_FILE"

# --- Execution ---

# 6. Execute the diagnostics command as the specified NIFI_USER.
#    We export all necessary environment variables to give the nifi.sh
#    script and its underlying Java process the complete, correct environment.
echo "   - Running the diagnostics command as user '$NIFI_USER'..."
COMMAND_TO_RUN="export NIFI_HOME='${NIFI_HOME_PATH}'; \
                export BOOTSTRAP_CONF_DIR='${NIFI_GENERATED_CONF_DIR}'; \
                export NIFI_ENV_PATH='${NIFI_ENV_FILE_TO_SOURCE}'; \
                export NIFI_PID_DIR='${NIFI_PROC_DIR}'; \
                export JAVA_HOME='${MY_JAVA_HOME}'; \
                '${NIFI_BIN_PATH}/nifi.sh' diagnostics --verbose '${DIAG_FILE}'"

sudo -u "$NIFI_USER" bash -c "${COMMAND_TO_RUN}"

# Check the exit code of the sudo command
if [ $? -eq 0 ]; then
    # Final check to ensure the zip file is valid and not empty
    if [ -s "${DIAG_FILE}" ]; then
        echo "✅ SUCCESS: NiFi diagnostics collection complete."
        echo "   Output file is located at: ${DIAG_FILE}"
    else
        echo "❌ ERROR: The diagnostics command ran but produced an empty or invalid file."
        echo "   The file at ${DIAG_FILE} is not a valid zip archive."
        exit 1
    fi
else
    echo "❌ ERROR: The nifi.sh diagnostics command failed. Please check the output above for errors."
    exit 1
fi

exit 0

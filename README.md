# Cloudera-Managed NiFi Diagnostics Collector

This Bash script is a robust tool designed to safely and reliably collect diagnostic bundles from an Apache NiFi instance managed by Cloudera Manager.

## Overview

In a Cloudera environment, NiFi's configuration is not static. Cloudera Manager generates dynamic configuration files in temporary process directories. This makes running standard NiFi command-line tools, like `nifi.sh diagnostics`, difficult because they cannot find the correct environment settings.

This script automates the entire process, working around Cloudera's complexities to provide a simple, one-command solution for gathering diagnostic information.

## Problem Solved

The standard `nifi.sh` script provided with the CFM parcel is designed for standalone installations and fails in a Cloudera-managed environment because it cannot locate the dynamically generated configuration files. This script solves that problem by:

1.  **Discovering Dynamic Paths**: It finds the exact process directory used by the currently running NiFi instance.
2.  **Extracting Correct Settings**: It reads the `bootstrap.conf` and `metric.properties` files from the process directory to find the precise `JAVA_HOME` and `conf` directory paths.
3.  **Building the Correct Environment**: It exports these dynamic paths as environment variables.
4.  **Executing as the Right User**: It runs the final command as the `nifi` service user, ensuring correct file permissions and security context.

## Requirements

* A Linux environment (e.g., RHEL, CentOS) where NiFi is managed by Cloudera Manager.
* The Cloudera CFM parcel must be installed.
* The script must be run by a user with `sudo` privileges (typically `root`).

## Usage

1.  **Save the Script**: Save the script from the Canvas to a file on your NiFi node (e.g., `run_nifi_diagnostics.sh`).

2.  **Make it Executable**: Open a terminal and grant execute permissions to the file.
    ```sh
    chmod +x run_nifi_diagnostics.sh
    ```

3.  **Run with Sudo**: Execute the script with `sudo` to ensure it has the necessary permissions to read the Cloudera agent directories.
    ```sh
    sudo ./run_nifi_diagnostics.sh
    ```

Upon successful execution, a `.zip` file containing the NiFi diagnostics bundle will be created in the `/tmp/` directory. The script will print the exact path to this file.

## How It Works

The script performs the following steps in sequence:

1.  **Pre-flight Checks**: Verifies it is running as `root` and that the base NiFi parcel directory exists.
2.  **Discover Process Directory**: Searches `/var/run/cloudera-scm-agent/process/` for the most recently created directory related to a NiFi process.
3.  **Extract JAVA_HOME**: Reads the `metric.properties` file within the process directory to get the correct Java path.
4.  **Extract Config Directory**: Reads the `bootstrap.conf` file to get the path of the generated `conf` directory.
5.  **Construct Environment**: Uses the extracted paths to build the `NIFI_ENV_PATH` and `JAVA_HOME` environment variables.
6.  **Execute Command**: Uses `sudo -u nifi` to switch to the `nifi` user and then runs the `nifi.sh diagnostics` command within a new Bash shell that has the correct environment variables exported.
7.  **Report Status**: Prints a success or failure message, including the final location of the diagnostic bundle.

## Configuration

The script contains a few `readonly` variables at the top that define standard paths and user names. These are unlikely to need changing in a standard Cloudera environment.

* `NIFI_USER`: The service account for NiFi (default: `nifi`).
* `NIFI_HOME_PATH`: The base path for the CFM parcel (default: `/opt/cloudera/parcels/CFM/NIFI`).



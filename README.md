# Cloudera-Managed NiFi Diagnostics Collector

A robust bash script designed to collect comprehensive diagnostics from Cloudera-managed Apache NiFi instances. This script resolves common issues with the standard `nifi.sh diagnostics` command in Cloudera environments by dynamically discovering and configuring the proper execution environment.

## 🚀 Features

- **Automatic Environment Discovery**: Dynamically locates NiFi process directories, Java home, and configuration paths
- **Cloudera-Optimized**: Specifically designed for Cloudera Manager (CM) managed NiFi deployments
- **Timeout Control**: Configurable timeout options to prevent hanging operations
- **Security-First**: Runs discovery as root but executes diagnostics as the NiFi user
- **Comprehensive Validation**: Multiple validation layers ensure reliable operation
- **Error Handling**: Detailed error messages with actionable remediation steps

## 📋 Prerequisites

- **Operating System**: Linux-based system with Cloudera Manager
- **Privileges**: Root or sudo access required
- **NiFi Installation**: Cloudera Flow Management (CFM) parcel installed
- **Services**: Cloudera Manager Agent and NiFi service running

## 🛠 Installation

1. **Download the script**:
   ```bash
   curl -O https://example.com/run_nifi_diagnostics.sh
   # or
   wget https://example.com/run_nifi_diagnostics.sh
   ```

2. **Make it executable**:
   ```bash
   chmod +x run_nifi_diagnostics.sh
   ```

3. **Verify permissions**:
   ```bash
   ls -la run_nifi_diagnostics.sh
   # Should show: -rwxr-xr-x
   ```

## 📖 Usage

### Basic Usage

```bash
# Run with default settings
sudo ./run_nifi_diagnostics.sh
```

### Advanced Usage

```bash
# Custom timeout settings
sudo ./run_nifi_diagnostics.sh --timeout 60 --read-timeout 120 --socket-timeout 600

# Add custom JVM options
sudo ./run_nifi_diagnostics.sh --custom-java-opts "-Xmx4g -XX:+UseG1GC"

# Debugging network issues
sudo ./run_nifi_diagnostics.sh --custom-java-opts "-Djavax.net.debug=all"

# Show help
sudo ./run_nifi_diagnostics.sh --help
```

## ⚙️ Configuration Options

| Option | Description | Default | Example |
|--------|-------------|---------|---------|
| `--timeout` | Connection timeout (seconds) | 30 | `--timeout 60` |
| `--read-timeout` | Read timeout (seconds) | 60 | `--read-timeout 120` |
| `--socket-timeout` | Socket timeout (seconds) | 300 | `--socket-timeout 600` |
| `--custom-java-opts` | Additional JVM options | None | `--custom-java-opts "-Xmx2g"` |
| `--help` | Show usage information | N/A | `--help` |

### Timeout Parameters Explained

- **Connection Timeout**: Maximum time to wait when establishing network connections
- **Read Timeout**: Maximum time to wait for data to be read from established connections  
- **Socket Timeout**: Overall timeout for socket operations (used as fallback)

## 📁 Output

The script generates a timestamped ZIP file containing comprehensive NiFi diagnostics:

```
/tmp/cloudera-nifi-diag-<hostname>-<YYYY_MM_DD_HH_MM>.zip
```

### Diagnostic Contents

The generated archive typically includes:
- System information and environment variables
- NiFi configuration files
- Log files (application, bootstrap, user)
- Thread dumps and heap information
- Flow configuration snapshots
- Repository information
- Network and security configurations

## 🔧 Troubleshooting

### Common Issues

#### 1. "Must be run as root" Error
```bash
❌ ERROR: This script must be run as root or with sudo privileges.
```
**Solution**: Run with `sudo`:
```bash
sudo ./run_nifi_diagnostics.sh
```

#### 2. "NiFi home path not found" Error
```bash
❌ ERROR: NiFi home path not found at '/opt/cloudera/parcels/CFM/NIFI'.
```
**Solutions**:
- Verify CFM parcel is installed and activated
- Check if NiFi is installed in a different location
- Ensure Cloudera Manager services are running

#### 3. "Could not find a running NiFi process directory" Error
```bash
❌ ERROR: Could not find a running NiFi process directory.
```
**Solutions**:
- Start the NiFi service in Cloudera Manager
- Check Cloudera Manager Agent status: `sudo systemctl status cloudera-scm-agent`
- Verify NiFi role is assigned and started

#### 4. Timeout Issues
```bash
❌ ERROR: Diagnostics collection timed out after 360 seconds.
```
**Solutions**:
```bash
# Increase timeouts for slow environments
sudo ./run_nifi_diagnostics.sh --socket-timeout 1200

# Check network connectivity to NiFi
curl -k https://localhost:8443/nifi/

# Monitor NiFi logs during collection
tail -f /var/log/nifi/nifi-app.log
```

#### 5. Insufficient Disk Space
```bash
⚠️ WARNING: Only 512MB available in /tmp. Diagnostics may require significant space.
```
**Solutions**:
```bash
# Clean up old diagnostic files
find /tmp -name "cloudera-nifi-diag-*" -mtime +7 -delete

# Use a different directory with more space
# (Modify DIAG_FILE variable in script)
```

### Debug Mode

For troubleshooting script issues, enable debug mode:
```bash
# Add debug flag to script execution
bash -x ./run_nifi_diagnostics.sh
```

## 🏗 Architecture

### Script Workflow

1. **Pre-flight Checks**
   - Validate root privileges
   - Verify NiFi installation paths
   - Check disk space

2. **Environment Discovery**
   - Locate active NiFi process directory
   - Extract Java home from process metrics
   - Find generated configuration directory
   - Validate environment script

3. **Configuration Setup**
   - Build timeout-related JAVA_OPTS
   - Combine with custom JVM options
   - Set environment variables

4. **Execution**
   - Switch to NiFi user context
   - Execute diagnostics with timeout protection
   - Validate output file

### Directory Structure

```
/opt/cloudera/parcels/CFM/NIFI/          # NiFi installation
├── bin/nifi.sh                          # NiFi control script
└── ...

/var/run/cloudera-scm-agent/process/     # Process directories
├── 123-nifi-NIFI_NODE/                 # Active NiFi process
│   ├── bootstrap.conf                  # Bootstrap configuration
│   ├── metric.properties               # Process metrics
│   └── ...
└── ...

/var/lib/nifi/conf/                      # Generated config directory
├── nifi.properties                     # Main configuration
├── nifi-env.sh                         # Environment script
└── ...
```

## 🔒 Security Considerations

- **Privilege Escalation**: Script requires root for discovery but drops to NiFi user for execution
- **Sensitive Data**: Diagnostic files may contain sensitive configuration data
- **File Permissions**: Output files inherit NiFi user permissions
- **Network Access**: Script may make network calls during diagnostics collection

### Best Practices

1. **Secure Storage**: Store diagnostic files in secure locations
2. **Access Control**: Limit access to diagnostic outputs
3. **Cleanup**: Remove old diagnostic files regularly
4. **Audit**: Log script execution for security auditing

## 📋 System Requirements

### Minimum Requirements
- **RAM**: 1GB available memory
- **Disk**: 2GB free space in `/tmp`
- **CPU**: Any modern x86_64 processor

### Supported Versions
- **Cloudera Manager**: 6.x, 7.x
- **NiFi**: 1.11.0+ (for `--verbose` flag support)
- **Java**: OpenJDK 8, 11, or Oracle JDK 8, 11
- **OS**: RHEL/CentOS 7+, Ubuntu 18.04+, SLES 12+

## 🤝 Contributing

### Reporting Issues
When reporting issues, please include:
- Script version (check header comment)
- Operating system and version
- Cloudera Manager version
- NiFi version
- Complete error output
- Steps to reproduce

### Enhancement Requests
- Describe the use case
- Provide examples of desired behavior
- Consider backward compatibility

## 📜 License

This script is provided under the Apache License 2.0. See LICENSE file for details.

## 📞 Support

For issues specific to:
- **Cloudera Products**: Contact Cloudera Support
- **Apache NiFi**: Consult NiFi documentation or community forums  
- **Script Issues**: Create an issue in the project repository

## 📚 Additional Resources

- [Apache NiFi Documentation](https://nifi.apache.org/docs.html)
- [Cloudera Flow Management Documentation](https://docs.cloudera.com/cfm/)
- [NiFi Troubleshooting Guide](https://nifi.apache.org/docs/nifi-docs/html/troubleshooting-guide.html)
- [Cloudera Manager API Documentation](https://cloudera.github.io/cm_api/)

---

**Version**: 13  
**Last Updated**: August 2025  
**Compatibility**: Cloudera Manager 6.x+, NiFi 1.11.0+

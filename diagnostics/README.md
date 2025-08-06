# NiFi Diagnostics Toolkit

A comprehensive suite of tools for collecting and analyzing Apache NiFi diagnostics in Cloudera-managed environments. This toolkit provides automated diagnostics collection with intelligent analysis and actionable recommendations.

![NiFi Diagnostics Toolkit](https://img.shields.io/badge/NiFi-Diagnostics%20Toolkit-blue.svg)
![Version](https://img.shields.io/badge/version-v13%2Fv1.0-green.svg)
![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)

## 📦 What's Included

The toolkit consists of two complementary scripts:

1. **`run_nifi_diagnostics.sh`** - Collection script that safely gathers comprehensive diagnostics from Cloudera-managed NiFi instances
2. **`nifi_diagnostics_analyzer.sh`** - Analysis script that examines diagnostic outputs and provides intelligent recommendations

## 🌟 Key Features

### Collection Script
- ✅ **Cloudera-Optimized**: Specifically designed for CM-managed deployments
- ✅ **Automatic Discovery**: Dynamically locates process directories and configurations
- ✅ **Timeout Control**: Configurable timeouts prevent hanging operations
- ✅ **Security-First**: Root discovery with secure user switching
- ✅ **Error Handling**: Comprehensive validation and clear error messages

### Analysis Script  
- 🔍 **Multi-Domain Analysis**: Performance, security, configuration, and flow analysis
- 📊 **Multiple Output Formats**: Text, JSON, and HTML reports
- 🎯 **Intelligent Filtering**: Filter by severity and category
- 💡 **Actionable Insights**: Specific recommendations for each issue
- 📈 **Trend Detection**: Identifies patterns in logs and configurations

## 🚀 Quick Start

### 1. Download the Scripts
```bash
# Download collection script
curl -O https://raw.githubusercontent.com/your-repo/nifi-diagnostics-toolkit/main/run_nifi_diagnostics.sh

# Download analysis script
curl -O https://raw.githubusercontent.com/your-repo/nifi-diagnostics-toolkit/main/nifi_diagnostics_analyzer.sh

# Make executable
chmod +x run_nifi_diagnostics.sh nifi_diagnostics_analyzer.sh
```

### 2. Collect Diagnostics
```bash
# Basic collection
sudo ./run_nifi_diagnostics.sh

# With custom timeouts
sudo ./run_nifi_diagnostics.sh --timeout 60 --read-timeout 120
```

### 3. Analyze Results
```bash
# Basic analysis
./nifi_diagnostics_analyzer.sh /tmp/cloudera-nifi-diag-hostname-2025_08_06_14_30.zip

# Generate HTML report
./nifi_diagnostics_analyzer.sh diagnostics.zip --output-format html --export report.html
```

## 🛠 Detailed Usage

### Collection Script (`run_nifi_diagnostics.sh`)

#### Prerequisites
- Root or sudo access
- Cloudera Manager with NiFi service running
- CFM parcel installed and activated

#### Command Line Options
```bash
sudo ./run_nifi_diagnostics.sh [options]

Options:
  --timeout <seconds>          Connection timeout (default: 30)
  --read-timeout <seconds>     Read timeout (default: 60)  
  --socket-timeout <seconds>   Socket timeout (default: 300)
  --custom-java-opts "<opts>"  Custom JVM options
  --help                       Show help message
```

#### Examples
```bash
# Standard collection
sudo ./run_nifi_diagnostics.sh

# High timeout for slow environments
sudo ./run_nifi_diagnostics.sh --socket-timeout 1200

# Debug network issues
sudo ./run_nifi_diagnostics.sh --custom-java-opts "-Djavax.net.debug=all"

# Performance tuning
sudo ./run_nifi_diagnostics.sh --custom-java-opts "-Xmx4g -XX:+UseG1GC"
```

### Analysis Script (`nifi_diagnostics_analyzer.sh`)

#### Command Line Options
```bash
./nifi_diagnostics_analyzer.sh <diagnostics.zip> [options]

Options:
  --output-format [text|json|html]     Output format (default: text)
  --severity [all|critical|warning|info]  Filter by severity
  --category [all|performance|security|config|flow]  Filter by category
  --verbose                            Detailed explanations
  --export <filename>                  Export to file
  --help                              Show help message
```

#### Examples
```bash
# Basic text analysis
./nifi_diagnostics_analyzer.sh diagnostics.zip

# Critical issues only
./nifi_diagnostics_analyzer.sh diagnostics.zip --severity critical

# Performance analysis with HTML export
./nifi_diagnostics_analyzer.sh diagnostics.zip \
  --category performance \
  --output-format html \
  --export performance-report.html \
  --verbose

# JSON output for automation
./nifi_diagnostics_analyzer.sh diagnostics.zip \
  --output-format json \
  --export results.json
```

## 📋 Analysis Categories

### 🚀 Performance Analysis
- **Memory Management**: JVM heap sizing, GC configuration
- **Threading**: Thread pool utilization, contention detection
- **I/O Operations**: Repository performance, disk utilization
- **Flow Efficiency**: Processor optimization opportunities

### 🔒 Security Analysis  
- **Encryption**: SSL/TLS configuration validation
- **Authentication**: User identity provider settings
- **Authorization**: Access control configuration
- **Certificate Management**: Keystore/truststore validation

### ⚙️ Configuration Analysis
- **Best Practices**: Industry standard compliance
- **Resource Allocation**: CPU, memory, disk assignments
- **Clustering**: Multi-node configuration validation
- **Integration**: External system connectivity

### 🔄 Flow Analysis
- **Design Patterns**: Anti-pattern detection
- **Complexity Assessment**: Flow maintainability metrics
- **Performance Bottlenecks**: Slow processor identification
- **Optimization Opportunities**: Efficiency improvements

## 📊 Sample Outputs

### Text Format
```
=========================================
         ANALYSIS SUMMARY
=========================================

Total Issues Found: 8
  🔴 Critical: 2
  🟡 Warning:  4
  🔵 Info:     2

🔴 CRITICAL ISSUES:
===================
• JVM heap size too small: 2g. Minimum 4GB recommended.
• OutOfMemoryError detected in logs.

🟡 WARNINGS:
============
• Using deprecated ConcMarkSweepGC. Consider upgrading to G1GC.
• Multiple repositories on same filesystem causing I/O contention.
• SSL/TLS not configured. NiFi running without encryption.
• High number of blocked threads: 25 blocked threads.

💡 RECOMMENDATIONS:
====================
• Set nifi.bootstrap.jvm.xmx to at least 4g for production use.
• Increase JVM heap size or investigate memory leaks.
• Replace CMS GC with G1GC: -XX:+UseG1GC
• Separate repositories across different disks/filesystems.
```

### JSON Format
```json
{
    "analysis_version": "1.0",
    "timestamp": "2025-08-06T14:30:00Z",
    "summary": {
        "total_issues": 8,
        "critical": 2,
        "warnings": 4,
        "info": 2
    },
    "issues": {
        "critical": [
            "JVM heap size too small: 2g. Minimum 4GB recommended.",
            "OutOfMemoryError detected in logs."
        ],
        "warnings": [
            "Using deprecated ConcMarkSweepGC. Consider upgrading to G1GC.",
            "Multiple repositories on same filesystem causing I/O contention."
        ]
    }
}
```

## 🔧 Troubleshooting

### Collection Script Issues

#### Permission Errors
```bash
❌ ERROR: This script must be run as root or with sudo privileges.
```
**Solution**: Use `sudo ./run_nifi_diagnostics.sh`

#### NiFi Not Found
```bash
❌ ERROR: Could not find a running NiFi process directory.
```
**Solutions**:
- Start NiFi service in Cloudera Manager
- Check agent status: `sudo systemctl status cloudera-scm-agent`
- Verify CFM parcel is activated

#### Timeout Issues  
```bash
❌ ERROR: Diagnostics collection timed out after 360 seconds.
```
**Solutions**:
```bash
# Increase timeouts
sudo ./run_nifi_diagnostics.sh --socket-timeout 1200

# Check connectivity
curl -k https://localhost:8443/nifi/
```

#### Disk Space
```bash
⚠️ WARNING: Only 512MB available in /tmp.
```
**Solutions**:
```bash
# Clean old diagnostics
find /tmp -name "cloudera-nifi-diag-*" -mtime +7 -delete

# Check space
df -h /tmp
```

### Analysis Script Issues

#### ZIP Extraction Errors
```bash
❌ ERROR: Failed to extract ZIP file. File may be corrupted.
```
**Solutions**:
- Verify ZIP file integrity: `unzip -t diagnostics.zip`
- Re-run collection script
- Check available disk space

#### Missing Files
```bash
⚠️ WARNING: nifi.properties file not found in diagnostics.
```
**Solutions**:
- Ensure collection completed successfully
- Check NiFi service status during collection
- Verify CM agent permissions

## 🏗 Architecture

### Collection Workflow
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Root Access   │───▶│   Environment    │───▶│   NiFi User     │
│   Validation    │    │   Discovery      │    │   Execution     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                       │
         ▼                        ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Pre-flight      │    │ Dynamic Config   │    │ Secure Command  │
│ Checks          │    │ Extraction       │    │ Execution       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Analysis Workflow
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  ZIP Archive    │───▶│   Content        │───▶│   Multi-Domain  │
│  Extraction     │    │   Validation     │    │   Analysis      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                        │                       │
         ▼                        ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ File Structure  │    │ Pattern          │    │ Recommendation │
│ Discovery       │    │ Recognition      │    │ Generation      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## 📚 File Structure

```
nifi-diagnostics-toolkit/
├── run_nifi_diagnostics.sh      # Collection script
├── nifi_diagnostics_analyzer.sh # Analysis script
├── README.md                    # This file
├── examples/
│   ├── sample-analysis-report.html
│   ├── sample-results.json
│   └── troubleshooting-guide.md
└── docs/
    ├── collection-guide.md
    ├── analysis-guide.md
    └── advanced-usage.md
```

## 🔄 Integration Examples

### Automated Monitoring
```bash
#!/bin/bash
# Weekly NiFi health check

TIMESTAMP=$(date +%Y%m%d_%H%M)
DIAG_FILE="/tmp/nifi-weekly-${TIMESTAMP}.zip"
REPORT_FILE="/reports/nifi-analysis-${TIMESTAMP}.html"

# Collect diagnostics
sudo ./run_nifi_diagnostics.sh --socket-timeout 600

# Analyze and generate report
./nifi_diagnostics_analyzer.sh "$DIAG_FILE" \
  --output-format html \
  --export "$REPORT_FILE"

# Alert on critical issues
CRITICAL_COUNT=$(./nifi_diagnostics_analyzer.sh "$DIAG_FILE" \
  --output-format json --severity critical | \
  jq '.summary.critical')

if [ "$CRITICAL_COUNT" -gt 0 ]; then
  echo "ALERT: $CRITICAL_COUNT critical issues found"
  # Send notification
fi
```

### CI/CD Pipeline Integration
```yaml
# .github/workflows/nifi-health-check.yml
name: NiFi Health Check
on:
  schedule:
    - cron: '0 2 * * 1'  # Weekly on Monday at 2 AM

jobs:
  health-check:
    runs-on: self-hosted
    steps:
      - name: Collect NiFi Diagnostics
        run: |
          sudo ./run_nifi_diagnostics.sh --timeout 120
          
      - name: Analyze Results
        run: |
          ./nifi_diagnostics_analyzer.sh /tmp/cloudera-nifi-diag-*.zip \
            --output-format json \
            --export analysis-results.json
            
      - name: Upload Analysis Report
        uses: actions/upload-artifact@v2
        with:
          name: nifi-analysis-report
          path: analysis-results.json
```

## 🎯 Best Practices

### Collection Best Practices
1. **Schedule Regular Collections**: Weekly or after major changes
2. **Monitor Disk Space**: Ensure adequate space before collection
3. **Use Appropriate Timeouts**: Adjust based on environment performance
4. **Secure Storage**: Store diagnostic files in secure locations
5. **Cleanup Strategy**: Remove old diagnostics regularly

### Analysis Best Practices
1. **Focus on Critical Issues First**: Address high-severity items immediately
2. **Track Progress**: Use JSON output for programmatic tracking
3. **Share Reports**: Use HTML format for stakeholder communication
4. **Trend Analysis**: Compare reports over time for trend identification
5. **Action Planning**: Create remediation plans from recommendations

## 📊 Performance Benchmarks

| Environment | Collection Time | Analysis Time | Report Size |
|-------------|----------------|---------------|-------------|
| Small (2 nodes, <100 processors) | 2-5 minutes | 30-60 seconds | 50-100 MB |
| Medium (4 nodes, 100-500 processors) | 5-10 minutes | 1-2 minutes | 100-250 MB |
| Large (8+ nodes, 500+ processors) | 10-20 minutes | 2-5 minutes | 250-500 MB |

## 🤝 Contributing

We welcome contributions! Here's how to get started:

### Reporting Issues
Please include:
- Script version (check header comments)
- Operating system and version  
- Cloudera Manager version
- NiFi version
- Complete error output
- Steps to reproduce

### Feature Requests
- Describe the use case
- Provide examples of desired behavior
- Consider backward compatibility
- Include performance implications

### Development Setup
```bash
# Clone the repository
git clone https://github.com/your-org/nifi-diagnostics-toolkit.git

# Make scripts executable
cd nifi-diagnostics-toolkit
chmod +x *.sh

# Run tests (if available)
./run-tests.sh
```

## 📋 System Requirements

### Collection Script Requirements
- **OS**: RHEL/CentOS 7+, Ubuntu 18.04+, SLES 12+
- **Privileges**: Root or sudo access
- **Memory**: 1GB available RAM
- **Disk**: 2GB free space in `/tmp`
- **NiFi**: 1.11.0+ (for --verbose support)
- **CM**: 6.x, 7.x

### Analysis Script Requirements
- **OS**: Any modern Linux distribution
- **Memory**: 512MB available RAM
- **Disk**: 1GB free space for extraction
- **Tools**: `unzip`, `bash` 4.0+
- **Optional**: `jq` for JSON processing

## 🔐 Security Considerations

### Data Privacy
- **Sensitive Information**: Diagnostics may contain configuration secrets
- **Access Control**: Limit access to diagnostic files
- **Retention Policy**: Define data retention and deletion policies
- **Encryption**: Consider encrypting diagnostic files at rest

### Execution Security  
- **Privilege Management**: Collection requires root, analysis does not
- **User Switching**: Uses secure `sudo -u` for privilege dropping
- **Input Validation**: All user inputs are validated
- **Error Handling**: No sensitive information in error messages

## 📜 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 📞 Support and Community

### Getting Help
- **Documentation**: Check docs/ directory for detailed guides
- **Issues**: Report bugs via GitHub issues
- **Discussions**: Join community discussions

### Commercial Support
For enterprise support and consulting:
- **Cloudera Support**: For Cloudera-specific issues
- **Professional Services**: Custom development and integration

## 🗺 Roadmap

### Version 2.0 (Planned)
- [ ] Real-time monitoring integration
- [ ] Advanced machine learning analysis
- [ ] Custom rule engine
- [ ] REST API interface
- [ ] Multi-cluster support

### Version 1.1 (In Progress)
- [ ] Windows support for analysis script
- [ ] Database output format
- [ ] Custom report templates
- [ ] Email notification support

## 📚 Additional Resources

### Documentation
- [NiFi Administration Guide](https://nifi.apache.org/docs/nifi-docs/html/administration-guide.html)
- [Cloudera Flow Management Documentation](https://docs.cloudera.com/cfm/)
- [NiFi System Administrator's Guide](https://nifi.apache.org/docs/nifi-docs/html/administration-guide.html)

### Training and Certification
- [Apache NiFi Certification](https://www.cloudera.com/services-and-support/training/certification.html)
- [NiFi Best Practices](https://community.cloudera.com/t5/Community-Articles/NiFi-Best-Practices/ta-p/244282)

### Community Resources
- [Apache NiFi Slack](https://apachenifi.slack.com/)
- [NiFi Mailing Lists](https://nifi.apache.org/mailing_lists.html)
- [Cloudera Community](https://community.cloudera.com/)

---

**Version**: Collection v13, Analysis v1.0  
**Last Updated**: August 2025  
**Compatibility**: Cloudera Manager 6.x+, NiFi 1.11.0+

For the latest updates and releases, visit: [GitHub Repository](https://github.com/your-org/nifi-diagnostics-toolkit)

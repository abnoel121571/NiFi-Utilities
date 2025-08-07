# Apache NiFi JSON Parser

A comprehensive Python tool for analyzing and extracting processor configurations from Apache NiFi flow definition JSON files. This parser helps you understand your NiFi flows by extracting processor details, configurations, and relationships in multiple exportable formats.

## 🚀 Features

- **Multi-format JSON Support**: Handles various NiFi JSON export structures (`flowContents`, `processGroupFlow`, `versionedFlowSnapshot`, etc.)
- **Recursive Processing**: Automatically discovers processors in nested process groups
- **Smart Data Cleaning**: Removes control characters, handles newlines, and sanitizes data for CSV export
- **Security-Aware**: Automatically masks sensitive properties (passwords, secrets, keys, credentials)
- **Multiple Export Formats**: Generates three different CSV views for comprehensive analysis
- **Focus on Key Processors**: Highlights important processor types like MergeContent, FetchS3Object, InvokeHTTP, etc.
- **Status Analysis**: Shows processor states (RUNNING, STOPPED, DISABLED) with visual indicators

## 📋 Requirements

- Python 3.6+
- Standard library only (no external dependencies)

## 🔧 Installation

1. Download the `NiFi-flow.json-parser.py` script
2. Make it executable (Unix/Linux/Mac):
   ```bash
   chmod +x NiFi-flow.json-parser.py
   ```

## 💻 Usage

### Basic Usage
```bash
python NiFi-flow.json-parser.py <path_to_nifi_json_file>
```

### Example
```bash
python NiFi-flow.json-parser.py my_nifi_flow.json
```

## 📊 Output Files

The script generates three CSV files optimized for different analysis needs:

### 1. `nifi_processor_summary.csv`
**Main summary file** - One row per processor with key configurations in separate columns
- Processor details (name, ID, type, status, location)
- Up to 5 key configurations as individual columns
- Total property count
- All properties as JSON for detailed analysis

### 2. `nifi_key_processors.csv`
**Focused analysis** - Only includes important processor types:
- MergeContent, FetchS3Object, PutS3Object
- GetFile, PutFile, InvokeHTTP
- ExecuteScript, SplitText, RouteOnAttribute
- UpdateAttribute, ConvertRecord, Kafka processors
- Wait/Notify processors

### 3. `nifi_properties_matrix.csv`
**Property matrix view** - Each property becomes a column
- Perfect for comparing processors of the same type
- Shows all unique properties across all processors
- Ideal for identifying configuration differences

## 🎯 Supported Processor Types

The parser provides enhanced analysis for common NiFi processors:

| Processor Category | Processors |
|-------------------|------------|
| **File Operations** | GetFile, PutFile |
| **AWS S3** | FetchS3Object, PutS3Object |
| **HTTP** | InvokeHTTP |
| **Data Processing** | MergeContent, SplitText, SplitJson, SplitXml |
| **Routing** | RouteOnAttribute, RouteOnContent |
| **Text Processing** | UpdateAttribute, ReplaceText, ExtractText |
| **Record Processing** | ConvertRecord, QueryRecord, PartitionRecord |
| **Messaging** | PublishKafka, ConsumeKafka |
| **Flow Control** | Wait, Notify |
| **Scripting** | ExecuteScript, ExecuteStreamCommand |
| **Testing** | GenerateFlowFile |

## 🔍 Key Features in Detail

### Smart Property Detection
The parser automatically identifies and highlights key properties based on processor type:
- **MergeContent**: Merge Format, Strategy, Entry counts
- **S3 Processors**: Bucket, Object Key, Region, Credentials
- **HTTP Processors**: URL, Method, Timeouts, Authentication
- **File Processors**: Directories, Filters, Conflict Resolution
- **And many more...**

### Security Features
- Automatically detects and masks sensitive properties
- Properties containing "password", "secret", "key", "credential", or "token" are shown as `***SENSITIVE***`
- Protects against accidental credential exposure

### Data Cleaning
- Removes control characters and null bytes
- Normalizes whitespace and newlines
- Truncates very long values with `...[TRUNCATED]` indicator
- Escapes CSV-incompatible characters

### Status Tracking
Visual status indicators for processors:
- 🟢 RUNNING
- 🔴 STOPPED  
- ⚫ DISABLED
- 🔍 UNKNOWN

## 📈 Example Console Output

```
✅ SUCCESS: Found 45 processors!

============================================================
PROCESSOR TYPES FOUND:
============================================================

🚦 PROCESSOR STATUS SUMMARY:
  🟢 Running: 32
  🔴 Stopped: 8
  ⚫ Disabled: 5

  • MergeContent: 3 instances
  • FetchS3Object: 2 instances
  • InvokeHTTP: 5 instances
  • UpdateAttribute: 12 instances
  • RouteOnAttribute: 4 instances

============================================================
EXPORTING CSV FILES:
============================================================

🎉 Analysis complete!
📊 Total processors: 45
🎯 Key processors found: 28

📁 Generated CSV files:
  • nifi_processor_summary.csv - Main summary with key configs
  • nifi_key_processors.csv - Only important processor types  
  • nifi_properties_matrix.csv - All properties as columns

💡 Open these CSV files in Excel/Google Sheets for easy analysis!
```

## 🔧 Advanced Usage

### Using as a Python Module

```python
from NiFi_flow_json_parser import NiFiFlowParser

# Initialize parser
parser = NiFiFlowParser('my_flow.json')

# Load and parse
if parser.load_json():
    processors = parser.parse_flow()
    
    # Get specific processor types
    merge_processors = parser.get_processors_by_type('MergeContent')
    
    # Get all processor types
    all_types = parser.get_processor_types()
    
    # Create focused inventory
    inventory = parser.create_processor_inventory()
```

### Analyzing JSON Structure
The parser includes debugging capabilities to analyze unknown JSON structures:

```python
parser.analyze_json_structure()  # Prints detailed JSON structure
```

## 🐛 Troubleshooting

### No Processors Found
If the script reports "No processors found":

1. **Check JSON Structure**: The JSON might have a different structure than expected
2. **Verify File Format**: Ensure it's a valid NiFi flow export (not a template or other format)
3. **Check File Encoding**: The file should be UTF-8 encoded
4. **Review Console Output**: Look for structure analysis hints in the output

### Common JSON Export Types
The parser handles these NiFi export formats:
- Flow snapshots (`versionedFlowSnapshot.flowContents`)
- Process group flows (`processGroupFlow.flow`)
- Direct flow contents (`flowContents`)
- Simple processor arrays (`processors`)

### Large Files
For very large NiFi flows:
- The script automatically truncates long property values
- Memory usage scales with the number of processors
- Consider filtering to specific process groups if needed

## 🤝 Contributing

Contributions are welcome! Areas for improvement:
- Additional processor type recognition
- Support for more JSON structure variants
- Enhanced property analysis for specific processors
- Additional export formats

## 📝 License

This script is provided as-is for analyzing NiFi configurations. Use responsibly and ensure you have permission to analyze the NiFi flows you're processing.

## ⚠️ Important Notes

- **Sensitive Data**: The script masks sensitive properties, but review outputs before sharing
- **File Size**: Very large NiFi flows may require significant processing time
- **Backup**: Always keep backups of your original JSON files
- **Permissions**: Ensure you have appropriate permissions to analyze the NiFi configurations

## 🔗 Related Tools

This parser complements other NiFi management tools:
- NiFi Registry for version control
- NiFi Toolkit for command-line operations  
- Custom monitoring solutions for production environments

---

**Happy NiFi Flow Analysis!** 🚀

#!/usr/bin/env python3
"""
Apache NiFi JSON Parser
Extracts processor information and configurations from NiFi flow definition JSON files.
"""

import json
import sys
import re
from typing import Dict, List, Any
from pathlib import Path


class NiFiFlowParser:
    """Parser for Apache NiFi flow definition JSON files."""
    
    def __init__(self, json_file_path: str):
        """Initialize the parser with a JSON file path."""
        self.json_file_path = Path(json_file_path)
        self.flow_data = None
        self.processors = []
    
    @staticmethod
    def clean_data(value: Any) -> str:
        """Clean data by removing control characters, newlines, and extra whitespace."""
        if value is None:
            return ''
        
        # Convert to string
        str_value = str(value)
        
        # Remove control characters (ASCII 0-31 except tab, and ASCII 127)
        # Keep tab (9), but replace with space for CSV compatibility
        str_value = re.sub(r'[\x00-\x08\x0B-\x1F\x7F]', '', str_value)
        
        # Replace newlines and carriage returns with spaces
        str_value = re.sub(r'[\r\n]+', ' ', str_value)
        
        # Replace multiple whitespace with single space
        str_value = re.sub(r'\s+', ' ', str_value)
        
        # Strip leading/trailing whitespace
        str_value = str_value.strip()
        
        # Remove null bytes that sometimes appear in JSON
        str_value = str_value.replace('\x00', '')
        
        return str_value
    
    @staticmethod
    def clean_property_value(value: Any, max_length: int = 1000) -> str:
        """Clean and truncate property values for CSV export."""
        cleaned = NiFiFlowParser.clean_data(value)
        
        # Truncate very long values
        if len(cleaned) > max_length:
            cleaned = cleaned[:max_length] + "...[TRUNCATED]"
        
        # Escape double quotes for CSV safety
        if '"' in cleaned:
            cleaned = cleaned.replace('"', '""')
        
        return cleaned
    
    @staticmethod
    def clean_sensitive_property(prop_name: str, prop_value: Any) -> str:
        """Handle sensitive properties with cleaning."""
        if any(sensitive in prop_name.lower() for sensitive in ['password', 'secret', 'key', 'credential', 'token']):
            return "***SENSITIVE***" if prop_value else "Not Set"
        else:
            return NiFiFlowParser.clean_property_value(prop_value)
        
    def load_json(self) -> bool:
        """Load and parse the JSON file."""
        try:
            with open(self.json_file_path, 'r', encoding='utf-8') as file:
                self.flow_data = json.load(file)
            print(f"Successfully loaded JSON file: {self.json_file_path}")
            return True
        except FileNotFoundError:
            print(f"Error: File not found - {self.json_file_path}")
            return False
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON format - {e}")
            return False
        except Exception as e:
            print(f"Error loading file: {e}")
            return False
    
    def extract_processors_from_group(self, process_group: Dict[str, Any], group_name: str = "Root") -> List[Dict]:
        """Recursively extract processors from process groups."""
        processors = []
        
        # Extract processors from current group
        if 'processors' in process_group:
            for processor in process_group['processors']:
                processor_info = self.parse_processor(processor, group_name)
                processors.append(processor_info)
        
        # Recursively extract from child process groups
        if 'processGroups' in process_group:
            for child_group in process_group['processGroups']:
                child_group_name = child_group.get('name', 'Unnamed Group')
                full_group_name = f"{group_name}/{child_group_name}" if group_name != "Root" else child_group_name
                child_processors = self.extract_processors_from_group(child_group, full_group_name)
                processors.extend(child_processors)
        
        return processors
    
    def parse_processor(self, processor: Dict[str, Any], group_name: str) -> Dict[str, Any]:
        """Parse individual processor and extract configuration."""
        # Determine processor state/status
        processor_state = self.get_processor_state(processor)
        
        processor_info = {
            'id': self.clean_data(processor.get('identifier', processor.get('id', 'Unknown'))),
            'name': self.clean_data(processor.get('name', 'Unnamed Processor')),
            'type': self.clean_data(processor.get('type', processor.get('class', 'Unknown Type'))),
            'group': self.clean_data(group_name),
            'state': processor_state,  # Already cleaned in get_processor_state
            'scheduling_strategy': self.clean_data(processor.get('schedulingStrategy', 'Unknown')),
            'concurrent_tasks': processor.get('concurrentlySchedulableTaskCount', processor.get('maxConcurrentTasks', 1)),
            'scheduling_period': self.clean_data(processor.get('schedulingPeriod', processor.get('runSchedule', 'Unknown'))),
            'penalty_duration': self.clean_data(processor.get('penaltyDuration', 'Unknown')),
            'yield_duration': self.clean_data(processor.get('yieldDuration', 'Unknown')),
            'bulletin_level': self.clean_data(processor.get('bulletinLevel', 'Unknown')),
            'auto_terminated_relationships': [self.clean_data(rel) for rel in processor.get('autoTerminatedRelationships', [])],
            'properties': {},
            'relationships': []
        }
        
        # Extract properties - handle different property structures
        if 'properties' in processor and processor['properties']:
            # Clean all property keys and values
            for key, value in processor['properties'].items():
                clean_key = self.clean_data(key)
                clean_value = self.clean_property_value(value)
                processor_info['properties'][clean_key] = clean_value
        elif 'config' in processor and 'properties' in processor['config']:
            # Clean all property keys and values
            for key, value in processor['config']['properties'].items():
                clean_key = self.clean_data(key)
                clean_value = self.clean_property_value(value)
                processor_info['properties'][clean_key] = clean_value
        
        # Extract relationships
        if 'relationships' in processor:
            processor_info['relationships'] = [
                {
                    'name': self.clean_data(rel.get('name', 'Unknown')),
                    'description': self.clean_data(rel.get('description', 'No description')),
                    'autoTerminate': rel.get('autoTerminate', False)
                }
                for rel in processor['relationships']
            ]
        
        # Handle component-level information if present
        if 'component' in processor:
            component = processor['component']
            processor_info.update({
                'id': self.clean_data(component.get('id', processor_info['id'])),
                'name': self.clean_data(component.get('name', processor_info['name'])),
                'type': self.clean_data(component.get('type', processor_info['type'])),
            })
            if 'config' in component:
                config = component['config']
                processor_info.update({
                    'concurrent_tasks': config.get('concurrentlySchedulableTaskCount', processor_info['concurrent_tasks']),
                    'scheduling_period': self.clean_data(config.get('schedulingPeriod', processor_info['scheduling_period'])),
                    'penalty_duration': self.clean_data(config.get('penaltyDuration', processor_info['penalty_duration'])),
                    'yield_duration': self.clean_data(config.get('yieldDuration', processor_info['yield_duration'])),
                    'bulletin_level': self.clean_data(config.get('bulletinLevel', processor_info['bulletin_level'])),
                    'auto_terminated_relationships': [self.clean_data(rel) for rel in config.get('autoTerminatedRelationships', processor_info['auto_terminated_relationships'])],
                })
                if 'properties' in config:
                    # Clean properties from component config
                    cleaned_properties = {}
                    for key, value in config['properties'].items():
                        clean_key = self.clean_data(key)
                        clean_value = self.clean_property_value(value)
                        cleaned_properties[clean_key] = clean_value
                    processor_info['properties'] = cleaned_properties
        
        return processor_info
    
    def get_processor_state(self, processor: Dict[str, Any]) -> str:
        """Determine the processor state (RUNNING, STOPPED, DISABLED)."""
        # Check different possible locations for state information
        state = "UNKNOWN"
        
        # Method 1: Direct state field
        if 'state' in processor:
            state = processor['state']
        
        # Method 2: Inside component wrapper
        elif 'component' in processor:
            component = processor['component']
            if 'state' in component:
                state = component['state']
            elif 'config' in component and 'schedulingStrategy' in component['config']:
                # Sometimes disabled processors have different scheduling info
                if component['config'].get('schedulingStrategy') == 'DISABLED':
                    state = "DISABLED"
        
        # Method 3: Check status field
        elif 'status' in processor:
            status = processor['status']
            if isinstance(status, dict):
                state = status.get('runStatus', status.get('aggregateSnapshot', {}).get('runStatus', 'UNKNOWN'))
            else:
                state = str(status)
        
        # Method 4: Check runStatus in various nested locations
        elif 'runStatus' in processor:
            state = processor['runStatus']
        
        # Method 5: Look for status in nested structures
        else:
            # Check common nested paths
            nested_paths = [
                ['status', 'runStatus'],
                ['status', 'aggregateSnapshot', 'runStatus'],
                ['component', 'status', 'runStatus'],
                ['component', 'runStatus'],
                ['config', 'schedulingStrategy']
            ]
            
            for path in nested_paths:
                current = processor
                try:
                    for key in path:
                        current = current[key]
                    if current:
                        state = current
                        break
                except (KeyError, TypeError):
                    continue
        
        # Normalize the state value
        if isinstance(state, str):
            state = self.clean_data(state).upper()
            
            # Map various state representations to standard values
            state_mapping = {
                'RUNNING': 'RUNNING',
                'RUN': 'RUNNING',
                'STARTED': 'RUNNING',
                'START': 'RUNNING',
                'STOPPED': 'STOPPED',
                'STOP': 'STOPPED',
                'DISABLED': 'DISABLED',
                'INVALID': 'DISABLED',
                'VALIDATING': 'STOPPED',
                'VALID': 'STOPPED'  # Valid but not necessarily running
            }
            
            return state_mapping.get(state, state)
        
        return "UNKNOWN"
    
    def analyze_json_structure(self):
        """Analyze and print the JSON structure to help with debugging."""
        print(f"\n{'='*60}")
        print("JSON STRUCTURE ANALYSIS")
        print(f"{'='*60}")
        
        def print_structure(data, level=0, max_level=3):
            indent = "  " * level
            if level > max_level:
                return
            
            if isinstance(data, dict):
                for key, value in data.items():
                    if isinstance(value, dict):
                        print(f"{indent}{key}: {{dict with {len(value)} keys}}")
                        if level < max_level:
                            print_structure(value, level + 1, max_level)
                    elif isinstance(value, list):
                        print(f"{indent}{key}: [list with {len(value)} items]")
                        if value and level < max_level:
                            print(f"{indent}  First item type: {type(value[0]).__name__}")
                            if isinstance(value[0], dict):
                                print(f"{indent}  First item keys: {list(value[0].keys())}")
                    else:
                        value_str = str(value)[:50] + "..." if len(str(value)) > 50 else str(value)
                        print(f"{indent}{key}: {value_str}")
            elif isinstance(data, list):
                print(f"{indent}List with {len(data)} items")
                if data:
                    print(f"{indent}First item type: {type(data[0]).__name__}")
        
        print_structure(self.flow_data)
        print(f"{'='*60}\n")
    
    def find_processors_recursively(self, data, path="root"):
        """Recursively search for processors in any part of the JSON structure."""
        processors = []
        
        if isinstance(data, dict):
            # Check if this dict contains processors
            if 'processors' in data and isinstance(data['processors'], list):
                print(f"Found {len(data['processors'])} processors at: {path}")
                for processor in data['processors']:
                    processor_info = self.parse_processor(processor, path)
                    processors.append(processor_info)
            
            # Recursively search in all dict values
            for key, value in data.items():
                if key != 'processors':  # Avoid processing the same processors twice
                    child_processors = self.find_processors_recursively(value, f"{path}.{key}")
                    processors.extend(child_processors)
        
        elif isinstance(data, list):
            # Search in list items
            for i, item in enumerate(data):
                child_processors = self.find_processors_recursively(item, f"{path}[{i}]")
                processors.extend(child_processors)
        
        return processors
    
    def parse_flow(self) -> List[Dict]:
        """Parse the entire flow and extract all processors."""
        if not self.flow_data:
            print("No flow data loaded. Please load JSON first.")
            return []
        
        # First, analyze the structure
        self.analyze_json_structure()
        
        processors = []
        
        # Handle known JSON structures first
        if 'flowContents' in self.flow_data:
            print("Detected: NiFi Template export format")
            flow_contents = self.flow_data['flowContents']
            processors = self.extract_processors_from_group(flow_contents, "Root")
        elif 'processGroupFlow' in self.flow_data:
            print("Detected: Process Group export format")
            flow_contents = self.flow_data['processGroupFlow']['flow']
            processors = self.extract_processors_from_group(flow_contents, "Root")
        elif 'versionedFlowSnapshot' in self.flow_data:
            print("Detected: Registry versioned flow format")
            flow_contents = self.flow_data['versionedFlowSnapshot']['flowContents']
            processors = self.extract_processors_from_group(flow_contents, "Root")
        elif 'flow' in self.flow_data:
            print("Detected: Flow export format")
            flow_contents = self.flow_data['flow']
            processors = self.extract_processors_from_group(flow_contents, "Root")
        elif 'processors' in self.flow_data:
            print("Detected: Direct processor list format")
            for processor in self.flow_data['processors']:
                processor_info = self.parse_processor(processor, "Root")
                processors.append(processor_info)
        else:
            print("Unknown format - attempting recursive search...")
            processors = self.find_processors_recursively(self.flow_data)
        
        if not processors:
            print("No processors found with standard parsing. Trying recursive search...")
            processors = self.find_processors_recursively(self.flow_data)
        
        print(f"Total processors found: {len(processors)}")
        self.processors = processors
        return processors
    
    def print_processor_summary(self):
        """Print a summary of all processors with focus on key configurations."""
        if not self.processors:
            print("No processors found.")
            return
        
        print(f"\n{'='*100}")
        print(f"NIFI PROCESSOR CONFIGURATION SUMMARY - Total Processors: {len(self.processors)}")
        print(f"{'='*100}")
        
        # Group processors by type for better organization
        processors_by_type = {}
        for proc in self.processors:
            proc_type = proc['type'].split('.')[-1]  # Get just the class name
            if proc_type not in processors_by_type:
                processors_by_type[proc_type] = []
            processors_by_type[proc_type].append(proc)
        
        # Display processors grouped by type
        for proc_type in sorted(processors_by_type.keys()):
            procs = processors_by_type[proc_type]
            print(f"\n{'▼' * 80}")
            print(f"PROCESSOR TYPE: {proc_type} ({len(procs)} instances)")
            print(f"{'▼' * 80}")
            
            for i, proc in enumerate(procs, 1):
                print(f"\n[{i}] NAME: {proc['name']}")
                print(f"    PROCESSOR ID: {proc['id']}")
                print(f"    FULL TYPE: {proc['type']}")
                print(f"    GROUP LOCATION: {proc['group']}")
                print(f"    CONCURRENT TASKS: {proc['concurrent_tasks']}")
                print(f"    SCHEDULING: {proc['scheduling_period']}")
                
                if proc['auto_terminated_relationships']:
                    print(f"    AUTO-TERMINATED: {', '.join(proc['auto_terminated_relationships'])}")
                
                # Show key properties based on processor type
                if proc['properties']:
                    key_props = self.get_key_properties_for_processor(proc_type, proc['properties'])
                    if key_props:
                        print(f"    KEY CONFIGURATIONS:")
                        for key, value in key_props.items():
                            # Handle sensitive properties
                            if any(sensitive in key.lower() for sensitive in ['password', 'secret', 'key', 'credential']):
                                display_value = "***SENSITIVE***" if value else "Not Set"
                            else:
                                display_value = str(value)[:100] + "..." if len(str(value)) > 100 else str(value)
                            print(f"      • {key}: {display_value}")
                    
                    # Show all properties count
                    print(f"    TOTAL PROPERTIES: {len(proc['properties'])}")
                    
                    # Optionally show all properties (truncated)
                    if len(proc['properties']) <= 10:  # Only show all if not too many
                        print(f"    ALL PROPERTIES:")
                        for key, value in proc['properties'].items():
                            if key not in (key_props.keys() if key_props else []):
                                if any(sensitive in key.lower() for sensitive in ['password', 'secret', 'key', 'credential']):
                                    display_value = "***SENSITIVE***" if value else "Not Set"
                                else:
                                    display_value = str(value)[:80] + "..." if len(str(value)) > 80 else str(value)
                                print(f"      • {key}: {display_value}")
    
    def get_key_properties_for_processor(self, proc_type: str, properties: dict) -> dict:
        """Extract key properties based on processor type."""
        key_props = {}
        proc_type_lower = proc_type.lower()
        
        # Define key properties for common processors
        key_property_mappings = {
            'mergecontent': ['Merge Format', 'Merge Strategy', 'Minimum Number of Entries', 'Maximum Number of Entries', 'Minimum Group Size', 'Maximum Group Size', 'Delimiter Strategy'],
            'fetchs3object': ['Bucket', 'Object Key', 'Region', 'Access Key ID', 'Secret Access Key', 'Credentials File', 'AWS Credentials Provider service'],
            'puts3object': ['Bucket', 'Object Key', 'Region', 'Access Key ID', 'Secret Access Key', 'Content Type', 'Storage Class'],
            'getfile': ['Input Directory', 'File Filter', 'Recurse Subdirectories', 'Keep Source File', 'Minimum File Age', 'Maximum File Age'],
            'putfile': ['Directory', 'Conflict Resolution Strategy', 'Create Missing Directories'],
            'invokehttp': ['HTTP Method', 'Remote URL', 'SSL Context Service', 'Username', 'Password', 'Connect Timeout', 'Read Timeout'],
            'executescript': ['Script Engine', 'Script File', 'Script Body'],
            'executestream': ['Command Path', 'Command Arguments', 'Working Directory'],
            'splittext': ['Line Split Count', 'Maximum Fragment Size', 'Header Line Count', 'Remove Trailing Newlines'],
            'splitjson': ['JsonPath Expression'],
            'splitxml': ['Split Depth'],
            'routeonattribute': ['Routing Strategy'],
            'routeoncontent': ['Match Requirement'],
            'updateattribute': [],  # All properties are relevant for UpdateAttribute
            'extracttext': ['Character Set', 'Maximum Buffer Size'],
            'replacetext': ['Search Value', 'Replacement Value', 'Character Set', 'Maximum Buffer Size', 'Replacement Strategy'],
            'convertrecord': ['Record Reader', 'Record Writer'],
            'queryrecord': ['Record Reader', 'Record Writer', 'Include Zero Record FlowFiles'],
            'partitionrecord': ['Record Reader', 'Record Writer', 'Partition Values'],
            'publishkafka': ['Kafka Brokers', 'Topic Name', 'Delivery Guarantee', 'Key Attribute Encoding', 'Message Key Field'],
            'consumekafka': ['Kafka Brokers', 'Topic Name(s)', 'Topic Name Format', 'Group ID', 'Offset Reset'],
            'wait': ['Release Signal Identifier', 'Target Signal Count', 'Signal Counter Name'],
            'notify': ['Release Signal Identifier', 'Signal Counter Name', 'Signal Counter Delta'],
            'generateflowfile': ['File Size', 'Batch Size', 'Data Format', 'Custom Text'],
        }
        
        # Find matching processor type (partial match)
        relevant_properties = []
        for key, props in key_property_mappings.items():
            if key in proc_type_lower:
                relevant_properties = props
                break
        
        # Extract the relevant properties
        for prop_key, prop_value in properties.items():
            clean_prop_key = self.clean_data(prop_key)
            
            # Always include if it's in our key list
            if clean_prop_key in relevant_properties or prop_key in relevant_properties:
                key_props[clean_prop_key] = self.clean_sensitive_property(prop_key, prop_value)
            # Also include properties that look important (non-empty values)
            elif prop_value and str(prop_value).strip():
                # For UpdateAttribute, include all non-empty properties
                if 'updateattribute' in proc_type_lower:
                    key_props[clean_prop_key] = self.clean_sensitive_property(prop_key, prop_value)
                # For others, include if it looks like a key configuration
                elif any(keyword in clean_prop_key.lower() for keyword in ['url', 'path', 'directory', 'file', 'host', 'port', 'topic', 'queue', 'table', 'query', 'expression', 'format', 'strategy']):
                    key_props[clean_prop_key] = self.clean_sensitive_property(prop_key, prop_value)
        
        return key_props
    
    def export_processor_summary_csv(self, output_file: str = "nifi_processor_summary.csv"):
        """Export processor summary in a clean table format for spreadsheet viewing."""
        import csv
        
        if not self.processors:
            print("No processors to export.")
            return
        
        try:
            with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
                fieldnames = [
                    'Processor_Name', 'Processor_ID', 'Processor_Type', 'Status', 'Full_Class_Name',
                    'Group_Location', 'Concurrent_Tasks', 'Scheduling_Period', 'Scheduling_Strategy',
                    'Auto_Terminated_Relationships', 'Key_Config_1_Name', 'Key_Config_1_Value',
                    'Key_Config_2_Name', 'Key_Config_2_Value', 'Key_Config_3_Name', 'Key_Config_3_Value',
                    'Key_Config_4_Name', 'Key_Config_4_Value', 'Key_Config_5_Name', 'Key_Config_5_Value',
                    'Total_Properties_Count', 'All_Properties_JSON'
                ]
                
                writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
                writer.writeheader()
                
                for proc in self.processors:
                    proc_type = proc['type'].split('.')[-1]  # Just the class name
                    
                    # Get key properties for this processor type
                    key_props = self.get_key_properties_for_processor(proc_type, proc['properties'])
                    key_props_list = list(key_props.items())
                    
                    row = {
                        'Processor_Name': proc['name'],
                        'Processor_ID': proc['id'],
                        'Processor_Type': proc_type,
                        'Status': proc['state'],
                        'Full_Class_Name': proc['type'],
                        'Group_Location': proc['group'],
                        'Concurrent_Tasks': proc['concurrent_tasks'],
                        'Scheduling_Period': proc['scheduling_period'],
                        'Scheduling_Strategy': proc['scheduling_strategy'],
                        'Auto_Terminated_Relationships': '; '.join(proc['auto_terminated_relationships']),
                        'Total_Properties_Count': len(proc['properties']),
                        'All_Properties_JSON': json.dumps(proc['properties']) if proc['properties'] else '{}'
                    }
                    
                    # Add up to 5 key configurations as separate columns
                    for i in range(5):
                        config_name_key = f'Key_Config_{i+1}_Name'
                        config_value_key = f'Key_Config_{i+1}_Value'
                        
                        if i < len(key_props_list):
                            prop_name, prop_value = key_props_list[i]
                            row[config_name_key] = self.clean_data(prop_name)
                            # prop_value is already cleaned and sensitive data handled
                            row[config_value_key] = prop_value
                        else:
                            row[config_name_key] = ''
                            row[config_value_key] = ''
                    
                    writer.writerow(row)
            
            print(f"✅ Processor summary exported to: {output_file}")
            print(f"📊 This CSV contains one row per processor with key configurations in columns")
            
        except Exception as e:
            print(f"❌ Error exporting summary CSV: {e}")

    def export_focused_processors_csv(self, output_file: str = "nifi_key_processors.csv"):
        """Export only the key processor types (MergeContent, FetchS3Object, etc.) in a focused table."""
        import csv
        
        if not self.processors:
            print("No processors to export.")
            return
        
        # Focus on key processor types
        focus_processors = [
            'MergeContent', 'FetchS3Object', 'PutS3Object', 'GetFile', 'PutFile',
            'InvokeHTTP', 'ExecuteScript', 'ExecuteStreamCommand', 'SplitText', 
            'SplitJson', 'SplitXml', 'RouteOnAttribute', 'RouteOnContent', 'UpdateAttribute', 
            'ReplaceText', 'ExtractText', 'ConvertRecord', 'QueryRecord', 
            'PublishKafka', 'ConsumeKafka', 'Wait', 'Notify', 'GenerateFlowFile'
        ]
        
        # Filter processors to only include focus types
        filtered_processors = []
        for proc in self.processors:
            proc_type = proc['type'].split('.')[-1]
            for focus_type in focus_processors:
                if focus_type.lower() in proc_type.lower():
                    filtered_processors.append(proc)
                    break
        
        if not filtered_processors:
            print("❌ No key processors found to export.")
            return
        
        try:
            with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
                fieldnames = [
                    'Processor_Type', 'Status', 'Name', 'ID', 'Group_Location', 
                    'Concurrent_Tasks', 'Scheduling_Period', 'Scheduling_Strategy', 'Config_1', 'Value_1',
                    'Config_2', 'Value_2', 'Config_3', 'Value_3', 'Config_4', 'Value_4',
                    'Config_5', 'Value_5', 'Config_6', 'Value_6', 'Total_Props'
                ]
                
                writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
                writer.writeheader()
                
                for proc in filtered_processors:
                    proc_type = proc['type'].split('.')[-1]
                    key_props = self.get_key_properties_for_processor(proc_type, proc['properties'])
                    key_props_list = list(key_props.items())
                    
                    row = {
                        'Processor_Type': proc_type,
                        'Status': proc['state'],
                        'Name': proc['name'],
                        'ID': proc['id'],
                        'Group_Location': proc['group'],
                        'Concurrent_Tasks': proc['concurrent_tasks'],
                        'Scheduling_Period': proc['scheduling_period'],
                        'Scheduling_Strategy': proc['scheduling_strategy'],
                        'Total_Props': len(proc['properties'])
                    }
                    
                    # Add up to 6 key configurations
                    for i in range(6):
                        config_key = f'Config_{i+1}'
                        value_key = f'Value_{i+1}'
                        
                        if i < len(key_props_list):
                            prop_name, prop_value = key_props_list[i]
                            row[config_key] = self.clean_data(prop_name)
                            # prop_value is already cleaned and truncated appropriately
                            row[value_key] = prop_value
                        else:
                            row[config_key] = ''
                            row[value_key] = ''
                    
                    writer.writerow(row)
            
            print(f"✅ Key processors exported to: {output_file}")
            print(f"📊 Found {len(filtered_processors)} key processors out of {len(self.processors)} total")
            
        except Exception as e:
            print(f"❌ Error exporting focused CSV: {e}")

    def export_properties_matrix_csv(self, output_file: str = "nifi_properties_matrix.csv"):
        """Export a matrix view where each property is a column - great for comparing similar processors."""
        import csv
        
        if not self.processors:
            print("No processors to export.")
            return
        
        # Collect all unique property names across all processors
        all_properties = set()
        for proc in self.processors:
            all_properties.update(proc['properties'].keys())
        
        all_properties = sorted(all_properties)
        
        try:
            with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
                # Create fieldnames with processor info + all properties as columns
                fieldnames = [
                    'Processor_Name', 'Processor_ID', 'Processor_Type', 'Status', 
                    'Group_Location', 'Concurrent_Tasks', 'Scheduling_Period', 'Scheduling_Strategy'
                ] + all_properties
                
                writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
                writer.writeheader()
                
                for proc in self.processors:
                    proc_type = proc['type'].split('.')[-1]
                    
                    row = {
                        'Processor_Name': proc['name'],
                        'Processor_ID': proc['id'],
                        'Processor_Type': proc_type,
                        'Status': proc['state'],
                        'Group_Location': proc['group'],
                        'Concurrent_Tasks': proc['concurrent_tasks'],
                        'Scheduling_Period': proc['scheduling_period'],
                        'Scheduling_Strategy': proc['scheduling_strategy']
                    }
                    
                    # Add each property as a column
                    for prop_name in all_properties:
                        prop_value = proc['properties'].get(prop_name, '')
                        
                        # Properties are already cleaned, just handle display length
                        clean_value = prop_value if len(str(prop_value)) <= 100 else str(prop_value)[:100] + "...[TRUNCATED]"
                        row[prop_name] = clean_value
                    
                    writer.writerow(row)
            
            print(f"✅ Properties matrix exported to: {output_file}")
            print(f"📊 Matrix has {len(all_properties)} property columns across {len(self.processors)} processors")
            
        except Exception as e:
            print(f"❌ Error exporting properties matrix: {e}")
    
    def create_processor_inventory(self):
        """Create a focused inventory of specific processor types and their key configs."""
        if not self.processors:
            print("No processors found for inventory.")
            return
        
        # Focus on common/interesting processor types
        focus_processors = [
            'MergeContent', 'FetchS3Object', 'PutS3Object', 'GetFile', 'PutFile',
            'InvokeHTTP', 'ExecuteScript', 'ExecuteStreamCommand', 'SplitText', 
            'SplitJson', 'RouteOnAttribute', 'UpdateAttribute', 'ReplaceText',
            'ConvertRecord', 'QueryRecord', 'PublishKafka', 'ConsumeKafka',
            'Wait', 'Notify', 'GenerateFlowFile'
        ]
        
        print(f"\n{'#' * 100}")
        print(f"FOCUSED PROCESSOR INVENTORY - KEY PROCESSORS AND CONFIGURATIONS")
        print(f"{'#' * 100}")
        
        found_focus_processors = {}
        
        for proc in self.processors:
            proc_type = proc['type'].split('.')[-1]
            
            # Check if this is one of our focus processors
            for focus_type in focus_processors:
                if focus_type.lower() in proc_type.lower():
                    if focus_type not in found_focus_processors:
                        found_focus_processors[focus_type] = []
                    found_focus_processors[focus_type].append(proc)
                    break
        
        # Display focused inventory
        for focus_type in sorted(found_focus_processors.keys()):
            procs = found_focus_processors[focus_type]
            print(f"\n{'=' * 60}")
            print(f"🔧 {focus_type.upper()} PROCESSORS ({len(procs)} found)")
            print(f"{'=' * 60}")
            
            for proc in procs:
                print(f"\n  📋 NAME: {proc['name']}")
                print(f"  🆔 ID: {proc['id']}")
                print(f"  📍 LOCATION: {proc['group']}")
                print(f"  ⚙️  SCHEDULING: {proc['scheduling_period']} | Tasks: {proc['concurrent_tasks']}")
                
                # Get key configurations
                key_props = self.get_key_properties_for_processor(focus_type, proc['properties'])
                if key_props:
                    print(f"  🔑 KEY CONFIGURATIONS:")
                    for key, value in key_props.items():
                        if any(sensitive in key.lower() for sensitive in ['password', 'secret', 'key', 'credential']):
                            display_value = "***HIDDEN***" if value else "Not Set"
                        else:
                            display_value = str(value) if len(str(value)) <= 60 else str(value)[:60] + "..."
                        print(f"     • {key}: {display_value}")
                
                print(f"  📊 TOTAL PROPERTIES: {len(proc['properties'])}")
        
        # Show summary
        print(f"\n{'#' * 100}")
        print(f"INVENTORY SUMMARY:")
        print(f"{'#' * 100}")
        for focus_type, procs in found_focus_processors.items():
            print(f"  • {focus_type}: {len(procs)} instances")
        
        total_focus = sum(len(procs) for procs in found_focus_processors.values())
        print(f"\nTotal Focus Processors: {total_focus} out of {len(self.processors)} total processors")
        
        return found_focus_processors
    
    def get_status_emoji(self, state: str) -> str:
        """Get emoji representation for processor state."""
        state_emojis = {
            'RUNNING': '🟢',
            'STOPPED': '🔴', 
            'DISABLED': '⚫',
            'UNKNOWN': '🔍'
        }
        return state_emojis.get(state.upper(), '❓')
    
    def get_processors_by_type(self, processor_type: str) -> List[Dict]:
        """Get all processors of a specific type."""
        return [proc for proc in self.processors if processor_type.lower() in proc['type'].lower()]
    
    def get_processor_types(self) -> List[str]:
        """Get list of unique processor types."""
        return list(set(proc['type'] for proc in self.processors))


def main():
    """Main function to demonstrate usage."""
    if len(sys.argv) != 2:
        print("Usage: python nifi_parser.py <path_to_nifi_json_file>")
        print("\nThis script will:")
        print("  • Parse your NiFi JSON export file")
        print("  • Focus on key processors like MergeContent, FetchS3Object, etc.")
        print("  • Export multiple CSV formats for spreadsheet analysis")
        print("  • Show processor IDs and key configurations")
        sys.exit(1)
    
    json_file_path = sys.argv[1]
    
    # Initialize parser
    parser = NiFiFlowParser(json_file_path)
    
    # Load and parse the JSON file
    if not parser.load_json():
        sys.exit(1)
    
    # Extract processors
    processors = parser.parse_flow()
    
    if not processors:
        print("\n❌ No processors found in the JSON file.")
        print("\n🔍 This could happen if:")
        print("  • The JSON structure is different than expected")
        print("  • The file is not a NiFi flow export")
        print("  • The processors are nested differently")
        print("\n📋 Check the JSON structure analysis above for clues.")
        sys.exit(1)
    
    print(f"\n✅ SUCCESS: Found {len(processors)} processors!")
    
    # Show processor types summary
    print(f"\n{'=' * 60}")
    print("PROCESSOR TYPES FOUND:")
    print(f"{'=' * 60}")
    processor_types = {}
    for proc in processors:
        proc_type = proc['type'].split('.')[-1]
        if proc_type in processor_types:
            processor_types[proc_type] += 1
        else:
            processor_types[proc_type] = 1
    
    # Show processor status summary
    running_count = sum(1 for p in processors if p['state'] == 'RUNNING')
    stopped_count = sum(1 for p in processors if p['state'] == 'STOPPED')
    disabled_count = sum(1 for p in processors if p['state'] == 'DISABLED')
    unknown_count = sum(1 for p in processors if p['state'] not in ['RUNNING', 'STOPPED', 'DISABLED'])
    
    print(f"\n🚦 PROCESSOR STATUS SUMMARY:")
    print(f"  🟢 Running: {running_count}")
    print(f"  🔴 Stopped: {stopped_count}")
    print(f"  ⚫ Disabled: {disabled_count}")
    if unknown_count > 0:
        print(f"  🔍 Unknown: {unknown_count}")
    
    for proc_type in sorted(processor_types.keys()):
        count = processor_types[proc_type]
        print(f"  • {proc_type}: {count} instance{'s' if count != 1 else ''}")
    
    # Export multiple CSV formats
    print(f"\n{'=' * 60}")
    print("EXPORTING CSV FILES:")
    print(f"{'=' * 60}")
    
    # 1. Summary CSV - One row per processor with key configs in columns
    parser.export_processor_summary_csv("nifi_processor_summary.csv")
    
    # 2. Focused CSV - Only key processors (MergeContent, FetchS3Object, etc.)
    parser.export_focused_processors_csv("nifi_key_processors.csv")
    
    # 3. Properties Matrix - All properties as columns (good for comparing similar processors)
    parser.export_properties_matrix_csv("nifi_properties_matrix.csv")
    
    # Brief console summary
    focus_processors = [
        'MergeContent', 'FetchS3Object', 'PutS3Object', 'GetFile', 'PutFile',
        'InvokeHTTP', 'ExecuteScript', 'SplitText', 'RouteOnAttribute', 'UpdateAttribute'
    ]
    
    found_focus = 0
    for proc in processors:
        proc_type = proc['type'].split('.')[-1]
        for focus_type in focus_processors:
            if focus_type.lower() in proc_type.lower():
                found_focus += 1
                break
    
    print(f"\n🎉 Analysis complete!")
    print(f"📊 Total processors: {len(processors)}")
    print(f"🎯 Key processors found: {found_focus}")
    print(f"\n📁 Generated CSV files:")
    print(f"  • nifi_processor_summary.csv - Main summary with key configs")
    print(f"  • nifi_key_processors.csv - Only important processor types")
    print(f"  • nifi_properties_matrix.csv - All properties as columns")
    print(f"\n💡 Open these CSV files in Excel/Google Sheets for easy analysis!")


if __name__ == "__main__":
    main()

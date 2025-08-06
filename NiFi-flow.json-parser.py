#!/usr/bin/env python3
"""
Apache NiFi JSON Parser
Extracts processor information and configurations from NiFi flow definition JSON files.
"""

import json
import sys
from typing import Dict, List, Any
from pathlib import Path


class NiFiFlowParser:
    """Parser for Apache NiFi flow definition JSON files."""
    
    def __init__(self, json_file_path: str):
        """Initialize the parser with a JSON file path."""
        self.json_file_path = Path(json_file_path)
        self.flow_data = None
        self.processors = []
        
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
        processor_info = {
            'id': processor.get('identifier', 'Unknown'),
            'name': processor.get('name', 'Unnamed Processor'),
            'type': processor.get('type', 'Unknown Type'),
            'group': group_name,
            'state': processor.get('schedulingStrategy', 'Unknown'),
            'concurrent_tasks': processor.get('concurrentlySchedulableTaskCount', 1),
            'scheduling_period': processor.get('schedulingPeriod', 'Unknown'),
            'penalty_duration': processor.get('penaltyDuration', 'Unknown'),
            'yield_duration': processor.get('yieldDuration', 'Unknown'),
            'bulletin_level': processor.get('bulletinLevel', 'Unknown'),
            'auto_terminated_relationships': processor.get('autoTerminatedRelationships', []),
            'properties': {},
            'relationships': []
        }
        
        # Extract properties
        if 'properties' in processor and processor['properties']:
            processor_info['properties'] = processor['properties']
        
        # Extract relationships
        if 'relationships' in processor:
            processor_info['relationships'] = [
                {
                    'name': rel.get('name', 'Unknown'),
                    'description': rel.get('description', 'No description'),
                    'autoTerminate': rel.get('autoTerminate', False)
                }
                for rel in processor['relationships']
            ]
        
        return processor_info
    
    def parse_flow(self) -> List[Dict]:
        """Parse the entire flow and extract all processors."""
        if not self.flow_data:
            print("No flow data loaded. Please load JSON first.")
            return []
        
        processors = []
        
        # Handle different JSON structures
        if 'flowContents' in self.flow_data:
            # Template export format
            flow_contents = self.flow_data['flowContents']
            processors = self.extract_processors_from_group(flow_contents, "Root")
        elif 'processGroupFlow' in self.flow_data:
            # Process group export format
            flow_contents = self.flow_data['processGroupFlow']['flow']
            processors = self.extract_processors_from_group(flow_contents, "Root")
        elif 'processors' in self.flow_data:
            # Direct processor list
            for processor in self.flow_data['processors']:
                processor_info = self.parse_processor(processor, "Root")
                processors.append(processor_info)
        else:
            # Try to find processors in the root level
            processors = self.extract_processors_from_group(self.flow_data, "Root")
        
        self.processors = processors
        return processors
    
    def print_processor_summary(self):
        """Print a summary of all processors."""
        if not self.processors:
            print("No processors found.")
            return
        
        print(f"\n{'='*80}")
        print(f"NIFI PROCESSOR SUMMARY - Total Processors: {len(self.processors)}")
        print(f"{'='*80}")
        
        for i, proc in enumerate(self.processors, 1):
            print(f"\n[{i}] {proc['name']}")
            print(f"    ID: {proc['id']}")
            print(f"    Type: {proc['type']}")
            print(f"    Group: {proc['group']}")
            print(f"    Concurrent Tasks: {proc['concurrent_tasks']}")
            print(f"    Scheduling Period: {proc['scheduling_period']}")
            print(f"    Auto-terminated Relationships: {', '.join(proc['auto_terminated_relationships']) if proc['auto_terminated_relationships'] else 'None'}")
            
            if proc['properties']:
                print(f"    Properties ({len(proc['properties'])} total):")
                for key, value in proc['properties'].items():
                    # Truncate long values for readability
                    display_value = str(value)[:100] + "..." if len(str(value)) > 100 else str(value)
                    print(f"      • {key}: {display_value}")
            
            if proc['relationships']:
                print(f"    Relationships:")
                for rel in proc['relationships']:
                    auto_term = " [AUTO-TERMINATE]" if rel['autoTerminate'] else ""
                    print(f"      • {rel['name']}{auto_term}")
    
    def export_to_csv(self, output_file: str = "nifi_processors.csv"):
        """Export processor information to CSV file."""
        import csv
        
        if not self.processors:
            print("No processors to export.")
            return
        
        try:
            with open(output_file, 'w', newline='', encoding='utf-8') as csvfile:
                fieldnames = [
                    'name', 'id', 'type', 'group', 'concurrent_tasks', 
                    'scheduling_period', 'penalty_duration', 'yield_duration',
                    'bulletin_level', 'auto_terminated_relationships', 'properties_count'
                ]
                
                writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
                writer.writeheader()
                
                for proc in self.processors:
                    row = {
                        'name': proc['name'],
                        'id': proc['id'],
                        'type': proc['type'],
                        'group': proc['group'],
                        'concurrent_tasks': proc['concurrent_tasks'],
                        'scheduling_period': proc['scheduling_period'],
                        'penalty_duration': proc['penalty_duration'],
                        'yield_duration': proc['yield_duration'],
                        'bulletin_level': proc['bulletin_level'],
                        'auto_terminated_relationships': '; '.join(proc['auto_terminated_relationships']),
                        'properties_count': len(proc['properties'])
                    }
                    writer.writerow(row)
            
            print(f"Processor information exported to: {output_file}")
        except Exception as e:
            print(f"Error exporting to CSV: {e}")
    
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
        print("No processors found in the JSON file.")
        sys.exit(1)
    
    # Print summary
    parser.print_processor_summary()
    
    # Show processor types
    print(f"\n{'='*50}")
    print("PROCESSOR TYPES FOUND:")
    print(f"{'='*50}")
    for proc_type in sorted(parser.get_processor_types()):
        count = len(parser.get_processors_by_type(proc_type))
        print(f"• {proc_type} ({count} instances)")
    
    # Export to CSV
    parser.export_to_csv()
    
    print(f"\nParsing complete! Found {len(processors)} processors.")


if __name__ == "__main__":
    main()

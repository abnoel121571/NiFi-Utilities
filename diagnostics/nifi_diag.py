#!/usr/bin/env python3
"""
Apache NiFi Diagnostic File Analyzer
Interactive tool to parse and analyze NiFi diagnostic output
"""

import argparse
import re
import json
from typing import Dict, List, Optional, Any
from pathlib import Path
import sys
from datetime import datetime


class NiFiDiagnosticAnalyzer:
    def __init__(self, diagnostic_file: str):
        self.diagnostic_file = Path(diagnostic_file)
        self.sections = {}
        self.raw_content = ""
        self.parse_diagnostic_file()
    
    def parse_diagnostic_file(self):
        """Parse the diagnostic file and organize into sections"""
        try:
            with open(self.diagnostic_file, 'r', encoding='utf-8') as f:
                self.raw_content = f.read()
        except Exception as e:
            print(f"Error reading file: {e}")
            sys.exit(1)
        
        # Common section patterns in NiFi diagnostics
        section_patterns = [
            (r"=+ System Diagnostics =+", "system_diagnostics"),
            (r"=+ NiFi Properties =+", "nifi_properties"),
            (r"=+ Bootstrap Properties =+", "bootstrap_properties"),
            (r"=+ JVM Information =+", "jvm_information"),
            (r"=+ Memory Usage =+", "memory_usage"),
            (r"=+ Garbage Collection =+", "garbage_collection"),
            (r"=+ Thread Information =+", "thread_information"),
            (r"=+ Process Groups =+", "process_groups"),
            (r"=+ Processors =+", "processors"),
            (r"=+ Controller Services =+", "controller_services"),
            (r"=+ Reporting Tasks =+", "reporting_tasks"),
            (r"=+ Connections =+", "connections"),
            (r"=+ Provenance =+", "provenance"),
            (r"=+ FlowFile Repository =+", "flowfile_repository"),
            (r"=+ Content Repository =+", "content_repository"),
            (r"=+ Disk Usage =+", "disk_usage"),
            (r"=+ Network Information =+", "network_information"),
            (r"=+ Operating System =+", "operating_system"),
            (r"=+ Environment Variables =+", "environment_variables"),
            (r"=+ Cluster Information =+", "cluster_information"),
            (r"=+ Registry Clients =+", "registry_clients"),
        ]
        
        # Find all section boundaries
        section_starts = []
        for pattern, name in section_patterns:
            matches = list(re.finditer(pattern, self.raw_content, re.IGNORECASE))
            for match in matches:
                section_starts.append((match.start(), name, match.group()))
        
        # Sort by position in file
        section_starts.sort(key=lambda x: x[0])
        
        # Extract content for each section
        for i, (start_pos, section_name, header) in enumerate(section_starts):
            if i < len(section_starts) - 1:
                end_pos = section_starts[i + 1][0]
                content = self.raw_content[start_pos:end_pos].strip()
            else:
                content = self.raw_content[start_pos:].strip()
            
            self.sections[section_name] = {
                'header': header,
                'content': content,
                'start_pos': start_pos
            }
    
    def list_sections(self):
        """Display all available sections"""
        print("\n" + "="*60)
        print("AVAILABLE DIAGNOSTIC SECTIONS")
        print("="*60)
        
        if not self.sections:
            print("No sections found. The file may not be a standard NiFi diagnostic output.")
            return
        
        for i, (section_name, section_data) in enumerate(self.sections.items(), 1):
            display_name = section_name.replace('_', ' ').title()
            content_lines = len(section_data['content'].split('\n'))
            print(f"{i:2d}. {display_name:<25} ({content_lines} lines)")
    
    def display_section(self, section_name: str):
        """Display a specific section"""
        if section_name not in self.sections:
            print(f"Section '{section_name}' not found.")
            return
        
        section = self.sections[section_name]
        display_name = section_name.replace('_', ' ').title()
        
        print("\n" + "="*80)
        print(f"SECTION: {display_name.upper()}")
        print("="*80)
        print(section['content'])
        print("="*80)
    
    def analyze_memory_usage(self):
        """Analyze memory usage section with specific insights"""
        if 'memory_usage' not in self.sections:
            print("Memory usage section not found.")
            return
        
        content = self.sections['memory_usage']['content']
        print("\n" + "="*60)
        print("MEMORY ANALYSIS")
        print("="*60)
        
        # Look for heap memory information
        heap_pattern = r"Heap Memory Usage.*?used:\s*(\d+)\s*bytes.*?max:\s*(\d+)\s*bytes"
        heap_match = re.search(heap_pattern, content, re.DOTALL)
        
        if heap_match:
            used_bytes = int(heap_match.group(1))
            max_bytes = int(heap_match.group(2))
            used_mb = used_bytes / (1024 * 1024)
            max_mb = max_bytes / (1024 * 1024)
            usage_percent = (used_bytes / max_bytes) * 100
            
            print(f"Heap Memory Usage:")
            print(f"  Used: {used_mb:.2f} MB ({used_bytes:,} bytes)")
            print(f"  Max:  {max_mb:.2f} MB ({max_bytes:,} bytes)")
            print(f"  Usage: {usage_percent:.1f}%")
            
            if usage_percent > 80:
                print(f"  ⚠️  WARNING: High memory usage!")
            elif usage_percent > 90:
                print(f"  🚨 CRITICAL: Very high memory usage!")
        
        print("\nFull Memory Section:")
        print("-" * 40)
        print(content)
    
    def analyze_processors(self):
        """Analyze processor information"""
        if 'processors' not in self.sections:
            print("Processors section not found.")
            return
        
        content = self.sections['processors']['content']
        print("\n" + "="*60)
        print("PROCESSOR ANALYSIS")
        print("="*60)
        
        # Count different processor types
        processor_lines = [line for line in content.split('\n') 
                          if 'Type:' in line and 'org.apache.nifi.processors' in line]
        
        processor_types = {}
        for line in processor_lines:
            type_match = re.search(r'Type:\s*(.+)', line)
            if type_match:
                proc_type = type_match.group(1).strip()
                processor_types[proc_type] = processor_types.get(proc_type, 0) + 1
        
        if processor_types:
            print("Processor Type Distribution:")
            for proc_type, count in sorted(processor_types.items()):
                short_name = proc_type.split('.')[-1]
                print(f"  {short_name:<30} : {count}")
        
        print(f"\nTotal Processors: {sum(processor_types.values())}")
        print("\nFull Processors Section:")
        print("-" * 40)
        print(content)
    
    def search_content(self, query: str):
        """Search for specific content across all sections"""
        print(f"\n" + "="*60)
        print(f"SEARCH RESULTS FOR: '{query}'")
        print("="*60)
        
        found_any = False
        for section_name, section_data in self.sections.items():
            content = section_data['content']
            if query.lower() in content.lower():
                found_any = True
                display_name = section_name.replace('_', ' ').title()
                print(f"\nFound in {display_name}:")
                
                # Show context around matches
                lines = content.split('\n')
                for i, line in enumerate(lines):
                    if query.lower() in line.lower():
                        start_line = max(0, i - 2)
                        end_line = min(len(lines), i + 3)
                        print(f"  Lines {start_line + 1}-{end_line}:")
                        for j in range(start_line, end_line):
                            marker = ">>> " if j == i else "    "
                            print(f"{marker}{lines[j]}")
                        print()
        
        if not found_any:
            print(f"No matches found for '{query}'")
    
    def get_section_by_number(self, num: int) -> Optional[str]:
        """Get section name by menu number"""
        if 1 <= num <= len(self.sections):
            return list(self.sections.keys())[num - 1]
        return None
    
    def interactive_menu(self):
        """Main interactive menu"""
        print(f"\n🔍 NiFi Diagnostic Analyzer")
        print(f"📁 File: {self.diagnostic_file}")
        print(f"📊 File size: {self.diagnostic_file.stat().st_size:,} bytes")
        print(f"🔧 Sections found: {len(self.sections)}")
        
        while True:
            print("\n" + "="*60)
            print("MAIN MENU")
            print("="*60)
            print("1. List all sections")
            print("2. View specific section")
            print("3. Analyze memory usage")
            print("4. Analyze processors")
            print("5. Search content")
            print("6. Show file info")
            print("0. Exit")
            print("-" * 60)
            
            try:
                choice = input("Enter your choice (0-6): ").strip()
                
                if choice == '0':
                    print("Goodbye! 👋")
                    break
                elif choice == '1':
                    self.list_sections()
                elif choice == '2':
                    self.list_sections()
                    try:
                        section_num = int(input("\nEnter section number: "))
                        section_name = self.get_section_by_number(section_num)
                        if section_name:
                            self.display_section(section_name)
                        else:
                            print("Invalid section number.")
                    except ValueError:
                        print("Please enter a valid number.")
                elif choice == '3':
                    self.analyze_memory_usage()
                elif choice == '4':
                    self.analyze_processors()
                elif choice == '5':
                    query = input("Enter search term: ").strip()
                    if query:
                        self.search_content(query)
                    else:
                        print("Please enter a search term.")
                elif choice == '6':
                    self.show_file_info()
                else:
                    print("Invalid choice. Please try again.")
                    
            except KeyboardInterrupt:
                print("\n\nExiting... 👋")
                break
            except Exception as e:
                print(f"Error: {e}")
    
    def show_file_info(self):
        """Show file information and summary"""
        print("\n" + "="*60)
        print("FILE INFORMATION")
        print("="*60)
        
        stat = self.diagnostic_file.stat()
        print(f"File: {self.diagnostic_file}")
        print(f"Size: {stat.st_size:,} bytes ({stat.st_size / (1024*1024):.2f} MB)")
        print(f"Modified: {datetime.fromtimestamp(stat.st_mtime).strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Total lines: {len(self.raw_content.split(chr(10))):,}")
        print(f"Sections found: {len(self.sections)}")
        
        if self.sections:
            print("\nSection Summary:")
            for name, data in self.sections.items():
                lines = len(data['content'].split('\n'))
                display_name = name.replace('_', ' ').title()
                print(f"  {display_name:<25}: {lines:>5} lines")


def main():
    parser = argparse.ArgumentParser(
        description="Interactive NiFi Diagnostic File Analyzer",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python nifi_analyzer.py diagnostic_output.txt
  python nifi_analyzer.py /path/to/nifi_diagnostics.log
        """
    )
    
    parser.add_argument(
        'diagnostic_file',
        help='Path to the NiFi diagnostic file'
    )
    
    args = parser.parse_args()
    
    # Verify file exists
    if not Path(args.diagnostic_file).exists():
        print(f"Error: File '{args.diagnostic_file}' not found.")
        sys.exit(1)
    
    # Create analyzer and start interactive session
    analyzer = NiFiDiagnosticAnalyzer(args.diagnostic_file)
    analyzer.interactive_menu()


if __name__ == "__main__":
    main()

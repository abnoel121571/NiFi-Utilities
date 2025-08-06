import json

def parse_nifi_flow_json(file_path):
    """
    Parses a NiFi flow.json file and returns its content as a Python dictionary.
    """
    try:
        with open(file_path, 'r') as file:
            flow_data = json.load(file)
            return flow_data
    except FileNotFoundError:
        print(f"Error: The file '{file_path}' was not found.")
        return None
    except json.JSONDecodeError as e:
        print(f"Error decoding JSON from '{file_path}': {e}")
        return None

def extract_processors_by_type(flow_config, target_type):
    """
    Extracts processors of a specific type from the NiFi flow configuration.

    Args:
        flow_config (dict): The NiFi flow configuration as a dictionary.
        target_type (str): The full class name of the processor type to extract
                           (e.g., 'org.apache.nifi.processors.standard.GetFile').

    Returns:
        list: A list of dictionaries, where each dictionary represents a processor
              of the specified type. Returns an empty list if no processors of that
              type are found or if the flow_config is invalid.
    """
    if not flow_config or 'flow' not in flow_config or 'processors' not in flow_config['flow']:
        return []

    extracted_processors = []
    for processor in flow_config['flow']['processors']:
        if processor.get('type') == target_type:
            extracted_processors.append(processor)
    return extracted_processors

# Example Usage:
flow_file_path = 'path/to/your/flow.json' # Replace with your flow.json file
flow_config = parse_nifi_flow_json(flow_file_path)

if flow_config:
    # Example: Extract all "GetFile" processors
    getfile_processors = extract_processors_by_type(flow_config, 'org.apache.nifi.processors.standard.GetFile')
    if getfile_processors:
        print("\n'GetFile' Processors:")
        for processor in getfile_processors:
            print(f"- Name: {processor['name']}, ID: {processor['id']}")
    else:
        print("\nNo 'GetFile' processors found.")

    # Example: Extract all "PutHDFS" processors
    puthdfs_processors = extract_processors_by_type(flow_config, 'org.apache.nifi.processors.hadoop.PutHDFS')
    if puthdfs_processors:
        print("\n'PutHDFS' Processors:")
        for processor in puthdfs_processors:
            print(f"- Name: {processor['name']}, ID: {processor['id']}")
    else:
        print("\nNo 'PutHDFS' processors found.")

    # You can also extract other processor attributes like properties
    # For example, to print a specific property of each "GetFile" processor:
    if getfile_processors:
        print("\n'GetFile' Processors with their 'Input Directory' property:")
        for processor in getfile_processors:
            input_directory = processor.get('properties', {}).get('Input Directory')
            print(f"- Name: {processor['name']}, Input Directory: {input_directory}")


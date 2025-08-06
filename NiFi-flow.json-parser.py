import json

def parse_nifi_flow_json(file_path):
    """
    Parses a NiFi flow.json file and returns its content as a Python dictionary.

    Args:
        file_path (str): The path to the flow.json file.

    Returns:
        dict: The content of the flow.json file as a dictionary, or None if an error occurs.
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

# Example usage:
flow_file_path = 'path/to/your/flow.json' # Replace with the actual path to your flow.json file
flow_config = parse_nifi_flow_json(flow_file_path)

if flow_config:
    # Now you can access different parts of the NiFi flow configuration
    # For instance, print the processors within the flow:
    if 'flow' in flow_config and 'processors' in flow_config['flow']:
        print("Processors in the NiFi flow:")
        for processor in flow_config['flow']['processors']:
            print(f"- Name: {processor['name']}, Type: {processor['type']}") 

    # You can explore other elements like connections, controller services, etc.


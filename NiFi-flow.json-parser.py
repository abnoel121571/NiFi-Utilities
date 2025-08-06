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

def list_all_processors(flow_config):
    """
    Lists all processors found within the NiFi flow configuration.

    Args:
        flow_config (dict): The NiFi flow configuration as a dictionary.

    Returns:
        list: A list of dictionaries, where each dictionary represents a processor.
              Returns an empty list if no processors are found or if the
              flow_config is invalid.
    """
    if not flow_config or 'flow' not in flow_config or 'processors' not in flow_config['flow']:
        return []

    return flow_config['flow']['processors']

# Example Usage:
flow_file_path = 'path/to/your/flow.json' # Replace with your flow.json file
flow_config = parse_nifi_flow_json(flow_file_path)

if flow_config:
    all_processors = list_all_processors(flow_config)
    if all_processors:
        print("All Processors in the NiFi flow:")
        for processor in all_processors:
            # Each 'processor' is a dictionary containing details about that processor
            print(f"- Name: {processor['name']}, Type: {processor['type']}, ID: {processor['id']}") 
            # You can access other fields as needed, e.g., processor['config']['properties']
    else:
        print("No processors found in the NiFi flow.")


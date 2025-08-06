import json

# Load JSON data from a file (replace 'flow.json.nice' with your filename)
with open('flow.json.nice') as f:
    data = json.load(f)

# Function to get the first record (element) from each top-level key if value is list/array
def first_records_per_key(json_obj):
    result = {}
    for key, value in json_obj.items():
        if isinstance(value, list) and value:
            result[key] = value[0]
        else:
            # Either not a list or empty list; include as is or None
            result[key] = value if not isinstance(value, list) else None
    return result

first_records = first_records_per_key(data)
print("First record for each key:")
print(json.dumps(first_records, indent=2))

# Example: Filter controllerServices by name == "MergeContent"
controller_services = data.get('controllerServices', [])
filtered = [
    {
        'id': item.get('id'),
        'name': item.get('name'),
        'state': item.get('state'),
        'properties': item.get('config', {}).get('properties')
    }
    for item in controller_services
    if item.get('name') == 'MergeContent'
]

print("\nFiltered 'MergeContent' records in 'controllerServices':")
print(json.dumps(filtered, indent=2))

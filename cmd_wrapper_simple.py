import subprocess
import json

def CMD(command_string: str) -> dict:
    """Runs a shell command and automatically returns the parsed JSON dictionary."""
    result = subprocess.run(command_string, shell=True, capture_output=True, text=True, check=True)
    return json.loads(result.stdout)

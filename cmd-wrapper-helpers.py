import os
import sys
import shutil
import subprocess
from dataclasses import dataclass, field
from typing import List

@dataclass
class CmdConfig:
    """Simulates the Bash environment control variables for CMD."""
    exit_on_error: str = ""                # PRINT_EXIT | PRINT_RETURN | RETURN_1_STDOUT_EMPTY
    timeout: int = 0                       # Seconds (0 = no timeout)
    out_suffix: str = ""                   # Appended to filenames
    stdout: str = ""                       # Override stdout file path
    stderr: str = ""                       # Override stderr file path
    mask_secrets: List[str] = field(default_factory=list)

def CMD(*args: str, config: CmdConfig = None) -> int:
    """
    Generic CLI wrapper matching the original Bash logic.
    Accepts command arguments as separate strings (e.g., CMD("az", "account", "show")).
    """
    if not args:
        print("error: CMD requires at least one argument", file=sys.stderr)
        return 1

    # Initialize configuration defaults
    cfg = config if config is not None else CmdConfig()
    pid = os.getpid()
    
    # Derive binary name (basename $1)
    cli_binary = os.path.basename(args[0])
    suffix_str = f"_{cfg.out_suffix}" if cfg.out_suffix else ""
    
    # Auto-construct temp file paths if not explicitly overridden
    stdout_path = cfg.stdout or f"/tmp/{cli_binary}_stdout{suffix_str}.{pid}"
    stderr_path = cfg.stderr or f"/tmp/{cli_binary}_stderr{suffix_str}.{pid}"
    
    # Masking logic
    full_command_str = " ".join(args)
    pwmask = full_command_str
    for secret in cfg.mask_secrets:
        if secret:
            pwmask = pwmask.replace(secret, "***")
            
    # Print the command (without newline to match 'echo -n')
    if cfg.timeout > 0:
        print(f" + [timeout={cfg.timeout}s] {pwmask}", end="", flush=True)
    else:
        print(f" + {pwmask}", end="", flush=True)

    rc = 0
    try:
        # Run process with auto-constructed temp file streams
        with open(stdout_path, "w") as f_out, open(stderr_path, "w") as f_err:
            timeout_val = cfg.timeout if cfg.timeout > 0 else None
            
            subprocess.run(
                args, 
                stdout=f_out, 
                stderr=f_err, 
                timeout=timeout_val, 
                check=False  # Handled inline below
            )
    except subprocess.TimeoutExpired:
        # If it hits Python timeout, treat as generic failure (simulate timeout binary RC)
        rc = 124 
    except Exception:
        rc = 1
        
    # If the process successfully completed, fetch its true return code
    if rc == 0:
        # Re-evaluating status code via standard system checks if needed, 
        # but normally subprocess tracking handles it. Let's look up final status.
        pass

    # For safety, let's catch the exact exit code inside the context tracking
    # Wrapping subprocess directly to fetch code:
    with open(stdout_path, "w") as f_out, open(stderr_path, "w") as f_err:
        try:
            p = subprocess.run(args, stdout=f_out, stderr=f_err, timeout=cfg.timeout if cfg.timeout > 0 else None)
            rc = p.returncode
        except subprocess.TimeoutExpired:
            rc = 124

    # Handle error returns
    if rc != 0:
        print(f" failed (RC={rc})", file=sys.stderr)
        
        # Helper to print files if they contain content
        def dump_file(path):
            if os.path.exists(path) and os.path.getsize(path) > 0:
                with open(path, "r") as f:
                    shutil.copyfileobj(f, sys.stderr)

        if cfg.exit_on_error in ("PRINT_RETURN", "PRINT_EXIT"):
            dump_file(stdout_path)
            dump_file(stderr_path)
            
            if cfg.exit_on_error == "PRINT_EXIT":
                os._exit(rc) # Immediate termination (simulates kill -INT $$)
            return rc
        else:
            print(f" failed (RC={rc}) — continuing", file=sys.stderr)
            return rc
    else:
        print("") # Print success trailing newline
        
        # Check if file has data (RETURN_1_STDOUT_EMPTY logic)
        stdout_empty = not (os.path.exists(stdout_path) and os.path.getsize(stdout_path) > 0)
        if cfg.exit_on_error == "RETURN_1_STDOUT_EMPTY" and stdout_empty:
            return 1

    return 0


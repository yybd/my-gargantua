#!/usr/bin/env python3
import os
import re

repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
env_path = os.path.join(repo_root, ".env.release")
helper_path = os.path.join(repo_root, "Sources/GargantuaCore/Services/XPCPrivilegedUninstallHelper.swift")

# Parse .env.release
env_vars = {}
if os.path.exists(env_path):
    with open(env_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, val = line.split("=", 1)
                env_vars[key.strip()] = val.strip().strip('"').strip("'")

team_id = env_vars.get("TEAM_ID", "6AL5F29Z3D")
bundle_id = env_vars.get("BUNDLE_ID", "com.yybd.gargantua")

if os.path.exists(helper_path):
    with open(helper_path, "r") as f:
        content = f.read()
    
    # Replace teamID
    content = re.sub(
        r'public static let teamID = "[^"]+"',
        f'public static let teamID = "{team_id}"',
        content
    )
    # Replace appBundleID
    content = re.sub(
        r'public static let appBundleID = "[^"]+"',
        f'public static let appBundleID = "{bundle_id}"',
        content
    )
    # Replace helperBundleID
    content = re.sub(
        r'public static let helperBundleID = "[^"]+"',
        f'public static let helperBundleID = "{bundle_id}.privileged-helper"',
        content
    )
    
    with open(helper_path, "w") as f:
        f.write(content)
    print(f"Successfully applied local config: Team ID -> {team_id}, Bundle ID -> {bundle_id}")
else:
    print("XPCPrivilegedUninstallHelper.swift not found")

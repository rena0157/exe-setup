#!/usr/bin/env python3
"""Admin entry point for individually assigned VMs in the existing exe.dev pool."""
import argparse
import json
import re
import shlex
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CODES = ("JW", "LP", "MM", "DL")
REPO = "https://github.com/rena0157/exe-setup.git"
T3_VERSION = "0.0.41-nightly.20260910.1486"
BUN_VERSION = "1.4.0"


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, text=True, **kwargs)


def roster_entry(path, code, required=False):
    entry = json.loads(path.read_text()).get(code, {}) if path.exists() else {}
    if not isinstance(entry, dict):
        raise ValueError(f"Invalid roster entry for {code}")
    for field in ("name", "email"):
        value = entry.get(field, "")
        if not isinstance(value, str) or any(ord(c) < 32 for c in value):
            raise ValueError(f"Invalid {field} for {code}")
        if required and not value.strip():
            raise ValueError(f"Set {code}.{field} in {path}")
    if entry.get("email") and not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", entry["email"]):
        raise ValueError(f"Invalid email for {code}")
    return {k: entry.get(k, "") for k in ("name", "email")}


def inventory():
    return json.loads(run(["ssh", "exe.dev", "ls", "--json"], capture_output=True).stdout)["vms"]


def remote(vm, script, capture=False):
    return run(["ssh", f"{vm}.exe.xyz", "bash", "-s"], input=script, capture_output=capture)


def identity_script(code, person):
    values = {**person, "code": code, "vm": f"dev-{code.lower()}"}
    return "\n".join([
        "set -Eeuo pipefail", "umask 077", 'mkdir -p "$HOME/.config/team-dev"',
        "printf '%s\\n' " + shlex.quote(json.dumps(values)) + ' > "$HOME/.config/team-dev/identity.json"',
        *["git config --global user." + field + " " + shlex.quote(person[field])
          for field in ("name", "email") if person[field]],
    ]) + "\n"


def firstboot(code, person, ref):
    if not re.fullmatch(r"[0-9a-f]{40}", ref):
        raise ValueError("--ref must be a full reviewed commit SHA (40 lowercase hex characters)")
    return "\n".join([
        "#!/bin/bash", "set -Eeuo pipefail", "umask 077",
        'exec >>"$HOME/exe-setup-firstboot.log" 2>&1',
        'mkdir -p "$HOME/.local/state/team-dev"',
        'state="$HOME/.local/state/team-dev"',
        "trap 'printf failed > \"$state/install-status\"' ERR",
        'printf installing > "$state/install-status"',
        'rm -f "$state/acceptance.json"',
        'dest="$HOME/.local/share/exe-setup"',
        'if [[ ! -d "$dest/.git" ]]; then git clone ' + shlex.quote(REPO) + ' "$dest"; fi',
        'git -C "$dest" fetch origin ' + ref,
        'git -C "$dest" checkout --detach ' + ref,
        identity_script(code, person),
        "export TAILSCALE_MODE=off MISE_NODE_VERSION=24.20.0 T3_NPM_TAG=" + shlex.quote(T3_VERSION),
        '"$dest/setup.sh" --profile full --with-ai --tailscale off',
        'export PATH="/home/linuxbrew/.linuxbrew/bin:$HOME/.local/bin:$PATH"',
        'export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"',
        'mise use --global bun@' + BUN_VERSION,
        'install -m 0755 "$dest/scripts/exe-t3.sh" "$HOME/.local/bin/exe-t3"',
        'for bin in codex claude cloudflared; do /home/linuxbrew/.linuxbrew/bin/mise exec -- which "$bin"; done',
        'systemctl --user is-enabled --quiet t3code.service',
        'systemctl --user is-active --quiet t3code.service',
        '"$dest/scripts/doctor.sh" --profile full',
        'git -C "$dest" rev-parse HEAD > "$state/setup-ref"',
        '/home/linuxbrew/.linuxbrew/bin/mise exec -- node --version > "$state/node-version"',
        'mise exec -- bun --version > "$state/bun-version"',
        'printf base-ready > "$state/install-status"',
        'printf "Base ready; complete developer sign-ins and validation.\\n"',
    ]) + "\n"


def assert_owned(vm, vms):
    match = next((item for item in vms if item["vm_name"] == vm), None)
    if not match or not match.get("access", {}).get("admin"):
        raise ValueError(f"No administrator access to {vm}")
    return match


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--roster", type=Path, default=ROOT / ".team-dev/roster.json")
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("create", help="Create one VM, refusing existing names")
    create.add_argument("code", choices=CODES)
    create.add_argument("--ref", required=True)
    create.add_argument("--dry-run", action="store_true")
    repair = commands.add_parser("repair", help="Rerun pinned setup in place; restarts the assigned VM's T3 service")
    repair.add_argument("code", choices=CODES)
    repair.add_argument("--ref", required=True)
    repair.add_argument("--dry-run", action="store_true")
    onboard = commands.add_parser("onboard", help="Resume one explicit onboarding step")
    onboard.add_argument("code", choices=CODES)
    onboard.add_argument("--step", choices=("identity", "connect", "project", "verify"), default="identity")
    onboard.add_argument("--app-ref", help="Full reviewed app commit for a new clone; default origin/main")
    status = commands.add_parser("status", help="Read live installation, service, and access status")
    status.add_argument("code", choices=CODES, nargs="?")
    args = parser.parse_args()
    if args.command in ("create", "repair"):
        person = roster_entry(args.roster, args.code, required=args.command == "repair")
        script = firstboot(args.code, person, args.ref)
        if len(script.encode()) > 10240:
            raise ValueError("First-boot script exceeds exe.dev's 10 KiB limit")
        vm = f"dev-{args.code.lower()}"
        command = ["ssh", "exe.dev", "new", "--name", vm, "--image", "ghcr.io/boldsoftware/exeuntu",
                   "--cpu", "4", "--memory", "8GB", "--disk", "100GB", "--tag", "team-dev",
                   "--no-email", "--json", "--setup-script", "/dev/stdin"]
        if args.dry_run:
            print(shlex.join(command if args.command == "create" else ["ssh", f"{vm}.exe.xyz", "bash", "-s"]))
            print(script)
            return
        if args.command == "repair":
            assert_owned(vm, inventory())
            remote(vm, script)
            print(f"Repaired {vm}; run status and repeat acceptance checks.")
            return
        if any(item["vm_name"] == vm for item in inventory()):
            raise ValueError(f"{vm} already exists; refusing to modify or replace it")
        run(command, input=script)
        run(["ssh", "exe.dev", "share", "set-private", vm])
        run(["ssh", "exe.dev", "share", "port", vm, "3000"])
        print(f"Requested {vm}; use team-dev.sh status {args.code} to check first boot.")
        return
    vms = inventory()
    if args.command == "status":
        for code in (args.code,) if args.code else CODES:
            vm = f"dev-{code.lower()}"
            if not any(item["vm_name"] == vm for item in vms):
                print(f"{code}: not created")
                continue
            item = assert_owned(vm, vms)
            print(f"{code}: {vm}; proxy={item.get('proxy_share')}; port={item.get('proxy_port')}", flush=True)
            try:
                remote(vm, 'script="$HOME/.local/share/exe-setup/scripts/team-status.sh"\n'
                           'if [[ -f "$script" ]]; then bash "$script"; else echo "Installing: status script not available yet"; fi\n')
            except subprocess.CalledProcessError:
                print("  Unreachable or failed diagnostics; not ready")
        return
    person = roster_entry(args.roster, args.code, required=True)
    vm = f"dev-{args.code.lower()}"
    assert_owned(vm, vms)
    if args.step == "identity":
        remote(vm, identity_script(args.code, person))
        print(f"Identity configured. Next: ./team-dev.sh onboard {args.code} --step connect")
        print("When the developer is present, use their T3 account to complete browser authorization.")
        print("Private web access command (sends an invitation if needed):")
        print(shlex.join(["ssh", "exe.dev", "share", "add", vm, person["email"]]))
        return
    if args.step == "connect":
        command = 'export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"; $HOME/.local/bin/exe-t3 connect link --headless && systemctl --user restart t3code.service'
    elif args.step == "project":
        if args.app_ref and not re.fullmatch(r"[0-9a-f]{40}", args.app_ref):
            raise ValueError("--app-ref must be a full commit SHA")
        command = 'bash "$HOME/.local/share/exe-setup/scripts/team-project.sh"'
        if args.app_ref:
            command += " " + shlex.quote(args.app_ref)
    else:
        command = 'bash "$HOME/.local/share/exe-setup/scripts/team-verify.sh"'
    run(["ssh", "-t", f"{vm}.exe.xyz", "bash -lc " + shlex.quote(command)])


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error)) from None

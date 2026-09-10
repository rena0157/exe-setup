# Team development machines

JW, LP, MM, and DL each receive `dev-<lowercase initials>` with 4 vCPUs, 8 GB RAM,
and 100 GB disk. All VMs, including existing machines, share the current 16-vCPU /
64-GB pool. These commands never change the subscription or add team memberships.
Use one pilot before rolling out the remaining three. Keep at most one active
browser preview per VM and stop idle development servers.

## Administrator setup

Run on your own machine with Python 3 and authenticated exe.dev SSH:

```sh
mkdir -p .team-dev
cp team-roster.example.json .team-dev/roster.json
chmod 700 .team-dev
chmod 600 .team-dev/roster.json
```

Fill each name and email from the verified roster. `.team-dev/` is ignored by Git.
GitHub usernames are discovered from each person's login, not guessed from names.
Never copy another developer's home directory or credentials. An incomplete roster
allows machine creation but blocks identity onboarding.

Push the tested setup commit so new VMs can fetch it, then use its full SHA:

```sh
./team-dev.sh create JW --ref <40-character-setup-commit> --dry-run
./team-dev.sh create JW --ref <40-character-setup-commit>
./team-dev.sh status
```

Dry-run is completely offline. Creation refuses an existing name; it does not resize,
delete, or overwrite anything. First boot installs the normal full development profile,
Node 24.20.0, Bun 1.4.0 via mise, and the pinned T3 version declared in `scripts/team_dev.py`. Tailscale
enrollment is disabled. The T3 service uses lingering and retains the Homebrew PATH fix.
No developer credentials are provisioned. The exe.dev proxy stays private on port 3000.

Follow `~/exe-setup-firstboot.log` on the VM. Installation status and versions are in
`~/.local/state/team-dev`. A failed installer never records `base-ready`. A base-ready
VM still needs accounts and acceptance; saved Connect state alone is not a connectivity test.

## Onboard a developer

```sh
./team-dev.sh onboard JW
./team-dev.sh onboard JW --step connect
```

The first step applies the verified Git identity and prints the exact named web-sharing
command. Execute that command to grant Web access; it may send an email invitation.
Keep the developer outside the exe.dev team and do not use `--root` or public sharing.

For Connect, have the assigned developer present. They open the CLI's authorization
URL and sign in to their own T3 account; enter the returned code in the same CLI session.
The helper restarts T3 after successful linking. Sign in to that same account in T3 Code
and select the new environment. The administrator does not link the VM to their own T3 account.

Developers have a full local terminal as `exedev`, with sudo, matching ardev. Web sharing
does not grant exe.dev shell access; T3 terminal access is separate. You retain provider-level
administration over SSH even if T3 is broken.

In the T3 terminal, sign in to Codex (`codex login --device-auth`) and Claude
(`claude auth login`). Device-code login may need enabling in the developer's ChatGPT
account/workspace. Confirm the reported provider identities. Do not paste passwords or
auth caches into scripts, Git, logs, or tickets.

Run project onboarding from the administrator terminal or the same script in T3:

```sh
./team-dev.sh onboard JW --step project --app-ref <40-character-app-commit>
# Alternatively, inside the VM:
bash ~/.local/share/exe-setup/scripts/team-project.sh <40-character-app-commit>
```

Use an app commit containing `bun run dev exe`. Once merged, omit `--app-ref` to clone main
and immediately create a feature branch. A partial clone left on main must be switched to
a feature branch before rerunning; existing work is never reset. Project setup uses mise to match Bun to packageManager.

The helper checks GitHub login, clones app.caivanos, creates a unique onboarding branch,
installs locked dependencies, and runs `env init`. Each developer needs access to the existing
Vercel, Neon, and Railway projects. Complete their CLI sign-ins; the existing headless Neon
walkthrough uses their API key. Railway needs access capable of provisioning environments,
not a restricted project token. Supply any requested local Trigger development key privately.

The helper preserves local settings and sets the private VM URL and developer email redirect,
then runs `env up` and `env doctor`. It never copies ardev's `.env` or edits generated runtime
files. Feature branches have managed Neon/Electric Preview data; existing shared integration
secrets retain the app's current behavior. Internal Newstar networking is outside this rollout.

## Daily development

Select the assigned T3 environment, open `~/src/app.caivanos`, and start:

```sh
bun run dev exe
```

Open `https://dev-jw.exe.xyz` (substitute your initials), authenticate to exe.dev, then
sign in to the app using its email/password flow. Microsoft callback registrations are
not part of the initial setup. Browser live reload uses WSS through the same private proxy.
Do not serve T3 through the app proxy. Stop the dev server when finished; leave T3 running.

Create future worktrees using `bun run worktree`; initialize each checkout's local URL/email
settings and Preview through the existing workflow. Switch which worktree serves port 3000
rather than running several servers there. Keep work on feature branches and push regularly.

## Acceptance and capacity

```sh
./team-dev.sh onboard JW --step verify
```

This checks the host, services, provider logins, project environment, checks, focused tests,
and build. It records acceptance only after the operator confirms actual client tests:

- T3 reconnects after closing SSH and after reboot; both providers run a task.
- The developer can log in to the private app and observe live reload.
- Signed-out and other-developer clients cannot access the VM or its preview.
- A commit and PR use the developer's own identity.

Use a small branch change for the PR and verify Preview database and email redirection.
Status reports any recorded acceptance separately from current service state.

After the pilot passes, repeat create/onboard/verify for LP, MM, DL using the same setup
revision. Measure overlapping checks/builds on two and then four VMs; record elapsed time,
`free -h`, `vmstat 1 10`, and any OOM events. Observe the existing VMs too. Reduce simultaneous
heavy jobs first; do not upgrade the subscription automatically. RAM can be resized individually
only after measured need and a pool-headroom check.

## Recovery, updates, and offboarding

Admin shell: `ssh dev-jw.exe.xyz`. T3 control: `exe-t3 service status`,
`systemctl --user restart t3code.service`, and `exe-t3 connect status`.
The `exe-t3` wrapper executes the active installed version without fetching another CLI.
Trial updates on the pilot and use the matching version's documented `service update`.

To recover a failed first boot, fix the logged cause, then run
`./team-dev.sh repair JW --ref <reviewed-setup-commit>` (supports `--dry-run`). It refuses
unowned or absent VMs, converges setup in place, and updates the status marker; it does
restart T3. Use the original SHA or a reviewed fix. Do not run create again or replace a working VM.

Rebuild from provisioning and pushed branches. Restic is installed but backups are disabled;
unpushed files and T3 history have no automated recovery guarantee. Preserve them explicitly
before retiring a machine. Monitor actual disk and bandwidth against the existing pool.

For offboarding, stop T3 first, unlink/logout Connect, revoke paired client sessions using
`exe-t3 auth`, remove the named exe.dev share, and revoke GitHub/provider/project credentials.
Verify old clients are denied. Archive needed work before separately approving VM deletion.
No automated command in this repository deletes a developer VM or Preview environment.

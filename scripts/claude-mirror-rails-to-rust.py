#!/usr/bin/env python3
"""
Mirror Rails implementation to Rust using Claude Code.

Runs in a loop:
  1. Sleeps for a configurable interval
  2. Fetches from origin
  3. Detects new commits on main that touch ruby-rails/ or tickets/
  4. Invokes Claude Code (--dangerously-skip-permissions) to bring
     rust-actix/ up to date with the changes

Usage:
    python3 scripts/claude-mirror-rails-to-rust.py [--interval SECONDS] [--once] [--dry-run]

Must be run from the repository root (/IdeaProjects/irked-adjacent).
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import time
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("mirror")

REPO_ROOT = Path(__file__).resolve().parent.parent
STATE_FILE = REPO_ROOT / "scripts" / ".mirror-state.json"
RELEVANT_PATHS = ("ruby-rails/", "tickets/", "acceptance-tests/")


def run(cmd, **kwargs):
    """Run a command, return stdout. Raises on failure."""
    log.debug("Running: %s", " ".join(cmd))
    result = subprocess.run(
        cmd, capture_output=True, text=True, cwd=str(REPO_ROOT), **kwargs
    )
    if result.returncode != 0:
        log.error("Command failed: %s\nstderr: %s", " ".join(cmd), result.stderr)
        raise RuntimeError(f"Command failed: {' '.join(cmd)}")
    return result.stdout.strip()


def load_state():
    """Load the last-processed commit SHA from disk."""
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return {}


def save_state(state):
    """Persist state to disk."""
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)
    log.debug("State saved: %s", state)


def git_fetch():
    """Fetch latest from origin."""
    log.info("Fetching from origin...")
    run(["git", "fetch", "origin"])


def get_remote_head():
    """Return the SHA of origin/main."""
    return run(["git", "rev-parse", "origin/main"])


def get_local_head():
    """Return the SHA of local main (HEAD)."""
    return run(["git", "rev-parse", "HEAD"])


def commits_between(old_sha, new_sha):
    """Return list of commit SHAs between old and new (exclusive of old)."""
    if old_sha == new_sha:
        return []
    output = run(["git", "rev-list", "--ancestry-path", f"{old_sha}..{new_sha}"])
    if not output:
        return []
    return output.split("\n")


def has_relevant_changes(old_sha, new_sha):
    """Check if any commits between old and new touch relevant paths."""
    diff_output = run(
        ["git", "diff", "--name-only", old_sha, new_sha]
    )
    if not diff_output:
        return False
    changed_files = diff_output.split("\n")
    return any(
        f.startswith(prefix) for f in changed_files for prefix in RELEVANT_PATHS
    )


def get_commit_summary(old_sha, new_sha):
    """Get a human-readable summary of commits and changes."""
    # Commit log
    log_output = run([
        "git", "log", "--oneline", "--no-decorate", f"{old_sha}..{new_sha}"
    ])

    # Changed files in relevant paths
    diff_stat = run([
        "git", "diff", "--stat", old_sha, new_sha, "--",
        *RELEVANT_PATHS
    ])

    # Full diff of relevant paths (capped to avoid enormous prompts)
    full_diff = run([
        "git", "diff", old_sha, new_sha, "--",
        *RELEVANT_PATHS
    ])

    # Cap the diff at ~50k chars to stay within reasonable prompt size
    if len(full_diff) > 50_000:
        full_diff = full_diff[:50_000] + "\n\n... [diff truncated at 50k chars] ..."

    return log_output, diff_stat, full_diff


def fast_forward_local():
    """Fast-forward local main to match origin/main."""
    log.info("Fast-forwarding local main to origin/main...")
    run(["git", "merge", "--ff-only", "origin/main"])


def build_claude_prompt(log_output, diff_stat, full_diff):
    """Build the prompt to send to Claude Code."""
    return f"""You are mirroring changes from a Ruby on Rails CMS implementation to a Rust (Actix Web) implementation.

The following new commits have landed on main, affecting the Rails implementation, tickets, or acceptance tests:

## New commits
```
{log_output}
```

## Changed files summary
```
{diff_stat}
```

## Full diff of changes
```diff
{full_diff}
```

## Your task

1. Read and understand what the new Rails commits do (new features, bug fixes, structural changes, tickets, acceptance tests).
2. Look at the current state of the rust-actix/ implementation to understand where it stands.
3. Bring the rust-actix/ implementation up to date with the ruby-rails/ implementation based on these changes.
4. Follow idiomatic Rust and Actix Web patterns — do NOT do a literal line-by-line translation.
5. If tickets/ or acceptance-tests/ were updated, read them carefully as they define the contract.
6. Run `cargo check` and `cargo clippy` in the rust-actix/ directory to verify your changes compile.
7. If there are acceptance tests, check whether there's a way to run them against the Rust implementation.
8. Commit your changes with a clear message referencing the Rails commits you're mirroring.

Important:
- The project author is learning Rust, so write clear, idiomatic code with helpful comments where the Rust approach diverges significantly from Rails.
- Pay attention to security and accessibility concerns.
- If the Rails changes don't require any Rust changes (e.g. Rails-only config), just note that and exit.
"""


def invoke_claude(prompt, dry_run=False):
    """Run Claude Code with the given prompt."""
    if dry_run:
        log.info("DRY RUN — would invoke Claude with prompt:\n%s", prompt[:500] + "...")
        return True

    log.info("Invoking Claude Code...")
    result = subprocess.run(
        [
            "claude",
            "--dangerously-skip-permissions",
            "--print",
            "--verbose",
            "-p", prompt,
        ],
        cwd=str(REPO_ROOT / "rust-actix"),
        text=True,
        timeout=600,  # 10 minute timeout
    )

    if result.returncode != 0:
        log.error("Claude exited with code %d", result.returncode)
        return False

    log.info("Claude completed successfully.")
    return True


def mirror_once(dry_run=False):
    """Run one iteration of the mirror loop. Returns True if work was done."""
    state = load_state()
    last_processed = state.get("last_processed_sha")

    git_fetch()
    remote_head = get_remote_head()

    if not last_processed:
        # First run — initialize state to current HEAD, don't process history
        log.info("First run. Initializing state to origin/main (%s).", remote_head[:8])
        save_state({"last_processed_sha": remote_head})
        return False

    if last_processed == remote_head:
        log.info("No new commits on origin/main. Nothing to do.")
        return False

    commits = commits_between(last_processed, remote_head)
    log.info(
        "Found %d new commit(s): %s..%s",
        len(commits), last_processed[:8], remote_head[:8],
    )

    if not has_relevant_changes(last_processed, remote_head):
        log.info("New commits don't touch relevant paths. Skipping.")
        save_state({"last_processed_sha": remote_head})
        return False

    log_output, diff_stat, full_diff = get_commit_summary(last_processed, remote_head)
    log.info("Changes to mirror:\n%s", diff_stat)

    # Fast-forward local branch before running Claude
    fast_forward_local()

    prompt = build_claude_prompt(log_output, diff_stat, full_diff)
    success = invoke_claude(prompt, dry_run=dry_run)

    if success:
        # Update state to the remote head we just processed
        new_head = get_local_head()  # may have advanced if Claude committed
        save_state({"last_processed_sha": new_head})
        log.info("State updated to %s.", new_head[:8])
    else:
        log.warning("Claude invocation failed. State NOT advanced — will retry next loop.")

    return True


def main():
    parser = argparse.ArgumentParser(
        description="Mirror Rails implementation changes to Rust using Claude Code."
    )
    parser.add_argument(
        "--interval", type=int, default=60,
        help="Seconds to sleep between iterations (default: 60).",
    )
    parser.add_argument(
        "--once", action="store_true",
        help="Run a single iteration and exit.",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would be done without invoking Claude.",
    )
    parser.add_argument(
        "--reset", action="store_true",
        help="Reset state file and exit. Next run will initialize fresh.",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Enable debug logging.",
    )
    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    if args.reset:
        if STATE_FILE.exists():
            STATE_FILE.unlink()
            log.info("State file removed.")
        else:
            log.info("No state file to remove.")
        return

    # Sanity checks
    if not (REPO_ROOT / ".git").exists():
        log.error("Not in a git repository. Run from the repo root.")
        sys.exit(1)

    if not (REPO_ROOT / "rust-actix").is_dir():
        log.error("rust-actix/ directory not found.")
        sys.exit(1)

    log.info("Starting mirror loop (interval=%ds, dry_run=%s)", args.interval, args.dry_run)

    if args.once:
        mirror_once(dry_run=args.dry_run)
        return

    while True:
        try:
            mirror_once(dry_run=args.dry_run)
        except Exception:
            log.exception("Error in mirror loop iteration. Will retry.")

        log.info("Sleeping %d seconds...", args.interval)
        time.sleep(args.interval)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
release_push.py

Stage all changes, commit, push to remote, and post a changelog to a Discord webhook.

Usage:
  python release_push.py [--branch BRANCH] [--message MSG] [--force] [--commits N] [--webhook URL]

By default it uses branch `main`, collects the last 20 commits for the changelog,
and will attempt a normal `git push`. Use `--force` to force-push.
If `DISCORD_WEBHOOK` environment variable is set it will be used; otherwise the
script will attempt to extract a webhook from `auto_push.ps1` if present.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime

try:
    # Python 3
    from urllib.request import Request, urlopen
except Exception:
    from urllib2 import Request, urlopen


def run(cmd, cwd=None, check=False, capture=False):
    proc = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.STDOUT if capture else None, shell=True, text=True)
    out, _ = proc.communicate()
    if check and proc.returncode != 0:
        raise RuntimeError(f"Command failed ({cmd}): {proc.returncode}\n{out}")
    return proc.returncode, out


def find_webhook_from_auto_push(repo_path):
    path = os.path.join(repo_path, 'auto_push.ps1')
    if not os.path.exists(path):
        return None
    text = open(path, 'r', encoding='utf-8', errors='ignore').read()
    m = re.search(r"\$DiscordWebhook\s*=\s*'([^']+)'", text)
    if m:
        return m.group(1).strip()
    m = re.search(r"\$webhook\s*=\s*'([^']+)'", text)
    if m:
        return m.group(1).strip()
    return None


def post_webhook(webhook, changelog, title='Release pushed'):
    if not webhook:
        print('No webhook configured; skipping webhook post')
        return False, 'no-webhook'

    # Discord embed description has a large but finite limit; truncate if needed
    desc = changelog.strip()
    if len(desc) > 3900:
        desc = desc[:3900] + '\n...'

    payload = {
        'username': 'Release Bot',
        'embeds': [
            {
                'title': title,
                'description': desc,
                'timestamp': datetime.utcnow().isoformat() + 'Z'
            }
        ]
    }

    data = json.dumps(payload).encode('utf-8')
    req = Request(webhook, data=data, headers={'Content-Type': 'application/json'})
    try:
        resp = urlopen(req, timeout=15)
        status = resp.getcode()
        body = resp.read().decode('utf-8', errors='ignore')
        print(f'Webhook POST returned {status}')
        return True, body
    except Exception as e:
        print('Webhook POST failed:', e)
        return False, str(e)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--branch', default='main')
    p.add_argument('--message', default=None)
    p.add_argument('--force', action='store_true')
    p.add_argument('--commits', type=int, default=20)
    p.add_argument('--webhook', default=None)
    args = p.parse_args()

    repo = os.getcwd()

    # Stage all changes
    print('Staging changes...')
    run('git add -A', cwd=repo, check=False)

    # Are there changes to commit?
    code, status_out = run('git status --porcelain', cwd=repo, capture=True)
    if status_out.strip() == '':
        print('No changes to commit.')
    else:
        msg = args.message or f'Auto-release: {datetime.utcnow().isoformat()}'
        print('Committing changes:', msg)
        try:
            run(f'git commit -m "{msg}"', cwd=repo, check=True)
        except RuntimeError as e:
            print('Commit failed or nothing to commit:', e)

    # Push
    print(f'Pushing to origin {args.branch}...')
    code, out = run(f'git push origin {args.branch}', cwd=repo, capture=True)
    if code != 0:
        print('Push failed:', out)
        if args.force:
            print('Attempting force-push...')
            code2, out2 = run(f'git push origin {args.branch} --force', cwd=repo, capture=True)
            if code2 == 0:
                print('Force-push succeeded')
            else:
                print('Force-push failed:', out2)
        else:
            print('Use --force to overwrite remote if that is intended.')

    # Build changelog
    code, changelog = run(f'git log -n {args.commits} --pretty=format:"%h - %an: %s"', cwd=repo, capture=True)
    if changelog.strip() == '':
        changelog = '(no commits found)'

    # Determine webhook
    webhook = args.webhook or os.environ.get('DISCORD_WEBHOOK') or find_webhook_from_auto_push(repo)

    ok, resp = post_webhook(webhook, changelog, title=f'Auto push to {args.branch}')
    if ok:
        print('Changelog posted to webhook.')
    else:
        print('Failed to post changelog:', resp)


if __name__ == '__main__':
    main()

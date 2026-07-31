# Connecting to the WorkTracker Supabase project (Claude in VS Code)

Follow this file top to bottom — it's the only thing you need. The repo
already contains `.mcp.json` (repo root), which tells Claude Code how to
connect to the shared Supabase project (ref `tngclmwzaeolvvefgptq`) in
read-only mode. You don't create or edit that file — you just need your own
access token so it can authenticate as you.

## 1. Clone/open the repo

Nothing to configure here — `.mcp.json` is already committed.

## 2. Get invited to the Supabase project

Ask the project owner (Matej) to add you as a member of the Supabase
project/org. Without this, your token won't have access no matter what
you set locally.

## 3. Generate your own personal access token

1. Go to https://supabase.com/dashboard/account/tokens
2. Generate a new token (e.g. name it "claude-code-worktracker")
3. Copy it — it starts with `sbp_` and is only shown once

## 4. Set it as an environment variable

`.mcp.json` reads the token from `SUPABASE_ACCESS_TOKEN` in your
environment — never store it in the repo.

**Windows (PowerShell), persists across sessions:**
```powershell
setx SUPABASE_ACCESS_TOKEN "sbp_your_token_here"
```
Restart VS Code afterward so it picks up the new variable.

**macOS/Linux (add to `~/.zshrc` or `~/.bashrc`):**
```bash
export SUPABASE_ACCESS_TOKEN="sbp_your_token_here"
```

## 5. Open the repo in VS Code and approve the MCP server

Claude Code will detect `.mcp.json` and prompt you to approve the
`supabase` server the first time you use it. Approve it — you're done.

## Notes

- Read-only: Claude can inspect schema, run read queries, and check
  advisors, but can't apply migrations. Use the Supabase dashboard or CLI
  for schema changes.
- This Supabase project also hosts a separate CRM/agronomy schema unrelated
  to WorkTracker (tables like `CUSTOMER`, `ORDER`, `PRODUCT`, etc.) — don't
  assume every table in the project belongs to this app.
- Never commit your token. It stays in your local environment only.

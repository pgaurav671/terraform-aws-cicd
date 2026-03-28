# 08 — Git & GitHub Setup

## What we did and why

### The repo situation

The working directory `c:/Users/GauravPatil/Desktop/Terraform+AWS` was already a git
repo but pointed at an old remote (`Terraform-AWS-VPC`). We:

1. Created a new GitHub repo `terraform-aws-cicd`
2. Changed the remote URL to point there
3. Committed and pushed all the new project files
4. Added `.claude/` to `.gitignore` and removed it from tracking

---

## Creating the GitHub repo

```bash
gh repo create terraform-aws-cicd \
  --public \
  --description "AWS Infrastructure with Terraform, CI/CD pipelines, EKS, Helm, and ArgoCD"
```

- `gh` — GitHub CLI (must be installed and authenticated)
- `--public` — visible to anyone
- This creates the repo on GitHub AND outputs the URL

Check auth status:
```bash
gh auth status
```

Login if needed:
```bash
gh auth login
```

---

## Changing the remote

```bash
# See current remotes
git remote -v

# Change where 'origin' points
git remote set-url origin https://github.com/pgaurav671/terraform-aws-cicd.git

# Verify
git remote -v
```

- `origin` is the conventional name for your primary remote
- `git push` by default pushes to `origin`
- You can have multiple remotes (e.g. `origin` for GitHub, `upstream` for a fork source)

---

## Staging specific files

```bash
git add README.md cicd-k8s-project/
```

- `git add` moves files to the **staging area** (index)
- Only staged files are included in the next commit
- We added specific files/folders, not everything (`git add .`)
  - This is safer — avoids accidentally committing secrets or unrelated files

```bash
git status --short
```

Status codes:
- `A` = Added (new file staged)
- `M` = Modified (existing file changed, staged)
- `?? ` = Untracked (not staged, not in .gitignore)
- ` M` = Modified but NOT staged

---

## Removing a file from git tracking

```bash
git rm -r --cached .claude/
```

- `rm` = remove from git's index (tracking)
- `-r` = recursive (for directories)
- `--cached` = remove from tracking ONLY, do NOT delete from your filesystem

Without `--cached`, `git rm` would delete the file from disk too.

After this command:
- `.claude/` is still on your computer ✓
- Git no longer tracks it ✓
- Future commits won't include it ✓
- But it will still show in `git log` for old commits (git history is immutable)

---

## .gitignore

```
# AI Tool Config
.claude/

# Terraform
**/.terraform/
*.tfstate
*.tfstate.*

# Secrets
.env
.env.*
*.pem
```

- `.gitignore` tells git which files/folders to ignore completely
- `**/.terraform/` — the `**` matches any directory depth (works in subdirectories too)
- `*.tfstate` — wildcard, matches any file ending in `.tfstate`
- Adding to `.gitignore` only affects **untracked** files
  - If a file is already tracked (committed before), you must also `git rm --cached` it

---

## Committing

```bash
git commit -m "feat: add cicd-k8s-project and root README with Mermaid diagrams"
```

Good commit message conventions (Conventional Commits):
- `feat:` — new feature
- `fix:` — bug fix
- `docs:` — documentation only
- `chore:` — maintenance (updating .gitignore, bumping versions)
- `refactor:` — code change, no new feature or bug fix
- `ci:` — changes to CI/CD config

---

## Pushing

```bash
# First push — set upstream tracking branch
git push -u origin main

# Subsequent pushes
git push
```

- `-u origin main` = set `origin/main` as the upstream for the local `main` branch
- After `-u`, just `git push` works (no need to specify remote and branch)

---

## GitHub Actions permissions

Workflows need to push commits back (CD workflow updates values.yaml).
This is handled by `${{ secrets.GITHUB_TOKEN }}` — automatically provided by GitHub,
no setup needed.

```yaml
- uses: actions/checkout@v4
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
```

For the commit to succeed:
```
GitHub repo → Settings → Actions → General → Workflow permissions
→ Select "Read and write permissions"
```

---

## Useful git commands

```bash
# See recent commits
git log --oneline -10

# See what changed in a commit
git show abc123

# See difference between working dir and last commit
git diff

# See staged changes (what's about to be committed)
git diff --cached

# Undo staging (unstage a file)
git restore --staged README.md

# Discard local changes to a file (DESTRUCTIVE)
git restore README.md

# See all branches
git branch -a

# Create and switch to new branch
git checkout -b feature/my-feature

# Merge branch into current
git merge feature/my-feature

# Revert a commit (creates a new undo commit, safe for shared branches)
git revert abc123

# See who changed what line (blame)
git blame app/src/index.js
```

---

## gh CLI useful commands

```bash
# Create repo
gh repo create my-repo --public

# Clone a repo
gh repo clone pgaurav671/terraform-aws-cicd

# Open repo in browser
gh repo view --web

# Create a pull request
gh pr create --title "feat: add new feature" --body "Description here"

# List PRs
gh pr list

# Merge a PR
gh pr merge 1

# List GitHub Actions runs
gh run list

# Watch a running workflow
gh run watch

# View workflow run details
gh run view 123456
```

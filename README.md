# template-repo-sync

## quick start

1. Create new repo from this template on github

2. Create new repo on platform P

3. Get all repo's token and repo-url

- github
  - (User) Settings -> Developer Settings -> Personal access tokens -> Tokens(classic)
  - select: repo & workflow  
- cnb
  - (User) Settings -> Access tokens -> Add access token
  - select: Git Read/Write Credentials & ISSUE & PR Management

4. Set all secrets and repo url

- github
  - (Repo) Settings -> Security -> Secrets and variables -> Actions -> New repository secret
  - [Option] Write into `secrets` cnb repo `secrets/github-secrets.yml`
- cnb
  - Write into `secrets` cnb repo `secrets/github-secrets.yml`

5. Modify secret's name

- github  
  update `CNB_TOKEN` and `CNB_REPO` in `.github/workflows/sync-to-cnb.yml`
- cnb
  update `GITHUB_TOKEN` and `GITHUB_REPO` in `.cnb.yml` 
  

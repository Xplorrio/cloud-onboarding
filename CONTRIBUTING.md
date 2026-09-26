# Contributing

## Running the checks

Every pull request runs the checks in
[`.github/workflows/validate.yml`](.github/workflows/validate.yml). Run the
same checks locally with one command:

```bash
make check      # or: ./scripts/check-all.sh
```

It needs these tools on your `PATH` (the versions CI uses):

| Tool | Version |
|---|---|
| Terraform | 1.16.4 (1.10 or later works) |
| tflint | 0.64.0 |
| Terragrunt | 1.1.6 |
| cfn-lint | 1.57.0 (`pip install cfn-lint==1.57.0`) |
| Bicep CLI | 0.47.16 |
| shellcheck | 0.11.0 |
| gitleaks | 8.30.1 |
| Python | 3.14 |

Nothing runs against a cloud account. The Terraform tests plan against fake
credentials and mocked providers, and no check applies anything.

### The client data key

`scripts/check-client-data.py` refuses to run without `CLIENT_DATA_HMAC_KEY`,
the key its customer name list is hashed with. Maintainers keep it outside the
repository; export it before running the checks:

```bash
export CLIENT_DATA_HMAC_KEY="$(cat ~/.config/xplorr/cloud-onboarding/client-data-hmac-key)"
```

In CI it is the repository secret of the same name. To add a name to the list,
run `python3 scripts/check-client-data.py --hash "Some Name"` with the key
exported and paste the printed line into the script.

## Rules for changes

- **Permissions.** Every permission must be a read that Xplorr actually calls
  (`services/cloud-sync-service/src` in the Xplorr app). The AWS policy lives in
  both `aws/terraform/policy.tf` and `aws/cloudformation/role.yaml`;
  `scripts/check-policy-drift.py` fails if they differ. After editing
  `role.yaml`, run `python3 scripts/sync-stackset.py` to refresh the copy in
  `stackset.yaml`.
- **Placeholders only.** Use `111111111111`, `00000000-0000-0000-0000-000000000000`,
  `my-project`, `example.com`. Never a real account, tenant, subscription,
  project, email or customer name.
- **Versions.** Before pinning a provider, module, API version, action or tool,
  check its latest stable release. Actions are pinned by commit SHA with the
  version in a comment.
- **Writing.** No em dashes. `scripts/check-style.py` lists the rest.
- **Changelog.** Add an entry to `CHANGELOG.md`.

## Pull requests from forks

CI jobs are skipped for pull requests from forks: the jobs may run on
self hosted runners, and the client data check needs a repository secret that
forks do not get. A maintainer reviews the change and, if it looks right,
pushes it to a branch in this repository to run CI there.

## Releases

- Releases are annotated tags, `vMAJOR.MINOR.PATCH`, cut from `main` after CI
  passes, with an entry in `CHANGELOG.md`.
- **Tags are immutable.** Customers pin module sources to a tag
  (`?ref=v0.1.1`), so a pushed tag is never moved, deleted or re-pushed. Fix a
  mistake with a new patch tag.
- Update the `?ref=` examples in the READMEs to the new tag in the same commit
  as the changelog entry.
- A change that renames an input or output, or changes what a template
  creates, is a breaking change: bump the minor version while below 1.0.

```bash
git tag -a v0.1.2 -m "v0.1.2"
GIT_SSH_COMMAND="ssh -i <your key>" git push origin main v0.1.2
```

## Before making this repository public

Do all of these first:

1. **Recreate the repository from one clean commit.** The history holds the
   earlier unsalted SHA-256 hashes of the customer name list (short names, easy
   to reverse) and the original author's personal email. History is not
   rewritten here, so: create a new empty repository, copy the current tree
   into one commit authored with a work address, push it, re-create the tags
   from that commit, and delete the old repository.
2. **Use GitHub hosted runners.** Delete the `RUNNER_LABEL` repository
   variable, so every job runs on `ubuntu-latest`. The fork guard in the
   workflow is not a real control on a public repository: a fork's pull request
   runs the fork's own copy of the workflow file.
3. **Require approval for workflows from outside collaborators** (Settings >
   Actions > General > "Require approval for all outside collaborators").
4. **Check the runner group.** The `xplorr-runners` self hosted runner group
   must not allow public repositories (Organization settings > Actions >
   Runner groups).
5. **Add rulesets.** A tag ruleset on `v*` that blocks deletion, updates and
   force pushes, and a branch ruleset on `main` that requires a pull request
   and a passing Validate workflow and blocks force pushes.
6. Re-create the `CLIENT_DATA_HMAC_KEY` secret in the new repository.
7. Replace the `CODEOWNERS` placeholder with a real team.

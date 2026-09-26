# Security policy

## Reporting a vulnerability

Please report security issues privately by email to **security@xplorr.io**.
Do not open a public issue or pull request for a vulnerability.

Include what you found, where (file and line, or template and parameter), and
how to reproduce it. We acknowledge reports within three working days and
keep you informed until the issue is fixed.

## Scope

This repository creates identities and read-only permissions in your cloud
accounts. Reports we particularly want:

- a template granting more than read access, or more than it documents
- a trust policy that lets a principal other than the intended one assume a
  role or use a service principal or service account
- a credential (access key, client secret, private key) written to Terraform
  state, logs, outputs or files where the documentation says it is not
- a check in `scripts/` or CI that can be bypassed

## Supported versions

Fixes are made on `main` and released as a new tag. Use the latest tag.

## Handling credentials

The templates never create an AWS access key, and create an Azure client
secret or a Google Cloud key only when you opt in. If you opt in, the secret
is stored in plain text in your Terraform state; keep that state in an
encrypted, access controlled backend.

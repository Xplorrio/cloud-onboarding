#!/usr/bin/env python3
"""Fail if the AWS read policy differs between Terraform and CloudFormation.

Compares the actions in the "read" policy document of aws/terraform/policy.tf
with the actions in the xplorr-read policy of aws/cloudformation/role.yaml.
stackset.yaml embeds role.yaml, and sync-stackset.py --check covers that copy.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ACTION = r"[a-z0-9-]+:[A-Za-z*]+"


def terraform_actions():
    text = (ROOT / "aws/terraform/policy.tf").read_text()
    start = text.index('data "aws_iam_policy_document" "read"')
    end = text.index('data "aws_iam_policy_document" "trust"')
    return set(re.findall(r'"(' + ACTION + r')"', text[start:end]))


def cloudformation_actions():
    text = (ROOT / "aws/cloudformation/role.yaml").read_text()
    start = text.index("PolicyName: xplorr-read")
    end = text.index("Tags:", start)
    block = text[start:end]
    return set(re.findall(r"^\s*(?:- |Action: )(" + ACTION + r")\s*$", block, re.MULTILINE))


def main():
    tf, cfn = terraform_actions(), cloudformation_actions()
    if not tf or not cfn:
        print("Policy drift check could not read the policies")
        return 1
    if tf != cfn:
        print("AWS policy drift between policy.tf and role.yaml:")
        for a in sorted(tf - cfn):
            print(f"  only in policy.tf: {a}")
        for a in sorted(cfn - tf):
            print(f"  only in role.yaml: {a}")
        return 1
    print(f"AWS policy matches in policy.tf and role.yaml ({len(tf)} actions)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

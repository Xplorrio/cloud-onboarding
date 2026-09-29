#!/usr/bin/env python3
"""Fail if an AWS policy differs between Terraform and CloudFormation.

Compares the actions in the "read" policy document of aws/terraform/policy.tf
with the actions in the xplorr-read policy of aws/cloudformation/role.yaml.
stackset.yaml embeds role.yaml, and sync-stackset.py --check covers that copy.

Then compares the actions of the opt-in write role, every action type turned
on: aws/terraform/modules/write-role/main.tf (everything above the trust
policy) with the xplorr-write policy of aws/cloudformation/write-role.yaml.
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


def terraform_write_actions():
    text = (ROOT / "aws/terraform/modules/write-role/main.tf").read_text()
    end = text.index('data "aws_iam_policy_document" "trust"')
    # Condition keys (variable = "ec2:CreateAction") look like actions; skip them.
    lines = [line for line in text[:end].splitlines() if "variable" not in line]
    return set(re.findall(r'"(' + ACTION + r')"', "\n".join(lines)))


def cloudformation_write_actions():
    text = (ROOT / "aws/cloudformation/write-role.yaml").read_text()
    start = text.index("PolicyName: xplorr-write")
    end = text.index("Tags:", start)
    block = text[start:end]
    return set(re.findall(r"^\s*(?:- |Action: )(" + ACTION + r")\s*$", block, re.MULTILINE))


def compare(name, tf_file, cfn_file, tf, cfn):
    if not tf or not cfn:
        print(f"Policy drift check could not read the {name} policies")
        return 1
    if tf != cfn:
        print(f"AWS {name} policy drift between {tf_file} and {cfn_file}:")
        for a in sorted(tf - cfn):
            print(f"  only in {tf_file}: {a}")
        for a in sorted(cfn - tf):
            print(f"  only in {cfn_file}: {a}")
        return 1
    print(f"AWS {name} policy matches in {tf_file} and {cfn_file} ({len(tf)} actions)")
    return 0


def main():
    failed = compare("read", "policy.tf", "role.yaml", terraform_actions(), cloudformation_actions())
    failed |= compare(
        "write", "modules/write-role/main.tf", "write-role.yaml",
        terraform_write_actions(), cloudformation_write_actions(),
    )
    return failed


if __name__ == "__main__":
    sys.exit(main())

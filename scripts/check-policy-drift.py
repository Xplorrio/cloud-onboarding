#!/usr/bin/env python3
"""Fail if an AWS policy differs between Terraform and CloudFormation.

Compares the actions in the "read" policy document of aws/terraform/policy.tf
with the actions in the xplorr-read policy of aws/cloudformation/role.yaml.
stackset.yaml embeds role.yaml, and sync-stackset.py --check covers that copy.

Then compares the actions of the opt-in write role, every action type turned
on: aws/terraform/modules/write-role/main.tf (everything above the trust
policy) with the xplorr-write policy of aws/cloudformation/write-role.yaml,
and checks that the one Xplorr role the keyless write role trusts has the
same default in the module, the parent module and the template.
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


def write_trust_defaults():
    arn = r'"?(arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+)"?'
    found = {}
    for name, path, pattern in [
        ("modules/write-role/variables.tf", "aws/terraform/modules/write-role/variables.tf",
         r'variable "xplorr_principal_arn".*?default\s*=\s*' + arn),
        ("variables.tf", "aws/terraform/variables.tf",
         r'variable "write_xplorr_principal_arn".*?default\s*=\s*' + arn),
        ("write-role.yaml", "aws/cloudformation/write-role.yaml",
         r"XplorrPrincipalArn:\n\s*Type: String\n\s*Default: " + arn),
    ]:
        m = re.search(pattern, (ROOT / path).read_text(), re.S)
        found[name] = m.group(1) if m else None
    values = set(found.values())
    if None in values or len(values) != 1:
        print("AWS write role trust drift, the Xplorr actions role differs:")
        for name, value in found.items():
            print(f"  {name}: {value}")
        return 1
    print(f"AWS write role trusts the same Xplorr role everywhere ({values.pop()})")
    return 0


def main():
    failed = write_trust_defaults()
    failed |= compare("read", "policy.tf", "role.yaml", terraform_actions(), cloudformation_actions())
    failed |= compare(
        "write", "modules/write-role/main.tf", "write-role.yaml",
        terraform_write_actions(), cloudformation_write_actions(),
    )
    return failed


if __name__ == "__main__":
    sys.exit(main())

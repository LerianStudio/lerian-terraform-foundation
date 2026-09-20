#!/usr/bin/env python3
"""Check real Terraform resource plans with mocked providers; no AWS calls.

Requires Terraform >= 1.7 and init -backend=false in both tested roots.
Nested module resources are not visible to root tftest assertions, so inspect
Terraform's verbose JSON plan instead of duplicating the upstream HCL.
"""

import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]


def test_plan(relative):
    result = subprocess.run(
        ["terraform", f"-chdir={ROOT / relative}", "test", "-json", "-verbose"],
        capture_output=True,
        text=True,
        check=False,
    )
    events = [json.loads(line) for line in result.stdout.splitlines()]
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    summary = next(
        event["test_summary"] for event in events if event["type"] == "test_summary"
    )
    assert summary["failed"] == 0 and summary["passed"] > 0, summary
    print(f"{relative}: {summary['passed']} test runs passed")
    plans = [event["test_plan"] for event in events if event["type"] == "test_plan"]
    assert plans, f"{relative}: no verbose plans returned"
    return plans


def check_eks(plan):
    resources = plan["resource_changes"]
    templates = [r for r in resources if r["type"] == "aws_launch_template"]
    groups = [r for r in resources if r["type"] == "aws_eks_node_group"]
    assert len(templates) == len(groups) == 2, (
        "Expected both managed node groups and their launch templates"
    )
    for template in templates:
        batch = '["batch"]' in template["address"]
        group = "batch" if batch else "default"
        expected = {
            "Product": "lerian",
            "Environment": "dev",
            "ManagedBy": "terraform",
            "Repository": "lerian-terraform-foundation",
            "Project": "test-project",
            "CostCenter": "batch-cost-center" if batch else "test-cost-center",
            "Owner": "batch-owner" if batch else "test-owner",
            "Name": f"lerian-dev-eks-{group}",
            "k8s.io/cluster-autoscaler/enabled": "true",
            "k8s.io/cluster-autoscaler/lerian-dev-eks": "owned",
        }
        specs = {
            s["resource_type"]: s["tags"]
            for s in template["change"]["after"]["tag_specifications"]
        }
        for kind in ("instance", "volume", "network-interface"):
            assert specs.get(kind) == expected, (template["address"], kind, specs)
        node = next(
            r for r in groups if r["module_address"] == template["module_address"]
        )
        assert node["change"]["after"]["tags"] == expected
        assert len(node["change"]["after"]["launch_template"]) == 1
    # EKS owns the underlying ASGs. If the root starts managing one, require a
    # deliberate propagation test rather than silently ignoring the new path.
    assert not any(
        r["type"] in ("aws_autoscaling_group", "aws_autoscaling_group_tag")
        for r in resources
    )
    print("EKS: instance, volume and ENI launch tags verified for both node groups")


if __name__ == "__main__":
    test_plan("examples/aws/bootstrap")
    for plan in test_plan("examples/aws/infra-base/eks"):
        check_eks(plan)

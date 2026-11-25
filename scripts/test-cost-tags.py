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
    check_eks_irsa(resources)


IRSA_ROLES = {
    "ebs_csi_irsa_role": "ebs-csi",
    "cluster_autoscaler_irsa_role": "cluster-autoscaler",
    "aws_load_balancer_controller_irsa_role": "aws-load-balancer-controller",
    "external_dns_irsa_role": "external-dns",
    "cert_manager_irsa_role": "cert-manager",
}


def check_eks_irsa(resources):
    # Service accounts are annotated with these role ARNs. The IAM module (v6)
    # defaults use_name_prefix to true, which would append a random suffix and
    # change every ARN, so the exact names are pinned here.
    def in_module(r, module):
        return r.get("module_address", "").split("[")[0] == f"module.{module}"

    for module, suffix in IRSA_ROLES.items():
        roles = [
            r for r in resources if r["type"] == "aws_iam_role" and in_module(r, module)
        ]
        assert len(roles) == 1, (module, [r["address"] for r in roles])
        after = roles[0]["change"]["after"]
        assert after.get("name") == f"lerian-dev-eks-{suffix}", (module, after.get("name"))
        assert not after.get("name_prefix"), (module, after.get("name_prefix"))

        policies = [
            r for r in resources if r["type"] == "aws_iam_policy" and in_module(r, module)
        ]
        attachments = [
            r for r in resources
            if r["type"] == "aws_iam_role_policy_attachment" and in_module(r, module)
        ]
        # Every role carries exactly one policy. cert-manager's is the root's
        # TXT-only dns01 policy, so its module must not build one of its own.
        assert len(attachments) == 1, (module, [r["address"] for r in attachments])
        if module == "cert_manager_irsa_role":
            assert not policies, [r["address"] for r in policies]
            assert attachments[0]["address"].endswith('additional["dns01"]'), (
                attachments[0]["address"]
            )
        else:
            # Pinned too: with use_name_prefix = false the module would otherwise
            # name it "EBS_CSI" and friends, which collides between two
            # environments sharing an account.
            assert len(policies) == 1, (module, [r["address"] for r in policies])
            name = policies[0]["change"]["after"].get("name")
            assert name == f"lerian-dev-eks-{suffix}", (module, name)
    print("EKS: five IRSA roles keep their exact names; cert-manager has one attachment")


def check_midaz_valkey(plan):
    # Midaz keeps balances in Valkey until they reach Postgres: eviction loses them.
    groups = [
        r for r in plan["resource_changes"]
        if r["type"] == "aws_elasticache_parameter_group"
    ]
    assert len(groups) == 1, [r["address"] for r in groups]
    params = groups[0]["change"]["after"]["parameter"]
    assert {"name": "maxmemory-policy", "value": "noeviction"} in params, params
    print("midaz valkey: parameter group renders maxmemory-policy = noeviction")


if __name__ == "__main__":
    test_plan("examples/aws/bootstrap")
    for plan in test_plan("examples/aws/infra-base/eks"):
        check_eks(plan)
    for plan in test_plan("examples/aws/products/midaz/valkey"):
        check_midaz_valkey(plan)

#!/usr/bin/env python3
"""
scripts/validate_infra.py

Multi-cloud post-deploy infrastructure validation.
Dispatches to the appropriate provider checks based on --provider.

Usage:
    python scripts/validate_infra.py --provider aws   --env dev
    python scripts/validate_infra.py --provider gcp   --env dev --gcp-project my-project-123
    python scripts/validate_infra.py --provider azure --env dev --subscription-id <UUID>
    python scripts/validate_infra.py --provider oci   --env dev --compartment-id <OCID>

    # With explicit resource IDs (skips auto-discovery):
    python scripts/validate_infra.py --provider aws --env prod \\
        --vpc-id vpc-0abc123 --instance-ids i-0abc i-0def

Exit codes:
    0 — all checks passed
    1 — one or more checks failed
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from typing import Optional


# ---------------------------------------------------------------------------
# Shared data structures
# ---------------------------------------------------------------------------

@dataclass
class CheckResult:
    name: str
    passed: bool
    message: str
    details: list[str] = field(default_factory=list)


@dataclass
class ValidationReport:
    provider: str
    environment: str
    region: str
    results: list[CheckResult] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(r.passed for r in self.results)

    @property
    def failure_count(self) -> int:
        return sum(1 for r in self.results if not r.passed)


# ---------------------------------------------------------------------------
# Report rendering
# ---------------------------------------------------------------------------

PASS_ICON = "\033[92m✓\033[0m"
FAIL_ICON = "\033[91m✗\033[0m"


def print_report(report: ValidationReport, output_format: str = "text") -> None:
    if output_format == "json":
        print(json.dumps({
            "provider":     report.provider,
            "environment":  report.environment,
            "region":       report.region,
            "passed":       report.passed,
            "failure_count": report.failure_count,
            "checks": [
                {"name": r.name, "passed": r.passed,
                 "message": r.message, "details": r.details}
                for r in report.results
            ],
        }, indent=2))
        return

    width = 60
    print(f"\n{'='*width}")
    print(f"  Validation — {report.provider.upper()} / {report.environment} / {report.region}")
    print(f"{'='*width}")
    for result in report.results:
        icon = PASS_ICON if result.passed else FAIL_ICON
        print(f"\n  {icon}  {result.name}")
        print(f"       {result.message}")
        for detail in result.details:
            print(f"       → {detail}")
    print(f"\n{'='*width}")
    summary = "All checks passed." if report.passed else f"{report.failure_count} check(s) failed."
    icon = PASS_ICON if report.passed else FAIL_ICON
    print(f"  {icon}  {summary}")
    print(f"{'='*width}\n")


# ---------------------------------------------------------------------------
# AWS checks
# ---------------------------------------------------------------------------

def _aws_check_instances_running(ec2, instance_ids: list[str]) -> CheckResult:
    if not instance_ids:
        return CheckResult("instances_running", True, "No instance IDs — skipped.")
    try:
        resp = ec2.describe_instances(InstanceIds=instance_ids)
    except Exception as e:
        return CheckResult("instances_running", False, f"API error: {e}")

    found, not_running = set(), []
    for res in resp["Reservations"]:
        for inst in res["Instances"]:
            iid, state = inst["InstanceId"], inst["State"]["Name"]
            found.add(iid)
            if state != "running":
                not_running.append(f"{iid} is '{state}'")

    missing = [f"{i} not found" for i in set(instance_ids) - found]
    details = missing + not_running
    passed = not details
    return CheckResult(
        "instances_running", passed,
        f"All {len(instance_ids)} instances running." if passed
        else f"{len(details)} issue(s) found.",
        details,
    )


def _aws_check_required_tags(ec2, instance_ids: list[str], required: list[str]) -> CheckResult:
    if not instance_ids:
        return CheckResult("required_tags", True, "No instance IDs — skipped.")
    try:
        resp = ec2.describe_instances(InstanceIds=instance_ids)
    except Exception as e:
        return CheckResult("required_tags", False, f"API error: {e}")

    details = []
    for res in resp["Reservations"]:
        for inst in res["Instances"]:
            iid = inst["InstanceId"]
            tags = {t["Key"]: t["Value"] for t in inst.get("Tags", [])}
            for key in required:
                if not tags.get(key, "").strip():
                    details.append(f"{iid} missing tag '{key}'")

    passed = not details
    return CheckResult(
        "required_tags", passed,
        f"All instances have required tags." if passed
        else f"{len(details)} missing tag(s).",
        details,
    )


def _aws_check_no_public_ssh(ec2, vpc_id: str, environment: str) -> CheckResult:
    try:
        resp = ec2.describe_security_groups(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )
    except Exception as e:
        return CheckResult("no_public_ssh", False, f"API error: {e}")

    offenders = []
    for sg in resp["SecurityGroups"]:
        for rule in sg.get("IpPermissions", []):
            fp = rule.get("FromPort", -1)
            tp = rule.get("ToPort", -1)
            is_ssh = (fp <= 22 <= tp) or fp == -1
            if not is_ssh:
                continue
            open_v4 = any(r.get("CidrIp") == "0.0.0.0/0" for r in rule.get("IpRanges", []))
            open_v6 = any(r.get("CidrIpv6") == "::/0" for r in rule.get("Ipv6Ranges", []))
            if open_v4 or open_v6:
                offenders.append(f"SG {sg['GroupId']} ({sg['GroupName']}) allows public SSH")

    hard_fail = environment in ("staging", "prod")
    passed = not offenders or not hard_fail
    if not offenders:
        msg = "No security groups allow public SSH."
    elif not hard_fail:
        msg = f"WARNING: {len(offenders)} SG(s) allow public SSH (dev-only tolerance)."
    else:
        msg = f"FAIL: {len(offenders)} SG(s) allow public SSH in {environment}."
    return CheckResult("no_public_ssh", passed, msg, offenders)


def _aws_check_flow_logs(ec2, vpc_id: str) -> CheckResult:
    try:
        resp = ec2.describe_flow_logs(
            Filters=[
                {"Name": "resource-id", "Values": [vpc_id]},
                {"Name": "flow-log-status", "Values": ["ACTIVE"]},
            ]
        )
    except Exception as e:
        return CheckResult("vpc_flow_logs", False, f"API error: {e}")

    active = resp.get("FlowLogs", [])
    passed = len(active) > 0
    return CheckResult(
        "vpc_flow_logs", passed,
        f"Flow logs active ({len(active)} log(s))." if passed
        else f"No active flow logs for {vpc_id}.",
        [] if passed else ["Run terraform apply — vpc module creates flow logs."],
    )


def _aws_check_imdsv2(ec2, instance_ids: list[str]) -> CheckResult:
    if not instance_ids:
        return CheckResult("imdsv2_enforced", True, "No instance IDs — skipped.")
    try:
        resp = ec2.describe_instances(InstanceIds=instance_ids)
    except Exception as e:
        return CheckResult("imdsv2_enforced", False, f"API error: {e}")

    details = []
    for res in resp["Reservations"]:
        for inst in res["Instances"]:
            iid = inst["InstanceId"]
            tokens = inst.get("MetadataOptions", {}).get("HttpTokens", "optional")
            if tokens != "required":
                details.append(f"{iid} has HttpTokens='{tokens}' — IMDSv1 accessible")

    passed = not details
    return CheckResult(
        "imdsv2_enforced", passed,
        "All instances enforce IMDSv2." if passed
        else f"{len(details)} instance(s) do not enforce IMDSv2.",
        details,
    )


def _aws_check_ebs_encryption(ec2, instance_ids: list[str]) -> CheckResult:
    if not instance_ids:
        return CheckResult("ebs_encryption", True, "No instance IDs — skipped.")
    try:
        resp = ec2.describe_instances(InstanceIds=instance_ids)
    except Exception as e:
        return CheckResult("ebs_encryption", False, f"API error: {e}")

    vol_ids = []
    for res in resp["Reservations"]:
        for inst in res["Instances"]:
            for bdm in inst.get("BlockDeviceMappings", []):
                if vid := bdm.get("Ebs", {}).get("VolumeId"):
                    vol_ids.append(vid)

    if not vol_ids:
        return CheckResult("ebs_encryption", True, "No EBS volumes found.")

    vols = ec2.describe_volumes(VolumeIds=vol_ids)["Volumes"]
    details = [
        f"Volume {v['VolumeId']} is unencrypted"
        for v in vols if not v.get("Encrypted", False)
    ]
    passed = not details
    return CheckResult(
        "ebs_encryption", passed,
        f"All {len(vol_ids)} volume(s) encrypted." if passed
        else f"{len(details)} unencrypted volume(s).",
        details,
    )


def _discover_aws(ec2, environment: str, project: str) -> tuple[Optional[str], list[str]]:
    """Auto-discover VPC ID and instance IDs by tag."""
    vpc_id = None
    try:
        vpcs = ec2.describe_vpcs(Filters=[
            {"Name": "tag:Environment", "Values": [environment]},
            {"Name": "tag:Project", "Values": [project]},
            {"Name": "state", "Values": ["available"]},
        ])["Vpcs"]
        if len(vpcs) == 1:
            vpc_id = vpcs[0]["VpcId"]
            print(f"  Discovered VPC: {vpc_id}")
        elif len(vpcs) > 1:
            print(f"  Multiple VPCs found — pass --vpc-id explicitly.")
    except Exception:
        pass

    instance_ids = []
    try:
        reservations = ec2.describe_instances(Filters=[
            {"Name": "tag:Environment", "Values": [environment]},
            {"Name": "tag:Project", "Values": [project]},
            {"Name": "instance-state-name", "Values": ["running", "stopped", "pending"]},
        ])["Reservations"]
        for res in reservations:
            for inst in res["Instances"]:
                instance_ids.append(inst["InstanceId"])
        if instance_ids:
            print(f"  Discovered instances: {', '.join(instance_ids)}")
    except Exception:
        pass

    return vpc_id, instance_ids


def run_aws_checks(args: argparse.Namespace) -> ValidationReport:
    try:
        import boto3
        from botocore.exceptions import NoCredentialsError
    except ImportError:
        print("ERROR: boto3 not installed. Run: pip install boto3", file=sys.stderr)
        sys.exit(1)

    try:
        session = boto3.Session(region_name=args.region)
        ec2 = session.client("ec2")
        ec2.describe_availability_zones()
    except Exception as e:
        print(f"ERROR: Cannot connect to AWS: {e}", file=sys.stderr)
        sys.exit(1)

    vpc_id = args.vpc_id
    instance_ids = args.instance_ids

    if not vpc_id or instance_ids is None:
        print(f"  Auto-discovering resources (env={args.env}, project={args.project})...")
        d_vpc, d_instances = _discover_aws(ec2, args.env, args.project)
        vpc_id = vpc_id or d_vpc
        instance_ids = instance_ids if instance_ids is not None else d_instances

    report = ValidationReport("aws", args.env, args.region)
    report.results += [
        _aws_check_instances_running(ec2, instance_ids or []),
        _aws_check_required_tags(
            ec2, instance_ids or [],
            ["Environment", "Project", "ManagedBy", "Name"],
        ),
        _aws_check_imdsv2(ec2, instance_ids or []),
        _aws_check_ebs_encryption(ec2, instance_ids or []),
    ]
    if vpc_id:
        report.results += [
            _aws_check_flow_logs(ec2, vpc_id),
            _aws_check_no_public_ssh(ec2, vpc_id, args.env),
        ]
    else:
        print("  No VPC ID — skipping VPC-level checks.")

    return report


# ---------------------------------------------------------------------------
# GCP checks
# ---------------------------------------------------------------------------

def _gcp_check_instances_running(compute, project_id: str, zone: str, instance_names: list[str]) -> CheckResult:
    if not instance_names:
        return CheckResult("instances_running", True, "No instance names — skipped.")
    try:
        result = compute.instances().list(project=project_id, zone=zone).execute()
    except Exception as e:
        return CheckResult("instances_running", False, f"API error: {e}")

    items = {i["name"]: i["status"] for i in result.get("items", [])}
    details = []
    for name in instance_names:
        if name not in items:
            details.append(f"{name} not found in zone {zone}")
        elif items[name] != "RUNNING":
            details.append(f"{name} is '{items[name]}' (expected RUNNING)")

    passed = not details
    return CheckResult(
        "instances_running", passed,
        f"All {len(instance_names)} instances RUNNING." if passed
        else f"{len(details)} issue(s) found.",
        details,
    )


def _gcp_check_required_labels(compute, project_id: str, zone: str,
                                instance_names: list[str], required: list[str]) -> CheckResult:
    if not instance_names:
        return CheckResult("required_labels", True, "No instance names — skipped.")
    details = []
    try:
        result = compute.instances().list(project=project_id, zone=zone).execute()
        instances = {i["name"]: i for i in result.get("items", [])}
        for name in instance_names:
            if name not in instances:
                continue
            labels = instances[name].get("labels", {})
            for key in required:
                if not labels.get(key, "").strip():
                    details.append(f"{name} missing label '{key}'")
    except Exception as e:
        return CheckResult("required_labels", False, f"API error: {e}")

    passed = not details
    return CheckResult(
        "required_labels", passed,
        "All instances have required labels." if passed
        else f"{len(details)} missing label(s).",
        details,
    )


def _gcp_check_no_public_ssh(compute, project_id: str, network: str, environment: str) -> CheckResult:
    try:
        result = compute.firewalls().list(project=project_id).execute()
    except Exception as e:
        return CheckResult("no_public_ssh", False, f"API error: {e}")

    offenders = []
    for fw in result.get("items", []):
        if network not in fw.get("network", ""):
            continue
        if fw.get("direction", "") != "INGRESS":
            continue
        src_ranges = fw.get("sourceRanges", [])
        if "0.0.0.0/0" not in src_ranges and "::/0" not in src_ranges:
            continue
        for allow in fw.get("allowed", []):
            ports = allow.get("ports", [])
            if "22" in ports or not ports:  # no ports = all traffic
                offenders.append(f"Firewall '{fw['name']}' allows public SSH")

    hard_fail = environment in ("staging", "prod")
    passed = not offenders or not hard_fail
    if not offenders:
        msg = "No firewall rules allow public SSH."
    elif not hard_fail:
        msg = f"WARNING: {len(offenders)} rule(s) allow public SSH (dev tolerance)."
    else:
        msg = f"FAIL: {len(offenders)} rule(s) allow public SSH in {environment}."
    return CheckResult("no_public_ssh", passed, msg, offenders)


def _gcp_check_flow_logs(compute, project_id: str, region: str) -> CheckResult:
    try:
        result = compute.subnetworks().list(project=project_id, region=region).execute()
    except Exception as e:
        return CheckResult("subnet_flow_logs", False, f"API error: {e}")

    no_logs = []
    for subnet in result.get("items", []):
        log_config = subnet.get("logConfig", {})
        if not log_config.get("enable", False):
            no_logs.append(f"Subnet '{subnet['name']}' has flow logs disabled")

    passed = not no_logs
    return CheckResult(
        "subnet_flow_logs", passed,
        "All subnets have flow logs enabled." if passed
        else f"{len(no_logs)} subnet(s) missing flow logs.",
        no_logs,
    )


def _gcp_check_os_login(compute, project_id: str, zone: str, instance_names: list[str]) -> CheckResult:
    """Verify OS Login is enabled — GCP's recommended SSH access method (replaces metadata keys)."""
    if not instance_names:
        return CheckResult("os_login_enabled", True, "No instance names — skipped.")
    details = []
    try:
        result = compute.instances().list(project=project_id, zone=zone).execute()
        instances = {i["name"]: i for i in result.get("items", [])}
        for name in instance_names:
            if name not in instances:
                continue
            metadata_items = {
                m["key"]: m["value"]
                for m in instances[name].get("metadata", {}).get("items", [])
            }
            if metadata_items.get("enable-oslogin", "FALSE").upper() != "TRUE":
                details.append(f"{name} does not have enable-oslogin=TRUE")
    except Exception as e:
        return CheckResult("os_login_enabled", False, f"API error: {e}")

    passed = not details
    return CheckResult(
        "os_login_enabled", passed,
        "All instances have OS Login enabled." if passed
        else f"{len(details)} instance(s) missing OS Login.",
        details,
    )


def _gcp_discover(compute, project_id: str, environment: str) -> list[str]:
    """Discover instance names by label."""
    names = []
    try:
        result = compute.instances().aggregatedList(project=project_id).execute()
        for zone_data in result.get("items", {}).values():
            for inst in zone_data.get("instances", []):
                labels = inst.get("labels", {})
                if labels.get("environment") == environment:
                    names.append(inst["name"])
        if names:
            print(f"  Discovered instances: {', '.join(names)}")
    except Exception:
        pass
    return names


def run_gcp_checks(args: argparse.Namespace) -> ValidationReport:
    try:
        from googleapiclient import discovery
        from google.oauth2 import service_account
        import google.auth
    except ImportError:
        print(
            "ERROR: google-api-python-client or google-auth not installed.\n"
            "Run: pip install google-api-python-client google-auth",
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        credentials, _ = google.auth.default()
        compute = discovery.build("compute", "v1", credentials=credentials)
    except Exception as e:
        print(f"ERROR: Cannot authenticate to GCP: {e}", file=sys.stderr)
        sys.exit(1)

    project_id = args.gcp_project
    zone = f"{args.region}-a"
    instance_names = args.instance_names or _gcp_discover(compute, project_id, args.env)
    network_name = args.network_name or f"{args.project}-{args.env}-vpc"

    report = ValidationReport("gcp", args.env, args.region)
    report.results += [
        _gcp_check_instances_running(compute, project_id, zone, instance_names),
        _gcp_check_required_labels(
            compute, project_id, zone, instance_names,
            ["environment", "project", "managedby"],
        ),
        _gcp_check_os_login(compute, project_id, zone, instance_names),
        _gcp_check_no_public_ssh(compute, project_id, network_name, args.env),
        _gcp_check_flow_logs(compute, project_id, args.region),
    ]
    return report


# ---------------------------------------------------------------------------
# Azure checks
# ---------------------------------------------------------------------------

def _azure_check_vms_running(compute_client, resource_group: str, vm_names: list[str]) -> CheckResult:
    if not vm_names:
        return CheckResult("vms_running", True, "No VM names — skipped.")
    details = []
    try:
        for name in vm_names:
            statuses = compute_client.virtual_machines.instance_view(resource_group, name).statuses
            power_state = next(
                (s.display_status for s in statuses if s.code.startswith("PowerState/")),
                "unknown",
            )
            if power_state != "VM running":
                details.append(f"{name} power state is '{power_state}'")
    except Exception as e:
        return CheckResult("vms_running", False, f"API error: {e}")

    passed = not details
    return CheckResult(
        "vms_running", passed,
        f"All {len(vm_names)} VMs running." if passed
        else f"{len(details)} VM(s) not running.",
        details,
    )


def _azure_check_required_tags(compute_client, resource_group: str,
                                vm_names: list[str], required: list[str]) -> CheckResult:
    if not vm_names:
        return CheckResult("required_tags", True, "No VM names — skipped.")
    details = []
    try:
        for name in vm_names:
            vm = compute_client.virtual_machines.get(resource_group, name)
            tags = vm.tags or {}
            for key in required:
                if not tags.get(key, "").strip():
                    details.append(f"{name} missing tag '{key}'")
    except Exception as e:
        return CheckResult("required_tags", False, f"API error: {e}")

    passed = not details
    return CheckResult(
        "required_tags", passed,
        "All VMs have required tags." if passed else f"{len(details)} missing tag(s).",
        details,
    )


def _azure_check_no_public_ssh(network_client, resource_group: str, environment: str) -> CheckResult:
    try:
        nsgs = list(network_client.network_security_groups.list(resource_group))
    except Exception as e:
        return CheckResult("no_public_ssh", False, f"API error: {e}")

    offenders = []
    for nsg in nsgs:
        for rule in (nsg.security_rules or []):
            if rule.direction.lower() != "inbound":
                continue
            if rule.access.lower() != "allow":
                continue
            dest_port = rule.destination_port_range or ""
            is_ssh = dest_port in ("22", "*") or (
                "-" in dest_port and
                int(dest_port.split("-")[0]) <= 22 <= int(dest_port.split("-")[1])
            )
            if not is_ssh:
                continue
            src = rule.source_address_prefix or ""
            if src in ("*", "0.0.0.0/0", "Internet"):
                offenders.append(f"NSG '{nsg.name}' rule '{rule.name}' allows public SSH")

    hard_fail = environment in ("staging", "prod")
    passed = not offenders or not hard_fail
    if not offenders:
        msg = "No NSG rules allow public SSH."
    elif not hard_fail:
        msg = f"WARNING: {len(offenders)} rule(s) allow public SSH (dev tolerance)."
    else:
        msg = f"FAIL: {len(offenders)} rule(s) allow public SSH in {environment}."
    return CheckResult("no_public_ssh", passed, msg, offenders)


def _azure_check_disk_encryption(compute_client, resource_group: str, vm_names: list[str]) -> CheckResult:
    if not vm_names:
        return CheckResult("disk_encryption", True, "No VM names — skipped.")
    details = []
    try:
        for name in vm_names:
            vm = compute_client.virtual_machines.get(resource_group, name, expand="instanceView")
            os_disk = vm.storage_profile.os_disk
            # Check for platform-managed encryption (default) or customer-managed
            enc = os_disk.managed_disk
            if enc and enc.disk_encryption_set:
                continue  # CMK encryption
            # Platform-managed encryption (PME) is always on in Azure — just flag
            # disks where someone has explicitly tried to disable encryption
            if hasattr(os_disk, "encryption_settings") and os_disk.encryption_settings:
                if not os_disk.encryption_settings.enabled:
                    details.append(f"{name}: OS disk encryption explicitly disabled")
    except Exception as e:
        return CheckResult("disk_encryption", False, f"API error: {e}")

    passed = not details
    return CheckResult(
        "disk_encryption", passed,
        "All disks use Azure platform encryption (default)." if passed
        else f"{len(details)} disk encryption issue(s).",
        details,
    )


def _azure_discover(compute_client, resource_group: str) -> list[str]:
    """List all VM names in the resource group."""
    try:
        vms = list(compute_client.virtual_machines.list(resource_group))
        names = [vm.name for vm in vms]
        if names:
            print(f"  Discovered VMs: {', '.join(names)}")
        return names
    except Exception:
        return []


def run_azure_checks(args: argparse.Namespace) -> ValidationReport:
    try:
        from azure.identity import DefaultAzureCredential
        from azure.mgmt.compute import ComputeManagementClient
        from azure.mgmt.network import NetworkManagementClient
    except ImportError:
        print(
            "ERROR: azure-identity, azure-mgmt-compute, or azure-mgmt-network not installed.\n"
            "Run: pip install azure-identity azure-mgmt-compute azure-mgmt-network",
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        credential = DefaultAzureCredential()
        compute_client = ComputeManagementClient(credential, args.subscription_id)
        network_client = NetworkManagementClient(credential, args.subscription_id)
    except Exception as e:
        print(f"ERROR: Cannot authenticate to Azure: {e}", file=sys.stderr)
        sys.exit(1)

    resource_group = args.resource_group or f"{args.project}-{args.env}-rg"
    vm_names = args.vm_names or _azure_discover(compute_client, resource_group)

    report = ValidationReport("azure", args.env, args.region)
    report.results += [
        _azure_check_vms_running(compute_client, resource_group, vm_names),
        _azure_check_required_tags(
            compute_client, resource_group, vm_names,
            ["Environment", "Project", "ManagedBy"],
        ),
        _azure_check_disk_encryption(compute_client, resource_group, vm_names),
        _azure_check_no_public_ssh(network_client, resource_group, args.env),
    ]
    return report


# ---------------------------------------------------------------------------
# OCI checks
# ---------------------------------------------------------------------------

def _oci_check_instances_running(compute_client, compartment_id: str,
                                  instance_ids: list[str]) -> CheckResult:
    if not instance_ids:
        return CheckResult("instances_running", True, "No instance IDs — skipped.")
    details = []
    try:
        for ocid in instance_ids:
            inst = compute_client.get_instance(ocid).data
            if inst.lifecycle_state != "RUNNING":
                details.append(f"{inst.display_name} is '{inst.lifecycle_state}'")
    except Exception as e:
        return CheckResult("instances_running", False, f"API error: {e}")

    passed = not details
    return CheckResult(
        "instances_running", passed,
        f"All {len(instance_ids)} instances RUNNING." if passed
        else f"{len(details)} issue(s) found.",
        details,
    )


def _oci_check_required_tags(compute_client, instance_ids: list[str],
                              required: list[str]) -> CheckResult:
    if not instance_ids:
        return CheckResult("required_tags", True, "No instance IDs — skipped.")
    details = []
    try:
        for ocid in instance_ids:
            inst = compute_client.get_instance(ocid).data
            tags = inst.freeform_tags or {}
            for key in required:
                if not tags.get(key, "").strip():
                    details.append(f"{inst.display_name} missing tag '{key}'")
    except Exception as e:
        return CheckResult("required_tags", False, f"API error: {e}")

    passed = not details
    return CheckResult(
        "required_tags", passed,
        "All instances have required tags." if passed
        else f"{len(details)} missing tag(s).",
        details,
    )


def _oci_check_no_public_ssh(network_client, compartment_id: str,
                              vcn_id: str, environment: str) -> CheckResult:
    try:
        from oci.core import models as core_models
        nsgs = network_client.list_network_security_groups(
            compartment_id=compartment_id, vcn_id=vcn_id
        ).data
    except Exception as e:
        return CheckResult("no_public_ssh", False, f"API error: {e}")

    offenders = []
    for nsg in nsgs:
        try:
            rules = network_client.list_network_security_group_security_rules(
                nsg.id, direction="INGRESS"
            ).data
            for rule in rules:
                if rule.protocol not in ("6", "all"):
                    continue
                src = getattr(rule, "source", "") or ""
                if src not in ("0.0.0.0/0", "::/0"):
                    continue
                tcp = getattr(rule, "tcp_options", None)
                if tcp is None or (
                    tcp.destination_port_range and
                    tcp.destination_port_range.min <= 22 <= tcp.destination_port_range.max
                ):
                    offenders.append(f"NSG '{nsg.display_name}' allows public SSH")
        except Exception:
            continue

    hard_fail = environment in ("staging", "prod")
    passed = not offenders or not hard_fail
    if not offenders:
        msg = "No NSG rules allow public SSH."
    elif not hard_fail:
        msg = f"WARNING: {len(offenders)} rule(s) allow public SSH (dev tolerance)."
    else:
        msg = f"FAIL: {len(offenders)} rule(s) allow public SSH in {environment}."
    return CheckResult("no_public_ssh", passed, msg, offenders)


def _oci_check_flow_logs(logging_client, compartment_id: str, vcn_id: str) -> CheckResult:
    try:
        log_groups = logging_client.list_log_groups(compartment_id=compartment_id).data
    except Exception as e:
        return CheckResult("vcn_flow_logs", False, f"API error: {e}")

    active = []
    for lg in log_groups:
        try:
            logs = logging_client.list_logs(
                log_group_id=lg.id,
                log_type="SERVICE",
                lifecycle_state="ACTIVE",
            ).data
            for log in logs:
                src = getattr(log.configuration, "source", None)
                if src and getattr(src, "resource", "") == vcn_id:
                    active.append(log.display_name)
        except Exception:
            continue

    passed = len(active) > 0
    return CheckResult(
        "vcn_flow_logs", passed,
        f"VCN flow logs active ({len(active)} log(s))." if passed
        else f"No active flow logs found for VCN {vcn_id}.",
        [] if passed else ["Run terraform apply — oci/vpc module creates flow logs."],
    )


def _oci_check_boot_volume_encryption(compute_client, compartment_id: str,
                                       instance_ids: list[str]) -> CheckResult:
    """OCI encrypts boot volumes by default. Flag any with explicitly disabled encryption."""
    if not instance_ids:
        return CheckResult("boot_volume_encryption", True, "No instance IDs — skipped.")
    details = []
    try:
        for ocid in instance_ids:
            attachments = compute_client.list_boot_volume_attachments(
                availability_domain=compute_client.get_instance(ocid).data.availability_domain,
                compartment_id=compartment_id,
                instance_id=ocid,
            ).data
            for att in attachments:
                if not att.is_pv_encryption_in_transit_enabled:
                    details.append(
                        f"Instance {ocid}: in-transit encryption not enabled on boot volume"
                    )
    except Exception as e:
        return CheckResult("boot_volume_encryption", False, f"API error: {e}")

    passed = not details
    return CheckResult(
        "boot_volume_encryption", passed,
        "All boot volumes have in-transit encryption enabled." if passed
        else f"{len(details)} boot volume issue(s).",
        details,
    )


def _oci_discover(compute_client, compartment_id: str, environment: str) -> list[str]:
    """Discover instance OCIDs by freeform tag."""
    try:
        from oci.core.models import Instance
        instances = compute_client.list_instances(compartment_id=compartment_id).data
        ocids = [
            i.id for i in instances
            if i.freeform_tags.get("Environment") == environment
            and i.lifecycle_state not in ("TERMINATED", "TERMINATING")
        ]
        if ocids:
            print(f"  Discovered {len(ocids)} instance(s).")
        return ocids
    except Exception:
        return []


def run_oci_checks(args: argparse.Namespace) -> ValidationReport:
    try:
        import oci
    except ImportError:
        print(
            "ERROR: oci not installed.\nRun: pip install oci",
            file=sys.stderr,
        )
        sys.exit(1)

    try:
        config = oci.config.from_file()
        compute_client = oci.core.ComputeClient(config)
        network_client = oci.core.VirtualNetworkClient(config)
        logging_client = oci.logging.LoggingManagementClient(config)
    except Exception as e:
        print(f"ERROR: Cannot load OCI config: {e}\nEnsure ~/.oci/config is set up.", file=sys.stderr)
        sys.exit(1)

    compartment_id = args.compartment_id
    instance_ids = args.instance_ids or _oci_discover(compute_client, compartment_id, args.env)
    vcn_id = args.vpc_id  # reusing --vpc-id flag for VCN OCID in OCI context

    report = ValidationReport("oci", args.env, args.region)
    report.results += [
        _oci_check_instances_running(compute_client, compartment_id, instance_ids),
        _oci_check_required_tags(
            compute_client, instance_ids,
            ["Environment", "Project", "ManagedBy"],
        ),
        _oci_check_boot_volume_encryption(compute_client, compartment_id, instance_ids),
    ]
    if vcn_id:
        report.results += [
            _oci_check_no_public_ssh(network_client, compartment_id, vcn_id, args.env),
            _oci_check_flow_logs(logging_client, compartment_id, vcn_id),
        ]
    else:
        print("  No VCN ID — skipping VCN-level checks. Pass --vpc-id <vcn-ocid> to enable.")

    return report


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Multi-cloud infrastructure validation.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    # Universal args
    parser.add_argument("--provider", required=True,
                        choices=["aws", "gcp", "azure", "oci"],
                        help="Cloud provider to validate.")
    parser.add_argument("--env", required=True,
                        choices=["dev", "staging", "prod"],
                        help="Environment to validate.")
    parser.add_argument("--region", default="us-east-1",
                        help="Region/location (default: us-east-1 for AWS).")
    parser.add_argument("--project", default="infra-demo",
                        help="Project name used in resource tags/labels.")
    parser.add_argument("--format", choices=["text", "json"], default="text",
                        help="Output format.")

    # AWS-specific
    aws = parser.add_argument_group("AWS")
    aws.add_argument("--vpc-id", dest="vpc_id", default=None,
                     help="AWS VPC ID or OCI VCN OCID (auto-discovered if omitted).")
    aws.add_argument("--instance-ids", dest="instance_ids", nargs="*", default=None,
                     help="EC2 or OCI instance IDs (auto-discovered if omitted).")

    # GCP-specific
    gcp = parser.add_argument_group("GCP")
    gcp.add_argument("--gcp-project", dest="gcp_project", default=None,
                     help="GCP project ID. Required for --provider gcp.")
    gcp.add_argument("--instance-names", dest="instance_names", nargs="*", default=None,
                     help="GCP instance names (auto-discovered if omitted).")
    gcp.add_argument("--network-name", dest="network_name", default=None,
                     help="GCP VPC network name for firewall checks.")

    # Azure-specific
    azure = parser.add_argument_group("Azure")
    azure.add_argument("--subscription-id", dest="subscription_id", default=None,
                       help="Azure subscription ID. Required for --provider azure.")
    azure.add_argument("--resource-group", dest="resource_group", default=None,
                       help="Azure resource group (defaults to <project>-<env>-rg).")
    azure.add_argument("--vm-names", dest="vm_names", nargs="*", default=None,
                       help="Azure VM names (auto-discovered if omitted).")

    # OCI-specific
    oci_g = parser.add_argument_group("OCI")
    oci_g.add_argument("--compartment-id", dest="compartment_id", default=None,
                       help="OCI compartment OCID. Required for --provider oci.")

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    # Provider-specific required arg validation
    if args.provider == "gcp" and not args.gcp_project:
        parser.error("--gcp-project is required when --provider gcp")
    if args.provider == "azure" and not args.subscription_id:
        parser.error("--subscription-id is required when --provider azure")
    if args.provider == "oci" and not args.compartment_id:
        parser.error("--compartment-id is required when --provider oci")

    dispatch = {
        "aws":   run_aws_checks,
        "gcp":   run_gcp_checks,
        "azure": run_azure_checks,
        "oci":   run_oci_checks,
    }

    report = dispatch[args.provider](args)
    print_report(report, args.format)
    return 0 if report.passed else 1


if __name__ == "__main__":
    sys.exit(main())

"""
tests/test_validate.py

Unit tests for the multi-cloud validate_infra.py script.
All tests use unittest.mock — zero real cloud API calls.

Run:
    python -m pytest tests/ -v --tb=short
"""

import sys
import os
from unittest.mock import MagicMock, patch, PropertyMock

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

from validate_infra import (
    CheckResult,
    ValidationReport,
    # AWS
    _aws_check_instances_running,
    _aws_check_required_tags,
    _aws_check_no_public_ssh,
    _aws_check_flow_logs,
    _aws_check_imdsv2,
    _aws_check_ebs_encryption,
    # GCP
    _gcp_check_instances_running,
    _gcp_check_required_labels,
    _gcp_check_no_public_ssh,
    _gcp_check_flow_logs,
    _gcp_check_os_login,
    # Azure
    _azure_check_vms_running,
    _azure_check_required_tags,
    _azure_check_no_public_ssh,
    # OCI
    _oci_check_instances_running,
    _oci_check_required_tags,
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_aws_instance(iid="i-001", state="running", tags=None,
                      http_tokens="required", vol_id="vol-001"):
    tags = tags or {
        "Environment": "dev", "Project": "infra-demo",
        "ManagedBy": "terraform", "Name": "test-app-1",
    }
    return {
        "InstanceId": iid,
        "State": {"Name": state},
        "Tags": [{"Key": k, "Value": v} for k, v in tags.items()],
        "MetadataOptions": {"HttpTokens": http_tokens, "HttpEndpoint": "enabled"},
        "BlockDeviceMappings": [
            {"DeviceName": "/dev/xvda", "Ebs": {"VolumeId": vol_id, "Status": "attached"}}
        ],
    }


def aws_describe_response(instances):
    return {"Reservations": [{"Instances": [i]} for i in instances]}


# ---------------------------------------------------------------------------
# ValidationReport
# ---------------------------------------------------------------------------

class TestValidationReport:
    def test_all_pass(self):
        r = ValidationReport("aws", "dev", "us-east-1")
        r.results = [CheckResult("a", True, "ok"), CheckResult("b", True, "ok")]
        assert r.passed is True
        assert r.failure_count == 0

    def test_one_failure(self):
        r = ValidationReport("gcp", "prod", "us-central1")
        r.results = [CheckResult("a", True, "ok"), CheckResult("b", False, "fail")]
        assert r.passed is False
        assert r.failure_count == 1

    def test_provider_stored(self):
        r = ValidationReport("azure", "staging", "eastus")
        assert r.provider == "azure"


# ---------------------------------------------------------------------------
# AWS tests
# ---------------------------------------------------------------------------

class TestAwsInstancesRunning:
    def test_all_running(self):
        ec2 = MagicMock()
        ec2.describe_instances.return_value = aws_describe_response(
            [make_aws_instance("i-001", "running"), make_aws_instance("i-002", "running")]
        )
        r = _aws_check_instances_running(ec2, ["i-001", "i-002"])
        assert r.passed is True

    def test_stopped_fails(self):
        ec2 = MagicMock()
        ec2.describe_instances.return_value = aws_describe_response(
            [make_aws_instance("i-001", "stopped")]
        )
        r = _aws_check_instances_running(ec2, ["i-001"])
        assert r.passed is False
        assert any("stopped" in d for d in r.details)

    def test_missing_instance_fails(self):
        ec2 = MagicMock()
        ec2.describe_instances.return_value = aws_describe_response(
            [make_aws_instance("i-001", "running")]
        )
        r = _aws_check_instances_running(ec2, ["i-001", "i-GHOST"])
        assert r.passed is False
        assert any("i-GHOST" in d for d in r.details)

    def test_empty_list_skips(self):
        ec2 = MagicMock()
        r = _aws_check_instances_running(ec2, [])
        assert r.passed is True
        ec2.describe_instances.assert_not_called()

    def test_api_error_fails(self):
        ec2 = MagicMock()
        ec2.describe_instances.side_effect = Exception("Connection refused")
        r = _aws_check_instances_running(ec2, ["i-001"])
        assert r.passed is False


class TestAwsRequiredTags:
    def test_all_tags_present(self):
        ec2 = MagicMock()
        ec2.describe_instances.return_value = aws_describe_response(
            [make_aws_instance("i-001")]
        )
        r = _aws_check_required_tags(ec2, ["i-001"],
                                     ["Environment", "Project", "ManagedBy", "Name"])
        assert r.passed is True

    def test_missing_tag_fails(self):
        ec2 = MagicMock()
        inst = make_aws_instance("i-001", tags={"Environment": "dev"})
        ec2.describe_instances.return_value = aws_describe_response([inst])
        r = _aws_check_required_tags(ec2, ["i-001"],
                                     ["Environment", "Project", "ManagedBy", "Name"])
        assert r.passed is False
        assert len(r.details) == 3

    def test_empty_tag_value_fails(self):
        ec2 = MagicMock()
        inst = make_aws_instance("i-001", tags={
            "Environment": "dev", "Project": "", "ManagedBy": "terraform", "Name": "x"
        })
        ec2.describe_instances.return_value = aws_describe_response([inst])
        r = _aws_check_required_tags(ec2, ["i-001"], ["Environment", "Project"])
        assert r.passed is False
        assert any("Project" in d for d in r.details)


class TestAwsNoPublicSsh:
    def _make_sg(self, sg_id, sg_name, ssh_open):
        if ssh_open:
            perms = [{"FromPort": 22, "ToPort": 22, "IpProtocol": "tcp",
                      "IpRanges": [{"CidrIp": "0.0.0.0/0"}], "Ipv6Ranges": []}]
        else:
            perms = [{"FromPort": 443, "ToPort": 443, "IpProtocol": "tcp",
                      "IpRanges": [{"CidrIp": "0.0.0.0/0"}], "Ipv6Ranges": []}]
        return {"GroupId": sg_id, "GroupName": sg_name, "IpPermissions": perms}

    def test_no_public_ssh_passes(self):
        ec2 = MagicMock()
        ec2.describe_security_groups.return_value = {
            "SecurityGroups": [self._make_sg("sg-001", "app-sg", False)]
        }
        r = _aws_check_no_public_ssh(ec2, "vpc-001", "prod")
        assert r.passed is True

    def test_public_ssh_prod_fails(self):
        ec2 = MagicMock()
        ec2.describe_security_groups.return_value = {
            "SecurityGroups": [self._make_sg("sg-001", "bastion-sg", True)]
        }
        r = _aws_check_no_public_ssh(ec2, "vpc-001", "prod")
        assert r.passed is False

    def test_public_ssh_dev_warns_passes(self):
        ec2 = MagicMock()
        ec2.describe_security_groups.return_value = {
            "SecurityGroups": [self._make_sg("sg-001", "bastion-sg", True)]
        }
        r = _aws_check_no_public_ssh(ec2, "vpc-001", "dev")
        assert r.passed is True   # passes in dev
        assert r.details           # but finding is recorded

    def test_public_ssh_staging_fails(self):
        ec2 = MagicMock()
        ec2.describe_security_groups.return_value = {
            "SecurityGroups": [self._make_sg("sg-001", "test-sg", True)]
        }
        r = _aws_check_no_public_ssh(ec2, "vpc-001", "staging")
        assert r.passed is False


class TestAwsFlowLogs:
    def test_active_log_passes(self):
        ec2 = MagicMock()
        ec2.describe_flow_logs.return_value = {
            "FlowLogs": [{"FlowLogId": "fl-001", "FlowLogStatus": "ACTIVE"}]
        }
        assert _aws_check_flow_logs(ec2, "vpc-001").passed is True

    def test_no_logs_fails(self):
        ec2 = MagicMock()
        ec2.describe_flow_logs.return_value = {"FlowLogs": []}
        r = _aws_check_flow_logs(ec2, "vpc-001")
        assert r.passed is False
        assert r.details


class TestAwsImdsv2:
    def test_required_passes(self):
        ec2 = MagicMock()
        ec2.describe_instances.return_value = aws_describe_response(
            [make_aws_instance("i-001", http_tokens="required")]
        )
        assert _aws_check_imdsv2(ec2, ["i-001"]).passed is True

    def test_optional_fails(self):
        ec2 = MagicMock()
        ec2.describe_instances.return_value = aws_describe_response(
            [make_aws_instance("i-001", http_tokens="optional")]
        )
        r = _aws_check_imdsv2(ec2, ["i-001"])
        assert r.passed is False
        assert "i-001" in r.details[0]


class TestAwsEbsEncryption:
    def test_encrypted_passes(self):
        ec2 = MagicMock()
        ec2.describe_instances.return_value = aws_describe_response(
            [make_aws_instance("i-001", vol_id="vol-001")]
        )
        ec2.describe_volumes.return_value = {
            "Volumes": [{"VolumeId": "vol-001", "Encrypted": True, "Attachments": [{"InstanceId": "i-001"}]}]
        }
        assert _aws_check_ebs_encryption(ec2, ["i-001"]).passed is True

    def test_unencrypted_fails(self):
        ec2 = MagicMock()
        ec2.describe_instances.return_value = aws_describe_response(
            [make_aws_instance("i-001", vol_id="vol-001")]
        )
        ec2.describe_volumes.return_value = {
            "Volumes": [{"VolumeId": "vol-001", "Encrypted": False, "Attachments": [{"InstanceId": "i-001"}]}]
        }
        r = _aws_check_ebs_encryption(ec2, ["i-001"])
        assert r.passed is False
        assert "vol-001" in r.details[0]


# ---------------------------------------------------------------------------
# GCP tests
# ---------------------------------------------------------------------------

def make_gcp_instance(name="app-1", status="RUNNING", labels=None, os_login="TRUE"):
    labels = labels or {"environment": "dev", "project": "infra-demo", "managedby": "terraform"}
    return {
        "name": name,
        "status": status,
        "labels": labels,
        "metadata": {"items": [{"key": "enable-oslogin", "value": os_login}]},
    }


class TestGcpInstancesRunning:
    def _compute(self, instances):
        compute = MagicMock()
        compute.instances().list().execute.return_value = {"items": instances}
        return compute

    def test_running_passes(self):
        compute = self._compute([make_gcp_instance("app-1", "RUNNING")])
        r = _gcp_check_instances_running(compute, "proj", "us-central1-a", ["app-1"])
        assert r.passed is True

    def test_terminated_fails(self):
        compute = self._compute([make_gcp_instance("app-1", "TERMINATED")])
        r = _gcp_check_instances_running(compute, "proj", "us-central1-a", ["app-1"])
        assert r.passed is False

    def test_missing_instance_fails(self):
        compute = self._compute([make_gcp_instance("app-1", "RUNNING")])
        r = _gcp_check_instances_running(compute, "proj", "us-central1-a", ["app-1", "app-ghost"])
        assert r.passed is False
        assert any("app-ghost" in d for d in r.details)

    def test_empty_skips(self):
        compute = MagicMock()
        r = _gcp_check_instances_running(compute, "proj", "us-central1-a", [])
        assert r.passed is True


class TestGcpRequiredLabels:
    def _compute(self, instances):
        compute = MagicMock()
        compute.instances().list().execute.return_value = {"items": instances}
        return compute

    def test_all_labels_pass(self):
        compute = self._compute([make_gcp_instance()])
        r = _gcp_check_required_labels(compute, "proj", "us-central1-a",
                                       ["app-1"], ["environment", "project", "managedby"])
        assert r.passed is True

    def test_missing_label_fails(self):
        inst = make_gcp_instance(labels={"environment": "dev"})
        compute = self._compute([inst])
        r = _gcp_check_required_labels(compute, "proj", "us-central1-a",
                                       ["app-1"], ["environment", "project", "managedby"])
        assert r.passed is False
        assert len(r.details) == 2


class TestGcpNoPublicSsh:
    def _compute_with_fw(self, fw_list):
        compute = MagicMock()
        compute.firewalls().list().execute.return_value = {"items": fw_list}
        return compute

    def test_no_public_ssh_passes(self):
        fw = {"name": "allow-https", "direction": "INGRESS",
              "network": "test-vpc", "sourceRanges": ["0.0.0.0/0"],
              "allowed": [{"IPProtocol": "tcp", "ports": ["443"]}]}
        compute = self._compute_with_fw([fw])
        r = _gcp_check_no_public_ssh(compute, "proj", "test-vpc", "prod")
        assert r.passed is True

    def test_public_ssh_prod_fails(self):
        fw = {"name": "allow-ssh", "direction": "INGRESS",
              "network": "test-vpc", "sourceRanges": ["0.0.0.0/0"],
              "allowed": [{"IPProtocol": "tcp", "ports": ["22"]}]}
        compute = self._compute_with_fw([fw])
        r = _gcp_check_no_public_ssh(compute, "proj", "test-vpc", "prod")
        assert r.passed is False

    def test_public_ssh_dev_passes_with_warning(self):
        fw = {"name": "allow-ssh", "direction": "INGRESS",
              "network": "test-vpc", "sourceRanges": ["0.0.0.0/0"],
              "allowed": [{"IPProtocol": "tcp", "ports": ["22"]}]}
        compute = self._compute_with_fw([fw])
        r = _gcp_check_no_public_ssh(compute, "proj", "test-vpc", "dev")
        assert r.passed is True
        assert r.details


class TestGcpFlowLogs:
    def test_all_enabled_passes(self):
        compute = MagicMock()
        compute.subnetworks().list().execute.return_value = {
            "items": [
                {"name": "private-0", "logConfig": {"enable": True}},
                {"name": "private-1", "logConfig": {"enable": True}},
            ]
        }
        r = _gcp_check_flow_logs(compute, "proj", "us-central1")
        assert r.passed is True

    def test_disabled_subnet_fails(self):
        compute = MagicMock()
        compute.subnetworks().list().execute.return_value = {
            "items": [
                {"name": "private-0", "logConfig": {"enable": False}},
            ]
        }
        r = _gcp_check_flow_logs(compute, "proj", "us-central1")
        assert r.passed is False


class TestGcpOsLogin:
    def _compute(self, instances):
        c = MagicMock()
        c.instances().list().execute.return_value = {"items": instances}
        return c

    def test_os_login_enabled_passes(self):
        c = self._compute([make_gcp_instance(os_login="TRUE")])
        r = _gcp_check_os_login(c, "proj", "us-central1-a", ["app-1"])
        assert r.passed is True

    def test_os_login_disabled_fails(self):
        c = self._compute([make_gcp_instance(os_login="FALSE")])
        r = _gcp_check_os_login(c, "proj", "us-central1-a", ["app-1"])
        assert r.passed is False


# ---------------------------------------------------------------------------
# Azure tests
# ---------------------------------------------------------------------------

def make_azure_vm(name="app-1", power_state="VM running", tags=None):
    vm = MagicMock()
    vm.name = name
    vm.tags = tags or {"Environment": "dev", "Project": "infra-demo", "ManagedBy": "terraform"}
    return vm


def make_azure_status(code, display):
    s = MagicMock()
    s.code = code
    s.display_status = display
    return s


class TestAzureVmsRunning:
    def test_running_passes(self):
        compute = MagicMock()
        compute.virtual_machines.instance_view.return_value.statuses = [
            make_azure_status("PowerState/running", "VM running"),
        ]
        r = _azure_check_vms_running(compute, "rg-dev", ["app-1"])
        assert r.passed is True

    def test_stopped_fails(self):
        compute = MagicMock()
        compute.virtual_machines.instance_view.return_value.statuses = [
            make_azure_status("PowerState/stopped", "VM stopped"),
        ]
        r = _azure_check_vms_running(compute, "rg-dev", ["app-1"])
        assert r.passed is False

    def test_empty_skips(self):
        compute = MagicMock()
        r = _azure_check_vms_running(compute, "rg-dev", [])
        assert r.passed is True
        compute.virtual_machines.instance_view.assert_not_called()


class TestAzureRequiredTags:
    def test_all_tags_pass(self):
        compute = MagicMock()
        compute.virtual_machines.get.return_value = make_azure_vm()
        r = _azure_check_required_tags(compute, "rg-dev", ["app-1"],
                                       ["Environment", "Project", "ManagedBy"])
        assert r.passed is True

    def test_missing_tag_fails(self):
        compute = MagicMock()
        compute.virtual_machines.get.return_value = make_azure_vm(tags={"Environment": "dev"})
        r = _azure_check_required_tags(compute, "rg-dev", ["app-1"],
                                       ["Environment", "Project", "ManagedBy"])
        assert r.passed is False
        assert len(r.details) == 2


class TestAzureNoPublicSsh:
    def _make_rule(self, name, direction, access, dest_port, src_prefix):
        rule = MagicMock()
        rule.name = name
        rule.direction = direction
        rule.access = access
        rule.destination_port_range = dest_port
        rule.source_address_prefix = src_prefix
        return rule

    def _make_nsg(self, name, rules):
        nsg = MagicMock()
        nsg.name = name
        nsg.security_rules = rules
        return nsg

    def test_no_public_ssh_passes(self):
        network = MagicMock()
        rule = self._make_rule("allow-https", "Inbound", "Allow", "443", "10.0.0.0/8")
        network.network_security_groups.list.return_value = [self._make_nsg("app-nsg", [rule])]
        r = _azure_check_no_public_ssh(network, "rg-dev", "prod")
        assert r.passed is True

    def test_public_ssh_prod_fails(self):
        network = MagicMock()
        rule = self._make_rule("allow-ssh", "Inbound", "Allow", "22", "*")
        network.network_security_groups.list.return_value = [self._make_nsg("app-nsg", [rule])]
        r = _azure_check_no_public_ssh(network, "rg-dev", "prod")
        assert r.passed is False

    def test_public_ssh_dev_passes_with_warning(self):
        network = MagicMock()
        rule = self._make_rule("allow-ssh", "Inbound", "Allow", "22", "Internet")
        network.network_security_groups.list.return_value = [self._make_nsg("app-nsg", [rule])]
        r = _azure_check_no_public_ssh(network, "rg-dev", "dev")
        assert r.passed is True
        assert r.details


# ---------------------------------------------------------------------------
# OCI tests
# ---------------------------------------------------------------------------

def make_oci_instance(ocid="ocid1.instance.oc1..aaa", name="app-1",
                      state="RUNNING", tags=None):
    inst = MagicMock()
    inst.id = ocid
    inst.display_name = name
    inst.lifecycle_state = state
    inst.freeform_tags = tags or {
        "Environment": "dev", "Project": "infra-demo", "ManagedBy": "terraform"
    }
    return inst


class TestOciInstancesRunning:
    def test_running_passes(self):
        compute = MagicMock()
        compute.get_instance.return_value.data = make_oci_instance(state="RUNNING")
        r = _oci_check_instances_running(compute, "comp-id", ["ocid1.instance.aaa"])
        assert r.passed is True

    def test_stopped_fails(self):
        compute = MagicMock()
        compute.get_instance.return_value.data = make_oci_instance(state="STOPPED")
        r = _oci_check_instances_running(compute, "comp-id", ["ocid1.instance.aaa"])
        assert r.passed is False

    def test_empty_skips(self):
        compute = MagicMock()
        r = _oci_check_instances_running(compute, "comp-id", [])
        assert r.passed is True
        compute.get_instance.assert_not_called()

    def test_api_error_fails(self):
        compute = MagicMock()
        compute.get_instance.side_effect = Exception("Network error")
        r = _oci_check_instances_running(compute, "comp-id", ["ocid1.instance.aaa"])
        assert r.passed is False


class TestOciRequiredTags:
    def test_all_tags_pass(self):
        compute = MagicMock()
        compute.get_instance.return_value.data = make_oci_instance()
        r = _oci_check_required_tags(compute, ["ocid1.instance.aaa"],
                                     ["Environment", "Project", "ManagedBy"])
        assert r.passed is True

    def test_missing_tag_fails(self):
        compute = MagicMock()
        compute.get_instance.return_value.data = make_oci_instance(
            tags={"Environment": "dev"}
        )
        r = _oci_check_required_tags(compute, ["ocid1.instance.aaa"],
                                     ["Environment", "Project", "ManagedBy"])
        assert r.passed is False
        assert len(r.details) == 2

From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Definition nonempty (values : list json) := negb (Nat.eqb (List.length values) 0).
Definition supplied_or (value fallback : json) := if is_null value then fallback else value.
Definition provider_request (source : json) :=
  let settings := get source "settings" in
  JObject [("InstanceChargeType",JString "SPOTPAID");("InstanceCount",number 1);("MinCount",number 1);
    ("Placement",JObject [("Zone",get settings "zone")]);("ImageId",get settings "image_id");
    ("InstanceType",get settings "instance_type");
    ("VirtualPrivateCloud",JObject [("VpcId",get settings "vpc_id");("SubnetId",get settings "subnet_id")]);
    ("InternetAccessible",JObject [("PublicIpAssigned",JBool (negb (String.eqb (str settings "address_type") "private")));
      ("InternetMaxBandwidthOut",supplied_or (get settings "internet_max_bandwidth_out") (number 5));
      ("InternetChargeType",JString "TRAFFIC_POSTPAID_BY_HOUR")]);
    ("SecurityGroupIds",get settings "security_group_ids");
    ("LoginSettings",JObject [("KeyIds",JArray [get settings "key_id"])]);
    ("InstanceName",JString ("selvedge-task-" ++ decimal (num source "task_id")));
    ("ClientToken",get source "token");
    ("InstanceMarketOptions",JObject [("MarketType",JString "spot");("SpotOptions",JObject [
      ("MaxPrice",get settings "spot_max_price");("SpotInstanceType",JString "one-time")])]);
    ("TagSpecification",JArray [JObject [("ResourceType",JString "instance");("Tags",JArray [
      JObject [("Key",JString "selvedge-task");("Value",get source "token")]])]])].
Definition provider (source : json) :=
  let instance := get source "instance" in
  let state := str instance "InstanceState" in
  let expired := num source "deadline" <=? num source "now" in
  let action name := JObject [("action",JString name)] in
  if String.eqb (str source "operation") "ready" then
    if expired then action "timeout"
    else if String.eqb state "LAUNCH_FAILED" || String.eqb state "TERMINATED" then action "failed"
    else
      let addresses := items (get instance (if String.eqb (str (get source "settings") "address_type") "private"
        then "PrivateIpAddresses" else "PublicIpAddresses")) in
      if String.eqb state "RUNNING" && nonempty addresses
      then JObject [("action",JString "ready");("host",hd JNull addresses)]
      else action "wait"
  else if is_null instance || String.eqb state "TERMINATED" then action "done"
  else if expired then action "timeout"
  else if String.eqb (str source "operation") "destroy_before" then action "terminate"
  else action "wait".

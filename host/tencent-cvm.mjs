import tencentcloud from 'tencentcloud-sdk-nodejs-cvm';
import { setTimeout as delay } from 'node:timers/promises';

const { Client } = tencentcloud.cvm.v20170312;

/** CVM owns allocation and destruction; execution is the separate SSH boundary. */
export function tencentCvmBackend(settings) {
  if (!process.env.TENCENTCLOUD_SECRET_ID || !process.env.TENCENTCLOUD_SECRET_KEY) {
    throw new Error('Tencent CVM requires TENCENTCLOUD_SECRET_ID and TENCENTCLOUD_SECRET_KEY in the service environment');
  }
  const endpoint = settings.api_endpoint ? new URL(settings.api_endpoint) : undefined;
  const client = new Client({
    credential: { secretId: process.env.TENCENTCLOUD_SECRET_ID, secretKey: process.env.TENCENTCLOUD_SECRET_KEY,
      token: process.env.TENCENTCLOUD_TOKEN },
    region: settings.region,
    profile: { httpProfile: { reqTimeout: 30,
      ...(endpoint ? { endpoint: endpoint.host, protocol: endpoint.protocol + '//' } :
        { proxy: process.env.HTTPS_PROXY ?? process.env.https_proxy }) } },
  });
  const request = (action, parameters, signal) => client.request(action, parameters, { signal });

  async function describe(instanceId, signal) {
    try {
      const response = await request('DescribeInstances', { InstanceIds: [instanceId] }, signal);
      return response.InstanceSet?.find(instance => instance.InstanceId === instanceId);
    } catch (error) {
      // DEFENSE: Tencent returns NotFound after an instance has already been reclaimed or destroyed.
      if (error.code === 'InvalidInstanceId.NotFound') return undefined;
      throw error;
    }
  }

  return {
    kind: 'tencent_cvm',
    request(token, taskId) {
      return { InstanceChargeType: 'SPOTPAID', InstanceCount: 1, MinCount: 1,
        Placement: { Zone: settings.zone }, ImageId: settings.image_id, InstanceType: settings.instance_type,
        VirtualPrivateCloud: { VpcId: settings.vpc_id, SubnetId: settings.subnet_id },
        InternetAccessible: { PublicIpAssigned: settings.address_type !== 'private',
          InternetMaxBandwidthOut: settings.internet_max_bandwidth_out ?? 5, InternetChargeType: 'TRAFFIC_POSTPAID_BY_HOUR' },
        SecurityGroupIds: settings.security_group_ids, LoginSettings: { KeyIds: [settings.key_id] },
        InstanceName: `selvedge-task-${taskId}`, ClientToken: token,
        InstanceMarketOptions: { MarketType: 'spot', SpotOptions: { MaxPrice: settings.spot_max_price, SpotInstanceType: 'one-time' } },
        TagSpecification: [{ ResourceType: 'instance', Tags: [{ Key: 'selvedge-task', Value: token }] }] };
    },
    async create(parameters, { signal } = {}) {
      let response;
      try { response = await request('RunInstances', parameters, signal); }
      catch (error) {
        // DEFENSE: The SDK reserves code for API rejections; transport failures can follow a successful, unobserved allocation.
        if (error.code) error.allocationRejected = true;
        throw error;
      }
      if (!Array.isArray(response.InstanceIdSet) || response.InstanceIdSet.length !== 1) {
        throw new Error('Tencent CVM creation did not return exactly one instance');
      }
      return response.InstanceIdSet[0];
    },
    async ready(instanceId, { signal, deadline } = {}) {
      while (Date.now() < deadline) {
        signal?.throwIfAborted();
        const instance = await describe(instanceId, signal);
        if (instance?.InstanceState === 'RUNNING') {
          const addresses = settings.address_type === 'private' ? instance.PrivateIpAddresses : instance.PublicIpAddresses;
          if (addresses?.length) return { instance_id: instanceId, host: addresses[0] };
        }
        if (['LAUNCH_FAILED', 'TERMINATED'].includes(instance?.InstanceState)) {
          throw new Error(`Tencent CVM failed to start (${instance.InstanceState})`);
        }
        await delay(Math.min(2000, Math.max(1, deadline - Date.now())), undefined, { signal });
      }
      throw new Error('Tencent CVM startup deadline exceeded');
    },
    async destroy(instanceId, { signal, deadline = Date.now() + 120_000 } = {}) {
      const existing = await describe(instanceId, signal);
      if (!existing || existing.InstanceState === 'TERMINATED') return;
      try { await request('TerminateInstances', { InstanceIds: [instanceId], ReleaseAddress: true }, signal); }
      catch (error) {
        // DEFENSE: The spot scheduler may reclaim the instance between observation and termination.
        if (error.code !== 'InvalidInstanceId.NotFound') throw error;
        return;
      }
      while (Date.now() < deadline) {
        const instance = await describe(instanceId, signal);
        if (!instance || instance.InstanceState === 'TERMINATED') return;
        await delay(Math.min(2000, Math.max(1, deadline - Date.now())), undefined, { signal });
      }
      throw new Error(`Tencent CVM destruction deadline exceeded (${instanceId})`);
    },
  };
}

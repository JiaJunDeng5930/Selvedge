import tencentcloud from 'tencentcloud-sdk-nodejs-cvm';
import { CommonClient } from 'tencentcloud-sdk-nodejs-common';
import { boundary } from './public/model-boundary.mjs';
import { setTimeout as delay } from 'node:timers/promises';

const { Client } = tencentcloud.cvm.v20170312;

/** CVM owns allocation and destruction; execution is the separate SSH boundary. */
export function tencentCvmBackend(settings) {
  if (!process.env.TENCENTCLOUD_SECRET_ID || !process.env.TENCENTCLOUD_SECRET_KEY) {
    throw new Error('Tencent CVM requires TENCENTCLOUD_SECRET_ID and TENCENTCLOUD_SECRET_KEY in the service environment');
  }
  // Credentials are a per-operation snapshot: identity and allocation use the same signer.
  const credential = { secretId: process.env.TENCENTCLOUD_SECRET_ID,
    secretKey: process.env.TENCENTCLOUD_SECRET_KEY, token: process.env.TENCENTCLOUD_TOKEN };
  const endpoint = settings.api_endpoint ? new URL(settings.api_endpoint) : undefined;
  const configuration = { credential, region: settings.region,
    profile: { httpProfile: { reqTimeout: 30,
      ...(endpoint ? { endpoint: endpoint.host, protocol: endpoint.protocol + '//' } :
        { proxy: process.env.HTTPS_PROXY ?? process.env.https_proxy }) } } };
  const client = new Client(configuration);
  const identity = new CommonClient('sts.tencentcloudapi.com', '2018-08-13', configuration);
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
      return boundary('control.resource.request', { settings, token, task_id: taskId });
    },
    async scope({ signal } = {}) {
      const response = await identity.request('GetCallerIdentity', {}, { signal });
      // DEFENSE: Identity responses without an owning account cannot authorize billable allocation.
      if (typeof response.AccountId !== 'string' || !/^[0-9]+$/.test(response.AccountId)) {
        throw new Error('Tencent identity did not return the owning AccountId');
      }
      return { provider: 'tencent_cvm', account_id: response.AccountId, region: settings.region,
        endpoint: endpoint ? endpoint.origin : 'https://cvm.tencentcloudapi.com',
        credential_reference: 'service-environment:TENCENTCLOUD' };
    },
    async create(parameters, { signal } = {}) {
      // Every exception after dispatch is unknown, including API and response-body errors.
      // Recovery uses only DescribeInstances; it never replays this request.
      const response = await request('RunInstances', parameters, signal);
      return { ids: Array.isArray(response.InstanceIdSet) ? response.InstanceIdSet : [],
        complete: typeof response.RequestId === 'string' && response.RequestId.length > 0 &&
          Array.isArray(response.InstanceIdSet) && response.InstanceIdSet.length === 1 &&
          typeof response.InstanceIdSet[0] === 'string' && response.InstanceIdSet[0].length > 0 };
    },
    async scan(token, offset, { signal } = {}) {
      const response = await request('DescribeInstances', {
        Filters: [{ Name: 'tag:selvedge-task', Values: [token] }], Offset: offset, Limit: 100,
      }, signal);
      // DEFENSE: An interrupted or malformed page cannot establish the absence of a paid allocation.
      if (!Array.isArray(response.InstanceSet) || !Number.isSafeInteger(response.TotalCount) || response.TotalCount < 0) {
        throw new Error('Tencent reconciliation returned an incomplete instance page');
      }
      return { instances: response.InstanceSet, total: response.TotalCount };
    },
    async ready(instanceId, { signal, deadline } = {}) {
      while (true) {
        signal?.throwIfAborted();
        const instance = await describe(instanceId, signal);
        const plan = boundary('control.resource.provider', {
          operation: 'ready', instance: instance ?? null, settings, now: Date.now(), deadline,
        });
        if (plan.action === 'ready') return { instance_id: instanceId, host: plan.host };
        if (plan.action === 'failed') throw new Error(`Tencent CVM failed to start (${instance.InstanceState})`);
        if (plan.action === 'timeout') throw new Error('Tencent CVM startup deadline exceeded');
        await delay(Math.min(2000, Math.max(1, deadline - Date.now())), undefined, { signal });
      }
    },
    async destroy(instanceId, { signal, deadline = Date.now() + 120_000 } = {}) {
      let operation = 'destroy_before';
      while (true) {
        const instance = await describe(instanceId, signal);
        const plan = boundary('control.resource.provider', {
          operation, instance: instance ?? null, settings, now: Date.now(), deadline,
        });
        if (plan.action === 'done') return;
        if (plan.action === 'timeout') throw new Error(`Tencent CVM destruction deadline exceeded (${instanceId})`);
        if (plan.action === 'terminate') {
          try { await request('TerminateInstances', { InstanceIds: [instanceId], ReleaseAddress: true }, signal); }
          catch (error) {
            // DEFENSE: Spot reclamation can complete between the observation and termination request.
            if (error.code !== 'InvalidInstanceId.NotFound') throw error;
            return;
          }
          operation = 'destroy_after';
        } else await delay(Math.min(2000, Math.max(1, deadline - Date.now())), undefined, { signal });
      }
    },
  };
}

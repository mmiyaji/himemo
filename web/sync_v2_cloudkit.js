'use strict';
// CloudKit JS bridge for the existing v2 encrypted record protocol. Configure
// only with a CloudKit Dashboard API token; no decrypted note data is passed.
(function (root) {
  const idPattern = /^[A-Za-z0-9_-]{1,80}$/;
  const maxPayload = 16 * 1024 * 1024;
  const maxHeader = 65536;
  let container;
  let database;
  let writesEnabled = false;
  let sandboxNamespace = null;
  let sessionRevision = 0;
  let signOutPromise;
  const fail = code => { const error = new Error(code); error.safeCode = code; throw error; };
  const encodedBytes = text => new TextEncoder().encode(text).length;
  function identifier(value) { if (typeof value !== 'string' || !idPattern.test(value)) fail('cloudkit_v2_invalidRequest'); return value; }
  function serverCode(error) {
    const raw = error && (error.serverErrorCode || error.ckErrorCode);
    const extension = error && error.extensionErrorCode;
    if (raw === 'NOT_FOUND' || raw === 'UNKNOWN_ITEM') return '11';
    if (raw === 'ZONE_NOT_FOUND') return '26';
    if (raw === 'USER_DELETED_ZONE' || extension === 'USER_DELETED_ZONE') return '28';
    if (raw === 'CHANGE_TOKEN_EXPIRED' || extension === 'CHANGE_TOKEN_EXPIRED') return 'cloudkit_v2_cursor_expired';
    if (raw === 'AUTHENTICATION_REQUIRED' || raw === 'AUTHENTICATION_FAILED') return 'cloudkit_v2_signedOut';
    return 'cloudkit_v2_unavailable';
  }
  function check(response) {
    if (!response || response.isError || response.hasErrors || (Array.isArray(response.errors) && response.errors.length)) {
      const error = response && (response.isError ? response : response.errors && response.errors[0]);
      fail(serverCode(error));
    }
    return response;
  }
  function unbase64(value) {
    if (typeof value !== 'string' || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) fail('cloudkit_v2_invalidRequest');
    const binary = atob(value); const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }
  function base64(bytes) { let result = ''; for (let i = 0; i < bytes.length; i += 32768) result += String.fromCharCode(...bytes.subarray(i, i + 32768)); return btoa(result); }
  async function account() {
    if (!container || !database) fail('cloudkit_v2_notConfigured');
    const user = await container.fetchCurrentUserIdentity();
    if (!user || typeof user.userRecordName !== 'string' || !user.userRecordName) fail('cloudkit_v2_signedOut');
    return user.userRecordName;
  }
  async function scope(args) {
    const current = await account();
    if (args.accountId !== current) fail('cloudkit_v2_accountChanged');
    return sandboxNamespace
      ? 'HiMemoSyncV2WebTest-' + sandboxNamespace + '-' + identifier(args.generationId)
      : 'HiMemoSyncV2-' + identifier(args.generationId);
  }
  async function fetchRecord(zone, id) {
    const result = check(await database.fetchRecords(identifier(id), {zoneID: zone}));
    if (!Array.isArray(result.records) || result.records.length !== 1) fail('cloudkit_v2_invalidRecord');
    const record = result.records[0];
    if (!record || record.recordName !== id || record.recordType !== 'HiMemoSyncV2Change' || record.deleted) fail('cloudkit_v2_invalidRecord');
    return record;
  }
  function matchesZone(response, zone) {
    const zones = response && response.zones;
    const returned = Array.isArray(zones) && zones.length === 1 && zones[0].zoneID;
    return !!returned && (typeof returned === 'string' ? returned : returned.zoneName) === zone;
  }
  function headerOf(record) {
    const value = record.fields && record.fields.encryptedHeader && record.fields.encryptedHeader.value;
    if (typeof value !== 'string' || !value || encodedBytes(value) > maxHeader) fail('cloudkit_v2_invalidRecord');
    return value;
  }
  async function payloadOf(record) {
    const asset = record.fields && record.fields.encryptedPayload && record.fields.encryptedPayload.value;
    if (asset == null) return null;
    if (typeof asset.downloadURL !== 'string') fail('cloudkit_v2_invalidRecord');
    const url = new URL(asset.downloadURL.replace('${f}', 'payload'));
    if (url.protocol !== 'https:') fail('cloudkit_v2_invalidRecord');
    const response = await fetch(url.toString(), {credentials:'omit', redirect:'error', cache:'no-store'});
    if (!response.ok) fail('cloudkit_v2_unavailable');
    const length = Number(response.headers.get('content-length'));
    if (length > maxPayload) fail('cloudkit_v2_invalidRecord');
    let bytes;
    if (response.body && typeof response.body.getReader === 'function') {
      const reader = response.body.getReader();
      const parts = []; let total = 0;
      try {
        for (;;) {
          const chunk = await reader.read();
          if (chunk.done) break;
          if (!(chunk.value instanceof Uint8Array)) fail('cloudkit_v2_invalidRecord');
          total += chunk.value.length;
          if (total > maxPayload) { await reader.cancel(); fail('cloudkit_v2_invalidRecord'); }
          parts.push(chunk.value);
        }
      } finally { reader.releaseLock(); }
      bytes = new Uint8Array(total);
      let offset = 0; for (const part of parts) { bytes.set(part, offset); offset += part.length; }
    } else {
      if (!Number.isFinite(length) || length <= 0 || length > maxPayload) fail('cloudkit_v2_invalidRecord');
      bytes = new Uint8Array(await response.arrayBuffer());
    }
    if (!bytes.length || bytes.length > maxPayload) fail('cloudkit_v2_invalidRecord');
    return bytes;
  }
  async function invoke(method, args) {
    if (method === 'cloudKitV2AccountId') return await account();
    const boundDatabase = database;
    const revision = sessionRevision;
    const zone = await scope(args);
    if (database !== boundDatabase || revision !== sessionRevision) fail('cloudkit_v2_accountChanged');
    let value;
    if (method === 'cloudKitV2Prepare') {
      if (!writesEnabled) fail('cloudkit_v2_writeDisabled');
      try {
        if (!matchesZone(check(await database.saveRecordZones(zone)), zone)) fail('cloudkit_v2_invalidRecord');
      }
      catch (original) {
        let existing;
        try { existing = check(await database.fetchRecordZones(zone)); } catch (_) { throw original; }
        if (!matchesZone(existing, zone)) throw original;
      }
      value = null;
    } else if (method === 'cloudKitV2FetchHeader') {
      value = headerOf(await fetchRecord(zone, args.id));
    } else if (method === 'cloudKitV2FetchPayload') {
      const bytes = await payloadOf(await fetchRecord(zone, args.id));
      if (!bytes) fail('cloudkit_v2_invalidRecord'); value = base64(bytes);
    } else if (method === 'cloudKitV2FetchHeaders') {
      if (!Number.isInteger(args.limit) || args.limit < 1 || args.limit > 200 || (args.cursor != null && (typeof args.cursor !== 'string' || !args.cursor))) fail('cloudkit_v2_invalidRequest');
      const options = {zoneID: {zoneName: zone}, desiredKeys: ['encryptedHeader'], resultsLimit:args.limit};
      if (args.cursor != null) options.syncToken = args.cursor;
      // The CloudKit JS SDK passes resultsLimit to changes/zone. Still never
      // advance the token if a server returns more than can be staged.
      const response = check(await database.fetchRecordZoneChanges(options));
      if (!Array.isArray(response.zones) || response.zones.length !== 1) fail('cloudkit_v2_invalidRecord');
      const changes = response.zones[0];
      if (!changes || typeof changes.syncToken !== 'string' || !changes.syncToken || typeof changes.moreComing !== 'boolean' || !Array.isArray(changes.records) || (changes.errors != null && !Array.isArray(changes.errors))) fail('cloudkit_v2_invalidRecord');
      if (changes.zoneID != null && (typeof changes.zoneID === 'string' ? changes.zoneID : changes.zoneID.zoneName) !== zone) fail('cloudkit_v2_invalidRecord');
      const errors = changes.errors || [];
      if (changes.records.length + errors.length > args.limit) fail('cloudkit_v2_pageTooLarge');
      const headers = [], issues = [];
      for (const error of errors) {
        const code = serverCode(error);
        if (code === 'cloudkit_v2_cursor_expired' || code === 'cloudkit_v2_signedOut' || code === '26' || code === '28') fail(code);
        const id = error && error.recordName;
        if (typeof id !== 'string' || !id || encodedBytes(id) > 1024) fail(code);
        issues.push({id, reason:'record_unavailable'});
      }
      for (const record of changes.records) {
        const id = record && record.recordName;
        if (typeof id !== 'string' || !id || encodedBytes(id) > 1024) fail('cloudkit_v2_invalidRecord');
        if (!idPattern.test(id)) { issues.push({id, reason:'invalid_record'}); continue; }
        if (record.deleted === true) { issues.push({id, reason:'remote_deleted'}); continue; }
        try { if (record.recordType !== 'HiMemoSyncV2Change') throw new Error(); headers.push({id, header:headerOf(record)}); }
        catch (_) { issues.push({id, reason:'invalid_record'}); }
      }
      value = {cursor:changes.syncToken, hasMore:changes.moreComing, headers, issues};
    } else if (method === 'cloudKitV2Publish') {
      if (!writesEnabled) fail('cloudkit_v2_writeDisabled');
      identifier(args.id);
      if (typeof args.header !== 'string' || !args.header || encodedBytes(args.header) > maxHeader) fail('cloudkit_v2_invalidRequest');
      const payload = args.payload == null ? null : unbase64(args.payload);
      if (payload && (!payload.length || payload.length > maxPayload)) fail('cloudkit_v2_invalidRequest');
      const fields = {encryptedHeader: {value: args.header}};
      if (payload) fields.encryptedPayload = {value: new Blob([payload])};
      // Use the explicit CloudKit create operation, never createOrUpdate.
      // On ambiguous failure read back and accept only byte-identical data.
      try {
        const batch = database.newRecordsBatch({zoneID:zone, atomic:true});
        batch.create({recordName:args.id, recordType:'HiMemoSyncV2Change', fields});
        const saved = check(await batch.commit());
        if (!Array.isArray(saved.records) || saved.records.length !== 1 || saved.records[0].recordName !== args.id || saved.records[0].recordType !== 'HiMemoSyncV2Change' || headerOf(saved.records[0]) !== args.header || (!!saved.records[0].fields.encryptedPayload) !== !!payload) fail('cloudkit_v2_invalidRecord');
      }
      catch (original) {
        let existing; try { existing = await fetchRecord(zone, args.id); } catch (_) { throw original; }
        const oldPayload = await payloadOf(existing);
        if (headerOf(existing) !== args.header || (oldPayload === null) !== (payload === null) || (payload && (payload.length !== oldPayload.length || payload.some((byte, i) => byte !== oldPayload[i])))) fail('cloudkit_v2_recordCollision');
      }
      value = null;
    } else fail('cloudkit_v2_invalidRequest');
    if (database !== boundDatabase || revision !== sessionRevision || await account() !== args.accountId || revision !== sessionRevision) fail('cloudkit_v2_accountChanged');
    return value;
  }
  async function result(operation) {
    try { return JSON.stringify({ok:true, value: await operation()}); }
    catch (error) { return JSON.stringify({ok:false, code: error && error.safeCode || serverCode(error)}); }
  }
  function clearSession() {
    sessionRevision++;
    container = null;
    database = null;
    sandboxNamespace = null;
    writesEnabled = false;
    signOutPromise = null;
  }
  root.himemoCloudKitV2 = {
    configure: optionsJson => result(async () => {
      clearSession();
      const revision = sessionRevision;
      const options = JSON.parse(optionsJson);
      if (!root.CloudKit || !options || typeof options.containerIdentifier !== 'string' || !options.containerIdentifier || typeof options.apiToken !== 'string' || !options.apiToken || !['development','production'].includes(options.environment)) fail('cloudkit_v2_notConfigured');
      // This Web bridge has never been validated against live CloudKit writes.
      // Production must remain read-only even if a caller enables writes.
      if (options.environment === 'production' && options.enableWrites === true) fail('cloudkit_v2_writeDisabled');
      const sandbox = options.sandboxNamespace;
      if (sandbox != null && (options.environment !== 'development' || typeof sandbox !== 'string' || !/^[A-Za-z0-9_-]{16,32}$/.test(sandbox))) fail('cloudkit_v2_notConfigured');
      if (options.enableWrites === true && !sandbox) fail('cloudkit_v2_writeDisabled');
      // CloudKit errors are surfaced as fixed safe codes, not SDK logs that may
      // contain request metadata or credentials.
      const noLog = () => {};
      root.CloudKit.configure({containers:[{containerIdentifier:options.containerIdentifier, environment:options.environment, apiTokenAuth:{apiToken:options.apiToken, persist:false}}], services:{logger:{info:noLog,log:noLog,warn:noLog,error:noLog}}});
      const configured = root.CloudKit.getDefaultContainer();
      const identity = await configured.setUpAuth();
      if (revision !== sessionRevision) fail('cloudkit_v2_accountChanged');
      container = configured; database = configured.privateCloudDatabase;
      sandboxNamespace = sandbox || null;
      writesEnabled = options.enableWrites === true;
      try {
        if (typeof configured.whenUserSignsOut !== 'function') fail('cloudkit_v2_notConfigured');
        signOutPromise = Promise.resolve(configured.whenUserSignsOut());
        signOutPromise.then(() => {
          if (revision === sessionRevision && container === configured) clearSession();
        }).catch(() => {});
      } catch (error) {
        if (revision === sessionRevision) clearSession();
        throw error;
      }
      return !!(identity && identity.userRecordName);
    }),
    waitForSignIn: () => result(async () => {
      const configured = container;
      const revision = sessionRevision;
      if (!configured) fail('cloudkit_v2_notConfigured');
      const identity = await configured.whenUserSignsIn();
      if (revision !== sessionRevision || configured !== container) fail('cloudkit_v2_accountChanged');
      if (!identity || typeof identity.userRecordName !== 'string' || !identity.userRecordName) fail('cloudkit_v2_signedOut');
      return identity.userRecordName;
    }),
    waitForSignOut: () => result(async () => {
      const pending = signOutPromise;
      if (!pending) fail('cloudkit_v2_notConfigured');
      await pending;
      return null;
    }),
    // Drops this bridge's references; the CloudKit-managed sign-out button is
    // still responsible for ending the Apple session itself.
    disconnect: () => result(async () => { clearSession(); return null; }),
    invoke: (method, argsJson) => result(() => invoke(method, JSON.parse(argsJson)))
  };
})(globalThis);

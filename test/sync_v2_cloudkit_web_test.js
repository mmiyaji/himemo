'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
require('../web/sync_v2_cloudkit.js');
const bridge = globalThis.himemoCloudKitV2;
const decode = async p => JSON.parse(await p);

function fixture() {
  let current = 'account-A';
  let signalSignIn, signalSignOut;
  const signedIn = new Promise(resolve => { signalSignIn = resolve; });
  const signedOut = new Promise(resolve => { signalSignOut = resolve; });
  const saved = new Map();
  let changes = {syncToken:'token-1', moreComing:false, records:[]};
  let overrideSave;
  const db = {
    async saveRecordZones(zone) { return {zones:[{zoneID:{zoneName:zone}}], hasErrors:false}; },
    async fetchRecords(id) {
      if (!saved.has(id)) return {hasErrors:true, errors:[{serverErrorCode:'NOT_FOUND'}]};
      return {hasErrors:false, records:[saved.get(id)]};
    },
    async fetchRecordZoneChanges(options) { assert.match(options.zoneID.zoneName, /^HiMemoSyncV2(?:WebTest-isolated-test-01)?-generation-A$/); assert.ok(Number.isInteger(options.resultsLimit)); return {hasErrors:false, zones:[changes]}; },
    async saveRecords(record) {
      if (overrideSave) return overrideSave(record);
      if (saved.has(record.recordName)) return {hasErrors:true, errors:[{serverErrorCode:'SERVER_RECORD_CHANGED'}]};
      saved.set(record.recordName, record);
      return {hasErrors:false, records:[record]};
    },
    newRecordsBatch(options) {
      assert.equal(options.atomic, true);
      assert.equal(options.zoneID, 'HiMemoSyncV2WebTest-isolated-test-01-generation-A');
      let record;
      return {create(value) {record = value; return this;}, async commit() {return db.saveRecords(record);}};
    },
  };
  const container = {privateCloudDatabase:db, async setUpAuth(){return current ? {userRecordName:current} : null;}, async fetchCurrentUserIdentity(){return current ? {userRecordName:current} : null;}, whenUserSignsIn(){return signedIn;}, whenUserSignsOut(){return signedOut;}};
  globalThis.CloudKit = {configure(){}, getDefaultContainer(){return container;}};
  return {saved, setUser(value){current=value;}, setChanges(value){changes=value;}, setSave(value){overrideSave=value;}, signIn(value){current=value;signalSignIn({userRecordName:value});}, signOut(){current=null;signalSignOut();}};
}
async function initialize() {
  const response = await decode(bridge.configure(JSON.stringify({containerIdentifier:'iCloud.test',apiToken:'test-token',environment:'development',enableWrites:true,sandboxNamespace:'isolated-test-01'})));
  assert.equal(response.ok, true);
}
const call = (method, args = {}) => decode(bridge.invoke(method, JSON.stringify(args)));
const scope = {accountId:'account-A',generationId:'generation-A'};

test('configuration requires CloudKit and explicit token', async () => {
  fixture();
  await initialize();
  const response = await decode(bridge.configure(JSON.stringify({containerIdentifier:'iCloud.test',environment:'production'})));
  assert.deepEqual(response, {ok:false,code:'cloudkit_v2_notConfigured'});
  assert.deepEqual(await call('cloudKitV2AccountId'), {ok:false,code:'cloudkit_v2_notConfigured'});
});

test('account changes fail closed and metadata is scoped', async () => {
  const f = fixture(); await initialize();
  assert.equal((await call('cloudKitV2AccountId')).value, 'account-A');
  assert.equal((await call('cloudKitV2Prepare',scope)).ok, true);
  f.setUser('account-B');
  assert.deepEqual(await call('cloudKitV2Prepare',scope), {ok:false,code:'cloudkit_v2_accountChanged'});
});

test('zone preparation accepts an existing matching zone on retry', async () => {
  const f = fixture(); await initialize();
  const db = globalThis.CloudKit.getDefaultContainer().privateCloudDatabase;
  db.saveRecordZones = async () => ({hasErrors:true,errors:[{serverErrorCode:'ZONE_ALREADY_EXISTS'}]});
  db.fetchRecordZones = async zone => ({hasErrors:false,zones:[{zoneID:{zoneName:zone}}]});
  assert.equal((await call('cloudKitV2Prepare',scope)).ok, true);
  db.fetchRecordZones = async () => ({hasErrors:false,zones:[{zoneID:{zoneName:'other'}}]});
  assert.deepEqual(await call('cloudKitV2Prepare',scope), {ok:false,code:'cloudkit_v2_unavailable'});
  f.setUser('account-B');
  assert.equal((await call('cloudKitV2Prepare',scope)).ok, false);
});

test('writes remain disabled in both environments', async () => {
  for (const environment of ['development', 'production']) {
    const f = fixture();
    const configured = await decode(bridge.configure(JSON.stringify({containerIdentifier:'iCloud.test',apiToken:'test-token',environment,enableWrites:false})));
    assert.equal(configured.ok, true);
    assert.deepEqual(await call('cloudKitV2Publish',{...scope,id:'one',header:'cipher'}), {ok:false,code:'cloudkit_v2_writeDisabled'});
    assert.deepEqual(await call('cloudKitV2Prepare',scope), {ok:false,code:'cloudkit_v2_writeDisabled'});
    assert.equal(f.saved.size, 0);
  }
});

test('production cannot enable writes even with explicit opt-in', async () => {
  const f = fixture();
  const configured = await decode(bridge.configure(JSON.stringify({containerIdentifier:'iCloud.test',apiToken:'test-token',environment:'production',enableWrites:true})));
  assert.deepEqual(configured, {ok:false,code:'cloudkit_v2_writeDisabled'});
  assert.equal(f.saved.size, 0);
});

test('development writes require an explicit isolated namespace', async () => {
  const f = fixture();
  for (const sandboxNamespace of [undefined, 'short', 'invalid/path/12345']) {
    const result = await decode(bridge.configure(JSON.stringify({containerIdentifier:'iCloud.test',apiToken:'test-token',environment:'development',enableWrites:true,sandboxNamespace})));
    assert.equal(result.ok, false);
    assert.equal(f.saved.size, 0);
  }
});

test('sandbox metadata and generation use only isolated zone prefixes', async () => {
  fixture(); await initialize();
  const zones = [];
  const db = globalThis.CloudKit.getDefaultContainer().privateCloudDatabase;
  db.saveRecordZones = async zone => { zones.push(zone); return {zones:[{zoneID:{zoneName:zone}}],hasErrors:false}; };
  assert.equal((await call('cloudKitV2Prepare',{...scope,generationId:'metadata-v1'})).ok, true);
  assert.equal((await call('cloudKitV2Prepare',scope)).ok, true);
  assert.deepEqual(zones, ['HiMemoSyncV2WebTest-isolated-test-01-metadata-v1','HiMemoSyncV2WebTest-isolated-test-01-generation-A']);
});

test('disconnect prevents a pending sandbox request from starting a write', async () => {
  fixture(); await initialize();
  const container = globalThis.CloudKit.getDefaultContainer();
  let release;
  let reached;
  const pendingIdentity = new Promise(resolve => { release = resolve; });
  const started = new Promise(resolve => { reached = resolve; });
  let writes = 0;
  container.fetchCurrentUserIdentity = () => { reached(); return pendingIdentity; };
  container.privateCloudDatabase.saveRecordZones = async () => { writes++; throw Error('unexpected write'); };
  const request = call('cloudKitV2Prepare', scope);
  await started;
  await decode(bridge.disconnect());
  release({userRecordName:'account-A'});
  assert.deepEqual(await request, {ok:false,code:'cloudkit_v2_accountChanged'});
  assert.equal(writes, 0);
});

test('create-only records accept identical replay, reject changed content', async () => {
  fixture(); await initialize();
  const args = {...scope,id:'record-A',header:'ciphertext'};
  assert.equal((await call('cloudKitV2Publish',args)).ok, true);
  assert.equal((await call('cloudKitV2Publish',args)).ok, true);
  assert.deepEqual(await call('cloudKitV2Publish',{...args,header:'other'}), {ok:false,code:'cloudkit_v2_recordCollision'});
  assert.equal((await call('cloudKitV2FetchHeader',args)).value, 'ciphertext');
});

test('an empty save response is not treated as a publication acknowledgement', async () => {
  const f = fixture(); await initialize();
  f.setSave(() => ({hasErrors:false,records:[]}));
  assert.deepEqual(await call('cloudKitV2Publish',{...scope,id:'missing',header:'cipher'}), {ok:false,code:'cloudkit_v2_invalidRecord'});
});

test('change pages preserve deletes and reject oversized pages without cursor', async () => {
  const f = fixture(); await initialize();
  f.setChanges({syncToken:'next',moreComing:true,records:[{recordName:'one',recordType:'HiMemoSyncV2Change',fields:{encryptedHeader:{value:'a'}}},{recordName:'two',deleted:true}]});
  const result = await call('cloudKitV2FetchHeaders',{...scope,limit:2});
  assert.deepEqual(result.value, {cursor:'next',hasMore:true,headers:[{id:'one',header:'a'}],issues:[{id:'two',reason:'remote_deleted'}]});
  const oversized = await call('cloudKitV2FetchHeaders',{...scope,limit:1});
  assert.deepEqual(oversized, {ok:false,code:'cloudkit_v2_pageTooLarge'});
  assert.equal('value' in oversized, false);
});

test('zone-level errors do not advance cursor', async () => {
  const f = fixture(); await initialize();
  f.setChanges({syncToken:'next',moreComing:false,records:[],errors:[{serverErrorCode:'SERVICE_UNAVAILABLE'}]});
  const result = await call('cloudKitV2FetchHeaders',{...scope,limit:20});
  assert.deepEqual(result, {ok:false,code:'cloudkit_v2_unavailable'});
});

test('expired token, sign-out and malformed record IDs do not lose changes', async () => {
  const f = fixture(); await initialize();
  f.setChanges({syncToken:'next',moreComing:false,records:[],errors:[{serverErrorCode:'CHANGE_TOKEN_EXPIRED'}]});
  assert.deepEqual(await call('cloudKitV2FetchHeaders',{...scope,limit:20}), {ok:false,code:'cloudkit_v2_cursor_expired'});
  f.setChanges({syncToken:'next',moreComing:false,records:[],errors:[{serverErrorCode:'BAD_REQUEST',extensionErrorCode:'CHANGE_TOKEN_EXPIRED'}]});
  assert.deepEqual(await call('cloudKitV2FetchHeaders',{...scope,limit:20}), {ok:false,code:'cloudkit_v2_cursor_expired'});
  f.setChanges({syncToken:'next',moreComing:false,records:[{recordName:'invalid/id',deleted:true}],errors:[]});
  const page = await call('cloudKitV2FetchHeaders',{...scope,limit:20});
  assert.deepEqual(page.value.issues, [{id:'invalid/id',reason:'invalid_record'}]);
  f.setChanges({syncToken:'next',moreComing:false,records:[],errors:[{serverErrorCode:'AUTHENTICATION_REQUIRED'}]});
  assert.deepEqual(await call('cloudKitV2FetchHeaders',{...scope,limit:20}), {ok:false,code:'cloudkit_v2_signedOut'});
});

test('sign in awaits Apple and sign out clears the bridge session', async () => {
  const f = fixture(); f.setUser(null);
  const configured = await decode(bridge.configure(JSON.stringify({containerIdentifier:'iCloud.test',apiToken:'test-token',environment:'development'})));
  assert.deepEqual(configured, {ok:true,value:false});
  const waiting = decode(bridge.waitForSignIn());
  f.signIn('account-A');
  assert.deepEqual(await waiting, {ok:true,value:'account-A'});
  assert.deepEqual(await call('cloudKitV2AccountId'), {ok:true,value:'account-A'});
  const signOut = decode(bridge.waitForSignOut());
  f.signOut(); await Promise.resolve(); await Promise.resolve();
  assert.deepEqual(await signOut, {ok:true,value:null});
  assert.deepEqual(await call('cloudKitV2AccountId'), {ok:false,code:'cloudkit_v2_notConfigured'});
});

test('disconnect invalidates an in-flight sign-in', async () => {
  const f = fixture(); f.setUser(null);
  await decode(bridge.configure(JSON.stringify({containerIdentifier:'iCloud.test',apiToken:'test-token',environment:'development'})));
  const waiting = decode(bridge.waitForSignIn());
  assert.deepEqual(await decode(bridge.disconnect()), {ok:true,value:null});
  f.signIn('account-A');
  assert.deepEqual(await waiting, {ok:false,code:'cloudkit_v2_accountChanged'});
});

test('a response for a different zone cannot advance the cursor', async () => {
  const f = fixture(); await initialize();
  f.setChanges({zoneID:{zoneName:'HiMemoSyncV2-other'},syncToken:'next',moreComing:false,records:[]});
  assert.deepEqual(await call('cloudKitV2FetchHeaders',{...scope,limit:20}), {ok:false,code:'cloudkit_v2_invalidRecord'});
});

test('asset publication uses Blob and output errors do not expose secrets', async () => {
  const f = fixture(); await initialize();
  f.setSave(record => {assert.ok(record.fields.encryptedPayload.value instanceof Blob); throw new Error('secret diagnostic');});
  const response = await call('cloudKitV2Publish',{...scope,id:'record-B',header:'safe',payload:'AQID'});
  assert.deepEqual(response, {ok:false,code:'cloudkit_v2_unavailable'});
  assert.doesNotMatch(JSON.stringify(response),/secret/);
});

test('asset replay compares all encrypted bytes and rejects changed content', async () => {
  const f = fixture(); await initialize();
  f.saved.set('record-B', {recordName:'record-B',recordType:'HiMemoSyncV2Change',fields:{
    encryptedHeader:{value:'cipher'}, encryptedPayload:{value:{downloadURL:'https://assets.example/${f}'}}
  }});
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(new Uint8Array([1,2,3]));
  try {
    const args = {...scope,id:'record-B',header:'cipher',payload:'AQID'};
    assert.deepEqual(await call('cloudKitV2Publish',args), {ok:true,value:null});
    assert.deepEqual(await call('cloudKitV2Publish',{...args,payload:'AQIE'}), {ok:false,code:'cloudkit_v2_recordCollision'});
    assert.deepEqual(await call('cloudKitV2FetchPayload',args), {ok:true,value:'AQID'});
  } finally { globalThis.fetch = originalFetch; }
});

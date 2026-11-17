'use strict';
(() => {
  const status = document.getElementById('status');
  const token = document.getElementById('token');
  const container = document.getElementById('container');
  const environment = document.getElementById('environment');
  const connect = document.getElementById('connect');
  const check = document.getElementById('check');
  const disconnect = document.getElementById('disconnect');
  let account = null;
  let revision = 0;

  function display(message) { status.textContent = message; }
  function setConnected(connected) { check.disabled = !connected; disconnect.disabled = !connected; }
  async function parse(promise) {
    try { return JSON.parse(await promise); }
    catch (_) { return {ok:false,code:'cloudkit_v2_unavailable'}; }
  }
  function message(code) {
    switch (code) {
      case 'cloudkit_v2_notConfigured': return 'CloudKitを読み込めません。APIトークンと接続環境を確認してください。';
      case 'cloudkit_v2_signedOut': return 'Appleのサインインが必要です。';
      case 'cloudkit_v2_accountChanged': return 'Appleアカウントが変更されました。接続し直してください。';
      case '11': case '26': return 'この環境に暗号化同期の登録情報が見つかりません。';
      case '28': return 'この環境のクラウド同期データは削除されています。';
      default: return '接続できませんでした。CloudKitの設定と通信を確認してください。';
    }
  }
  function requireBridge() {
    if (!globalThis.himemoCloudKitV2 || !globalThis.CloudKit) { display(message('cloudkit_v2_notConfigured')); return false; }
    return true;
  }
  async function signedIn(id, operation) {
    if (operation !== revision) return;
    account = id;
    setConnected(true);
    display('Appleにサインインしました。「登録情報を確認」を押してください。');
  }
  connect.addEventListener('click', async () => {
    const current = ++revision;
    account = null; setConnected(false);
    if (!globalThis.isSecureContext) { display('HTTPSまたはlocalhostで開いてください。'); return; }
    if (!token.value.trim()) { display('APIトークンを入力してください。'); return; }
    if (!container.value.trim()) { display('コンテナIDを入力してください。'); return; }
    if (!requireBridge()) return;
    const options = {containerIdentifier:container.value.trim(), apiToken:token.value.trim(), environment:environment.value, enableWrites:false};
    token.value = '';
    connect.disabled = true;
    display('CloudKitに接続しています。');
    const configured = await parse(globalThis.himemoCloudKitV2.configure(JSON.stringify(options)));
    options.apiToken = '';
    if (current !== revision) return;
    connect.disabled = false;
    if (!configured.ok) { display(message(configured.code)); return; }
    const signedOut = parse(globalThis.himemoCloudKitV2.waitForSignOut());
    void signedOut.then(result => {
      if (current !== revision || !result.ok) return;
      ++revision;
      account = null; setConnected(false);
      display('Appleからサインアウトしました。接続をやり直してください。');
    });
    if (configured.value) {
      const currentUser = await parse(globalThis.himemoCloudKitV2.invoke('cloudKitV2AccountId','{}'));
      if (current !== revision) return;
      if (!currentUser.ok) { display(message(currentUser.code)); return; }
      await signedIn(currentUser.value, current);
    } else {
      display('Appleのサインインボタンからサインインしてください。');
      const signed = await parse(globalThis.himemoCloudKitV2.waitForSignIn());
      if (current !== revision) return;
      if (!signed.ok) { display(message(signed.code)); return; }
      await signedIn(signed.value, current);
    }
  });
  check.addEventListener('click', async () => {
    if (!account || !requireBridge()) return;
    const current = revision;
    check.disabled = true;
    display('登録情報を確認しています。');
    const response = await parse(globalThis.himemoCloudKitV2.invoke('cloudKitV2FetchHeader', JSON.stringify({
      accountId:account, generationId:'metadata-v1', id:'active-generation-v1'
    })));
    if (current !== revision) return;
    check.disabled = false;
    if (!response.ok) { display(message(response.code)); return; }
    display('暗号化同期の登録情報を読み取れました。内容は表示していません。');
  });
  disconnect.addEventListener('click', async () => {
    ++revision; account = null; token.value = ''; setConnected(false); connect.disabled = false;
    if (globalThis.himemoCloudKitV2) await parse(globalThis.himemoCloudKitV2.disconnect());
    display('ローカル接続を解除しました。Appleからサインアウトする場合は、Appleのボタンを使用してください。');
  });
})();

part of 'home_page.dart';

String _syncProgressLabel(AppStrings strings, SyncTransferState transferState) {
  if (transferState.stage != SyncTransferStage.busy) {
    return strings.localized(
      en: 'Sync',
      ja: '同期',
      zh: '同步',
      ko: '동기화',
      es: 'Sincronizar',
      de: 'Synchronisieren',
    );
  }
  return switch (transferState.progress) {
    SyncTransferProgress.checkingRemote => strings.localized(
      en: 'Checking',
      ja: '確認中',
      zh: '检查中',
      ko: '확인 중',
      es: 'Comprobando',
      de: 'Prufen',
    ),
    SyncTransferProgress.preparingBundle => strings.localized(
      en: 'Preparing',
      ja: '準備中',
      zh: '准备中',
      ko: '준비 중',
      es: 'Preparando',
      de: 'Vorbereiten',
    ),
    SyncTransferProgress.uploadingBundle => strings.localized(
      en: 'Uploading',
      ja: 'アップロード中',
      zh: '上传中',
      ko: '업로드 중',
      es: 'Subiendo',
      de: 'Hochladen',
    ),
    SyncTransferProgress.downloadingBundle => strings.localized(
      en: 'Downloading',
      ja: 'ダウンロード中',
      zh: '下载中',
      ko: '다운로드 중',
      es: 'Descargando',
      de: 'Herunterladen',
    ),
    SyncTransferProgress.applyingBundle => strings.localized(
      en: 'Applying',
      ja: '適用中',
      zh: '应用中',
      ko: '적용 중',
      es: 'Aplicando',
      de: 'Anwenden',
    ),
    SyncTransferProgress.finalizing => strings.localized(
      en: 'Finishing',
      ja: '完了処理中',
      zh: '完成中',
      ko: '마무리 중',
      es: 'Finalizando',
      de: 'Abschliessen',
    ),
    SyncTransferProgress.none => strings.localized(
      en: 'Syncing',
      ja: '同期中',
      zh: '同步中',
      ko: '동기화 중',
      es: 'Sincronizando',
      de: 'Synchronisierung',
    ),
  };
}

String _syncProgressDescription(
  AppStrings strings,
  SyncTransferState transferState,
  SyncProvider provider,
) {
  if (transferState.stage == SyncTransferStage.busy) {
    final detail = transferState.detail;
    final completed = transferState.completedItems;
    final total = transferState.totalItems;
    if (detail != null && detail.isNotEmpty) {
      final localizedDetail = _localizedSyncProgressDetail(strings, detail);
      final itemProgress = completed != null && total != null && total > 0
          ? ' ($completed/$total)'
          : '';
      return '$localizedDetail$itemProgress';
    }
    return switch (transferState.progress) {
      SyncTransferProgress.checkingRemote => strings.localized(
        en: 'Checking the latest cloud bundle and local queue.',
        ja: 'クラウド上の最新バンドルとこの端末の未同期変更を確認しています。',
        zh: '正在检查最新云端包和本机待同步更改。',
        ko: '최신 클라우드 번들과 이 기기의 미동기화 변경 사항을 확인하고 있습니다.',
        es: 'Comprobando el ultimo paquete en la nube y la cola local.',
        de: 'Aktuelles Cloud-Paket und lokale Warteschlange werden gepruft.',
      ),
      SyncTransferProgress.preparingBundle => strings.localized(
        en: 'Preparing an encrypted bundle from local notes and attachments.',
        ja: 'ローカルのメモと添付から暗号化バンドルを準備しています。',
        zh: '正在根据本机备忘和附件准备加密包。',
        ko: '로컬 메모와 첨부 파일로 암호화 번들을 준비하고 있습니다.',
        es: 'Preparando un paquete cifrado con notas y adjuntos locales.',
        de: 'Verschlusseltes Paket aus lokalen Notizen und Anhangen wird vorbereitet.',
      ),
      SyncTransferProgress.uploadingBundle => strings.localized(
        en: 'Uploading the encrypted bundle to the selected cloud target.',
        ja: '暗号化バンドルを選択中のクラウド同期先へアップロードしています。',
        zh: '正在将加密包上传到选定的云同步目标。',
        ko: '암호화 번들을 선택한 클라우드 동기화 대상으로 업로드하고 있습니다.',
        es: 'Subiendo el paquete cifrado al destino de nube seleccionado.',
        de: 'Verschlusseltes Paket wird zum ausgewahlten Cloud-Ziel hochgeladen.',
      ),
      SyncTransferProgress.downloadingBundle => strings.localized(
        en: 'Downloading the remote bundle before applying cloud changes.',
        ja: 'クラウド側の変更を適用するため、リモートバンドルをダウンロードしています。',
        zh: '正在下载远程包以应用云端更改。',
        ko: '클라우드 변경 사항을 적용하기 위해 원격 번들을 다운로드하고 있습니다.',
        es: 'Descargando el paquete remoto antes de aplicar cambios de nube.',
        de: 'Remote-Paket wird heruntergeladen, bevor Cloud-Anderungen angewendet werden.',
      ),
      SyncTransferProgress.applyingBundle => strings.localized(
        en: 'Decrypting and applying the downloaded bundle to local notes.',
        ja: 'ダウンロードしたバンドルを復号し、ローカルのメモへ適用しています。',
        zh: '正在解密下载的包并应用到本机备忘。',
        ko: '다운로드한 번들을 복호화하여 로컬 메모에 적용하고 있습니다.',
        es: 'Descifrando y aplicando el paquete descargado a las notas locales.',
        de: 'Heruntergeladenes Paket wird entschlusselt und lokal angewendet.',
      ),
      SyncTransferProgress.finalizing => strings.localized(
        en: 'Finishing sync and updating local metadata.',
        ja: '同期を完了し、ローカルの同期情報を更新しています。',
        zh: '正在完成同步并更新本机元数据。',
        ko: '동기화를 완료하고 로컬 메타데이터를 업데이트하고 있습니다.',
        es: 'Finalizando la sincronizacion y actualizando metadatos locales.',
        de: 'Synchronisierung wird abgeschlossen und lokale Metadaten aktualisiert.',
      ),
      SyncTransferProgress.none => strings.localized(
        en: 'Cloud sync is running.',
        ja: 'クラウド同期を実行しています。',
        zh: '云同步正在运行。',
        ko: '클라우드 동기화를 실행하고 있습니다.',
        es: 'La sincronizacion en la nube esta en curso.',
        de: 'Cloud-Synchronisierung lauft.',
      ),
    };
  }
  final message = transferState.message;
  if (message != null && message.isNotEmpty) {
    return _localizedSyncTransferMessage(strings, message, provider);
  }
  return switch (transferState.stage) {
    SyncTransferStage.success => strings.localized(
      en: 'The last sync operation completed.',
      ja: '直近の同期操作は完了しています。',
      zh: '最近的同步操作已完成。',
      ko: '최근 동기화 작업이 완료되었습니다.',
      es: 'La ultima operacion de sincronizacion se completo.',
      de: 'Der letzte Synchronisierungsvorgang ist abgeschlossen.',
    ),
    SyncTransferStage.error => strings.localized(
      en: 'The last sync operation needs attention.',
      ja: '直近の同期操作で確認が必要です。',
      zh: '最近的同步操作需要确认。',
      ko: '최근 동기화 작업에 확인이 필요합니다.',
      es: 'La ultima operacion de sincronizacion requiere atencion.',
      de: 'Der letzte Synchronisierungsvorgang erfordert Aufmerksamkeit.',
    ),
    SyncTransferStage.idle || SyncTransferStage.busy => strings.localized(
      en: 'Sync is ready.',
      ja: '同期を実行できます。',
      zh: '可以同步。',
      ko: '동기화할 수 있습니다.',
      es: 'La sincronizacion esta lista.',
      de: 'Synchronisierung ist bereit.',
    ),
  };
}

String _localizedSyncProgressDetail(AppStrings strings, String detail) {
  final elapsedMatch = RegExp(r' \(\d+s\)$').firstMatch(detail);
  final elapsedSuffix = elapsedMatch?.group(0) ?? '';
  final normalizedDetail = elapsedMatch == null
      ? detail
      : detail.substring(0, elapsedMatch.start);
  return switch (normalizedDetail) {
    'Checking cloud status' => strings.localized(
      en: 'Checking cloud status',
      ja: 'クラウドの状態を確認中',
    ),
    'Requesting latest iCloud metadata' =>
      strings.localized(
            en: 'Requesting latest iCloud metadata',
            ja: '\u0069\u0043\u006c\u006f\u0075\u0064 \u306e\u6700\u65b0\u60c5\u5831\u3092\u78ba\u8a8d\u4e2d',
          ) +
          elapsedSuffix,
    'iCloud is taking longer than usual' =>
      strings.localized(
            en: 'iCloud is taking longer than usual',
            ja: '\u0069\u0043\u006c\u006f\u0075\u0064 \u306e\u5fdc\u7b54\u306b\u6642\u9593\u304c\u304b\u304b\u3063\u3066\u3044\u307e\u3059',
          ) +
          elapsedSuffix,
    'Still waiting for iCloud metadata' =>
      strings.localized(
            en: 'Still waiting for iCloud metadata',
            ja: '\u0069\u0043\u006c\u006f\u0075\u0064 \u306e\u6700\u65b0\u60c5\u5831\u3092\u5f85\u3063\u3066\u3044\u307e\u3059',
          ) +
          elapsedSuffix,
    'Requesting latest Google Drive metadata' =>
      strings.localized(
            en: 'Requesting latest Google Drive metadata',
            ja: '\u0047\u006f\u006f\u0067\u006c\u0065 \u0044\u0072\u0069\u0076\u0065 \u306e\u6700\u65b0\u60c5\u5831\u3092\u78ba\u8a8d\u4e2d',
          ) +
          elapsedSuffix,
    'Using recent cloud status' => strings.localized(
      en: 'Using recent cloud status',
      ja: '\u76f4\u8fd1\u306e\u30af\u30e9\u30a6\u30c9\u72b6\u614b\u3092\u4f7f\u7528\u4e2d',
    ),
    'Reading sync history' => strings.localized(
      en: 'Reading sync history',
      ja: '同期履歴を確認中',
    ),
    'Checking transfer size' => strings.localized(
      en: 'Checking transfer size',
      ja: '転送サイズを確認中',
    ),
    'Checking local changes' => strings.localized(
      en: 'Checking local changes',
      ja: 'この端末の変更を確認中',
    ),
    'Applying note' => strings.localized(en: 'Applying notes', ja: 'ノートを反映中'),
    'Applying attachment for note' => strings.localized(
      en: 'Applying note attachments',
      ja: 'ノートの添付ファイルを反映中',
    ),
    'Applying block attachment for note' => strings.localized(
      en: 'Applying block attachments',
      ja: 'ブロック添付ファイルを反映中',
    ),
    'Checking attachments' => strings.localized(
      en: 'Checking attachments',
      ja: '添付ファイルを確認中',
    ),
    'Checking attachment objects' => strings.localized(
      en: 'Checking cloud attachments',
      ja: 'クラウド上の添付ファイルを確認中',
    ),
    'Preparing attachment' => strings.localized(
      en: 'Preparing attachments',
      ja: '添付ファイルを準備中',
    ),
    'Prepared attachment' => strings.localized(
      en: 'Prepared attachments',
      ja: '添付ファイルを準備済み',
    ),
    'Attachments already uploaded' => strings.localized(
      en: 'Attachments already uploaded',
      ja: '添付ファイルはアップロード済み',
    ),
    'Uploading attachment' => strings.localized(
      en: 'Uploading attachments',
      ja: '添付ファイルをアップロード中',
    ),
    'Uploaded attachment' => strings.localized(
      en: 'Uploaded attachments',
      ja: '添付ファイルをアップロード済み',
    ),
    _ => detail,
  };
}

String? _syncProgressItemProgressText(
  AppStrings strings,
  SyncTransferState state,
) {
  final completed = state.completedItems;
  final total = state.totalItems;
  if (completed == null || total == null || total <= 0) {
    return null;
  }
  return strings.localized(
    en: 'Items: $completed / $total',
    ja: '件数: $completed / $total',
    zh: '项目: $completed / $total',
    ko: '항목: $completed / $total',
    es: 'Elementos: $completed / $total',
    de: 'Elemente: $completed / $total',
  );
}

String _localizedSyncTransferMessage(
  AppStrings strings,
  String message,
  SyncProvider provider,
) {
  final providerName = _syncProviderName(provider);
  switch (message) {
    case 'sync.error.local_snapshot_incomplete':
      return strings.localized(
        en: 'Some pending notes cannot be uploaded yet. If private profile notes are included, open the matching private profile on this device and sync again.',
        ja: '未同期の一部のメモはまだアップロードできません。プライベートプロファイルのメモが含まれる場合は、この端末で該当プロファイルを開いてからもう一度同期してください。',
        zh: '部分待同步笔记暂时无法上传。如果包含私密配置文件的笔记，请先在此设备上打开对应配置文件，然后再次同步。',
        ko: '일부 대기 중인 메모는 아직 업로드할 수 없습니다. 비공개 프로필 메모가 포함된 경우 이 기기에서 해당 프로필을 연 뒤 다시 동기화하세요.',
        es: 'Algunas notas pendientes todavia no se pueden subir. Si incluyen notas de perfiles privados, abre el perfil privado correspondiente en este dispositivo y vuelve a sincronizar.',
        de: 'Einige ausstehende Notizen konnen noch nicht hochgeladen werden. Wenn private Profilnotizen enthalten sind, offne das passende private Profil auf diesem Gerat und synchronisiere erneut.',
      );
    case 'sync.error.bundle_decryption_failed':
      return strings.localized(
        en:
            'Sync data could not be decrypted.\n'
            '- The cloud recovery key may be different. Copy the cloud recovery key from the original device and import it on this device.\n'
            '- If notes or attachments were repaired on the original device, re-upload all notes from that device and sync again.\n'
            '- If private profile notes are included, open the target private profile on this device, then apply the bundle again.',
        ja:
            '同期データを復号できませんでした。\n'
            '・クラウド復元キーが違う可能性があります。元端末でクラウド復元キーをコピーし、この端末へ読み込んでください。\n'
            '・元端末で添付やメモを修復した場合は、元端末で全メモを再アップロードしてから同期してください。\n'
            '・プライベートプロファイルのメモが含まれる場合は、同期先端末で対象プロファイルを開いてから、もう一度適用してください。',
        zh:
            '无法解密同步数据。\n'
            '- 云恢复密钥可能不同。请从原设备复制云恢复密钥，并在此设备导入。\n'
            '- 如果在原设备修复了备忘或附件，请从原设备重新上传全部备忘后再同步。\n'
            '- 如果包含私密配置文件的备忘，请先在此设备打开目标私密配置文件，然后再次应用同步包。',
        ko:
            '동기화 데이터를 복호화할 수 없습니다.\n'
            '- 클라우드 복구 키가 다를 수 있습니다. 원래 기기에서 클라우드 복구 키를 복사해 이 기기로 가져오세요.\n'
            '- 원래 기기에서 메모나 첨부 파일을 복구했다면, 그 기기에서 모든 메모를 다시 업로드한 뒤 동기화하세요.\n'
            '- 개인 프로필 메모가 포함된 경우 이 기기에서 대상 개인 프로필을 연 뒤 번들을 다시 적용하세요.',
        es:
            'No se pudieron descifrar los datos de sincronizacion.\n'
            '- Es posible que la clave de recuperacion en la nube sea distinta. Copiala desde el dispositivo original e importala en este dispositivo.\n'
            '- Si reparaste notas o adjuntos en el dispositivo original, vuelve a subir todas las notas desde ese dispositivo y sincroniza de nuevo.\n'
            '- Si incluye notas de perfiles privados, abre el perfil privado correspondiente en este dispositivo y vuelve a aplicar el paquete.',
        de:
            'Synchronisierungsdaten konnten nicht entschlusselt werden.\n'
            '- Der Cloud-Wiederherstellungsschlussel ist moglicherweise anders. Kopiere ihn vom ursprunglichen Gerat und importiere ihn auf diesem Gerat.\n'
            '- Wenn Notizen oder Anhange auf dem ursprunglichen Gerat repariert wurden, lade alle Notizen von dort erneut hoch und synchronisiere noch einmal.\n'
            '- Wenn Notizen privater Profile enthalten sind, offne das Zielprofil auf diesem Gerat und wende das Paket erneut an.',
      );
    case 'sync.error.unlock_private_profiles_before_compact':
      return strings.localized(
        en: 'Open all private profiles on this device before compacting iCloud sync storage. This keeps private attachments from being pruned while their profile is locked.',
        ja: 'iCloud同期ストレージを整理する前に、この端末ですべてのプライベートプロファイルを開いてください。プロファイルがロック中の添付が削除されるのを防ぎます。',
        zh: '压缩 iCloud 同步存储前，请先在此设备上打开所有私密档案，以免锁定档案中的附件被清理。',
        ko: 'iCloud 동기화 저장 공간을 정리하기 전에 이 기기에서 모든 비공개 프로필을 여세요. 잠긴 프로필의 첨부 파일이 정리되지 않도록 합니다.',
        es: 'Abre todos los perfiles privados en este dispositivo antes de compactar el almacenamiento de sincronizacion de iCloud. Asi se evita eliminar adjuntos privados mientras el perfil esta bloqueado.',
        de: 'Offne alle privaten Profile auf diesem Gerat, bevor du den iCloud-Sync-Speicher bereinigst. So werden private Anhange nicht entfernt, solange ihr Profil gesperrt ist.',
      );
    case 'sync.error.bundle_key_missing':
      return strings.localized(
        en: 'The cloud recovery key for this sync bundle is not available on this device. Copy the cloud recovery key from the original device, import it here, then sync again.',
        ja: '同期バンドルを読むためのクラウド復元キーがこの端末にありません。元端末でクラウド復元キーをコピーし、この端末へ読み込んでから、もう一度同期してください。',
        zh: '此设备没有读取同步包所需的云恢复密钥。请从原设备复制云恢复密钥并在此设备导入，然后再次同步。',
        ko: '이 기기에 동기화 번들을 읽는 데 필요한 클라우드 복구 키가 없습니다. 원래 기기에서 키를 복사해 이 기기로 가져온 뒤 다시 동기화하세요.',
        es: 'La clave de recuperacion en la nube para este paquete no esta disponible en este dispositivo. Copiala desde el dispositivo original, importala aqui y sincroniza de nuevo.',
        de: 'Der Cloud-Wiederherstellungsschlussel fur dieses Synchronisierungspaket ist auf diesem Gerat nicht verfugbar. Kopiere ihn vom ursprunglichen Gerat, importiere ihn hier und synchronisiere erneut.',
      );
    case 'sync.error.icloud_keychain_waiting':
      return strings.localized(
        en: 'The cloud recovery key for this sync bundle is not on this device yet. iCloud Keychain may still be syncing. Wait a little and try again, or copy the cloud recovery key from the original device and import it here.',
        ja: '同期バンドルを読むためのクラウド復元キーがまだこの端末にありません。iCloud Keychain の同期待ちの可能性があります。しばらく待ってから再試行するか、元端末でクラウド復元キーをコピーしてこの端末へ読み込んでください。',
        zh: '此设备还没有读取同步包所需的云恢复密钥。可能正在等待 iCloud Keychain 同步。请稍后重试，或从原设备复制云恢复密钥并在此设备导入。',
        ko: '이 기기에 동기화 번들을 읽는 데 필요한 클라우드 복구 키가 아직 없습니다. iCloud Keychain 동기화 대기 중일 수 있습니다. 잠시 후 다시 시도하거나 원래 기기에서 키를 복사해 가져오세요.',
        es: 'La clave de recuperacion en la nube para este paquete aun no esta en este dispositivo. Es posible que iCloud Keychain siga sincronizando. Espera un poco e intentalo de nuevo, o copia la clave desde el dispositivo original e importala aqui.',
        de: 'Der Cloud-Wiederherstellungsschlussel fur dieses Paket ist noch nicht auf diesem Gerat. iCloud Keychain synchronisiert moglicherweise noch. Warte kurz und versuche es erneut oder importiere den Schlussel vom ursprunglichen Gerat.',
      );
    case 'sync.info.select_target_for_remote_status':
      return strings.localized(
        en: 'Select a cloud sync target before checking the remote status.',
        ja: 'リモートの状態を確認するには、先にクラウド同期先を選択してください。',
        zh: '请先选择云同步目标，再检查远程状态。',
        ko: '원격 상태를 확인하기 전에 클라우드 동기화 대상을 선택하세요.',
        es: 'Selecciona un destino de sincronizacion en la nube antes de comprobar el estado remoto.',
        de: 'Wahle zuerst ein Cloud-Synchronisierungsziel aus, bevor du den Remote-Status prufst.',
      );
    case 'sync.info.no_remote_bundle':
      return strings.localized(
        en: 'No remote bundle has been saved yet.',
        ja: 'リモートにはまだバンドルが保存されていません。',
        zh: '远程还没有保存同步包。',
        ko: '원격에 저장된 번들이 아직 없습니다.',
        es: 'Todavia no se ha guardado ningun paquete remoto.',
        de: 'Es wurde noch kein Remote-Paket gespeichert.',
      );
    case 'sync.info.remote_bundle_refreshed':
      return strings.localized(
        en: '$providerName bundle information was refreshed.',
        ja: '$providerName のバンドル情報を更新しました。',
        zh: '$providerName 的同步包信息已更新。',
        ko: '$providerName 번들 정보를 새로 고쳤습니다.',
        es: 'Se actualizo la informacion del paquete de $providerName.',
        de: 'Die Paketinformationen von $providerName wurden aktualisiert.',
      );
    case 'sync.error.select_target_for_upload':
    case 'sync.error.select_target_for_reupload':
    case 'sync.error.select_target_for_download':
      return strings.localized(
        en: 'Select a cloud sync target before continuing.',
        ja: '先にクラウド同期先を選択してください。',
        zh: '请先选择云同步目标再继续。',
        ko: '계속하기 전에 클라우드 동기화 대상을 선택하세요.',
        es: 'Selecciona un destino de sincronizacion en la nube antes de continuar.',
        de: 'Wahle zuerst ein Cloud-Synchronisierungsziel aus, bevor du fortfahrst.',
      );
    case 'sync.error.conflict_download_first_or_force_upload':
      return strings.localized(
        en: 'This device has unsynced changes and the remote bundle may be newer. Download and apply the remote bundle first, or use force upload if you want this device to overwrite the remote bundle.',
        ja: 'この端末に未同期の変更があり、リモートにはより新しいバンドルがある可能性があります。先にリモートのバンドルをダウンロードして適用するか、上書きする場合は強制アップロードを使用してください。',
        zh: '此设备有未同步的更改，远程包可能更新。请先下载并应用远程包；如果要用此设备覆盖远程包，请使用强制上传。',
        ko: '이 기기에 미동기화 변경 사항이 있고 원격 번들이 더 최신일 수 있습니다. 먼저 원격 번들을 다운로드해 적용하거나, 이 기기로 덮어쓰려면 강제 업로드를 사용하세요.',
        es: 'Este dispositivo tiene cambios sin sincronizar y el paquete remoto puede ser mas reciente. Descarga y aplica primero el paquete remoto, o usa la subida forzada si quieres sobrescribirlo desde este dispositivo.',
        de: 'Dieses Gerat hat nicht synchronisierte Anderungen und das Remote-Paket ist moglicherweise neuer. Lade es zuerst herunter und wende es an, oder nutze erzwungenes Hochladen, wenn dieses Gerat das Remote-Paket uberschreiben soll.',
      );
    case 'sync.error.conflict_pending_remote_newer':
      return strings.localized(
        en: 'This device has unsynced changes, and a newer bundle exists on the remote sync target.',
        ja: 'この端末に未同期の変更があり、リモートにはより新しいバンドルがあります。',
        zh: '此设备有未同步的更改，远程同步目标上有较新的捆绑包。',
        ko: '이 기기에 동기화되지 않은 변경 사항이 있으며, 원격 동기화 대상에 더 새로운 번들이 있습니다.',
        es: 'Este dispositivo tiene cambios sin sincronizar y hay un paquete mas reciente en el destino remoto.',
        de: 'Dieses Gerat hat nicht synchronisierte Anderungen, und auf dem Remote-Synchronisierungsziel liegt ein neueres Paket vor.',
      );
    case 'sync.error.local_bundle_prepare_failed':
      return strings.localized(
        en: 'The local sync bundle could not be prepared.',
        ja: 'ローカルの同期バンドルを準備できませんでした。',
        zh: '无法准备本地同步包。',
        ko: '로컬 동기화 번들을 준비할 수 없습니다.',
        es: 'No se pudo preparar el paquete de sincronizacion local.',
        de: 'Das lokale Synchronisierungspaket konnte nicht vorbereitet werden.',
      );
    case 'sync.error.large_mobile_transfer_requires_confirmation':
      return strings.localized(
        en: 'This sync is large and the current connection appears to be mobile data. Confirm from the sync button before continuing.',
        ja: 'この同期は大きく、現在の接続はモバイル回線のようです。続行するには同期ボタンから確認してください。',
        zh: '本次同步较大，当前连接似乎是移动数据。请从同步按钮确认后继续。',
        ko: '이번 동기화는 크고 현재 연결이 모바일 데이터로 보입니다. 계속하려면 동기화 버튼에서 확인하세요.',
        es: 'Esta sincronizacion es grande y la conexion actual parece ser de datos moviles. Confirma desde el boton de sincronizacion antes de continuar.',
        de: 'Diese Synchronisierung ist gross und die aktuelle Verbindung scheint mobil zu sein. Bestatige uber die Synchronisierungsschaltflache, bevor du fortfahrst.',
      );
    case 'sync.info.upload_success':
      return strings.localized(
        en: 'Encrypted bundle uploaded to $providerName.',
        ja: '暗号化したバンドルを $providerName にアップロードしました。',
        zh: '已将加密同步包上传到 $providerName。',
        ko: '암호화된 번들을 $providerName에 업로드했습니다.',
        es: 'Paquete cifrado subido a $providerName.',
        de: 'Verschlusseltes Paket wurde zu $providerName hochgeladen.',
      );
    case 'sync.error.conflict_review_remote':
      return strings.localized(
        en: 'This device has unsynced changes and the remote bundle may be newer. Review the remote changes before syncing.',
        ja: 'この端末に未同期の変更があり、リモートにはより新しいバンドルがある可能性があります。リモートの変更を確認してから同期してください。',
        zh: '此设备有未同步的更改，远程包可能更新。请先确认远程更改再同步。',
        ko: '이 기기에 미동기화 변경 사항이 있고 원격 번들이 더 최신일 수 있습니다. 동기화하기 전에 원격 변경 사항을 확인하세요.',
        es: 'Este dispositivo tiene cambios sin sincronizar y el paquete remoto puede ser mas reciente. Revisa los cambios remotos antes de sincronizar.',
        de: 'Dieses Gerat hat nicht synchronisierte Anderungen und das Remote-Paket ist moglicherweise neuer. Prufe die Remote-Anderungen vor der Synchronisierung.',
      );
    case 'sync.info.no_bundle_to_sync':
    case 'sync.info.no_usable_remote_bundle':
      return strings.localized(
        en: 'No usable sync bundle is available in $providerName.',
        ja: '$providerName に利用できる同期バンドルはありません。',
        zh: '$providerName 中没有可用的同步包。',
        ko: '$providerName에 사용할 수 있는 동기화 번들이 없습니다.',
        es: 'No hay ningun paquete de sincronizacion disponible en $providerName.',
        de: 'In $providerName ist kein nutzbares Synchronisierungspaket verfugbar.',
      );
    case 'sync.info.sync_success':
      return strings.localized(
        en: 'Synced with $providerName.',
        ja: '$providerName と同期済みです。',
        zh: '已与 $providerName 同步。',
        ko: '$providerName와 동기화되었습니다.',
        es: 'Sincronizado con $providerName.',
        de: 'Mit $providerName synchronisiert.',
      );
    case 'sync.error.selected_bundle_download_failed':
    case 'sync.error.remote_bundle_download_failed':
      return strings.localized(
        en: 'The selected remote bundle could not be downloaded.',
        ja: '選択したリモートバンドルをダウンロードできませんでした。',
        zh: '无法下载选定的远程同步包。',
        ko: '선택한 원격 번들을 다운로드할 수 없습니다.',
        es: 'No se pudo descargar el paquete remoto seleccionado.',
        de: 'Das ausgewahlte Remote-Paket konnte nicht heruntergeladen werden.',
      );
    case 'sync.error.download_before_apply':
    case 'sync.error.download_before_review':
      return strings.localized(
        en: 'Download a remote bundle before continuing.',
        ja: '続行する前にリモートバンドルをダウンロードしてください。',
        zh: '请先下载远程包再继续。',
        ko: '계속하기 전에 원격 번들을 다운로드하세요.',
        es: 'Descarga un paquete remoto antes de continuar.',
        de: 'Lade zuerst ein Remote-Paket herunter, bevor du fortfahrst.',
      );
    case 'sync.error.downloaded_bundle_decryption_failed':
      return strings.localized(
        en: 'The downloaded bundle could not be decrypted.',
        ja: 'ダウンロードしたバンドルを復号できませんでした。',
        zh: '无法解密已下载的同步包。',
        ko: '다운로드한 번들을 복호화할 수 없습니다.',
        es: 'No se pudo descifrar el paquete descargado.',
        de: 'Das heruntergeladene Paket konnte nicht entschlusselt werden.',
      );
    case 'sync.error.attachment_object_hash_mismatch':
      return strings.localized(
        en: 'A downloaded attachment did not match its sync metadata. Re-upload all notes from the original device and sync again.',
        ja: 'ダウンロードした添付が同期メタデータと一致しませんでした。元端末で全メモを再アップロードしてから、もう一度同期してください。',
        zh: '下载的附件与同步元数据不匹配。请从原设备重新上传全部备忘后再同步。',
        ko: '다운로드한 첨부가 동기화 메타데이터와 일치하지 않습니다. 원래 기기에서 모든 메모를 다시 업로드한 뒤 동기화하세요.',
        es: 'Un adjunto descargado no coincide con sus metadatos de sincronizacion. Vuelve a subir todas las notas desde el dispositivo original y sincroniza de nuevo.',
        de: 'Ein heruntergeladener Anhang passt nicht zu seinen Synchronisierungsmetadaten. Lade alle Notizen vom ursprunglichen Gerat erneut hoch und synchronisiere noch einmal.',
      );
    case 'sync.error.private_profile_locked':
      return strings.localized(
        en: 'This bundle contains private profile notes. Enter the same private profile password on this device, open that profile, then apply the bundle again.',
        ja: 'プライベートプロファイルのメモが含まれています。同期先端末で同じプロファイルパスワードを入力して開いてから、もう一度適用してください。',
        zh: '此同步包包含私密配置文件的备忘。请在此设备输入相同的配置文件密码并打开该配置文件，然后再次应用同步包。',
        ko: '이 번들에는 개인 프로필 메모가 포함되어 있습니다. 이 기기에서 동일한 프로필 비밀번호를 입력해 프로필을 연 뒤 번들을 다시 적용하세요.',
        es: 'Este paquete contiene notas de perfiles privados. Introduce la misma contrasena de perfil en este dispositivo, abre ese perfil y vuelve a aplicar el paquete.',
        de: 'Dieses Paket enthalt Notizen privater Profile. Gib auf diesem Gerat dasselbe Profilpasswort ein, offne das Profil und wende das Paket erneut an.',
      );
    case 'sync.info.apply_success':
      return strings.localized(
        en: 'Downloaded bundle applied to local notes.',
        ja: 'ダウンロードしたバンドルをローカルのノートに反映しました。',
        zh: '已将下载的同步包应用到本地笔记。',
        ko: '다운로드한 번들을 로컬 노트에 적용했습니다.',
        es: 'Paquete descargado aplicado a las notas locales.',
        de: 'Heruntergeladenes Paket wurde auf lokale Notizen angewendet.',
      );
    case 'sync.info.private_profile_notes_pending_unlock':
      return strings.localized(
        en: 'Sync completed. Private profile notes will be applied after you open the matching private profile on this device.',
        ja: '同期は完了しました。プライベートプロファイルのメモは、この端末で該当するプロファイルを開いたあとに反映されます。',
        zh: '同步已完成。私人配置文件中的笔记会在你在此设备上打开对应配置文件后应用。',
        ko: '동기화가 완료되었습니다. 비공개 프로필 메모는 이 기기에서 해당 프로필을 연 뒤 적용됩니다.',
        es: 'La sincronizacion se completo. Las notas de perfiles privados se aplicaran cuando abras el perfil privado correspondiente en este dispositivo.',
        de: 'Die Synchronisierung ist abgeschlossen. Notizen privater Profile werden angewendet, nachdem du das passende private Profil auf diesem Gerat geoffnet hast.',
      );
    case 'sync.info.deferred_attachments_downloaded':
      return strings.localized(
        en: 'Pending attachments were downloaded.',
        ja: '保留中の添付をダウンロードしました。',
        zh: '已下载待处理附件。',
        ko: '보류 중인 첨부를 다운로드했습니다.',
        es: 'Se descargaron los adjuntos pendientes.',
        de: 'Ausstehende Anhänge wurden heruntergeladen.',
      );
    case 'sync.info.no_deferred_attachments':
      return strings.localized(
        en: 'No pending attachments need to be downloaded.',
        ja: 'ダウンロード待ちの添付はありません。',
        zh: '没有需要下载的待处理附件。',
        ko: '다운로드할 보류 중인 첨부가 없습니다.',
        es: 'No hay adjuntos pendientes para descargar.',
        de: 'Keine ausstehenden Anhänge zum Herunterladen.',
      );
    case 'sync.info.remote_bundle_saved_locally':
      return strings.localized(
        en: '$providerName remote bundle was saved to protected local storage.',
        ja: '$providerName のリモートバンドルをローカルの保護ストレージに保存しました。',
        zh: '已将 $providerName 远程包保存到本地受保护存储。',
        ko: '$providerName 원격 번들을 로컬 보호 저장소에 저장했습니다.',
        es: 'El paquete remoto de $providerName se guardo en el almacenamiento local protegido.',
        de: 'Das Remote-Paket von $providerName wurde im geschutzten lokalen Speicher abgelegt.',
      );
  }
  if (message ==
      '同期データを復号できませんでした。\n'
          '・クラウド復元キーが違う可能性があります。元端末でクラウド復元キーをコピーし、この端末へ読み込んでください。\n'
          '・元端末で添付やメモを修復した場合は、元端末で全メモを再アップロードしてから同期してください。\n'
          '・プライベートプロファイルのメモが含まれる場合は、同期先端末で対象プロファイルを開いてから、もう一度適用してください。') {
    return strings.localized(
      en:
          'Sync data could not be decrypted.\n'
          '- The cloud recovery key may be different. Copy the cloud recovery key from the original device and import it on this device.\n'
          '- If notes or attachments were repaired on the original device, re-upload all notes from that device and sync again.\n'
          '- If private profile notes are included, open the target private profile on this device, then apply the bundle again.',
      ja: message,
      zh:
          '无法解密同步数据。\n'
          '- 云恢复密钥可能不同。请从原设备复制云恢复密钥，并在此设备导入。\n'
          '- 如果在原设备修复了备忘或附件，请从原设备重新上传全部备忘后再同步。\n'
          '- 如果包含私密配置文件的备忘，请先在此设备打开目标私密配置文件，然后再次应用同步包。',
      ko:
          '동기화 데이터를 복호화할 수 없습니다.\n'
          '- 클라우드 복구 키가 다를 수 있습니다. 원래 기기에서 클라우드 복구 키를 복사해 이 기기로 가져오세요.\n'
          '- 원래 기기에서 메모나 첨부 파일을 복구했다면, 그 기기에서 모든 메모를 다시 업로드한 뒤 동기화하세요.\n'
          '- 개인 프로필 메모가 포함된 경우 이 기기에서 대상 개인 프로필을 연 뒤 번들을 다시 적용하세요.',
      es:
          'No se pudieron descifrar los datos de sincronizacion.\n'
          '- Es posible que la clave de recuperacion en la nube sea distinta. Copiala desde el dispositivo original e importala en este dispositivo.\n'
          '- Si reparaste notas o adjuntos en el dispositivo original, vuelve a subir todas las notas desde ese dispositivo y sincroniza de nuevo.\n'
          '- Si incluye notas de perfiles privados, abre el perfil privado correspondiente en este dispositivo y vuelve a aplicar el paquete.',
      de:
          'Synchronisierungsdaten konnten nicht entschlusselt werden.\n'
          '- Der Cloud-Wiederherstellungsschlussel ist moglicherweise anders. Kopiere ihn vom ursprunglichen Gerat und importiere ihn auf diesem Gerat.\n'
          '- Wenn Notizen oder Anhange auf dem ursprunglichen Gerat repariert wurden, lade alle Notizen von dort erneut hoch und synchronisiere noch einmal.\n'
          '- Wenn Notizen privater Profile enthalten sind, offne das Zielprofil auf diesem Gerat und wende das Paket erneut an.',
    );
  }
  if (message ==
      '同期バンドルを読むためのクラウド復元キーがこの端末にありません。元端末でクラウド復元キーをコピーし、この端末へ読み込んでから、もう一度同期してください。') {
    return strings.localized(
      en: 'The cloud recovery key for this sync bundle is not available on this device. Copy the cloud recovery key from the original device, import it here, then sync again.',
      ja: message,
      zh: '此设备没有读取同步包所需的云恢复密钥。请从原设备复制云恢复密钥并在此设备导入，然后再次同步。',
      ko: '이 기기에 동기화 번들을 읽는 데 필요한 클라우드 복구 키가 없습니다. 원래 기기에서 키를 복사해 이 기기로 가져온 뒤 다시 동기화하세요.',
      es: 'La clave de recuperacion en la nube para este paquete no esta disponible en este dispositivo. Copiala desde el dispositivo original, importala aqui y sincroniza de nuevo.',
      de: 'Der Cloud-Wiederherstellungsschlussel fur dieses Synchronisierungspaket ist auf diesem Gerat nicht verfugbar. Kopiere ihn vom ursprunglichen Gerat, importiere ihn hier und synchronisiere erneut.',
    );
  }
  if (message ==
      '同期バンドルを読むためのクラウド復元キーがまだこの端末にありません。iCloud Keychain の同期待ちの可能性があります。しばらく待ってから再試行するか、元端末でクラウド復元キーをコピーしてこの端末へ読み込んでください。') {
    return strings.localized(
      en: 'The cloud recovery key for this sync bundle is not on this device yet. iCloud Keychain may still be syncing. Wait a little and try again, or copy the cloud recovery key from the original device and import it here.',
      ja: message,
      zh: '此设备还没有读取同步包所需的云恢复密钥。可能正在等待 iCloud Keychain 同步。请稍后重试，或从原设备复制云恢复密钥并在此设备导入。',
      ko: '이 기기에 동기화 번들을 읽는 데 필요한 클라우드 복구 키가 아직 없습니다. iCloud Keychain 동기화 대기 중일 수 있습니다. 잠시 후 다시 시도하거나 원래 기기에서 키를 복사해 가져오세요.',
      es: 'La clave de recuperacion en la nube para este paquete aun no esta en este dispositivo. Es posible que iCloud Keychain siga sincronizando. Espera un poco e intentalo de nuevo, o copia la clave desde el dispositivo original e importala aqui.',
      de: 'Der Cloud-Wiederherstellungsschlussel fur dieses Paket ist noch nicht auf diesem Gerat. iCloud Keychain synchronisiert moglicherweise noch. Warte kurz und versuche es erneut oder importiere den Schlussel vom ursprunglichen Gerat.',
    );
  }
  if (message == 'リモートの状態を確認するには、先にクラウド同期先を選択してください。') {
    return strings.localized(
      en: 'Select a cloud sync target before checking the remote status.',
      ja: message,
      zh: '请先选择云同步目标，再检查远程状态。',
      ko: '원격 상태를 확인하기 전에 클라우드 동기화 대상을 선택하세요.',
      es: 'Selecciona un destino de sincronizacion en la nube antes de comprobar el estado remoto.',
      de: 'Wahle zuerst ein Cloud-Synchronisierungsziel aus, bevor du den Remote-Status prufst.',
    );
  }
  if (message == 'リモートにはまだバンドルが保存されていません。') {
    return strings.localized(
      en: 'No remote bundle has been saved yet.',
      ja: message,
      zh: '远程还没有保存同步包。',
      ko: '원격에 저장된 번들이 아직 없습니다.',
      es: 'Todavia no se ha guardado ningun paquete remoto.',
      de: 'Es wurde noch kein Remote-Paket gespeichert.',
    );
  }
  if (message == 'アップロードするには、先にクラウド同期先を選択してください。' ||
      message == '再アップロードするには、先にクラウド同期先を選択してください。' ||
      message == 'ダウンロードするには、先にクラウド同期先を選択してください。') {
    return strings.localized(
      en: 'Select a cloud sync target before continuing.',
      ja: message,
      zh: '请先选择云同步目标再继续。',
      ko: '계속하기 전에 클라우드 동기화 대상을 선택하세요.',
      es: 'Selecciona un destino de sincronizacion en la nube antes de continuar.',
      de: 'Wahle zuerst ein Cloud-Synchronisierungsziel aus, bevor du fortfahrst.',
    );
  }
  if (message.contains('先にリモートのバンドルをダウンロードして適用するか')) {
    return strings.localized(
      en: 'This device has unsynced changes and the remote bundle may be newer. Download and apply the remote bundle first, or use force upload if you want this device to overwrite the remote bundle.',
      ja: message,
      zh: '此设备有未同步的更改，远程包可能更新。请先下载并应用远程包；如果要用此设备覆盖远程包，请使用强制上传。',
      ko: '이 기기에 미동기화 변경 사항이 있고 원격 번들이 더 최신일 수 있습니다. 먼저 원격 번들을 다운로드해 적용하거나, 이 기기로 덮어쓰려면 강제 업로드를 사용하세요.',
      es: 'Este dispositivo tiene cambios sin sincronizar y el paquete remoto puede ser mas reciente. Descarga y aplica primero el paquete remoto, o usa la subida forzada si quieres sobrescribirlo desde este dispositivo.',
      de: 'Dieses Gerat hat nicht synchronisierte Anderungen und das Remote-Paket ist moglicherweise neuer. Lade es zuerst herunter und wende es an, oder nutze erzwungenes Hochladen, wenn dieses Gerat das Remote-Paket uberschreiben soll.',
    );
  }
  if (message.contains('リモートの変更を確認してから同期してください。')) {
    return strings.localized(
      en: 'This device has unsynced changes and the remote bundle may be newer. Review the remote changes before syncing.',
      ja: message,
      zh: '此设备有未同步的更改，远程包可能更新。请先确认远程更改再同步。',
      ko: '이 기기에 미동기화 변경 사항이 있고 원격 번들이 더 최신일 수 있습니다. 동기화하기 전에 원격 변경 사항을 확인하세요.',
      es: 'Este dispositivo tiene cambios sin sincronizar y el paquete remoto puede ser mas reciente. Revisa los cambios remotos antes de sincronizar.',
      de: 'Dieses Gerat hat nicht synchronisierte Anderungen und das Remote-Paket ist moglicherweise neuer. Prufe die Remote-Anderungen vor der Synchronisierung.',
    );
  }
  if (message == 'ローカルの同期バンドルを準備できませんでした。') {
    return strings.localized(
      en: 'The local sync bundle could not be prepared.',
      ja: message,
      zh: '无法准备本地同步包。',
      ko: '로컬 동기화 번들을 준비할 수 없습니다.',
      es: 'No se pudo preparar el paquete de sincronizacion local.',
      de: 'Das lokale Synchronisierungspaket konnte nicht vorbereitet werden.',
    );
  }
  if (message == '暗号化したバンドルを $providerName にアップロードしました。') {
    return strings.localized(
      en: 'Encrypted bundle uploaded to $providerName.',
      ja: message,
      zh: '已将加密同步包上传到 $providerName。',
      ko: '암호화된 번들을 $providerName에 업로드했습니다.',
      es: 'Paquete cifrado subido a $providerName.',
      de: 'Verschlusseltes Paket wurde zu $providerName hochgeladen.',
    );
  }
  if (message == '$providerName と同期済みです。') {
    return strings.localized(
      en: 'Synced with $providerName.',
      ja: message,
      zh: '已与 $providerName 同步。',
      ko: '$providerName와 동기화되었습니다.',
      es: 'Sincronizado con $providerName.',
      de: 'Mit $providerName synchronisiert.',
    );
  }
  if (message.contains('に同期できるバンドルはありません') ||
      message.contains('に利用できるリモートバンドルはありません')) {
    return strings.localized(
      en: 'No usable sync bundle is available in $providerName.',
      ja: message,
      zh: '$providerName 中没有可用的同步包。',
      ko: '$providerName에 사용할 수 있는 동기화 번들이 없습니다.',
      es: 'No hay ningun paquete de sincronizacion disponible en $providerName.',
      de: 'In $providerName ist kein nutzbares Synchronisierungspaket verfugbar.',
    );
  }
  if (message == '適用する前にリモートバンドルをダウンロードしてください。' ||
      message == '確認する前にリモートバンドルをダウンロードしてください。') {
    return strings.localized(
      en: 'Download a remote bundle before continuing.',
      ja: message,
      zh: '请先下载远程包再继续。',
      ko: '계속하기 전에 원격 번들을 다운로드하세요.',
      es: 'Descarga un paquete remoto antes de continuar.',
      de: 'Lade zuerst ein Remote-Paket herunter, bevor du fortfahrst.',
    );
  }
  if (message == 'ダウンロードしたバンドルを復号できませんでした。') {
    return strings.localized(
      en: 'The downloaded bundle could not be decrypted.',
      ja: message,
      zh: '无法解密已下载的同步包。',
      ko: '다운로드한 번들을 복호화할 수 없습니다.',
      es: 'No se pudo descifrar el paquete descargado.',
      de: 'Das heruntergeladene Paket konnte nicht entschlusselt werden.',
    );
  }
  if (message ==
      'プライベートプロファイルのメモが含まれています。同期先端末で同じプロファイルパスワードを入力して開いてから、もう一度適用してください。') {
    return strings.localized(
      en: 'This bundle contains private profile notes. Enter the same private profile password on this device, open that profile, then apply the bundle again.',
      ja: message,
      zh: '此同步包包含私密配置文件的备忘。请在此设备输入相同的配置文件密码并打开该配置文件，然后再次应用同步包。',
      ko: '이 번들에는 개인 프로필 메모가 포함되어 있습니다. 이 기기에서 동일한 프로필 비밀번호를 입력해 프로필을 연 뒤 번들을 다시 적용하세요.',
      es: 'Este paquete contiene notas de perfiles privados. Introduce la misma contrasena de perfil en este dispositivo, abre ese perfil y vuelve a aplicar el paquete.',
      de: 'Dieses Paket enthalt Notizen privater Profile. Gib auf diesem Gerat dasselbe Profilpasswort ein, offne das Profil und wende das Paket erneut an.',
    );
  }
  if (message == 'ダウンロードしたバンドルをローカルのノートに反映しました。') {
    return strings.localized(
      en: 'Downloaded bundle applied to local notes.',
      ja: message,
      zh: '已将下载的同步包应用到本地笔记。',
      ko: '다운로드한 번들을 로컬 노트에 적용했습니다.',
      es: 'Paquete descargado aplicado a las notas locales.',
      de: 'Heruntergeladenes Paket wurde auf lokale Notizen angewendet.',
    );
  }
  if (message.contains('のリモートバンドルをローカルの保護ストレージに保存しました。')) {
    return strings.localized(
      en: '$providerName remote bundle was saved to protected local storage.',
      ja: message,
      zh: '已将 $providerName 远程包保存到本地受保护存储。',
      ko: '$providerName 원격 번들을 로컬 보호 저장소에 저장했습니다.',
      es: 'El paquete remoto de $providerName se guardo en el almacenamiento local protegido.',
      de: 'Das Remote-Paket von $providerName wurde im geschutzten lokalen Speicher abgelegt.',
    );
  }
  return message;
}

double? _syncProgressValueForState(SyncTransferState state) {
  final completed = state.completedItems;
  final total = state.totalItems;
  if (completed != null && total != null && total > 0) {
    final base = _syncProgressBaseValue(state.progress) ?? 0;
    final next = switch (state.progress) {
      SyncTransferProgress.checkingRemote => 0.30,
      SyncTransferProgress.preparingBundle => 0.55,
      SyncTransferProgress.uploadingBundle => 0.76,
      SyncTransferProgress.downloadingBundle => 0.64,
      SyncTransferProgress.applyingBundle => 0.88,
      SyncTransferProgress.finalizing => 0.98,
      SyncTransferProgress.none => 1.0,
    };
    final ratio = (completed / total).clamp(0.0, 1.0);
    return base + (next - base) * ratio;
  }
  return _syncProgressBaseValue(state.progress);
}

double? _syncProgressBaseValue(SyncTransferProgress progress) {
  return switch (progress) {
    SyncTransferProgress.checkingRemote => 0.18,
    SyncTransferProgress.preparingBundle => 0.38,
    SyncTransferProgress.uploadingBundle => 0.64,
    SyncTransferProgress.downloadingBundle => 0.48,
    SyncTransferProgress.applyingBundle => 0.78,
    SyncTransferProgress.finalizing => 0.92,
    SyncTransferProgress.none => null,
  };
}

String _remoteBundleSummary(
  AppStrings strings,
  SyncProvider provider,
  SyncTransferState transferState,
  SyncBundleState? bundleState,
) {
  if (provider == SyncProvider.off) {
    return strings.text('home.remote.bundle.storage.is.not.configured.yet');
  }
  if (provider == SyncProvider.iCloud && transferState.remoteStatus == null) {
    return strings.text('home.no.icloud.bundle.metadata.loaded.yet');
  }
  if (provider != SyncProvider.googleDrive && provider != SyncProvider.iCloud) {
    return strings.text('home.remote.bundle.transport.is.not.available.yet');
  }
  if (provider == SyncProvider.off) {
    return strings.text('home.remote.bundle.storage.is.not.configured.yet.2');
  }
  if (provider == SyncProvider.iCloud && transferState.remoteStatus == null) {
    return strings.text('home.no.icloud.bundle.metadata.loaded.yet.2');
  }
  if (provider != SyncProvider.googleDrive && provider != SyncProvider.iCloud) {
    return strings.text(
      'home.remote.bundle.transport.is.only.wired.for.google.drive.r',
    );
  }
  final remote = transferState.remoteStatus;
  if (remote == null) {
    final lastRemoteAt = bundleState?.lastRemoteModifiedAt;
    if (lastRemoteAt != null) {
      final modifiedAt = _formatDateTime(lastRemoteAt, strings);
      return strings.localized(
        en: 'Last known remote bundle: $modifiedAt. Refresh to check for newer changes.',
        ja: '最後に確認したリモートバンドル: $modifiedAt。新しい変更を確認するには更新してください。',
        zh: '上次确认的远程包：$modifiedAt。请刷新以检查更新。',
        ko: '마지막으로 확인한 원격 번들: $modifiedAt. 새 변경 사항은 새로고침으로 확인하세요.',
        es: 'Ultimo paquete remoto conocido: $modifiedAt. Actualiza para comprobar cambios nuevos.',
        de: 'Zuletzt bekanntes Remote-Bundle: $modifiedAt. Aktualisiere, um neuere Anderungen zu prufen.',
      );
    }
    return strings.text('home.no.remote.bundle.metadata.loaded.yet');
  }
  final modifiedAt = remote.modifiedAt == null
      ? (strings.text('home.unknown.time'))
      : _formatDateTime(remote.modifiedAt!, strings);
  final sizeLabel = remote.sizeBytes == null
      ? (strings.text('home.size.unknown'))
      : strings.byteCount(remote.sizeBytes!);
  final noteCount = remote.noteCount == null ? '?' : '${remote.noteCount}';
  final attachmentCount = remote.attachmentCount == null
      ? '?'
      : '${remote.attachmentCount}';
  return strings.localized(
    en: 'Latest change bundle: $modifiedAt, $sizeLabel, $noteCount changed notes, $attachmentCount attachments.',
    ja: '最新の変更バンドル: $modifiedAt、$sizeLabel、変更ノート $noteCount 件、添付 $attachmentCount 件。',
    zh: '最新变更包：$modifiedAt，$sizeLabel，变更笔记 $noteCount 条，附件 $attachmentCount 个。',
    ko: '최신 변경 번들: $modifiedAt, $sizeLabel, 변경된 노트 $noteCount개, 첨부 $attachmentCount개.',
    es: 'Último paquete de cambios: $modifiedAt, $sizeLabel, $noteCount notas cambiadas, $attachmentCount adjuntos.',
    de: 'Letztes Änderungs-Bundle: $modifiedAt, $sizeLabel, $noteCount geänderte Notizen, $attachmentCount Anhänge.',
  );
}

enum _CloudSyncSnackBarAction {
  syncNow,
  refreshRemote,
  upload,
  download,
  apply,
}

String _cloudSyncSnackBarMessage(
  AppStrings strings,
  SyncTransferState state,
  _CloudSyncSnackBarAction action,
  SyncProvider provider,
) {
  final providerName = _syncProviderName(provider);
  if (state.stage == SyncTransferStage.error) {
    return switch (action) {
      _CloudSyncSnackBarAction.refreshRemote => strings.localized(
        en: 'Could not refresh remote sync status.',
        ja: 'リモート同期状態を更新できませんでした。',
        zh: '无法刷新远程同步状态。',
        ko: '원격 동기화 상태를 새로 고칠 수 없습니다.',
        es: 'No se pudo actualizar el estado de sincronizacion remota.',
        de: 'Der Remote-Synchronisierungsstatus konnte nicht aktualisiert werden.',
      ),
      _CloudSyncSnackBarAction.upload => strings.localized(
        en: 'Could not upload the sync bundle.',
        ja: '同期バンドルをアップロードできませんでした。',
        zh: '无法上传同步包。',
        ko: '동기화 번들을 업로드할 수 없습니다.',
        es: 'No se pudo subir el paquete de sincronizacion.',
        de: 'Das Synchronisierungspaket konnte nicht hochgeladen werden.',
      ),
      _CloudSyncSnackBarAction.download => strings.localized(
        en: 'Could not download the remote sync bundle.',
        ja: 'リモート同期バンドルをダウンロードできませんでした。',
        zh: '无法下载远程同步包。',
        ko: '원격 동기화 번들을 다운로드할 수 없습니다.',
        es: 'No se pudo descargar el paquete de sincronizacion remoto.',
        de: 'Das Remote-Synchronisierungspaket konnte nicht heruntergeladen werden.',
      ),
      _CloudSyncSnackBarAction.apply => strings.localized(
        en: 'Could not apply the downloaded sync bundle.',
        ja: 'ダウンロードした同期バンドルを適用できませんでした。',
        zh: '无法应用已下载的同步包。',
        ko: '다운로드한 동기화 번들을 적용할 수 없습니다.',
        es: 'No se pudo aplicar el paquete de sincronizacion descargado.',
        de: 'Das heruntergeladene Synchronisierungspaket konnte nicht angewendet werden.',
      ),
      _CloudSyncSnackBarAction.syncNow => strings.localized(
        en: 'Cloud sync could not be completed.',
        ja: 'クラウド同期を完了できませんでした。',
        zh: '无法完成云同步。',
        ko: '클라우드 동기화를 완료할 수 없습니다.',
        es: 'No se pudo completar la sincronizacion en la nube.',
        de: 'Die Cloud-Synchronisierung konnte nicht abgeschlossen werden.',
      ),
    };
  }
  return switch (action) {
    _CloudSyncSnackBarAction.refreshRemote =>
      state.remoteStatus == null
          ? strings.localized(
              en: 'No remote sync bundle has been saved yet.',
              ja: 'リモートにはまだ同期バンドルが保存されていません。',
              zh: '远程还没有保存同步包。',
              ko: '원격에 저장된 동기화 번들이 아직 없습니다.',
              es: 'Todavia no se ha guardado ningun paquete de sincronizacion remoto.',
              de: 'Es wurde noch kein Remote-Synchronisierungspaket gespeichert.',
            )
          : strings.localized(
              en: '$providerName bundle information was refreshed.',
              ja: '$providerName のバンドル情報を更新しました。',
              zh: '$providerName 的同步包信息已更新。',
              ko: '$providerName 번들 정보를 새로 고쳤습니다.',
              es: 'Se actualizo la informacion del paquete de $providerName.',
              de: 'Die Paketinformationen von $providerName wurden aktualisiert.',
            ),
    _CloudSyncSnackBarAction.upload => strings.localized(
      en: 'Encrypted bundle uploaded to $providerName.',
      ja: '暗号化したバンドルを $providerName にアップロードしました。',
      zh: '已将加密同步包上传到 $providerName。',
      ko: '암호화된 번들을 $providerName에 업로드했습니다.',
      es: 'Paquete cifrado subido a $providerName.',
      de: 'Verschlusseltes Paket wurde zu $providerName hochgeladen.',
    ),
    _CloudSyncSnackBarAction.download => strings.localized(
      en: 'Remote bundle download check completed for $providerName.',
      ja: '$providerName のリモートバンドル確認が完了しました。',
      zh: '$providerName 的远程包检查已完成。',
      ko: '$providerName 원격 번들 확인이 완료되었습니다.',
      es: 'Comprobacion de descarga del paquete remoto completada para $providerName.',
      de: 'Prufung des Remote-Paketdownloads fur $providerName abgeschlossen.',
    ),
    _CloudSyncSnackBarAction.apply => strings.localized(
      en: 'Downloaded bundle applied to local notes.',
      ja: 'ダウンロードしたバンドルをローカルのノートに反映しました。',
      zh: '已将下载的同步包应用到本地笔记。',
      ko: '다운로드한 번들을 로컬 노트에 적용했습니다.',
      es: 'Paquete descargado aplicado a las notas locales.',
      de: 'Heruntergeladenes Paket wurde auf lokale Notizen angewendet.',
    ),
    _CloudSyncSnackBarAction.syncNow => strings.localized(
      en: 'Synced with $providerName.',
      ja: '$providerName と同期済みです。',
      zh: '已与 $providerName 同步。',
      ko: '$providerName와 동기화되었습니다.',
      es: 'Sincronizado con $providerName.',
      de: 'Mit $providerName synchronisiert.',
    ),
  };
}

String? _cloudSyncAuthSnackBarMessage(AppStrings strings, String? message) {
  if (message == null || message.isEmpty) {
    return message;
  }
  return switch (message) {
    'Google Drive app-data access is authorized.' => strings.localized(
      en: 'Google Drive app-data access is authorized.',
      ja: 'Google Drive のアプリ専用領域へのアクセスを許可しました。',
      zh: '已授权访问 Google Drive 应用数据。',
      ko: 'Google Drive 앱 데이터 접근 권한이 승인되었습니다.',
      es: 'Se autorizo el acceso a los datos de la app en Google Drive.',
      de: 'Der Zugriff auf Google Drive-App-Daten wurde autorisiert.',
    ),
    'iCloud is selected as this device sync target.' => strings.localized(
      en: 'iCloud is selected as this device sync target.',
      ja: 'この端末の同期先として iCloud を選択しました。',
      zh: '已选择 iCloud 作为此设备的同步目标。',
      ko: '이 기기의 동기화 대상으로 iCloud를 선택했습니다.',
      es: 'iCloud esta seleccionado como destino de sincronizacion de este dispositivo.',
      de: 'iCloud ist als Synchronisierungsziel dieses Gerats ausgewahlt.',
    ),
    'iCloud sync is currently available on iPhone and iPad only.' =>
      strings.localized(
        en: 'iCloud sync is currently available on iPhone and iPad only.',
        ja: 'iCloud 同期は現在 iPhone と iPad でのみ利用できます。',
        zh: 'iCloud 同步目前仅可在 iPhone 和 iPad 上使用。',
        ko: 'iCloud 동기화는 현재 iPhone 및 iPad에서만 사용할 수 있습니다.',
        es: 'La sincronizacion con iCloud solo esta disponible en iPhone y iPad.',
        de: 'iCloud-Synchronisierung ist derzeit nur auf iPhone und iPad verfugbar.',
      ),
    _ => message,
  };
}

String _syncProviderName(SyncProvider provider) {
  return switch (provider) {
    SyncProvider.iCloud => 'iCloud',
    SyncProvider.googleDrive => 'Google Drive',
    SyncProvider.off => 'Cloud',
  };
}

Future<bool?> _showLargeMobileSyncConfirmDialog(
  BuildContext context,
  LargeSyncTransferWarning warning,
) {
  final strings = context.strings;
  final direction = switch (warning.direction) {
    LargeSyncTransferDirection.upload => strings.localized(
      en: 'upload',
      ja: 'アップロード',
      zh: '上传',
      ko: '업로드',
      es: 'subida',
      de: 'Upload',
    ),
    LargeSyncTransferDirection.download => strings.localized(
      en: 'download',
      ja: 'ダウンロード',
      zh: '下载',
      ko: '다운로드',
      es: 'descarga',
      de: 'Download',
    ),
  };
  final size = _formatBytes(warning.bytes);
  final threshold = _formatBytes(warning.thresholdBytes);
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        strings.localized(
          en: 'Sync over mobile data?',
          ja: 'モバイル回線で同期しますか？',
          zh: '要通过移动数据同步吗？',
          ko: '모바일 데이터로 동기화할까요?',
          es: 'Sincronizar con datos moviles?',
          de: 'Uber mobile Daten synchronisieren?',
        ),
      ),
      content: Text(
        strings.localized(
          en: 'This sync $direction is about $size, which is larger than the $threshold guideline. Continue only if mobile data usage is acceptable.',
          ja: 'この同期の$directionは約$sizeです。目安の$thresholdを超えています。モバイルデータ通信量に問題がない場合だけ続行してください。',
          zh: '本次同步$direction约为 $size，超过 $threshold 的建议值。仅在可以接受移动数据用量时继续。',
          ko: '이번 동기화 $direction 크기는 약 $size이며 기준인 $threshold를 넘습니다. 모바일 데이터 사용량이 괜찮을 때만 계속하세요.',
          es: 'Esta $direction de sincronizacion es de unos $size, por encima de la referencia de $threshold. Continua solo si aceptas el uso de datos moviles.',
          de: 'Diese Synchronisierungs-$direction ist etwa $size gross und liegt uber dem Richtwert von $threshold. Fahre nur fort, wenn mobile Datennutzung akzeptabel ist.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            strings.localized(
              en: 'Continue',
              ja: '続行',
              zh: '继续',
              ko: '계속',
              es: 'Continuar',
              de: 'Fortfahren',
            ),
          ),
        ),
      ],
    ),
  );
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  final fractionDigits = value >= 10 || unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
}

String _appUpdatesUnavailableDescription(AppStrings strings) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return strings.appUpdatesDescIos;
  }
  return strings.updateSupportedOnAndroidOnly;
}

String _versionWithBuildDate(AppStrings strings, String version) {
  final buildDate = _formattedBuildDate();
  if (buildDate == null) {
    return version;
  }
  return '$version / ${strings.buildDateLabel(buildDate)}';
}

String? _formattedBuildDate() {
  final value = _buildDateIso.trim();
  if (value.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  final date = parsed == null ? value : parsed.toLocal().toIso8601String();
  if (date.length >= 10) {
    return date.substring(0, 10).replaceAll('-', '/');
  }
  return value;
}

Future<void> _openStoreListingOrExplain(
  BuildContext context,
  AppStrings strings,
) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final id = _configuredAppStoreId();
    if (id == null) {
      _showStoreFeedback(context, strings.appStoreIdNotConfigured);
      return;
    }
    final opened = await _launchFirstExternal([
      Uri.parse('itms-apps://apps.apple.com/app/id$id'),
      Uri.parse('https://apps.apple.com/app/id$id'),
    ]);
    if (!context.mounted) {
      return;
    }
    if (!opened) {
      _showStoreFeedback(context, strings.appStoreOpenFailed);
    }
    return;
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final opened = await _launchFirstExternal([
      Uri.parse('market://details?id=$_androidStorePackageName'),
      Uri.parse(
        'https://play.google.com/store/apps/details?id=$_androidStorePackageName',
      ),
    ]);
    if (!context.mounted) {
      return;
    }
    if (!opened) {
      _showStoreFeedback(context, strings.appStoreOpenFailed);
    }
    return;
  }

  _showStoreFeedback(context, strings.updateStatusUnsupported);
}

Future<void> _openStoreReviewOrExplain(
  BuildContext context,
  AppStrings strings,
) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final id = _configuredAppStoreId();
    if (id == null) {
      _showStoreFeedback(context, strings.appStoreIdNotConfigured);
      return;
    }
    final opened = await _launchFirstExternal([
      Uri.parse('itms-apps://itunes.apple.com/app/id$id?action=write-review'),
      Uri.parse('https://apps.apple.com/app/id$id?action=write-review'),
    ]);
    if (!context.mounted) {
      return;
    }
    if (!opened) {
      _showStoreFeedback(context, strings.appStoreOpenFailed);
    }
    return;
  }

  await _openStoreListingOrExplain(context, strings);
}

String? _configuredAppStoreId() {
  final value = _appStoreId.trim();
  return value.isEmpty ? null : value;
}

Future<bool> _launchFirstExternal(List<Uri> uris) async {
  for (final uri in uris) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // Try the next URL, usually a web fallback after a store scheme.
    }
  }
  return false;
}

Future<void> _openExternalLink(
  BuildContext context,
  Uri uri,
  AppStrings strings,
) async {
  final shouldOpen = await _confirmExternalLinkOpen(context, uri.toString());
  if (!shouldOpen || !context.mounted) {
    return;
  }
  final opened = await _launchFirstExternal([uri]);
  if (!context.mounted || opened) {
    return;
  }
  _showStoreFeedback(context, strings.linkOpenFailed);
}

void _showStoreFeedback(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(showCloseIcon: true, content: Text(message)));
}

String _syncHistoryEntrySummary(
  AppStrings strings,
  SyncHistoryEntry entry,
  SyncProvider provider,
) {
  final status = entry.success
      ? strings.localized(en: 'Completed', ja: '\u5b8c\u4e86')
      : strings.localized(
          en: 'Needs attention',
          ja: '\u78ba\u8a8d\u304c\u5fc5\u8981',
        );
  final operation = _syncHistoryOperationLabel(strings, entry.operation);
  final stamp = _formatDateTime(entry.finishedAt, strings);
  final message = entry.message;
  if (message == null || message.isEmpty) {
    return '$status - $operation - $stamp';
  }
  return '$status - $operation - $stamp\n'
      '${_localizedSyncTransferMessage(strings, message, provider)}';
}

String _syncHistoryOperationLabel(AppStrings strings, String operation) {
  return switch (operation) {
    'upload' || 'sync.upload' => strings.localized(
      en: 'Upload',
      ja: '\u30a2\u30c3\u30d7\u30ed\u30fc\u30c9',
    ),
    'download' || 'sync.download' => strings.localized(
      en: 'Download',
      ja: '\u30c0\u30a6\u30f3\u30ed\u30fc\u30c9',
    ),
    'apply' || 'sync.apply' => strings.localized(
      en: 'Apply downloaded data',
      ja: '\u53d6\u5f97\u6e08\u307f\u30c7\u30fc\u30bf\u3092\u53cd\u6620',
    ),
    'sync.enable' => strings.localized(
      en: 'Enable sync',
      ja: '\u540c\u671f\u3092\u6709\u52b9\u5316',
    ),
    _ => operation,
  };
}

String _syncQueueHistoryLabel(AppStrings strings, SyncQueueSummary? summary) {
  if (summary == null) {
    return strings.localized(
      en: 'Queue: not recorded',
      ja: '\u30ad\u30e5\u30fc: \u672a\u8a18\u9332',
    );
  }
  if (!summary.hasPendingChanges) {
    return strings.localized(
      en: 'Queue: no pending changes',
      ja: '\u30ad\u30e5\u30fc: \u672a\u540c\u671f\u306a\u3057',
    );
  }
  return strings.pendingSyncSummary(
    total: summary.totalChanges,
    upserts: summary.upserts,
    deletes: summary.deletes,
    stamp: summary.lastQueuedAt == null
        ? strings.text('home.queue.ready')
        : strings.lastQueuedAt(_formatDateTime(summary.lastQueuedAt!, strings)),
  );
}

Future<void> _showSyncHistoryDialog(
  BuildContext context,
  List<SyncHistoryEntry> entries,
) async {
  final strings = context.strings;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          strings.localized(en: 'Sync history', ja: '\u540c\u671f\u5c65\u6b74'),
        ),
        content: SizedBox(
          width: 560,
          child: entries.isEmpty
              ? Text(
                  strings.localized(
                    en: 'No sync history has been recorded yet.',
                    ja: '\u307e\u3060\u540c\u671f\u5c65\u6b74\u306f\u3042\u308a\u307e\u305b\u3093\u3002',
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final icon = entry.success
                        ? Icons.check_circle_outline_rounded
                        : Icons.error_outline_rounded;
                    final color = entry.success
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error;
                    final detailLines = <String>[
                      _syncHistoryEntrySummary(strings, entry, entry.provider),
                      _syncQueueHistoryLabel(strings, entry.queueBefore),
                    ];
                    final queueAfter = entry.queueAfter;
                    if (queueAfter != null) {
                      final queueAfterLabel = _syncQueueHistoryLabel(
                        strings,
                        queueAfter,
                      );
                      detailLines.add(
                        '${strings.localized(en: 'After: ', ja: '\u5f8c: ')}$queueAfterLabel',
                      );
                    }
                    if (entry.noteCount != null ||
                        entry.attachmentCount != null) {
                      final bundleLabel = strings.localized(
                        en: 'Bundle: ',
                        ja: '\u30d0\u30f3\u30c9\u30eb: ',
                      );
                      detailLines.add(
                        '$bundleLabel${entry.noteCount ?? 0} notes / '
                        '${entry.attachmentCount ?? 0} attachments',
                      );
                    }
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(icon, color: color),
                      title: Text(
                        _syncHistoryOperationLabel(strings, entry.operation),
                      ),
                      subtitle: Text(detailLines.join('\n')),
                      isThreeLine: true,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.close),
          ),
        ],
      );
    },
  );
}

Future<void> _showSyncConflictListDialog(
  BuildContext context,
  WidgetRef ref,
  List<NoteEntry> conflictedNotes,
) async {
  final strings = context.strings;
  final selected = await showDialog<NoteEntry>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          strings.localized(
            en: 'Conflicts to resolve',
            ja: '\u89e3\u6c7a\u304c\u5fc5\u8981\u306a\u7af6\u5408',
          ),
        ),
        content: SizedBox(
          width: 560,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: conflictedNotes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final note = conflictedNotes[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.report_problem_outlined),
                title: Text(
                  note.title.isEmpty
                      ? strings.localized(
                          en: 'Untitled note',
                          ja: '\u7121\u984c\u306e\u30e1\u30e2',
                        )
                      : note.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _formatDateTime(note.updatedAt ?? note.createdAt, strings),
                ),
                trailing: TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(note),
                  child: Text(
                    strings.localized(en: 'Resolve', ja: '\u89e3\u6c7a'),
                  ),
                ),
                onTap: () => Navigator.of(dialogContext).pop(note),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
        ],
      );
    },
  );
  if (selected == null || !context.mounted) {
    return;
  }
  await _showNoteConflictResolver(context, ref, selected);
}

enum _NoteConflictResolution { keepLocal, useRemote, merge }

Future<void> _showNoteConflictResolver(
  BuildContext context,
  WidgetRef ref,
  NoteEntry localNote,
) async {
  final strings = context.strings;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      showCloseIcon: true,
      content: Text(
        strings.localized(
          en: 'Loading the latest remote version...',
          ja: 'リモートの最新版を読み込んでいます...',
          zh: '正在读取最新远程版本...',
          ko: '최신 원격 버전을 불러오는 중...',
          es: 'Cargando la version remota mas reciente...',
          de: 'Neueste Remote-Version wird geladen...',
        ),
      ),
    ),
  );
  final remoteNote = await ref
      .read(syncTransferControllerProvider.notifier)
      .downloadLatestRemoteNoteForConflict(localNote.id);
  messenger.hideCurrentSnackBar();
  if (!context.mounted) {
    return;
  }
  if (remoteNote == null) {
    messenger.showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'No remote version for this note was found in the latest bundle.',
            ja: '最新バンドルにこのメモのリモート版が見つかりませんでした。',
            zh: '最新捆绑包中未找到此笔记的远程版本。',
            ko: '최신 번들에서 이 메모의 원격 버전을 찾을 수 없습니다.',
            es: 'No se encontro una version remota de esta nota en el paquete mas reciente.',
            de: 'Im neuesten Paket wurde keine Remote-Version dieser Notiz gefunden.',
          ),
        ),
      ),
    );
    return;
  }

  final resolution = await showDialog<_NoteConflictResolution>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          strings.localized(
            en: 'Resolve note conflict',
            ja: 'メモの競合を解決',
            zh: '解决笔记冲突',
            ko: '메모 충돌 해결',
            es: 'Resolver conflicto de nota',
            de: 'Notizkonflikt losen',
          ),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.localized(
                    en: 'Compare the local and remote versions, then choose how to resolve this note.',
                    ja: 'ローカル版とリモート版の概要を確認し、このメモの扱いを選んでください。',
                    zh: '比较本地和远程版本，然后选择如何处理此笔记。',
                    ko: '로컬 버전과 원격 버전을 비교한 뒤 이 메모를 어떻게 처리할지 선택하세요.',
                    es: 'Compara las versiones local y remota y elige como resolver esta nota.',
                    de: 'Vergleiche lokale und Remote-Version und wahle, wie diese Notiz gelost wird.',
                  ),
                ),
                const SizedBox(height: 16),
                _ConflictVersionSummary(
                  label: strings.localized(
                    en: 'Local version',
                    ja: 'ローカル版',
                    zh: '本地版本',
                    ko: '로컬 버전',
                    es: 'Version local',
                    de: 'Lokale Version',
                  ),
                  note: localNote,
                ),
                const SizedBox(height: 12),
                _ConflictVersionSummary(
                  label: strings.localized(
                    en: 'Remote version',
                    ja: 'リモート版',
                    zh: '远程版本',
                    ko: '원격 버전',
                    es: 'Version remota',
                    de: 'Remote-Version',
                  ),
                  note: remoteNote,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
          TextButton.icon(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_NoteConflictResolution.useRemote),
            icon: const Icon(Icons.cloud_download_outlined),
            label: Text(
              strings.localized(
                en: 'Use remote',
                ja: 'リモートを採用',
                zh: '使用远程',
                ko: '원격 사용',
                es: 'Usar remoto',
                de: 'Remote verwenden',
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_NoteConflictResolution.merge),
            icon: const Icon(Icons.call_merge_rounded),
            label: Text(
              strings.localized(
                en: 'Merge',
                ja: 'マージ',
                zh: '合并',
                ko: '병합',
                es: 'Fusionar',
                de: 'Zusammenfuhren',
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_NoteConflictResolution.keepLocal),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(
              strings.localized(
                en: 'Keep local',
                ja: 'ローカルを採用',
                zh: '保留本地',
                ko: '로컬 유지',
                es: 'Mantener local',
                de: 'Lokal behalten',
              ),
            ),
          ),
        ],
      );
    },
  );
  if (resolution == null) {
    await ref
        .read(notesControllerProvider.notifier)
        .cleanupUnreferencedAttachments();
    return;
  }
  if (!context.mounted) {
    return;
  }

  try {
    switch (resolution) {
      case _NoteConflictResolution.keepLocal:
        final confirmed = await _confirmLargeMobileConflictUploadIfNeeded(
          context,
          ref,
        );
        if (!confirmed) {
          return;
        }
        await ref
            .read(notesControllerProvider.notifier)
            .resolveConflictKeepingLocal(localNote.id);
        await ref
            .read(syncTransferControllerProvider.notifier)
            .uploadCurrentBundle(force: true, allowLargeMobileTransfer: true);
        await ref
            .read(notesControllerProvider.notifier)
            .cleanupUnreferencedAttachments();
        break;
      case _NoteConflictResolution.useRemote:
        await ref
            .read(notesControllerProvider.notifier)
            .resolveConflictUsingRemote(remoteNote);
        await ref
            .read(syncTransferControllerProvider.notifier)
            .recordDownloadedBundleApplied();
        break;
      case _NoteConflictResolution.merge:
        final confirmed = await _confirmLargeMobileConflictUploadIfNeeded(
          context,
          ref,
        );
        if (!confirmed) {
          return;
        }
        await ref
            .read(notesControllerProvider.notifier)
            .resolveConflictByMerging(remoteNote);
        await ref
            .read(syncTransferControllerProvider.notifier)
            .uploadCurrentBundle(force: true, allowLargeMobileTransfer: true);
        break;
    }
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'Note conflict resolved.',
            ja: 'メモの競合を解決しました。',
            zh: '笔记冲突已解决。',
            ko: '메모 충돌이 해결되었습니다.',
            es: 'Conflicto de nota resuelto.',
            de: 'Notizkonflikt gelost.',
          ),
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(showCloseIcon: true, content: Text('$error')),
    );
  }
}

Future<bool> _confirmLargeMobileConflictUploadIfNeeded(
  BuildContext context,
  WidgetRef ref,
) async {
  final warning = await ref
      .read(syncTransferControllerProvider.notifier)
      .largeMobileTransferWarning(includeUpload: true, includeDownload: false);
  if (warning == null) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  return await _showLargeMobileSyncConfirmDialog(context, warning) ?? false;
}

class _ConflictVersionSummary extends StatelessWidget {
  const _ConflictVersionSummary({required this.label, required this.note});

  final String label;
  final NoteEntry note;

  @override
  Widget build(BuildContext context) {
    final changedAt = (note.updatedAt ?? note.createdAt).toLocal();
    final timeLabel =
        '${changedAt.year}/${changedAt.month}/${changedAt.day} '
        '${changedAt.hour.toString().padLeft(2, '0')}:${changedAt.minute.toString().padLeft(2, '0')}';
    final body = _normalizePreviewText(note.body, maxChars: 240);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            note.title.trim().isEmpty
                ? context.strings.localized(
                    en: '(Untitled)',
                    ja: '（無題）',
                    zh: '（无标题）',
                    ko: '(제목 없음)',
                    es: '(Sin titulo)',
                    de: '(Ohne Titel)',
                  )
                : note.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            body.isEmpty ? '-' : body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'rev ${note.revision} / $timeLabel / ${note.attachments.length} attachments',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: _mutedTextColor(context)),
          ),
        ],
      ),
    );
  }
}

enum _LocalArchiveExportKind { passwordProtectedZip, plainZip }

class _LocalArchiveExportOptions {
  const _LocalArchiveExportOptions({required this.kind, this.password});

  final _LocalArchiveExportKind kind;
  final String? password;
}

Future<void> _exportLocalArchive(
  BuildContext context,
  WidgetRef ref, {
  required Set<String> vaultIds,
}) async {
  final strings = context.strings;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final options = await _showLocalArchiveExportDialog(context);
    if (options == null || !context.mounted) {
      return;
    }
    final archive = await ref
        .read(syncTransferControllerProvider.notifier)
        .exportLocalArchive(password: options.password, vaultIds: vaultIds);
    if (!context.mounted) {
      return;
    }
    final savedPath = await FilePicker.saveFile(
      dialogTitle: strings.localized(
        en: 'File export',
        ja: 'ファイルエクスポート',
        zh: '文件导出',
        ko: '파일 내보내기',
        es: 'Exportar archivo',
        de: 'Datei exportieren',
      ),
      fileName: archive.fileName,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: archive.bytes,
    );
    if (!context.mounted) {
      return;
    }
    if (savedPath == null || savedPath.isEmpty) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              archive.bytes,
              name: archive.fileName,
              mimeType: 'application/zip',
            ),
          ],
          text: 'HiMemo ZIP archive',
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(
          strings.localized(
            en: 'Exported ${archive.noteCount} notes and ${archive.attachmentCount} attachments.',
            ja: '${archive.noteCount}件のメモと${archive.attachmentCount}件の添付を書き出しました。',
            zh: '已导出 ${archive.noteCount} 条笔记和 ${archive.attachmentCount} 个附件。',
            ko: '${archive.noteCount}개의 메모와 ${archive.attachmentCount}개의 첨부 파일을 내보냈습니다.',
            es: 'Se exportaron ${archive.noteCount} notas y ${archive.attachmentCount} adjuntos.',
            de: '${archive.noteCount} Notizen und ${archive.attachmentCount} Anhänge wurden exportiert.',
          ),
        ),
      ),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(showCloseIcon: true, content: Text('$error')),
    );
  }
}

Future<void> _importLocalArchive(BuildContext context, WidgetRef ref) async {
  final strings = context.strings;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(
            strings.localized(
              en: 'The selected archive could not be read.',
              ja: '選択したアーカイブを読み込めませんでした。',
              zh: '无法读取所选归档。',
              ko: '선택한 아카이브를 읽을 수 없습니다.',
              es: 'No se pudo leer el archivo seleccionado.',
              de: 'Das ausgewählte Archiv konnte nicht gelesen werden.',
            ),
          ),
        ),
      );
      return;
    }
    final password = await _passwordForLocalArchivePreview(context, ref, bytes);
    if (password == _cancelledArchivePassword || !context.mounted) {
      return;
    }
    final preview = await ref
        .read(syncTransferControllerProvider.notifier)
        .importLocalArchiveBytes(bytes, password: password);
    if (!context.mounted) {
      return;
    }
    final confirmed =
        await _showBundlePreviewDialog(
          context,
          preview,
          confirmLabel: strings.localized(
            en: 'Import',
            ja: '読み込む',
            zh: '导入',
            ko: '가져오기',
            es: 'Importar',
            de: 'Importieren',
          ),
          revealSensitiveDetails: _canRevealSyncBundlePreviewDetails(
            ref,
            preview,
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) {
      return;
    }
    await ref
        .read(syncTransferControllerProvider.notifier)
        .applyLocalArchiveBytes(bytes, password: password);
    if (!context.mounted) {
      return;
    }
    final message =
        ref.read(syncTransferControllerProvider).message ??
        strings.localized(
          en: 'Archive imported.',
          ja: 'アーカイブを読み込みました。',
          zh: '归档已导入。',
          ko: '아카이브를 가져왔습니다.',
          es: 'Archivo importado.',
          de: 'Archiv importiert.',
        );
    messenger.showSnackBar(
      SnackBar(showCloseIcon: true, content: Text(message)),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(showCloseIcon: true, content: Text('$error')),
    );
  }
}

const _cancelledArchivePassword = '\u0000__cancelled__';

Future<String?> _passwordForLocalArchivePreview(
  BuildContext context,
  WidgetRef ref,
  List<int> bytes,
) async {
  try {
    await ref
        .read(syncTransferControllerProvider.notifier)
        .importLocalArchiveBytes(bytes);
    return null;
  } catch (_) {
    if (!context.mounted) {
      return _cancelledArchivePassword;
    }
    return _showArchivePasswordDialog(context);
  }
}

Future<_LocalArchiveExportOptions?> _showLocalArchiveExportDialog(
  BuildContext context,
) async {
  final strings = context.strings;
  return showDialog<_LocalArchiveExportOptions>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          strings.localized(
            en: 'File export',
            ja: 'ファイルエクスポート',
            zh: '文件导出',
            ko: '파일 내보내기',
            es: 'Exportar archivo',
            de: 'Datei exportieren',
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.localized(
                  en: 'Choose a portable ZIP format. Password-protected ZIP is safer for storage and sharing. Plain ZIP is readable without HiMemo and is useful for long-term recovery.',
                  ja: '持ち運びしやすいZIP形式で書き出します。保存や共有にはキー付きZIPが安全です。プレーンZIPはHiMemoなしでも読めるため、長期的な復旧に向いています。',
                  zh: '请选择可移植的 ZIP 格式。带密码的 ZIP 更适合保存和共享；纯 ZIP 无需 HiMemo 也能读取，适合长期恢复。',
                  ko: '휴대 가능한 ZIP 형식으로 내보냅니다. 비밀번호 ZIP은 보관과 공유에 더 안전하고, 일반 ZIP은 HiMemo 없이도 읽을 수 있어 장기 복구에 적합합니다.',
                  es: 'Elige un formato ZIP portátil. El ZIP con contraseña es más seguro para guardar y compartir. El ZIP sin cifrar se puede leer sin HiMemo y sirve para recuperación a largo plazo.',
                  de: 'Wähle ein portables ZIP-Format. Ein passwortgeschütztes ZIP ist sicherer zum Speichern und Teilen. Ein unverschlüsseltes ZIP ist ohne HiMemo lesbar und eignet sich zur langfristigen Wiederherstellung.',
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: Text(
                  strings.localized(
                    en: 'Password-protected ZIP',
                    ja: 'キー付きZIP',
                    zh: '带密码的 ZIP',
                    ko: '비밀번호 ZIP',
                    es: 'ZIP con contraseña',
                    de: 'Passwortgeschütztes ZIP',
                  ),
                ),
                subtitle: Text(
                  strings.localized(
                    en: 'Recommended for normal backups.',
                    ja: '通常のバックアップにおすすめです。',
                    zh: '推荐用于普通备份。',
                    ko: '일반 백업에 권장됩니다.',
                    es: 'Recomendado para copias de seguridad normales.',
                    de: 'Für normale Backups empfohlen.',
                  ),
                ),
                onTap: () async {
                  final password = await _showArchivePasswordDialog(
                    dialogContext,
                    confirmPassword: true,
                  );
                  if (password == null || password.isEmpty) {
                    return;
                  }
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(
                      _LocalArchiveExportOptions(
                        kind: _LocalArchiveExportKind.passwordProtectedZip,
                        password: password,
                      ),
                    );
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(
                  strings.localized(
                    en: 'Plain ZIP',
                    ja: 'プレーンZIP',
                    zh: '纯 ZIP',
                    ko: '일반 ZIP',
                    es: 'ZIP sin cifrar',
                    de: 'Unverschlüsseltes ZIP',
                  ),
                ),
                subtitle: Text(
                  strings.localized(
                    en: 'Readable outside the app. Anyone with the file can see its contents.',
                    ja: 'アプリ外でも読めます。ファイルを持つ人は内容を閲覧できます。',
                    zh: '可在应用外读取。持有文件的人都能查看内容。',
                    ko: '앱 밖에서도 읽을 수 있습니다. 파일을 가진 사람은 내용을 볼 수 있습니다.',
                    es: 'Se puede leer fuera de la app. Cualquier persona con el archivo puede ver su contenido.',
                    de: 'Außerhalb der App lesbar. Jede Person mit der Datei kann den Inhalt sehen.',
                  ),
                ),
                onTap: () async {
                  final confirmed = await _confirmPlainZipExport(dialogContext);
                  if (confirmed && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(
                      const _LocalArchiveExportOptions(
                        kind: _LocalArchiveExportKind.plainZip,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.cancel),
          ),
        ],
      );
    },
  );
}

Future<bool> _confirmPlainZipExport(BuildContext context) async {
  final strings = context.strings;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        strings.localized(
          en: 'Export plain ZIP?',
          ja: 'プレーンZIPで書き出しますか？',
          zh: '导出纯 ZIP？',
          ko: '일반 ZIP으로 내보낼까요?',
          es: '¿Exportar ZIP sin cifrar?',
          de: 'Unverschlüsseltes ZIP exportieren?',
        ),
      ),
      content: Text(
        strings.localized(
          en: 'The exported file contains readable note text, tags, dates, locations, photos, videos, audio, and files. Store it only in a place you trust.',
          ja: '書き出したファイルには、メモ本文、タグ、日時、位置情報、写真、動画、音声、ファイルが読み取り可能な状態で含まれます。信頼できる場所にのみ保存してください。',
          zh: '导出的文件会以可读取状态包含笔记正文、标签、日期、位置、照片、视频、音频和文件。请只保存到可信位置。',
          ko: '내보낸 파일에는 메모 본문, 태그, 날짜, 위치, 사진, 동영상, 오디오, 파일이 읽을 수 있는 상태로 포함됩니다. 신뢰할 수 있는 위치에만 저장하세요.',
          es: 'El archivo exportado contiene texto, etiquetas, fechas, ubicaciones, fotos, videos, audio y archivos en formato legible. Guárdalo solo en un lugar de confianza.',
          de: 'Die exportierte Datei enthält lesbare Notiztexte, Tags, Daten, Standorte, Fotos, Videos, Audio und Dateien. Speichere sie nur an einem vertrauenswürdigen Ort.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            strings.localized(
              en: 'Export plain ZIP',
              ja: 'プレーンZIPで書き出す',
              zh: '导出纯 ZIP',
              ko: '일반 ZIP 내보내기',
              es: 'Exportar ZIP sin cifrar',
              de: 'Unverschlüsselt exportieren',
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> _showArchivePasswordDialog(
  BuildContext context, {
  bool confirmPassword = false,
}) async {
  final strings = context.strings;
  final controller = TextEditingController();
  final confirmController = TextEditingController();
  String? errorText;
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              confirmPassword
                  ? strings.localized(
                      en: 'Set archive key',
                      ja: 'アーカイブキーを設定',
                      zh: '设置归档密钥',
                      ko: '아카이브 키 설정',
                      es: 'Definir clave del archivo',
                      de: 'Archivschlüssel festlegen',
                    )
                  : strings.localized(
                      en: 'Archive key',
                      ja: 'アーカイブキー',
                      zh: '归档密钥',
                      ko: '아카이브 키',
                      es: 'Clave del archivo',
                      de: 'Archivschlüssel',
                    ),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    strings.localized(
                      en: 'This key is not stored by HiMemo. If you lose it, this ZIP cannot be imported.',
                      ja: 'このキーはHiMemoには保存されません。忘れると、このZIPは読み込めません。',
                      zh: '此密钥不会保存在 HiMemo 中。如果遗失，将无法导入此 ZIP。',
                      ko: '이 키는 HiMemo에 저장되지 않습니다. 잊어버리면 이 ZIP을 가져올 수 없습니다.',
                      es: 'HiMemo no guarda esta clave. Si la pierdes, no podrás importar este ZIP.',
                      de: 'HiMemo speichert diesen Schlüssel nicht. Wenn du ihn verlierst, kann dieses ZIP nicht importiert werden.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: strings.localized(
                        en: 'Key',
                        ja: 'キー',
                        zh: '密钥',
                        ko: '키',
                        es: 'Clave',
                        de: 'Schlüssel',
                      ),
                      errorText: errorText,
                    ),
                  ),
                  if (confirmPassword) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: strings.localized(
                          en: 'Confirm key',
                          ja: 'キーを確認',
                          zh: '确认密钥',
                          ko: '키 확인',
                          es: 'Confirmar clave',
                          de: 'Schlüssel bestätigen',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final password = controller.text;
                  if (password.length < 8) {
                    setState(() {
                      errorText = strings.localized(
                        en: 'Use at least 8 characters.',
                        ja: '8文字以上で入力してください。',
                        zh: '请至少输入 8 个字符。',
                        ko: '8자 이상 입력하세요.',
                        es: 'Usa al menos 8 caracteres.',
                        de: 'Mindestens 8 Zeichen verwenden.',
                      );
                    });
                    return;
                  }
                  if (confirmPassword && password != confirmController.text) {
                    setState(() {
                      errorText = strings.localized(
                        en: 'Keys do not match.',
                        ja: 'キーが一致しません。',
                        zh: '密钥不一致。',
                        ko: '키가 일치하지 않습니다.',
                        es: 'Las claves no coinciden.',
                        de: 'Die Schlüssel stimmen nicht überein.',
                      );
                    });
                    return;
                  }
                  Navigator.of(context).pop(password);
                },
                child: Text(
                  confirmPassword
                      ? strings.save
                      : strings.localized(
                          en: 'Continue',
                          ja: '続行',
                          zh: '继续',
                          ko: '계속',
                          es: 'Continuar',
                          de: 'Weiter',
                        ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  confirmController.dispose();
  return result;
}

Future<bool?> _showBundlePreviewDialog(
  BuildContext context,
  SyncBundlePreview preview, {
  required String confirmLabel,
  required bool revealSensitiveDetails,
}) {
  final strings = context.strings;
  final hidePrivateDetails =
      preview.privateVaultNoteCount > 0 && !revealSensitiveDetails;
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(strings.text('home.bundle.review')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.bundleNotes(preview.noteCount)),
                Text(strings.bundleAttachments(preview.attachmentCount)),
                Text(strings.bundleAdds(preview.addedCount)),
                Text(strings.bundleUpdates(preview.updatedCount)),
                Text(strings.bundleRemovals(preview.removedCount)),
                if (preview.privateVaultNoteCount > 0)
                  Text(
                    strings.bundlePrivateVaultAffected(
                      preview.privateVaultNoteCount,
                    ),
                  ),
                if (preview.deviceId != null && preview.deviceId!.isNotEmpty)
                  Text(strings.bundleRemoteDevice(preview.deviceId!)),
                if (preview.exportedAt != null)
                  Text(
                    strings.bundleExportedAt(
                      _formatDateTime(preview.exportedAt!, strings),
                    ),
                  ),
                if (hidePrivateDetails) ...[
                  const SizedBox(height: 12),
                  Text(
                    strings.localized(
                      en: 'This bundle includes locked private profile notes, so titles and note names are hidden. Unlock the target profile or enter admin mode to review details.',
                      ja: 'このバンドルにはロック中のプライベートプロファイルのメモが含まれるため、タイトルやメモ名は非表示です。詳細を確認するには対象プロファイルを解除するか、管理者モードに入ってください。',
                    ),
                  ),
                ],
                if (!hidePrivateDetails && preview.sampleTitles.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(strings.bundleSample(preview.sampleTitles.join(', '))),
                ],
                if (!hidePrivateDetails) ...[
                  _PreviewTitlesSection(
                    title: strings.text('home.added.notes'),
                    titles: preview.addedTitles,
                  ),
                  _PreviewTitlesSection(
                    title: strings.text('home.updated.notes'),
                    titles: preview.updatedTitles,
                  ),
                  _PreviewTitlesSection(
                    title: strings.text('home.removed.locally.after.apply'),
                    titles: preview.removedTitles,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}

bool _canRevealSyncBundlePreviewDetails(
  WidgetRef ref,
  SyncBundlePreview preview,
) {
  final privateVaultIds = preview.privateVaultIds;
  if (privateVaultIds.isEmpty) {
    return true;
  }
  if (ref.read(adminModeSessionControllerProvider)) {
    return true;
  }
  final accessibleVaultIds = ref
      .read(accessiblePrivateVaultIdsProvider)
      .toSet();
  return privateVaultIds.every(accessibleVaultIds.contains);
}

class _PreviewTitlesSection extends StatelessWidget {
  const _PreviewTitlesSection({required this.title, required this.titles});

  final String title;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    if (titles.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          for (final entry in titles)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('• $entry'),
            ),
        ],
      ),
    );
  }
}

Future<RemoteSyncBundleStatus?> _showBundleHistoryDialog(
  BuildContext context,
  List<RemoteSyncBundleStatus> history,
) {
  final strings = context.strings;
  return showDialog<RemoteSyncBundleStatus>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(strings.text('home.remote.bundle.history')),
        content: SizedBox(
          width: 520,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: history.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = history[index];
              final modifiedAt = entry.modifiedAt == null
                  ? (strings.text('home.unknown.time.2'))
                  : _formatDateTime(entry.modifiedAt!, strings);
              final counts = strings.bundleHistoryCounts(
                notes: entry.noteCount,
                attachments: entry.attachmentCount,
              );
              final device = entry.deviceId == null || entry.deviceId!.isEmpty
                  ? (strings.text('home.unknown.device'))
                  : entry.deviceId!;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(modifiedAt),
                subtitle: Text('${entry.fileName}\n$counts\n$device'),
                isThreeLine: true,
                trailing: index == 0
                    ? const Icon(Icons.history_toggle_off_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(entry),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.close),
          ),
        ],
      );
    },
  );
}

Future<String?> _showSyncKeyImportDialog(BuildContext context) {
  final strings = context.strings;
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(strings.text('home.import.recovery.key')),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: strings.text('home.paste.himemo.sync.key.v1'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(strings.text('home.import')),
          ),
        ],
      );
    },
  );
}

Future<void> _showSyncKeyQrDialog(
  BuildContext context, {
  required String backupCode,
}) {
  final strings = context.strings;
  return showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(
          strings.localized(
            en: 'Cloud recovery key QR',
            ja: 'クラウド復元キーのQR',
            zh: '云恢复密钥 QR',
            ko: '클라우드 복구 키 QR',
            es: 'QR de clave de recuperacion',
            de: 'QR fur Cloud-Wiederherstellungsschlussel',
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.localized(
                  en: 'This QR code contains the full cloud recovery key. Show it only in a private place.',
                  ja: 'このQRコードにはクラウド復元キー全体が含まれます。周囲に見られない場所で表示してください。',
                  zh: '此 QR 码包含完整的云恢复密钥。请仅在私密场所显示。',
                  ko: '이 QR 코드에는 전체 클라우드 복구 키가 포함됩니다. 주변에 보이지 않는 곳에서만 표시하세요.',
                  es: 'Este QR contiene la clave de recuperacion completa. Muestralo solo en un lugar privado.',
                  de: 'Dieser QR-Code enthalt den vollstandigen Wiederherstellungsschlussel. Zeige ihn nur an einem privaten Ort.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _CloudRecoveryKeyQrImage(data: backupCode),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.close),
          ),
        ],
      );
    },
  );
}

class _CloudRecoveryKeyQrImage extends StatefulWidget {
  const _CloudRecoveryKeyQrImage({required this.data});

  final String data;

  @override
  State<_CloudRecoveryKeyQrImage> createState() =>
      _CloudRecoveryKeyQrImageState();
}

class _CloudRecoveryKeyQrImageState extends State<_CloudRecoveryKeyQrImage> {
  late Future<Uint8List> _imageBytes;

  @override
  void initState() {
    super.initState();
    _imageBytes = _renderQrPng(widget.data);
  }

  @override
  void didUpdateWidget(covariant _CloudRecoveryKeyQrImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _imageBytes = _renderQrPng(widget.data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 260,
      child: FutureBuilder<Uint8List>(
        future: _imageBytes,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return Semantics(
              label: 'qr code',
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
                gaplessPlayback: true,
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Icon(
                Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.error,
                size: 32,
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Future<Uint8List> _renderQrPng(String data) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      gapless: false,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
    final byteData = await painter.toImageData(
      720,
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) {
      throw StateError('Failed to render recovery key QR code.');
    }
    return byteData.buffer.asUint8List();
  }
}

Future<String?> _showSyncKeyQrScannerDialog(BuildContext context) {
  final strings = context.strings;
  if (!_syncKeyQrScannerSupported) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          strings.localized(
            en: 'QR scanning is unavailable',
            ja: 'QR読み取りを利用できません',
            zh: '无法扫描 QR',
            ko: 'QR 스캔을 사용할 수 없습니다',
            es: 'El escaneo QR no esta disponible',
            de: 'QR-Scan ist nicht verfugbar',
          ),
        ),
        content: Text(
          strings.localized(
            en: 'Use copy and paste to import the cloud recovery key on this platform.',
            ja: 'この環境では、コピーと貼り付けでクラウド復元キーをインポートしてください。',
            zh: '请在此平台上使用复制和粘贴导入云恢复密钥。',
            ko: '이 환경에서는 복사와 붙여넣기로 클라우드 복구 키를 가져오세요.',
            es: 'Usa copiar y pegar para importar la clave de recuperacion en esta plataforma.',
            de: 'Importiere den Cloud-Wiederherstellungsschlussel auf dieser Plattform per Kopieren und Einfugen.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.close),
          ),
        ],
      ),
    );
  }
  return showDialog<String>(
    context: context,
    builder: (context) => _SyncKeyQrScannerDialog(strings: strings),
  );
}

bool get _syncKeyQrScannerSupported {
  if (kIsWeb) {
    return true;
  }
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

class _SyncKeyQrScannerDialog extends StatefulWidget {
  const _SyncKeyQrScannerDialog({required this.strings});

  final AppStrings strings;

  @override
  State<_SyncKeyQrScannerDialog> createState() =>
      _SyncKeyQrScannerDialogState();
}

class _SyncKeyQrScannerDialogState extends State<_SyncKeyQrScannerDialog> {
  late final MobileScannerController _controller;
  bool _completed = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_completed) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) {
        continue;
      }
      if (!raw.startsWith(SyncBundleKeyService.backupCodePrefix)) {
        setState(() {
          _errorText = widget.strings.localized(
            en: 'This QR code is not a HiMemo cloud recovery key.',
            ja: 'このQRコードはHiMemoのクラウド復元キーではありません。',
            zh: '此 QR 码不是 HiMemo 云恢复密钥。',
            ko: '이 QR 코드는 HiMemo 클라우드 복구 키가 아닙니다.',
            es: 'Este QR no es una clave de recuperacion de HiMemo.',
            de: 'Dieser QR-Code ist kein HiMemo-Cloud-Wiederherstellungsschlussel.',
          );
        });
        continue;
      }
      _completed = true;
      Navigator.of(context).pop(raw);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return AlertDialog(
      title: Text(
        strings.localized(
          en: 'Scan recovery key QR',
          ja: '復元キーQRを読み取り',
          zh: '扫描恢复密钥 QR',
          ko: '복구 키 QR 스캔',
          es: 'Escanear QR de recuperacion',
          de: 'Wiederherstellungs-QR scannen',
        ),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.localized(
                en: 'Point the camera at the QR code shown on the other device.',
                ja: '別の端末に表示したQRコードをカメラに向けてください。',
                zh: '将相机对准另一台设备上显示的 QR 码。',
                ko: '다른 기기에 표시된 QR 코드를 카메라로 비추세요.',
                es: 'Apunta la camara al QR mostrado en el otro dispositivo.',
                de: 'Richte die Kamera auf den QR-Code auf dem anderen Gerat.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 1,
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _handleDetect,
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        error.errorDetails?.message ?? error.toString(),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
      ],
    );
  }
}

Future<void> _handleSyncKeyImport(
  BuildContext context,
  WidgetRef ref,
  String backupCode,
) async {
  final strings = context.strings;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final normalized = backupCode.trim();
    final currentFingerprint = await ref
        .read(syncBundleKeyServiceProvider)
        .fingerprint();
    if (!context.mounted) {
      return;
    }
    final incomingFingerprint = ref
        .read(syncBundleKeyServiceProvider)
        .previewBackupCodeFingerprint(normalized);
    final shouldImport =
        await _showSyncKeyImportConfirmDialog(
          context,
          currentFingerprint: currentFingerprint,
          incomingFingerprint: incomingFingerprint,
        ) ??
        false;
    if (!shouldImport || !context.mounted) {
      return;
    }
    final fingerprint = await ref
        .read(syncBundleKeyServiceProvider)
        .importBackupCode(normalized);
    ref.invalidate(syncBundleFingerprintProvider);
    ref.read(syncTransferControllerProvider.notifier).clearLocalBundleCache();
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        showCloseIcon: true,
        content: Text(strings.recoveryKeyImported(fingerprint)),
      ),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(showCloseIcon: true, content: Text('$error')),
    );
  }
}

Future<String?> _showSingleSecretPrompt(
  BuildContext context, {
  required String title,
  required String label,
  required String helperText,
  required String actionLabel,
}) {
  final strings = context.strings;
  final controller = TextEditingController();
  String? errorText;
  return showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    helperText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: label,
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.length < 4) {
                    setState(() {
                      errorText = strings.useAtLeast4Chars;
                    });
                    return;
                  }
                  Navigator.of(context).pop(value);
                },
                child: Text(actionLabel),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<String?> _showSecretSetupDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  required String helperText,
}) {
  final strings = context.strings;
  final secretController = TextEditingController();
  final confirmController = TextEditingController();
  String? errorText;

  return showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    helperText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: secretController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: label,
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: confirmLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final secret = secretController.text.trim();
                  final confirm = confirmController.text.trim();
                  if (secret.length < 4) {
                    setState(() {
                      errorText = strings.useAtLeast4Chars;
                    });
                    return;
                  }
                  if (secret != confirm) {
                    setState(() {
                      errorText = strings.keysDoNotMatch;
                    });
                    return;
                  }
                  Navigator.of(context).pop(secret);
                },
                child: Text(strings.save),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<bool?> _showSyncKeyImportConfirmDialog(
  BuildContext context, {
  required String currentFingerprint,
  required String incomingFingerprint,
}) {
  final strings = context.strings;
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(strings.replaceRecoveryKey),
        content: Text(
          strings.replaceRecoveryKeyBody(
            currentFingerprint: currentFingerprint,
            incomingFingerprint: incomingFingerprint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.replaceKey),
          ),
        ],
      );
    },
  );
}

part of 'home_page.dart';

String _localizedSyncTransferMessage(
  AppStrings strings,
  String message,
  SyncProvider provider,
) {
  final providerName = _syncProviderName(provider);
  if (message.startsWith('$localAttachmentMissingMessageCode\n')) {
    final parts = message.split('\n');
    final label = parts.length > 1 ? parts[1] : '';
    final title = parts.length > 2 ? parts.sublist(2).join(' ').trim() : '';
    final noteName = title.isEmpty
        ? strings.localized(en: 'a note', ja: '無題のメモ')
        : strings.localized(en: '"$title"', ja: '「$title」');
    return strings.localized(
      en: 'The attachment "$label" in $noteName is missing on this device and could not be restored from the cloud. Open the note, remove or replace that attachment, then sync again.',
      ja: '$noteNameの添付「$label」がこの端末になく、クラウドからも復元できませんでした。メモを開いてこの添付を削除するか差し替えてから、もう一度同期してください。',
    );
  }
  switch (message) {
    case 'sync.error.local_snapshot_incomplete':
      return strings.localized(
        en: 'Some notes are waiting to sync. Open the matching private profile on this device, then sync again.',
        ja: '一部のメモを同期できません。該当するプライベートプロファイルをこの端末で開いてから、もう一度「今すぐ同期」をタップしてください。',
        zh: '部分待同步笔记暂时无法上传。如果包含私密配置文件的笔记，请先在此设备上打开对应配置文件，然后再次同步。',
        ko: '일부 대기 중인 메모는 아직 업로드할 수 없습니다. 비공개 프로필 메모가 포함된 경우 이 기기에서 해당 프로필을 연 뒤 다시 동기화하세요.',
        es: 'Algunas notas pendientes todavia no se pueden subir. Si incluyen notas de perfiles privados, abre el perfil privado correspondiente en este dispositivo y vuelve a sincronizar.',
        de: 'Einige ausstehende Notizen konnen noch nicht hochgeladen werden. Wenn private Profilnotizen enthalten sind, offne das passende private Profil auf diesem Gerat und synchronisiere erneut.',
      );
    case 'sync.error.bundle_decryption_failed':
      return strings.localized(
        en: 'Could not read the cloud backup. Import the recovery key from the original device, then sync again. If private notes are included, open that profile here. If you repaired attachments on the original device, re-upload all notes there.',
        ja: 'クラウドのバックアップを読み込めません。元端末の復元キーを読み込んで再度同期してください。プライベートメモがある場合は該当プロファイルを開き、元端末で添付を修復した場合は全メモを再送してください。',
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
        en: 'Open every private profile on this device before cleaning up iCloud storage. This keeps its attachments safe.',
        ja: 'iCloudの保存領域を整理する前に、この端末ですべてのプライベートプロファイルを開いてください。添付ファイルの削除を防げます。',
        zh: '压缩 iCloud 同步存储前，请先在此设备上打开所有私密档案，以免锁定档案中的附件被清理。',
        ko: 'iCloud 동기화 저장 공간을 정리하기 전에 이 기기에서 모든 비공개 프로필을 여세요. 잠긴 프로필의 첨부 파일이 정리되지 않도록 합니다.',
        es: 'Abre todos los perfiles privados en este dispositivo antes de compactar el almacenamiento de sincronizacion de iCloud. Asi se evita eliminar adjuntos privados mientras el perfil esta bloqueado.',
        de: 'Offne alle privaten Profile auf diesem Gerat, bevor du den iCloud-Sync-Speicher bereinigst. So werden private Anhange nicht entfernt, solange ihr Profil gesperrt ist.',
      );
    case 'sync.error.unlock_private_profiles_before_full_upload':
      return strings.localized(
        en: 'Open every private profile on this device before sending all notes. This keeps private notes and attachments included.',
        ja: 'すべてのメモを送る前に、この端末ですべてのプライベートプロファイルを開いてください。プライベートメモと添付を含められます。',
        zh: '上传完整同步快照前，请先在此设备上打开所有私密档案，以保留锁定档案中的备忘和附件。',
        ko: '전체 동기화 스냅샷을 업로드하기 전에 이 기기에서 모든 비공개 프로필을 여세요. 잠긴 비공개 메모와 첨부 파일을 스냅샷에 보존합니다.',
        es: 'Abre todos los perfiles privados en este dispositivo antes de subir una instantánea de sincronización completa. Así se conservan las notas y los adjuntos privados bloqueados.',
        de: 'Offne alle privaten Profile auf diesem Gerat, bevor du einen vollstandigen Synchronisations-Schnappschuss hochladst. So bleiben gesperrte private Notizen und Anhange erhalten.',
      );
    case 'sync.error.bundle_key_missing':
      return strings.localized(
        en: 'This device is missing the cloud recovery key. Copy it from the original device, import it here, then sync again.',
        ja: 'この端末にクラウド復元キーがありません。元端末でキーをコピーしてこの端末に読み込み、「今すぐ同期」をタップしてください。',
        zh: '此设备没有读取同步包所需的云恢复密钥。请从原设备复制云恢复密钥并在此设备导入，然后再次同步。',
        ko: '이 기기에 동기화 번들을 읽는 데 필요한 클라우드 복구 키가 없습니다. 원래 기기에서 키를 복사해 이 기기로 가져온 뒤 다시 동기화하세요.',
        es: 'La clave de recuperacion en la nube para este paquete no esta disponible en este dispositivo. Copiala desde el dispositivo original, importala aqui y sincroniza de nuevo.',
        de: 'Der Cloud-Wiederherstellungsschlussel fur dieses Synchronisierungspaket ist auf diesem Gerat nicht verfugbar. Kopiere ihn vom ursprunglichen Gerat, importiere ihn hier und synchronisiere erneut.',
      );
    case 'sync.error.icloud_keychain_waiting':
      return strings.localized(
        en: 'The cloud recovery key has not reached this device yet. Wait a moment and try again, or import the key from the original device.',
        ja: 'クラウド復元キーがまだこの端末に届いていません。少し待って再試行するか、元端末からキーを読み込んでください。',
        zh: '此设备还没有读取同步包所需的云恢复密钥。可能正在等待 iCloud Keychain 同步。请稍后重试，或从原设备复制云恢复密钥并在此设备导入。',
        ko: '이 기기에 동기화 번들을 읽는 데 필요한 클라우드 복구 키가 아직 없습니다. iCloud Keychain 동기화 대기 중일 수 있습니다. 잠시 후 다시 시도하거나 원래 기기에서 키를 복사해 가져오세요.',
        es: 'La clave de recuperacion en la nube para este paquete aun no esta en este dispositivo. Es posible que iCloud Keychain siga sincronizando. Espera un poco e intentalo de nuevo, o copia la clave desde el dispositivo original e importala aqui.',
        de: 'Der Cloud-Wiederherstellungsschlussel fur dieses Paket ist noch nicht auf diesem Gerat. iCloud Keychain synchronisiert moglicherweise noch. Warte kurz und versuche es erneut oder importiere den Schlussel vom ursprunglichen Gerat.',
      );
    case 'sync.info.select_target_for_remote_status':
      return strings.localized(
        en: 'Choose a cloud backup location before checking its status.',
        ja: '状態を確認する前に、クラウドの保存先を選んでください。',
        zh: '请先选择云同步目标，再检查远程状态。',
        ko: '원격 상태를 확인하기 전에 클라우드 동기화 대상을 선택하세요.',
        es: 'Selecciona un destino de sincronizacion en la nube antes de comprobar el estado remoto.',
        de: 'Wahle zuerst ein Cloud-Synchronisierungsziel aus, bevor du den Remote-Status prufst.',
      );
    case 'sync.info.no_remote_bundle':
      return strings.localized(
        en: 'No cloud backup has been saved yet.',
        ja: 'クラウドにバックアップがまだありません。',
        zh: '远程还没有保存同步包。',
        ko: '원격에 저장된 번들이 아직 없습니다.',
        es: 'Todavia no se ha guardado ningun paquete remoto.',
        de: 'Es wurde noch kein Remote-Paket gespeichert.',
      );
    case 'sync.info.remote_bundle_refreshed':
      return strings.localized(
        en: '$providerName backup status was refreshed.',
        ja: '$providerName のバックアップ状態を更新しました。',
        zh: '$providerName 的同步包信息已更新。',
        ko: '$providerName 번들 정보를 새로 고쳤습니다.',
        es: 'Se actualizo la informacion del paquete de $providerName.',
        de: 'Die Paketinformationen von $providerName wurden aktualisiert.',
      );
    case 'sync.error.select_target_for_upload':
    case 'sync.error.select_target_for_reupload':
    case 'sync.error.select_target_for_download':
      return strings.localized(
        en: 'Choose a cloud backup location first.',
        ja: '先にクラウドの保存先を選んでください。',
        zh: '请先选择云同步目标再继续。',
        ko: '계속하기 전에 클라우드 동기화 대상을 선택하세요.',
        es: 'Selecciona un destino de sincronizacion en la nube antes de continuar.',
        de: 'Wahle zuerst ein Cloud-Synchronisierungsziel aus, bevor du fortfahrst.',
      );
    case 'sync.error.conflict_download_first_or_force_upload':
      return strings.localized(
        en: 'This device has unsynced changes, and the cloud backup may be newer. Get the cloud backup first, or choose Force upload to replace it with this device’s notes.',
        ja: 'この端末に未同期の変更があり、クラウドのバックアップの方が新しい可能性があります。先にクラウドのバックアップを取得するか、この端末の内容で上書きするなら「強制アップロード」を選んでください。',
        zh: '此设备有未同步的更改，远程包可能更新。请先下载并应用远程包；如果要用此设备覆盖远程包，请使用强制上传。',
        ko: '이 기기에 미동기화 변경 사항이 있고 원격 번들이 더 최신일 수 있습니다. 먼저 원격 번들을 다운로드해 적용하거나, 이 기기로 덮어쓰려면 강제 업로드를 사용하세요.',
        es: 'Este dispositivo tiene cambios sin sincronizar y el paquete remoto puede ser mas reciente. Descarga y aplica primero el paquete remoto, o usa la subida forzada si quieres sobrescribirlo desde este dispositivo.',
        de: 'Dieses Gerat hat nicht synchronisierte Anderungen und das Remote-Paket ist moglicherweise neuer. Lade es zuerst herunter und wende es an, oder nutze erzwungenes Hochladen, wenn dieses Gerat das Remote-Paket uberschreiben soll.',
      );
    case 'sync.error.conflict_pending_remote_newer':
      return strings.localized(
        en: 'This device has unsynced changes, and a newer cloud backup exists. Get it first, or review the changes before syncing.',
        ja: 'この端末に未同期の変更があり、クラウドに新しいバックアップがあります。先に取得するか、変更を確認してから同期してください。',
        zh: '此设备有未同步的更改，远程同步目标上有较新的捆绑包。',
        ko: '이 기기에 동기화되지 않은 변경 사항이 있으며, 원격 동기화 대상에 더 새로운 번들이 있습니다.',
        es: 'Este dispositivo tiene cambios sin sincronizar y hay un paquete mas reciente en el destino remoto.',
        de: 'Dieses Gerat hat nicht synchronisierte Anderungen, und auf dem Remote-Synchronisierungsziel liegt ein neueres Paket vor.',
      );
    case 'sync.error.conflict_remote_changed_after_review':
      return strings.localized(
        en: 'The cloud backup changed while you were reviewing it. Reload the comparison, then sync again.',
        ja: '確認中にクラウドのバックアップが更新されました。比較を読み直してから、もう一度同期してください。',
        zh: '打开比较画面后，远程版本已更新。你的选择已保存在此设备上，但为避免覆盖，尚未上传。请重新加载比较结果后再同步。',
        ko: '비교 화면을 연 뒤 원격 버전이 변경되었습니다. 선택 결과는 이 기기에 저장되었지만 덮어쓰기를 막기 위해 업로드하지 않았습니다. 비교를 다시 불러온 뒤 동기화하세요.',
        es: 'La version remota cambio despues de abrir la comparacion. Tu eleccion se guardo en este dispositivo, pero no se subio para evitar una sobrescritura. Vuelve a cargar la comparacion antes de sincronizar.',
        de: 'Die Remote-Version wurde nach dem Offnen des Vergleichs geandert. Deine Auswahl ist auf diesem Gerat gespeichert, wurde aber zum Schutz vor Uberschreiben nicht hochgeladen. Lade den Vergleich vor dem Synchronisieren neu.',
      );
    case 'sync.error.local_bundle_prepare_failed':
      return strings.localized(
        en: 'This device could not prepare the backup. Try syncing again.',
        ja: 'この端末でバックアップを準備できませんでした。「今すぐ同期」をもう一度試してください。',
        zh: '无法准备本地同步包。',
        ko: '로컬 동기화 번들을 준비할 수 없습니다.',
        es: 'No se pudo preparar el paquete de sincronizacion local.',
        de: 'Das lokale Synchronisierungspaket konnte nicht vorbereitet werden.',
      );
    case 'sync.error.remote_history_incomplete':
      return strings.localized(
        en: 'The cloud history has no complete backup to restore from. On another device that still has all your notes, choose Re-upload all notes, then sync this device again.',
        ja: '復元に必要な全件バックアップがクラウドにありません。全メモが残っている別の端末で「全件再アップロード」を実行してから、この端末で再同期してください。',
        zh: '云端缺少完整备份。请在仍保存全部笔记的另一台设备上重新上传全部笔记，然后在此设备同步。',
        ko: '클라우드에 전체 백업이 없습니다. 모든 메모가 남아 있는 다른 기기에서 전체 메모를 다시 업로드한 후 이 기기를 동기화하세요.',
        es: 'No hay una copia completa en la nube. Vuelve a subir todas las notas desde otro dispositivo que las conserve y sincroniza este dispositivo.',
        de: 'In der Cloud fehlt eine vollständige Sicherung. Lade alle Notizen von einem anderen Gerät erneut hoch und synchronisiere dieses Gerät danach.',
      );
    case 'sync.error.remote_bundle_missing':
      return strings.localized(
        en: 'The cloud backup is incomplete, so nothing changed. Check your connection and tap Sync again.',
        ja: 'クラウドのバックアップを確認できなかったため、変更していません。通信状態を確認して「今すぐ同期」をもう一度タップしてください。',
        zh: '远程同步历史记录不完整，因此未应用任何更改。请检查网络连接后重试。',
        ko: '원격 동기화 기록이 완전하지 않아 변경 사항을 적용하지 않았습니다. 연결을 확인한 후 다시 동기화하세요.',
        es: 'El historial de sincronizacion remoto esta incompleto. No se aplicaron cambios. Comprueba la conexion y vuelve a sincronizar.',
        de: 'Der Remote-Synchronisierungsverlauf ist unvollstandig. Es wurden keine Anderungen angewendet. Prufe die Verbindung und synchronisiere erneut.',
      );
    case 'sync.error.private_note_conflict':
      return strings.localized(
        en: 'The same private note changed on both devices. Nothing was overwritten. Review both versions and choose which one to keep.',
        ja: '同じプライベートメモが両方の端末で変更されています。上書きはしていません。2つの内容を確認して、残す方を選んでください。',
        zh: '同一条私密笔记已在两台设备上更改。两个版本均未被覆盖。请确认内容后再选择要上传的版本。',
        ko: '같은 비공개 메모가 두 기기에서 변경되었습니다. 어느 버전도 덮어쓰지 않았습니다. 내용을 확인한 후 업로드할 버전을 선택하세요.',
        es: 'La misma nota privada se modifico en ambos dispositivos. No se sobrescribio ninguna version. Revisa ambos dispositivos antes de elegir que version subir.',
        de: 'Dieselbe private Notiz wurde auf beiden Geraten geandert. Keine Version wurde uberschrieben. Prufe beide Gerate, bevor du eine Version hochladst.',
      );
    case 'sync.error.private_profile_unlock_required':
      return strings.localized(
        en: 'Unlock the affected private profile to compare its pending note before syncing.',
        ja: '保留中のメモを安全に比較するため、該当するプライベートプロファイルを解除してから同期してください。',
        zh: '请先解锁相应的私密档案，再同步待处理的笔记。',
        ko: '보류 중인 메모를 비교할 수 있도록 해당 비공개 프로필을 먼저 잠금 해제하세요.',
        es: 'Desbloquea el perfil privado correspondiente para comparar la nota pendiente antes de sincronizar.',
        de: 'Entsperre das betroffene private Profil, um die ausstehende Notiz vor der Synchronisierung zu vergleichen.',
      );
    case 'sync.error.malformed_private_note':
      return strings.localized(
        en: 'The cloud backup contains invalid private-note data. Nothing changed. Try syncing again.',
        ja: 'クラウドのバックアップに不正なプライベートメモのデータがあるため、変更していません。「今すぐ同期」をもう一度試してください。',
        zh: '远程同步包中包含无效的私密笔记数据，因此未应用任何更改。',
        ko: '원격 번들에 잘못된 비공개 메모 데이터가 있어 변경 사항을 적용하지 않았습니다.',
        es: 'El paquete remoto contiene una entrada de nota privada no valida. No se aplicaron cambios.',
        de: 'Das Remote-Paket enthalt einen ungultigen privaten Notizeintrag. Es wurden keine Anderungen angewendet.',
      );
    case 'sync.error.remote_attachment_unavailable':
      return strings.localized(
        en: 'A required cloud attachment is not ready yet. Wait for the cloud to finish updating, then sync again.',
        ja: '必要な添付ファイルをクラウドからまだ取得できません。クラウドの更新が終わってから、もう一度「今すぐ同期」をタップしてください。',
        zh: '所需的远程附件尚不可用。同步包未标记为已应用，请等待云端更新完成后重试。',
        ko: '필요한 원격 첨부 파일을 아직 사용할 수 없습니다. 번들을 적용 완료로 표시하지 않았으므로 클라우드 업데이트 후 다시 동기화하세요.',
        es: 'Un adjunto remoto necesario aun no esta disponible. El paquete no se marco como aplicado; vuelve a sincronizar cuando termine la actualizacion en la nube.',
        de: 'Ein erforderlicher Remote-Anhang ist noch nicht verfugbar. Das Paket wurde nicht als angewendet markiert; synchronisiere nach Abschluss der Cloud-Aktualisierung erneut.',
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
        en: 'Your encrypted backup was sent to $providerName.',
        ja: '暗号化したバックアップを $providerName に保存しました。',
        zh: '已将加密同步包上传到 $providerName。',
        ko: '암호화된 번들을 $providerName에 업로드했습니다.',
        es: 'Paquete cifrado subido a $providerName.',
        de: 'Verschlusseltes Paket wurde zu $providerName hochgeladen.',
      );
    case 'sync.error.conflict_review_remote':
      return strings.localized(
        en: 'This device has unsynced changes, and the cloud backup may be newer. Review the cloud changes before syncing.',
        ja: 'この端末に未同期の変更があり、クラウドのバックアップの方が新しい可能性があります。クラウドの変更を確認してから同期してください。',
        zh: '此设备有未同步的更改，远程包可能更新。请先确认远程更改再同步。',
        ko: '이 기기에 미동기화 변경 사항이 있고 원격 번들이 더 최신일 수 있습니다. 동기화하기 전에 원격 변경 사항을 확인하세요.',
        es: 'Este dispositivo tiene cambios sin sincronizar y el paquete remoto puede ser mas reciente. Revisa los cambios remotos antes de sincronizar.',
        de: 'Dieses Gerat hat nicht synchronisierte Anderungen und das Remote-Paket ist moglicherweise neuer. Prufe die Remote-Anderungen vor der Synchronisierung.',
      );
    case 'sync.info.no_bundle_to_sync':
    case 'sync.info.no_usable_remote_bundle':
      return strings.localized(
        en: 'There is no usable cloud backup in $providerName.',
        ja: '$providerName に利用できるバックアップがありません。',
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
        en: 'The selected cloud backup could not be downloaded.',
        ja: '選択したクラウドのバックアップを取得できませんでした。',
        zh: '无法下载选定的远程同步包。',
        ko: '선택한 원격 번들을 다운로드할 수 없습니다.',
        es: 'No se pudo descargar el paquete remoto seleccionado.',
        de: 'Das ausgewahlte Remote-Paket konnte nicht heruntergeladen werden.',
      );
    case 'sync.error.download_before_apply':
    case 'sync.error.download_before_review':
      return strings.localized(
        en: 'Get the cloud backup before continuing.',
        ja: '続行する前にクラウドのバックアップを取得してください。',
        zh: '请先下载远程包再继续。',
        ko: '계속하기 전에 원격 번들을 다운로드하세요.',
        es: 'Descarga un paquete remoto antes de continuar.',
        de: 'Lade zuerst ein Remote-Paket herunter, bevor du fortfahrst.',
      );
    case 'sync.error.downloaded_bundle_decryption_failed':
      return strings.localized(
        en: 'The downloaded backup could not be read. Check the recovery key and try again.',
        ja: '取得したバックアップを読み込めませんでした。復元キーを確認して、もう一度試してください。',
        zh: '无法解密已下载的同步包。',
        ko: '다운로드한 번들을 복호화할 수 없습니다.',
        es: 'No se pudo descifrar el paquete descargado.',
        de: 'Das heruntergeladene Paket konnte nicht entschlusselt werden.',
      );
    case 'sync.error.attachment_object_hash_mismatch':
      return strings.localized(
        en: 'A downloaded attachment is damaged or outdated. On the original device, re-upload all notes, then sync again.',
        ja: '取得した添付ファイルが壊れているか古い可能性があります。元端末で全メモを再アップロードしてから、「今すぐ同期」をもう一度タップしてください。',
        zh: '下载的附件与同步元数据不匹配。请从原设备重新上传全部备忘后再同步。',
        ko: '다운로드한 첨부가 동기화 메타데이터와 일치하지 않습니다. 원래 기기에서 모든 메모를 다시 업로드한 뒤 동기화하세요.',
        es: 'Un adjunto descargado no coincide con sus metadatos de sincronizacion. Vuelve a subir todas las notas desde el dispositivo original y sincroniza de nuevo.',
        de: 'Ein heruntergeladener Anhang passt nicht zu seinen Synchronisierungsmetadaten. Lade alle Notizen vom ursprunglichen Gerat erneut hoch und synchronisiere noch einmal.',
      );
    case 'sync.error.private_profile_locked':
      return strings.localized(
        en: 'This backup contains private notes. Open the matching profile on this device, then sync again.',
        ja: 'このバックアップにはプライベートメモが含まれています。この端末で該当するプロファイルを開いてから、「今すぐ同期」をもう一度タップしてください。',
        zh: '此同步包包含私密配置文件的备忘。请在此设备输入相同的配置文件密码并打开该配置文件，然后再次应用同步包。',
        ko: '이 번들에는 개인 프로필 메모가 포함되어 있습니다. 이 기기에서 동일한 프로필 비밀번호를 입력해 프로필을 연 뒤 번들을 다시 적용하세요.',
        es: 'Este paquete contiene notas de perfiles privados. Introduce la misma contrasena de perfil en este dispositivo, abre ese perfil y vuelve a aplicar el paquete.',
        de: 'Dieses Paket enthalt Notizen privater Profile. Gib auf diesem Gerat dasselbe Profilpasswort ein, offne das Profil und wende das Paket erneut an.',
      );
    case 'sync.info.apply_success':
      return strings.localized(
        en: 'The cloud backup was restored to this device.',
        ja: 'クラウドのバックアップをこの端末に復元しました。',
        zh: '已将下载的同步包应用到本地笔记。',
        ko: '다운로드한 번들을 로컬 노트에 적용했습니다.',
        es: 'Paquete descargado aplicado a las notas locales.',
        de: 'Heruntergeladenes Paket wurde auf lokale Notizen angewendet.',
      );
    case 'sync.info.private_profile_notes_pending_unlock':
      return strings.localized(
        en: 'Sync completed. Open the matching private profile on this device to finish restoring its notes.',
        ja: '同期は完了しました。該当するプライベートプロファイルをこの端末で開くと、メモの復元が完了します。',
        zh: '同步已完成。私人配置文件中的笔记会在你在此设备上打开对应配置文件后应用。',
        ko: '동기화가 완료되었습니다. 비공개 프로필 메모는 이 기기에서 해당 프로필을 연 뒤 적용됩니다.',
        es: 'La sincronizacion se completo. Las notas de perfiles privados se aplicaran cuando abras el perfil privado correspondiente en este dispositivo.',
        de: 'Die Synchronisierung ist abgeschlossen. Notizen privater Profile werden angewendet, nachdem du das passende private Profil auf diesem Gerat geoffnet hast.',
      );
    case 'sync.info.deferred_attachments_downloaded':
      return strings.localized(
        en: 'Missing attachments were downloaded.',
        ja: '不足していた添付ファイルを取得しました。',
        zh: '已下载待处理附件。',
        ko: '보류 중인 첨부를 다운로드했습니다.',
        es: 'Se descargaron los adjuntos pendientes.',
        de: 'Ausstehende Anhänge wurden heruntergeladen.',
      );
    case 'sync.info.no_deferred_attachments':
      return strings.localized(
        en: 'There are no missing attachments to get.',
        ja: '取得が必要な添付ファイルはありません。',
        zh: '没有需要下载的待处理附件。',
        ko: '다운로드할 보류 중인 첨부가 없습니다.',
        es: 'No hay adjuntos pendientes para descargar.',
        de: 'Keine ausstehenden Anhänge zum Herunterladen.',
      );
    case 'sync.info.remote_bundle_saved_locally':
      return strings.localized(
        en: 'The $providerName backup was saved securely on this device.',
        ja: '$providerName のバックアップをこの端末に安全に保存しました。',
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
      en: 'This device is missing the cloud recovery key. Copy it from the original device, import it here, then sync again.',
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
      en: 'The cloud recovery key has not reached this device yet. Wait a moment and try again, or import the key from the original device.',
      ja: message,
      zh: '此设备还没有读取同步包所需的云恢复密钥。可能正在等待 iCloud Keychain 同步。请稍后重试，或从原设备复制云恢复密钥并在此设备导入。',
      ko: '이 기기에 동기화 번들을 읽는 데 필요한 클라우드 복구 키가 아직 없습니다. iCloud Keychain 동기화 대기 중일 수 있습니다. 잠시 후 다시 시도하거나 원래 기기에서 키를 복사해 가져오세요.',
      es: 'La clave de recuperacion en la nube para este paquete aun no esta en este dispositivo. Es posible que iCloud Keychain siga sincronizando. Espera un poco e intentalo de nuevo, o copia la clave desde el dispositivo original e importala aqui.',
      de: 'Der Cloud-Wiederherstellungsschlussel fur dieses Paket ist noch nicht auf diesem Gerat. iCloud Keychain synchronisiert moglicherweise noch. Warte kurz und versuche es erneut oder importiere den Schlussel vom ursprunglichen Gerat.',
    );
  }
  if (message == 'リモートの状態を確認するには、先にクラウド同期先を選択してください。') {
    return strings.localized(
      en: 'Choose a cloud backup location before checking its status.',
      ja: message,
      zh: '请先选择云同步目标，再检查远程状态。',
      ko: '원격 상태를 확인하기 전에 클라우드 동기화 대상을 선택하세요.',
      es: 'Selecciona un destino de sincronizacion en la nube antes de comprobar el estado remoto.',
      de: 'Wahle zuerst ein Cloud-Synchronisierungsziel aus, bevor du den Remote-Status prufst.',
    );
  }
  if (message == 'リモートにはまだバンドルが保存されていません。') {
    return strings.localized(
      en: 'No cloud backup has been saved yet.',
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
      en: 'This device has unsynced changes, and the cloud backup may be newer. Get it first, or choose Force upload to replace it with this device’s notes.',
      ja: message,
      zh: '此设备有未同步的更改，远程包可能更新。请先下载并应用远程包；如果要用此设备覆盖远程包，请使用强制上传。',
      ko: '이 기기에 미동기화 변경 사항이 있고 원격 번들이 더 최신일 수 있습니다. 먼저 원격 번들을 다운로드해 적용하거나, 이 기기로 덮어쓰려면 강제 업로드를 사용하세요.',
      es: 'Este dispositivo tiene cambios sin sincronizar y el paquete remoto puede ser mas reciente. Descarga y aplica primero el paquete remoto, o usa la subida forzada si quieres sobrescribirlo desde este dispositivo.',
      de: 'Dieses Gerat hat nicht synchronisierte Anderungen und das Remote-Paket ist moglicherweise neuer. Lade es zuerst herunter und wende es an, oder nutze erzwungenes Hochladen, wenn dieses Gerat das Remote-Paket uberschreiben soll.',
    );
  }
  if (message.contains('リモートの変更を確認してから同期してください。')) {
    return strings.localized(
      en: 'This device has unsynced changes, and the cloud backup may be newer. Review the cloud changes before syncing.',
      ja: message,
      zh: '此设备有未同步的更改，远程包可能更新。请先确认远程更改再同步。',
      ko: '이 기기에 미동기화 변경 사항이 있고 원격 번들이 더 최신일 수 있습니다. 동기화하기 전에 원격 변경 사항을 확인하세요.',
      es: 'Este dispositivo tiene cambios sin sincronizar y el paquete remoto puede ser mas reciente. Revisa los cambios remotos antes de sincronizar.',
      de: 'Dieses Gerat hat nicht synchronisierte Anderungen und das Remote-Paket ist moglicherweise neuer. Prufe die Remote-Anderungen vor der Synchronisierung.',
    );
  }
  if (message == 'ローカルの同期バンドルを準備できませんでした。') {
    return strings.localized(
      en: 'This device could not prepare the backup. Try syncing again.',
      ja: message,
      zh: '无法准备本地同步包。',
      ko: '로컬 동기화 번들을 준비할 수 없습니다.',
      es: 'No se pudo preparar el paquete de sincronizacion local.',
      de: 'Das lokale Synchronisierungspaket konnte nicht vorbereitet werden.',
    );
  }
  if (message == '暗号化したバンドルを $providerName にアップロードしました。') {
    return strings.localized(
      en: 'Your encrypted backup was sent to $providerName.',
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
      en: 'There is no usable cloud backup in $providerName.',
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
      en: 'Get the cloud backup before continuing.',
      ja: message,
      zh: '请先下载远程包再继续。',
      ko: '계속하기 전에 원격 번들을 다운로드하세요.',
      es: 'Descarga un paquete remoto antes de continuar.',
      de: 'Lade zuerst ein Remote-Paket herunter, bevor du fortfahrst.',
    );
  }
  if (message == 'ダウンロードしたバンドルを復号できませんでした。') {
    return strings.localized(
      en: 'The downloaded backup could not be read. Check the recovery key and try again.',
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
      en: 'This backup contains private notes. Open the matching profile on this device, then sync again.',
      ja: message,
      zh: '此同步包包含私密配置文件的备忘。请在此设备输入相同的配置文件密码并打开该配置文件，然后再次应用同步包。',
      ko: '이 번들에는 개인 프로필 메모가 포함되어 있습니다. 이 기기에서 동일한 프로필 비밀번호를 입력해 프로필을 연 뒤 번들을 다시 적용하세요.',
      es: 'Este paquete contiene notas de perfiles privados. Introduce la misma contrasena de perfil en este dispositivo, abre ese perfil y vuelve a aplicar el paquete.',
      de: 'Dieses Paket enthalt Notizen privater Profile. Gib auf diesem Gerat dasselbe Profilpasswort ein, offne das Profil und wende das Paket erneut an.',
    );
  }
  if (message == 'ダウンロードしたバンドルをローカルのノートに反映しました。') {
    return strings.localized(
      en: 'The cloud backup was restored to this device.',
      ja: message,
      zh: '已将下载的同步包应用到本地笔记。',
      ko: '다운로드한 번들을 로컬 노트에 적용했습니다.',
      es: 'Paquete descargado aplicado a las notas locales.',
      de: 'Heruntergeladenes Paket wurde auf lokale Notizen angewendet.',
    );
  }
  if (message.contains('のリモートバンドルをローカルの保護ストレージに保存しました。')) {
    return strings.localized(
      en: 'The $providerName backup was saved securely on this device.',
      ja: message,
      zh: '已将 $providerName 远程包保存到本地受保护存储。',
      ko: '$providerName 원격 번들을 로컬 보호 저장소에 저장했습니다.',
      es: 'El paquete remoto de $providerName se guardo en el almacenamiento local protegido.',
      de: 'Das Remote-Paket von $providerName wurde im geschutzten lokalen Speicher abgelegt.',
    );
  }
  return message;
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
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(showCloseIcon: true, content: Text(message)));
}

enum NoteConflictResolutionAction { keepLocal, useRemote, merge }

enum NoteConflictResolutionOutcomeKind { resolved, pendingSync, cancelled }

@immutable
class NoteConflictResolutionOutcome {
  const NoteConflictResolutionOutcome._(this.kind, this.message);

  const NoteConflictResolutionOutcome.resolved()
    : this._(NoteConflictResolutionOutcomeKind.resolved, null);

  const NoteConflictResolutionOutcome.pendingSync(String message)
    : this._(NoteConflictResolutionOutcomeKind.pendingSync, message);

  const NoteConflictResolutionOutcome.cancelled()
    : this._(NoteConflictResolutionOutcomeKind.cancelled, null);

  final NoteConflictResolutionOutcomeKind kind;
  final String? message;
}

typedef NoteConflictRemoteLoader = Future<PreparedSyncNote?> Function();
typedef NoteConflictResolver = Future<NoteConflictResolutionOutcome> Function(
  NoteConflictResolutionAction action,
  PreparedSyncNote remoteChange,
);

Future<void> _showNoteConflictResolver(
  BuildContext context,
  WidgetRef ref,
  NoteEntry localNote,
) async {
  if (usesSyncV2NoteBackend) {
    final notes = ref.read(notesControllerProvider.notifier);
    final workspace = ref.read(syncV2WorkspaceProvider);
    if (await showSyncV2ConflictDialog(context, ref, localNote)) {
      await notes.reloadFromStorage();
      unawaited(workspace.syncNow().catchError((Object _) {}));
    }
    return;
  }
  final strings = context.strings;
  final messenger = ScaffoldMessenger.of(context);
  final outcome = await showDialog<NoteConflictResolutionOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) =>
        NoteConflictResolverDialog(localNote: localNote),
  );
  if (outcome == null) {
    await ref
        .read(notesControllerProvider.notifier)
        .cleanupUnreferencedAttachments();
    return;
  }
  if (!context.mounted) {
    return;
  }

  final message = outcome.kind == NoteConflictResolutionOutcomeKind.pendingSync
      ? outcome.message ??
            strings.localized(
              en: 'The choice was saved on this device, but cloud sync is still pending.',
              ja: 'この端末への反映は完了しましたが、クラウド同期は保留中です。',
            )
      : strings.localized(
          en: 'Note conflict resolved.',
          ja: 'メモの競合を解決しました。',
          zh: '笔记冲突已解决。',
          ko: '메모 충돌이 해결되었습니다.',
          es: 'Conflicto de nota resuelto.',
          de: 'Notizkonflikt gelost.',
        );
  messenger.showSnackBar(SnackBar(showCloseIcon: true, content: Text(message)));
}

enum _NoteConflictDisplayMode { overview, details }

class NoteConflictResolverDialog extends ConsumerStatefulWidget {
  const NoteConflictResolverDialog({
    super.key,
    required this.localNote,
    this.loadRemote,
    this.resolve,
  });

  static const displayModeKey = Key('note-conflict-display-mode');
  static const keepLocalOptionKey = Key('note-conflict-keep-local');
  static const useRemoteOptionKey = Key('note-conflict-use-remote');
  static const mergeOptionKey = Key('note-conflict-merge');
  static const resolveButtonKey = Key('note-conflict-resolve-button');
  static const cancelButtonKey = Key('note-conflict-cancel-button');
  static const retryButtonKey = Key('note-conflict-retry-button');
  static const busyOverlayKey = Key('note-conflict-busy-overlay');

  final NoteEntry localNote;
  final NoteConflictRemoteLoader? loadRemote;
  final NoteConflictResolver? resolve;

  @override
  ConsumerState<NoteConflictResolverDialog> createState() =>
      _NoteConflictResolverDialogState();
}

class _NoteConflictResolverDialogState
    extends ConsumerState<NoteConflictResolverDialog> {
  PreparedSyncNote? _remoteChange;
  NoteConflictResolutionAction? _selectedAction;
  _NoteConflictDisplayMode _displayMode = _NoteConflictDisplayMode.overview;
  bool _loadingRemote = true;
  bool _resolving = false;
  String? _errorText;
  String? _reviewedRemoteFileId;

  bool get _busy => _resolving;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_loadRemote());
      }
    });
  }

  Future<void> _loadRemote() async {
    setState(() {
      _loadingRemote = true;
      _remoteChange = null;
      _selectedAction = null;
      _errorText = null;
      _reviewedRemoteFileId = null;
    });
    final notes = ref.read(notesControllerProvider.notifier);
    final usesProductionLoader = widget.loadRemote == null;
    try {
      final remoteChange =
          await (widget.loadRemote?.call() ??
              ref
                  .read(syncTransferControllerProvider.notifier)
                  .downloadLatestRemoteNoteForConflict(widget.localNote.id));
      final reviewedRemoteFileId = usesProductionLoader
          ? ref.read(syncTransferControllerProvider).remoteStatus?.fileId
          : null;
      if (!mounted) {
        if (usesProductionLoader) {
          await _cleanupConflictAttachmentsBestEffort(notes);
        }
        return;
      }
      if (remoteChange == null) {
        setState(() {
          _loadingRemote = false;
          _errorText = _remoteLoadFailureMessage();
        });
        return;
      }
      setState(() {
        _remoteChange = remoteChange;
        _reviewedRemoteFileId = reviewedRemoteFileId;
        _loadingRemote = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load remote conflict version: $error\n$stackTrace');
      if (!mounted) {
        if (usesProductionLoader) {
          await _cleanupConflictAttachmentsBestEffort(notes);
        }
        return;
      }
      setState(() {
        _loadingRemote = false;
        _errorText = _resolutionFailureMessage();
      });
    }
  }

  String _remoteLoadFailureMessage() {
    final strings = context.strings;
    if (widget.loadRemote == null) {
      final transfer = ref.read(syncTransferControllerProvider);
      final message = transfer.message;
      if (transfer.stage == SyncTransferStage.error &&
          message != null &&
          message.isNotEmpty) {
        return _localizedSyncTransferMessage(
          strings,
          message,
          ref.read(syncProviderControllerProvider),
        );
      }
    }
    return strings.localized(
      en: 'The latest remote bundle does not contain a version of this note. Refresh sync and try again.',
      ja: '最新のリモートバンドルにこのメモの版がありません。同期を更新してから、もう一度お試しください。',
    );
  }

  String _resolutionFailureMessage() {
    final strings = context.strings;
    if (widget.resolve == null) {
      final transfer = ref.read(syncTransferControllerProvider);
      final message = transfer.message;
      if (transfer.stage == SyncTransferStage.error &&
          message != null &&
          message.isNotEmpty) {
        return _localizedSyncTransferMessage(
          strings,
          message,
          ref.read(syncProviderControllerProvider),
        );
      }
    }
    return strings.localized(
      en: 'Conflict resolution did not finish. Check the sync status and try again.',
      ja: '競合の解決を完了できませんでした。同期状態を確認して、もう一度お試しください。',
    );
  }

  Future<void> _resolveSelected() async {
    final action = _selectedAction;
    final remoteChange = _remoteChange;
    if (action == null || remoteChange == null || _resolving) {
      return;
    }
    setState(() {
      _resolving = true;
      _errorText = null;
    });
    try {
      final outcome =
          await (widget.resolve?.call(action, remoteChange) ??
              _resolveWithControllers(action, remoteChange));
      if (!mounted) {
        return;
      }
      if (outcome.kind == NoteConflictResolutionOutcomeKind.cancelled) {
        setState(() => _resolving = false);
        return;
      }
      Navigator.of(context).pop(outcome);
    } catch (error, stackTrace) {
      debugPrint('Failed to resolve note conflict: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      setState(() {
        _resolving = false;
        _errorText = _resolutionFailureMessage();
      });
    }
  }

  Future<NoteConflictResolutionOutcome> _resolveWithControllers(
    NoteConflictResolutionAction action,
    PreparedSyncNote remoteChange,
  ) async {
    final notes = ref.read(notesControllerProvider.notifier);
    final transfer = ref.read(syncTransferControllerProvider.notifier);
    switch (action) {
      case NoteConflictResolutionAction.keepLocal:
        final confirmed = await _confirmLargeMobileConflictUploadIfNeeded(
          context,
          ref,
        );
        if (!confirmed) {
          return const NoteConflictResolutionOutcome.cancelled();
        }
        final isPrivate = isPrivateVaultId(widget.localNote.vaultId);
        final remoteContentHash = remoteChange.note.contentHash;
        if (isPrivate &&
            (remoteContentHash == null || remoteContentHash.isEmpty)) {
          throw StateError('sync.error.private_conflict_review_expired');
        }
        await notes.resolveConflictKeepingLocal(
          widget.localNote.id,
          remoteRevision: remoteChange.note.revision,
        );
        // Record the choice only after the local version is committed, so a
        // failed resolution never silently skips the remote version later.
        if (isPrivate) {
          await ref
              .read(syncBundleStateStoreProvider)
              .rememberLocalPrivateConflictChoice(
                widget.localNote.id,
                remoteContentHash!,
              );
        }
        try {
          await transfer.uploadCurrentBundle(
            deltaOnly: true,
            expectedRemoteFileId: _reviewedRemoteFileId,
            onlyPendingNoteIds: {widget.localNote.id},
            allowLargeMobileTransfer: true,
          );
          return _uploadOutcome();
        } catch (error, stackTrace) {
          debugPrint(
            'Conflict choice was saved but upload failed: '
            '$error\n$stackTrace',
          );
          return _postCommitFailureOutcome();
        } finally {
          await _cleanupConflictAttachmentsBestEffort(notes);
        }
      case NoteConflictResolutionAction.useRemote:
        if (remoteChange.action == PendingNoteChangeAction.delete) {
          await notes.resolveConflictUsingRemoteDelete(remoteChange.note);
        } else {
          await notes.resolveConflictUsingRemote(remoteChange.note);
        }
        await _cleanupConflictAttachmentsBestEffort(notes);
        return const NoteConflictResolutionOutcome.resolved();
      case NoteConflictResolutionAction.merge:
        final confirmed = await _confirmLargeMobileConflictUploadIfNeeded(
          context,
          ref,
        );
        if (!confirmed) {
          return const NoteConflictResolutionOutcome.cancelled();
        }
        await notes.resolveConflictByMerging(remoteChange.note);
        try {
          await transfer.uploadCurrentBundle(
            deltaOnly: true,
            expectedRemoteFileId: _reviewedRemoteFileId,
            onlyPendingNoteIds: {widget.localNote.id},
            allowLargeMobileTransfer: true,
          );
          return _uploadOutcome();
        } catch (error, stackTrace) {
          debugPrint(
            'Merged conflict was saved but upload failed: '
            '$error\n$stackTrace',
          );
          return _postCommitFailureOutcome();
        } finally {
          await _cleanupConflictAttachmentsBestEffort(notes);
        }
    }
  }

  Future<void> _cleanupConflictAttachmentsBestEffort(
    NotesController notes,
  ) async {
    try {
      await notes.cleanupUnreferencedAttachments();
    } catch (error, stackTrace) {
      debugPrint(
        'Conflict attachment cleanup will be retried later: '
        '$error\n$stackTrace',
      );
    }
  }

  NoteConflictResolutionOutcome _postCommitFailureOutcome() {
    return NoteConflictResolutionOutcome.pendingSync(
      context.strings.localized(
        en: 'The choice was saved on this device, but cloud sync is still pending. Open Sync status to try again.',
        ja: 'この端末への反映は完了しましたが、クラウド同期は保留中です。同期状態から再試行してください。',
      ),
    );
  }

  NoteConflictResolutionOutcome _uploadOutcome() {
    final transfer = ref.read(syncTransferControllerProvider);
    if (transfer.stage != SyncTransferStage.error) {
      return const NoteConflictResolutionOutcome.resolved();
    }
    final detail = _localizedSyncTransferMessage(
      context.strings,
      transfer.message ?? 'sync.error.conflict_review_remote',
      ref.read(syncProviderControllerProvider),
    );
    return NoteConflictResolutionOutcome.pendingSync(
      context.strings.localized(
        en: 'The choice was saved on this device, but it could not be uploaded yet. $detail',
        ja: 'この端末への反映は完了しましたが、クラウドへのアップロードは完了していません。$detail',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final size = MediaQuery.sizeOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final ready = _remoteChange != null && !_loadingRemote;
    final useFullScreen =
        size.height < 700 || size.width < 360 || textScale > 1.3;
    final contentHeight = ready
        ? math.min(620.0, math.max(400.0, size.height * 0.64))
        : 220.0;
    final title = strings.localized(
      en: 'Resolve note conflict',
      ja: 'メモの競合を解決',
      zh: '解决笔记冲突',
      ko: '메모 충돌 해결',
      es: 'Resolver conflicto de nota',
      de: 'Notizkonflikt losen',
    );
    final content = _loadingRemote
        ? _buildRemoteLoading(context)
        : _remoteChange == null
        ? _buildRemoteFailure(context)
        : _buildReadyContent(context, _remoteChange!);
    final dialog = useFullScreen
        ? Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: Text(title),
                automaticallyImplyLeading: false,
              ),
              body: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: content,
                ),
              ),
              bottomNavigationBar: _buildFullScreenActionBar(context),
            ),
          )
        : AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            title: Text(title),
            content: SizedBox(
              width: 680,
              height: contentHeight,
              child: content,
            ),
            actions: _buildActions(context),
          );
    return PopScope(
      canPop: !_busy,
      child: Stack(
        alignment: Alignment.center,
        children: [
          dialog,
          if (_resolving)
            Positioned.fill(
              child: _ConflictBusyOverlay(
                key: NoteConflictResolverDialog.busyOverlayKey,
                label: _resolvingLabel(strings),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFullScreenActionBar(BuildContext context) {
    return Material(
      elevation: 3,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: _buildActions(context),
          ),
        ),
      ),
    );
  }

  Widget _buildRemoteLoading(BuildContext context) {
    final strings = context.strings;
    return Semantics(
      liveRegion: true,
      label: strings.localized(
        en: 'Loading the latest remote version',
        ja: 'リモートの最新版を読み込み中',
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              strings.localized(
                en: 'Loading the latest remote version...',
                ja: 'リモートの最新版を読み込んでいます…',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              strings.localized(
                en: 'Keep this screen open until the comparison is ready.',
                ja: '比較の準備ができるまで、この画面を開いたままにしてください。',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: _mutedTextColor(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteFailure(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _errorText ?? _resolutionFailureMessage(),
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadyContent(
    BuildContext context,
    PreparedSyncNote remoteChange,
  ) {
    final strings = context.strings;
    final mergeWouldBeRelevant =
        remoteChange.action != PendingNoteChangeAction.delete &&
        widget.localNote.deletedAt == null &&
        remoteChange.note.deletedAt == null;
    final canMerge =
        mergeWouldBeRelevant &&
        _canSafelyMergeConflict(widget.localNote, remoteChange.note);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.localized(
            en: 'Compare the two versions, select one resolution method, then confirm.',
            ja: '2つの版を比較し、解決方法を1つ選んでから確定してください。',
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<_NoteConflictDisplayMode>(
          key: NoteConflictResolverDialog.displayModeKey,
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: _NoteConflictDisplayMode.overview,
              icon: const Icon(Icons.view_agenda_outlined),
              label: Text(strings.localized(en: 'Overview', ja: '概要')),
            ),
            ButtonSegment(
              value: _NoteConflictDisplayMode.details,
              icon: const Icon(Icons.difference_outlined),
              label: Text(
                strings.localized(en: 'Detailed differences', ja: '詳細差分'),
              ),
            ),
          ],
          selected: {_displayMode},
          onSelectionChanged: _resolving
              ? null
              : (selection) {
                  setState(() => _displayMode = selection.first);
                },
        ),
        const SizedBox(height: 12),
        if (_errorText != null) ...[
          _ConflictInlineError(message: _errorText!),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_displayMode == _NoteConflictDisplayMode.overview)
                  _ConflictOverview(
                    localNote: widget.localNote,
                    remoteChange: remoteChange,
                  )
                else
                  _ConflictDetailedComparison(
                    localNote: widget.localNote,
                    remoteChange: remoteChange,
                  ),
                const SizedBox(height: 20),
                Text(
                  strings.localized(en: 'Choose how to resolve', ja: '解決方法を選択'),
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _ConflictResolutionChoice(
                  key: NoteConflictResolverDialog.keepLocalOptionKey,
                  selected:
                      _selectedAction == NoteConflictResolutionAction.keepLocal,
                  icon: widget.localNote.deletedAt == null
                      ? Icons.phone_android_outlined
                      : Icons.delete_outline,
                  title: _resolutionTitle(
                    strings,
                    NoteConflictResolutionAction.keepLocal,
                    remoteChange,
                  ),
                  subtitle: _resolutionSubtitle(
                    strings,
                    NoteConflictResolutionAction.keepLocal,
                    remoteChange,
                  ),
                  onTap: () => setState(
                    () => _selectedAction =
                        NoteConflictResolutionAction.keepLocal,
                  ),
                ),
                const SizedBox(height: 8),
                _ConflictResolutionChoice(
                  key: NoteConflictResolverDialog.useRemoteOptionKey,
                  selected:
                      _selectedAction == NoteConflictResolutionAction.useRemote,
                  icon: remoteChange.action == PendingNoteChangeAction.delete
                      ? Icons.delete_sweep_outlined
                      : Icons.cloud_download_outlined,
                  title: _resolutionTitle(
                    strings,
                    NoteConflictResolutionAction.useRemote,
                    remoteChange,
                  ),
                  subtitle: _resolutionSubtitle(
                    strings,
                    NoteConflictResolutionAction.useRemote,
                    remoteChange,
                  ),
                  onTap: () => setState(
                    () => _selectedAction =
                        NoteConflictResolutionAction.useRemote,
                  ),
                ),
                if (canMerge) ...[
                  const SizedBox(height: 8),
                  _ConflictResolutionChoice(
                    key: NoteConflictResolverDialog.mergeOptionKey,
                    selected:
                        _selectedAction == NoteConflictResolutionAction.merge,
                    icon: Icons.call_merge_rounded,
                    title: _resolutionTitle(
                      strings,
                      NoteConflictResolutionAction.merge,
                      remoteChange,
                    ),
                    subtitle: _resolutionSubtitle(
                      strings,
                      NoteConflictResolutionAction.merge,
                      remoteChange,
                    ),
                    onTap: () => setState(
                      () =>
                          _selectedAction = NoteConflictResolutionAction.merge,
                    ),
                  ),
                ] else if (mergeWouldBeRelevant) ...[
                  const SizedBox(height: 8),
                  _ConflictMergeUnavailableNotice(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final strings = context.strings;
    if (_loadingRemote) {
      return [
        TextButton(
          key: NoteConflictResolverDialog.cancelButtonKey,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
      ];
    }
    if (_remoteChange == null) {
      return [
        TextButton(
          key: NoteConflictResolverDialog.cancelButtonKey,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton.icon(
          key: NoteConflictResolverDialog.retryButtonKey,
          onPressed: _loadRemote,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(strings.localized(en: 'Try again', ja: '再試行')),
        ),
      ];
    }
    return [
      TextButton(
        key: NoteConflictResolverDialog.cancelButtonKey,
        onPressed: _resolving ? null : () => Navigator.of(context).pop(),
        child: Text(strings.cancel),
      ),
      FilledButton.icon(
        key: NoteConflictResolverDialog.resolveButtonKey,
        onPressed: _selectedAction == null || _resolving
            ? null
            : _resolveSelected,
        icon: _resolving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_rounded),
        label: Text(strings.localized(en: 'Resolve this way', ja: 'この方法で解決')),
      ),
    ];
  }

  String _resolutionTitle(
    AppStrings strings,
    NoteConflictResolutionAction action,
    PreparedSyncNote remoteChange,
  ) {
    final localDeleted = widget.localNote.deletedAt != null;
    final remoteDeleted = remoteChange.action == PendingNoteChangeAction.delete;
    return switch (action) {
      NoteConflictResolutionAction.keepLocal =>
        localDeleted
            ? strings.localized(
                en: 'Keep this device deletion',
                ja: 'この端末の削除を採用',
              )
            : remoteDeleted
            ? strings.localized(
                en: 'Restore this device note',
                ja: 'この端末のメモを復元',
              )
            : strings.localized(en: 'Use this device version', ja: 'この端末の版を採用'),
      NoteConflictResolutionAction.useRemote =>
        remoteDeleted
            ? strings.localized(en: 'Use the remote deletion', ja: 'リモートの削除を採用')
            : localDeleted
            ? strings.localized(
                en: 'Restore the remote version',
                ja: 'リモート版を復元',
              )
            : strings.localized(en: 'Use the remote version', ja: 'リモート版を採用'),
      NoteConflictResolutionAction.merge => strings.localized(
        en: 'Keep both bodies',
        ja: '両方の本文を残す',
      ),
    };
  }

  String _resolutionSubtitle(
    AppStrings strings,
    NoteConflictResolutionAction action,
    PreparedSyncNote remoteChange,
  ) {
    final localDeleted = widget.localNote.deletedAt != null;
    final remoteDeleted = remoteChange.action == PendingNoteChangeAction.delete;
    return switch (action) {
      NoteConflictResolutionAction.keepLocal =>
        localDeleted
            ? strings.localized(
                en: 'Upload this device deletion and keep the note in Trash.',
                ja: 'この端末の削除を同期し、メモはゴミ箱に残します。',
              )
            : remoteDeleted
            ? strings.localized(
                en: 'Upload this device content again and restore the note remotely.',
                ja: 'この端末の内容を再アップロードし、リモート側でもメモを復元します。',
              )
            : strings.localized(
                en: 'Keep this device content and upload it to the remote target.',
                ja: 'この端末の内容を残して、リモートへアップロードします。',
              ),
      NoteConflictResolutionAction.useRemote =>
        remoteDeleted
            ? strings.localized(
                en: 'Move the note to Trash. Its current content remains available there.',
                ja: 'メモをゴミ箱へ移動します。現在の内容はゴミ箱内に保持されます。',
              )
            : localDeleted
            ? strings.localized(
                en: 'Replace the local deletion with the active remote version.',
                ja: 'この端末の削除を取り消し、リモート版で復元します。',
              )
            : strings.localized(
                en: 'Replace this device content with the remote version.',
                ja: 'この端末の内容をリモート版で置き換えます。',
              ),
      NoteConflictResolutionAction.merge => strings.localized(
        en: 'Keep the local title and tags, then combine both bodies and attachments.',
        ja: 'ローカルのタイトルとタグを残し、両方の本文と添付をまとめます。',
      ),
    };
  }

  String _resolvingLabel(AppStrings strings) {
    return switch (_selectedAction) {
      NoteConflictResolutionAction.keepLocal => strings.localized(
        en: 'Saving this device version and syncing...',
        ja: 'この端末の版を保存して同期しています…',
      ),
      NoteConflictResolutionAction.useRemote => strings.localized(
        en: 'Applying the remote result to this device...',
        ja: 'リモートの結果をこの端末へ反映しています…',
      ),
      NoteConflictResolutionAction.merge => strings.localized(
        en: 'Combining both versions and syncing...',
        ja: '両方の版をまとめて同期しています…',
      ),
      null => strings.localized(
        en: 'Resolving the conflict...',
        ja: '競合を解決しています…',
      ),
    };
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

class _ConflictBusyOverlay extends StatelessWidget {
  const _ConflictBusyOverlay({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        ModalBarrier(
          dismissible: false,
          color: colorScheme.scrim.withValues(alpha: 0.36),
        ),
        Center(
          child: Semantics(
            liveRegion: true,
            label: label,
            child: Card(
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.strings.localized(
                          en: 'Controls are temporarily locked to prevent duplicate changes.',
                          ja: '重複操作を防ぐため、完了まで操作をロックしています。',
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: _mutedTextColor(context)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConflictInlineError extends StatelessWidget {
  const _ConflictInlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictMergeUnavailableNotice extends StatelessWidget {
  const _ConflictMergeUnavailableNotice();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.strings.localized(
                en: 'Automatic merge is unavailable for rich or structured memos because it could lose formatting or block attachments. Choose either complete version instead.',
                ja: 'リッチメモやブロック構成を含むメモは、書式やブロック内の添付を失わないよう自動マージしません。どちらかの完全な版を選んでください。',
              ),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictResolutionChoice extends StatelessWidget {
  const _ConflictResolutionChoice({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      label: '$title. $subtitle',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected
              ? colorScheme.secondaryContainer
              : colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected
                  ? colorScheme.secondary
                  : colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Icon(icon, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: _mutedTextColor(context)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConflictOverview extends StatelessWidget {
  const _ConflictOverview({
    required this.localNote,
    required this.remoteChange,
  });

  final NoteEntry localNote;
  final PreparedSyncNote remoteChange;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final remoteDeleted = remoteChange.action == PendingNoteChangeAction.delete;
    final fields = _conflictFieldComparisons(context, localNote, remoteChange);
    final chips = fields.map((field) => field.label).take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          fields.isEmpty
              ? strings.localized(
                  en: 'No visible content differences were found.',
                  ja: '表示できる内容の差分はありません。',
                )
              : strings.localized(
                  en: '${fields.length} fields are different.',
                  ja: '${fields.length} 項目に差分があります。',
                ),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final label in chips)
                Chip(
                  avatar: const Icon(Icons.difference_outlined, size: 16),
                  label: Text(label),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final local = _ConflictVersionSummary(
              label: strings.localized(en: 'This device', ja: 'この端末'),
              note: localNote,
              isDeleted: localNote.deletedAt != null,
            );
            final remote = _ConflictVersionSummary(
              label: strings.localized(en: 'Remote', ja: 'リモート'),
              note: remoteChange.note,
              isDeleted: remoteDeleted,
            );
            if (constraints.maxWidth >= 560) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: local),
                  const SizedBox(width: 12),
                  Expanded(child: remote),
                ],
              );
            }
            return Column(
              children: [local, const SizedBox(height: 12), remote],
            );
          },
        ),
      ],
    );
  }
}

class _ConflictFieldComparison {
  const _ConflictFieldComparison({
    required this.label,
    required this.localValue,
    required this.remoteValue,
    this.lineDiff,
  });

  final String label;
  final String localValue;
  final String remoteValue;
  final List<_ConflictDiffLine>? lineDiff;
}

enum _ConflictDiffKind {
  common,
  localOnly,
  remoteOnly,
  omitted,
  truncated,
  largeExcerpt,
}

class _ConflictDiffLine {
  const _ConflictDiffLine(this.kind, this.text, {this.omittedCount = 0});

  final _ConflictDiffKind kind;
  final String text;
  final int omittedCount;
}

class _ConflictLineDiffPanel extends StatelessWidget {
  const _ConflictLineDiffPanel({required this.lines});

  final List<_ConflictDiffLine> lines;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            for (final line in lines)
              Container(
                width: double.infinity,
                color: switch (line.kind) {
                  _ConflictDiffKind.localOnly =>
                    colorScheme.errorContainer.withValues(alpha: 0.42),
                  _ConflictDiffKind.remoteOnly =>
                    colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                  _ConflictDiffKind.omitted => colorScheme.surfaceContainerHigh,
                  _ConflictDiffKind.truncated =>
                    colorScheme.surfaceContainerHigh,
                  _ConflictDiffKind.largeExcerpt =>
                    colorScheme.surfaceContainerHigh,
                  _ConflictDiffKind.common => colorScheme.surfaceContainerLow,
                },
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        switch (line.kind) {
                          _ConflictDiffKind.localOnly => strings.localized(
                            en: 'Device only',
                            ja: '端末のみ',
                          ),
                          _ConflictDiffKind.remoteOnly => strings.localized(
                            en: 'Remote only',
                            ja: 'リモートのみ',
                          ),
                          _ConflictDiffKind.omitted => strings.localized(
                            en: 'Unchanged',
                            ja: '共通部分',
                          ),
                          _ConflictDiffKind.truncated => strings.localized(
                            en: 'Omitted',
                            ja: '省略',
                          ),
                          _ConflictDiffKind.largeExcerpt => strings.localized(
                            en: 'Large memo',
                            ja: '大きなメモ',
                          ),
                          _ConflictDiffKind.common => '=',
                        },
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: switch (line.kind) {
                            _ConflictDiffKind.localOnly =>
                              colorScheme.onErrorContainer,
                            _ConflictDiffKind.remoteOnly =>
                              colorScheme.onTertiaryContainer,
                            _ => colorScheme.onSurfaceVariant,
                          },
                          fontWeight: line.kind == _ConflictDiffKind.common
                              ? FontWeight.w400
                              : FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: switch (line.kind) {
                        _ConflictDiffKind.omitted => Text(
                          strings.localized(
                            en: '${line.omittedCount} unchanged lines hidden',
                            ja: '共通する ${line.omittedCount} 行を省略',
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                        _ConflictDiffKind.truncated => Text(
                          strings.localized(
                            en: '${line.omittedCount} lines hidden; the beginning and end are shown',
                            ja: '${line.omittedCount} 行を省略（先頭と末尾を表示）',
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                        _ConflictDiffKind.largeExcerpt => Text(
                          strings.localized(
                            en: 'This memo is very large. Only bounded excerpts around the first and last changed positions are shown.',
                            ja: '本文が非常に大きいため、最初と最後の変更位置周辺のみを表示しています。',
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                        _ => SelectableText(
                          line.text.isEmpty
                              ? strings.localized(
                                  en: '(Empty line)',
                                  ja: '（空行）',
                                )
                              : line.text,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

List<_ConflictDiffLine> _buildConflictLineDiff(String local, String remote) {
  final normalizedLocal = _normalizeConflictText(local);
  final normalizedRemote = _normalizeConflictText(remote);
  const maximumSplitCharacters = 32 * 1024;
  if (normalizedLocal.length > maximumSplitCharacters ||
      normalizedRemote.length > maximumSplitCharacters) {
    return _buildLargeConflictTextDiff(normalizedLocal, normalizedRemote);
  }
  final localLines = normalizedLocal.split('\n');
  final remoteLines = normalizedRemote.split('\n');
  const maximumDirectLineCharacters = 2001;
  if (localLines.any((line) => line.length > maximumDirectLineCharacters) ||
      remoteLines.any((line) => line.length > maximumDirectLineCharacters)) {
    return _buildLargeConflictTextDiff(normalizedLocal, normalizedRemote);
  }
  const exactLineLimit = 300;
  const exactCellLimit = 90000;
  final exact =
      localLines.length <= exactLineLimit &&
      remoteLines.length <= exactLineLimit &&
      localLines.length * remoteLines.length <= exactCellLimit;
  final raw = exact
      ? _buildExactConflictLineDiff(localLines, remoteLines)
      : _buildCoarseConflictLineDiff(localLines, remoteLines);
  return _collapseCommonConflictLines(_limitConflictDiffLines(raw));
}

List<_ConflictDiffLine> _buildLargeConflictTextDiff(
  String local,
  String remote,
) {
  final sharedLength = math.min(local.length, remote.length);
  var prefix = 0;
  while (prefix < sharedLength &&
      local.codeUnitAt(prefix) == remote.codeUnitAt(prefix)) {
    prefix++;
  }

  var localEnd = local.length;
  var remoteEnd = remote.length;
  while (localEnd > prefix &&
      remoteEnd > prefix &&
      local.codeUnitAt(localEnd - 1) == remote.codeUnitAt(remoteEnd - 1)) {
    localEnd--;
    remoteEnd--;
  }

  final localRange = _largeConflictDisplayRange(local, prefix, localEnd);
  final remoteRange = _largeConflictDisplayRange(remote, prefix, remoteEnd);
  return [
    const _ConflictDiffLine(_ConflictDiffKind.largeExcerpt, ''),
    ..._buildChangedConflictTextSegment(
      local,
      start: localRange.$1,
      end: localRange.$2,
      kind: _ConflictDiffKind.localOnly,
    ),
    ..._buildChangedConflictTextSegment(
      remote,
      start: remoteRange.$1,
      end: remoteRange.$2,
      kind: _ConflictDiffKind.remoteOnly,
    ),
  ];
}

(int, int) _largeConflictDisplayRange(
  String value,
  int differenceStart,
  int differenceEnd,
) {
  const contextCharacters = 900;
  final lineStart = _conflictLineStart(value, differenceStart);
  final lastDifferenceIndex = differenceEnd > differenceStart
      ? differenceEnd - 1
      : differenceEnd;
  final lineEnd = _conflictLineEnd(value, lastDifferenceIndex);
  return (
    math.max(lineStart, differenceStart - contextCharacters),
    math.min(lineEnd, differenceEnd + contextCharacters),
  );
}

int _conflictLineStart(String value, int index) {
  if (index <= 0) {
    return 0;
  }
  return value.lastIndexOf('\n', math.min(index, value.length) - 1) + 1;
}

int _conflictLineEnd(String value, int index) {
  if (index >= value.length) {
    return value.length;
  }
  final newline = value.indexOf('\n', math.max(0, index));
  return newline < 0 ? value.length : newline;
}

List<_ConflictDiffLine> _buildChangedConflictTextSegment(
  String value, {
  required int start,
  required int end,
  required _ConflictDiffKind kind,
}) {
  const retainedAtEachEnd = 139;
  const characterBudgetAtEachEnd = 16 * 1024;
  final first = <(int, int, int)>[];
  final tail = ListQueue<(int, int, int)>();
  var firstCharacters = 0;
  var tailCharacters = 0;
  var lineCount = 0;
  var retainingFirst = true;

  void retainLine(int lineStart, int lineEnd) {
    lineCount++;
    final displayLength = _boundedConflictDiffLineDisplayLength(
      lineEnd - lineStart,
    );
    if (retainingFirst &&
        first.length < retainedAtEachEnd &&
        firstCharacters + displayLength <= characterBudgetAtEachEnd) {
      first.add((lineStart, lineEnd, displayLength));
      firstCharacters += displayLength;
      return;
    }
    retainingFirst = false;
    tail.addLast((lineStart, lineEnd, displayLength));
    tailCharacters += displayLength;
    while (tail.length > retainedAtEachEnd ||
        tailCharacters > characterBudgetAtEachEnd) {
      tailCharacters -= tail.removeFirst().$3;
    }
  }

  var lineStart = start;
  for (var index = start; index < end; index++) {
    if (value.codeUnitAt(index) != 10) {
      continue;
    }
    retainLine(lineStart, index);
    lineStart = index + 1;
  }
  retainLine(lineStart, end);

  _ConflictDiffLine line((int, int, int) range) => _ConflictDiffLine(
    kind,
    _boundedConflictDiffLineText(value, range.$1, range.$2),
  );

  final omittedCount = lineCount - first.length - tail.length;
  if (omittedCount <= 0) {
    return [...first.map(line), ...tail.map(line)];
  }
  return [
    ...first.map(line),
    _ConflictDiffLine(
      _ConflictDiffKind.truncated,
      '',
      omittedCount: omittedCount,
    ),
    ...tail.map(line),
  ];
}

int _boundedConflictDiffLineDisplayLength(int rawLength) {
  const retainedCharacters = 1000;
  const maximumCharacters = retainedCharacters * 2 + 1;
  return rawLength <= maximumCharacters
      ? rawLength
      : retainedCharacters * 2 + 3;
}

String _boundedConflictDiffLineText(String value, int start, int end) {
  const retainedCharacters = 1000;
  const maximumCharacters = retainedCharacters * 2 + 1;
  if (end - start <= maximumCharacters) {
    return value.substring(start, end);
  }
  var headEnd = start + retainedCharacters;
  if (_splitsSurrogatePair(value, headEnd)) {
    headEnd--;
  }
  var tailStart = end - retainedCharacters;
  if (_splitsSurrogatePair(value, tailStart)) {
    tailStart++;
  }
  return '${value.substring(start, headEnd)}\n…\n'
      '${value.substring(tailStart, end)}';
}

bool _splitsSurrogatePair(String value, int index) {
  if (index <= 0 || index >= value.length) {
    return false;
  }
  final before = value.codeUnitAt(index - 1);
  final after = value.codeUnitAt(index);
  return before >= 0xD800 &&
      before <= 0xDBFF &&
      after >= 0xDC00 &&
      after <= 0xDFFF;
}

List<_ConflictDiffLine> _limitConflictDiffLines(List<_ConflictDiffLine> lines) {
  const maximumVisibleLines = 600;
  const retainedAtEachEnd = 280;
  if (lines.length <= maximumVisibleLines) {
    return lines;
  }
  return [
    ...lines.take(retainedAtEachEnd),
    _ConflictDiffLine(
      _ConflictDiffKind.truncated,
      '',
      omittedCount: lines.length - retainedAtEachEnd * 2,
    ),
    ...lines.skip(lines.length - retainedAtEachEnd),
  ];
}

List<_ConflictDiffLine> _buildExactConflictLineDiff(
  List<String> local,
  List<String> remote,
) {
  final lengths = List.generate(
    local.length + 1,
    (_) => List<int>.filled(remote.length + 1, 0),
  );
  for (var localIndex = local.length - 1; localIndex >= 0; localIndex--) {
    for (var remoteIndex = remote.length - 1; remoteIndex >= 0; remoteIndex--) {
      lengths[localIndex][remoteIndex] =
          local[localIndex] == remote[remoteIndex]
          ? lengths[localIndex + 1][remoteIndex + 1] + 1
          : math.max(
              lengths[localIndex + 1][remoteIndex],
              lengths[localIndex][remoteIndex + 1],
            );
    }
  }

  final result = <_ConflictDiffLine>[];
  var localIndex = 0;
  var remoteIndex = 0;
  while (localIndex < local.length && remoteIndex < remote.length) {
    if (local[localIndex] == remote[remoteIndex]) {
      result.add(
        _boundedConflictTextDiffLine(
          _ConflictDiffKind.common,
          local[localIndex],
        ),
      );
      localIndex++;
      remoteIndex++;
    } else if (lengths[localIndex + 1][remoteIndex] >=
        lengths[localIndex][remoteIndex + 1]) {
      result.add(
        _boundedConflictTextDiffLine(
          _ConflictDiffKind.localOnly,
          local[localIndex],
        ),
      );
      localIndex++;
    } else {
      result.add(
        _boundedConflictTextDiffLine(
          _ConflictDiffKind.remoteOnly,
          remote[remoteIndex],
        ),
      );
      remoteIndex++;
    }
  }
  for (; localIndex < local.length; localIndex++) {
    result.add(
      _boundedConflictTextDiffLine(
        _ConflictDiffKind.localOnly,
        local[localIndex],
      ),
    );
  }
  for (; remoteIndex < remote.length; remoteIndex++) {
    result.add(
      _boundedConflictTextDiffLine(
        _ConflictDiffKind.remoteOnly,
        remote[remoteIndex],
      ),
    );
  }
  return result;
}

List<_ConflictDiffLine> _buildCoarseConflictLineDiff(
  List<String> local,
  List<String> remote,
) {
  var prefix = 0;
  while (prefix < local.length &&
      prefix < remote.length &&
      local[prefix] == remote[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < local.length - prefix &&
      suffix < remote.length - prefix &&
      local[local.length - 1 - suffix] == remote[remote.length - 1 - suffix]) {
    suffix++;
  }

  final localChangedCount = local.length - prefix - suffix;
  final remoteChangedCount = remote.length - prefix - suffix;
  return [
    ..._buildCommonConflictContext(local, start: 0, count: prefix),
    ..._buildChangedConflictSegment(
      local,
      start: prefix,
      count: localChangedCount,
      kind: _ConflictDiffKind.localOnly,
    ),
    ..._buildChangedConflictSegment(
      remote,
      start: prefix,
      count: remoteChangedCount,
      kind: _ConflictDiffKind.remoteOnly,
    ),
    ..._buildCommonConflictContext(
      local,
      start: local.length - suffix,
      count: suffix,
    ),
  ];
}

List<_ConflictDiffLine> _buildCommonConflictContext(
  List<String> lines, {
  required int start,
  required int count,
}) {
  if (count <= 6) {
    return [
      for (var offset = 0; offset < count; offset++)
        _boundedConflictTextDiffLine(
          _ConflictDiffKind.common,
          lines[start + offset],
        ),
    ];
  }
  return [
    _boundedConflictTextDiffLine(_ConflictDiffKind.common, lines[start]),
    _boundedConflictTextDiffLine(_ConflictDiffKind.common, lines[start + 1]),
    _ConflictDiffLine(_ConflictDiffKind.omitted, '', omittedCount: count - 4),
    _boundedConflictTextDiffLine(
      _ConflictDiffKind.common,
      lines[start + count - 2],
    ),
    _boundedConflictTextDiffLine(
      _ConflictDiffKind.common,
      lines[start + count - 1],
    ),
  ];
}

List<_ConflictDiffLine> _buildChangedConflictSegment(
  List<String> lines, {
  required int start,
  required int count,
  required _ConflictDiffKind kind,
}) {
  const maximumLinesPerSide = 280;
  const retainedAtEachEnd = 139;
  const maximumCharactersPerSide = 32 * 1024;
  const characterBudgetAtEachEnd = maximumCharactersPerSide ~/ 2;

  int displayLengthAt(int offset) =>
      _boundedConflictDiffLineDisplayLength(lines[start + offset].length);

  var totalCharacters = 0;
  if (count <= maximumLinesPerSide) {
    for (var offset = 0; offset < count; offset++) {
      totalCharacters += displayLengthAt(offset);
      if (totalCharacters > maximumCharactersPerSide) {
        break;
      }
    }
  }
  if (count <= maximumLinesPerSide &&
      totalCharacters <= maximumCharactersPerSide) {
    return [
      for (var offset = 0; offset < count; offset++)
        _boundedConflictTextDiffLine(kind, lines[start + offset]),
    ];
  }

  var firstCount = 0;
  var firstCharacters = 0;
  while (firstCount < count && firstCount < retainedAtEachEnd) {
    final displayLength = displayLengthAt(firstCount);
    if (firstCharacters + displayLength > characterBudgetAtEachEnd) {
      break;
    }
    firstCharacters += displayLength;
    firstCount++;
  }
  var tailStart = count;
  var tailCharacters = 0;
  while (tailStart > firstCount && count - tailStart < retainedAtEachEnd) {
    final displayLength = displayLengthAt(tailStart - 1);
    if (tailCharacters + displayLength > characterBudgetAtEachEnd) {
      break;
    }
    tailStart--;
    tailCharacters += displayLength;
  }
  final omittedCount = count - firstCount - (count - tailStart);
  return [
    for (var offset = 0; offset < firstCount; offset++)
      _boundedConflictTextDiffLine(kind, lines[start + offset]),
    _ConflictDiffLine(
      _ConflictDiffKind.truncated,
      '',
      omittedCount: omittedCount,
    ),
    for (var offset = tailStart; offset < count; offset++)
      _boundedConflictTextDiffLine(kind, lines[start + offset]),
  ];
}

_ConflictDiffLine _boundedConflictTextDiffLine(
  _ConflictDiffKind kind,
  String text,
) =>
    _ConflictDiffLine(kind, _boundedConflictDiffLineText(text, 0, text.length));

List<_ConflictDiffLine> _collapseCommonConflictLines(
  List<_ConflictDiffLine> lines,
) {
  final result = <_ConflictDiffLine>[];
  var index = 0;
  while (index < lines.length) {
    if (lines[index].kind != _ConflictDiffKind.common) {
      result.add(lines[index]);
      index++;
      continue;
    }
    final start = index;
    while (index < lines.length &&
        lines[index].kind == _ConflictDiffKind.common) {
      index++;
    }
    final count = index - start;
    if (count <= 6) {
      result.addAll(lines.getRange(start, index));
      continue;
    }
    result.addAll(lines.getRange(start, start + 2));
    result.add(
      _ConflictDiffLine(_ConflictDiffKind.omitted, '', omittedCount: count - 4),
    );
    result.addAll(lines.getRange(index - 2, index));
  }
  return result;
}

class _ConflictDetailedComparison extends StatelessWidget {
  const _ConflictDetailedComparison({
    required this.localNote,
    required this.remoteChange,
  });

  final NoteEntry localNote;
  final PreparedSyncNote remoteChange;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final remoteDeleted = remoteChange.action == PendingNoteChangeAction.delete;
    final fields = _conflictFieldComparisons(context, localNote, remoteChange);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (remoteDeleted) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    strings.localized(
                      en: 'The remote side contains a deletion record, not a readable body. Adopting it moves the current content to Trash instead of erasing it immediately.',
                      ja: 'リモート側には本文ではなく削除記録があります。削除を採用しても現在の内容はすぐ消去せず、ゴミ箱へ移動します。',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          strings.localized(
            en: 'Only fields with differences are shown. Text is selectable.',
            ja: '差分がある項目だけを表示しています。本文は選択して確認できます。',
          ),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: _mutedTextColor(context)),
        ),
        const SizedBox(height: 10),
        if (fields.isEmpty)
          Text(
            strings.localized(
              en: 'No visible content differences were found.',
              ja: '表示できる内容の差分はありません。',
            ),
          )
        else
          for (var index = 0; index < fields.length; index++) ...[
            _ConflictFieldCard(field: fields[index]),
            if (index != fields.length - 1) const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _ConflictFieldCard extends StatelessWidget {
  const _ConflictFieldCard({required this.field});

  final _ConflictFieldComparison field;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.difference_outlined,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  field.label,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                strings.localized(en: 'Different', ja: '差分あり'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (field.lineDiff case final lineDiff?)
            _ConflictLineDiffPanel(lines: lineDiff)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final local = _ConflictValuePanel(
                  label: strings.localized(en: 'This device', ja: 'この端末'),
                  value: field.localValue,
                  local: true,
                );
                final remote = _ConflictValuePanel(
                  label: strings.localized(en: 'Remote', ja: 'リモート'),
                  value: field.remoteValue,
                  local: false,
                );
                if (constraints.maxWidth >= 520) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: local),
                      const SizedBox(width: 10),
                      Expanded(child: remote),
                    ],
                  );
                }
                return Column(
                  children: [local, const SizedBox(height: 8), remote],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ConflictValuePanel extends StatelessWidget {
  const _ConflictValuePanel({
    required this.label,
    required this.value,
    required this.local,
  });

  final String label;
  final String value;
  final bool local;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = SelectableText(
      value,
      style: Theme.of(context).textTheme.bodySmall,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            (local
                    ? colorScheme.secondaryContainer
                    : colorScheme.tertiaryContainer)
                .withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
          text,
        ],
      ),
    );
  }
}

List<_ConflictFieldComparison> _conflictFieldComparisons(
  BuildContext context,
  NoteEntry local,
  PreparedSyncNote remoteChange,
) {
  final strings = context.strings;
  final remote = remoteChange.note;
  final remoteDeleted = remoteChange.action == PendingNoteChangeAction.delete;
  final fields = <_ConflictFieldComparison>[];

  void add(
    String label,
    String localValue,
    String remoteValue, {
    List<_ConflictDiffLine>? lineDiff,
  }) {
    fields.add(
      _ConflictFieldComparison(
        label: label,
        localValue: localValue,
        remoteValue: remoteValue,
        lineDiff: lineDiff,
      ),
    );
  }

  if ((local.deletedAt != null) != remoteDeleted) {
    add(
      strings.localized(en: 'State', ja: '状態'),
      _conflictNoteStateLabel(strings, local.deletedAt != null),
      _conflictNoteStateLabel(strings, remoteDeleted),
    );
  }
  if (!remoteDeleted) {
    if (local.title != remote.title) {
      add(
        strings.localized(en: 'Title', ja: 'タイトル'),
        _conflictEmptyLabel(strings, local.title),
        _conflictEmptyLabel(strings, remote.title),
      );
    }
    final normalizedLocalBody = _normalizeConflictText(local.body);
    final normalizedRemoteBody = _normalizeConflictText(remote.body);
    if (normalizedLocalBody != normalizedRemoteBody) {
      add(
        strings.localized(en: 'Body', ja: '本文'),
        _conflictEmptyLabel(strings, local.body),
        _conflictEmptyLabel(strings, remote.body),
        lineDiff: _buildConflictLineDiff(
          normalizedLocalBody,
          normalizedRemoteBody,
        ),
      );
    }
    final localBlocks = local.blocks
        .map(_conflictBlockSignature)
        .toList(growable: false);
    final remoteBlocks = remote.blocks
        .map(_conflictBlockSignature)
        .toList(growable: false);
    if (!listEquals(localBlocks, remoteBlocks)) {
      final localBlockLabel = _conflictBlocksLabel(strings, local.blocks);
      final remoteBlockLabel = _conflictBlocksLabel(strings, remote.blocks);
      add(
        strings.localized(en: 'Structure and formatting', ja: '構成・書式'),
        localBlockLabel,
        remoteBlockLabel,
        lineDiff: _buildConflictLineDiff(localBlockLabel, remoteBlockLabel),
      );
    }
    final localTags = _normalizedConflictTags(local.tags);
    final remoteTags = _normalizedConflictTags(remote.tags);
    if (!setEquals(localTags, remoteTags)) {
      add(
        strings.localized(en: 'Tags', ja: 'タグ'),
        _conflictTagsLabel(strings, local.tags),
        _conflictTagsLabel(strings, remote.tags),
      );
    }
    final localAttachments = local.attachments
        .map(_conflictAttachmentSignature)
        .toList(growable: false);
    final remoteAttachments = remote.attachments
        .map(_conflictAttachmentSignature)
        .toList(growable: false);
    if (!listEquals(localAttachments, remoteAttachments)) {
      add(
        strings.localized(en: 'Attachments', ja: '添付'),
        _conflictAttachmentsLabel(strings, local.attachments),
        _conflictAttachmentsLabel(strings, remote.attachments),
      );
    }
    if (local.isPinned != remote.isPinned) {
      add(
        strings.localized(en: 'Pinned', ja: 'ピン留め'),
        _conflictBooleanLabel(strings, local.isPinned),
        _conflictBooleanLabel(strings, remote.isPinned),
      );
    }
    if (!_sameConflictLocation(local.location, remote.location)) {
      add(
        strings.localized(en: 'Location', ja: '位置情報'),
        _conflictLocationLabel(strings, local.location),
        _conflictLocationLabel(strings, remote.location),
      );
    }
    if (!_sameConflictDate(local.archivedAt, remote.archivedAt)) {
      add(
        strings.localized(en: 'Archive', ja: 'アーカイブ'),
        _conflictOptionalDateLabel(strings, local.archivedAt),
        _conflictOptionalDateLabel(strings, remote.archivedAt),
      );
    }
    if (local.editorMode != remote.editorMode) {
      add(
        strings.localized(en: 'Memo format', ja: 'メモ形式'),
        _conflictEditorModeLabel(strings, local.editorMode),
        _conflictEditorModeLabel(strings, remote.editorMode),
      );
    }
    if (!_sameConflictDate(local.createdAt, remote.createdAt)) {
      add(
        strings.localized(en: 'Created', ja: '作成日時'),
        _formatConflictDateTime(local.createdAt),
        _formatConflictDateTime(remote.createdAt),
      );
    }
  }
  final localUpdated = local.updatedAt ?? local.createdAt;
  final remoteUpdated = remote.updatedAt ?? remote.createdAt;
  if (!_sameConflictDate(localUpdated, remoteUpdated)) {
    add(
      strings.localized(en: 'Last changed', ja: '最終変更'),
      _formatConflictDateTime(localUpdated),
      _formatConflictDateTime(remoteUpdated),
    );
  }
  if (local.revision != remote.revision) {
    add(
      strings.localized(en: 'Revision', ja: 'リビジョン'),
      '${local.revision}',
      '${remote.revision}',
    );
  }
  return fields;
}

String _normalizeConflictText(String value) {
  if (!value.contains('\r')) {
    return value;
  }
  return value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
}

Set<String> _normalizedConflictTags(List<String> tags) => {
  for (final tag in tags) canonicalizeNoteTag(tag),
};

bool _canSafelyMergeConflict(NoteEntry local, NoteEntry remote) {
  return local.editorMode == NoteEditorMode.quick &&
      remote.editorMode == NoteEditorMode.quick &&
      local.blocks.isEmpty &&
      remote.blocks.isEmpty;
}

String _conflictEmptyLabel(AppStrings strings, String value) {
  return value.trim().isEmpty
      ? strings.localized(en: '(Empty)', ja: '（空）')
      : value;
}

String _conflictTagsLabel(AppStrings strings, List<String> tags) {
  if (tags.isEmpty) {
    return strings.localized(en: '(None)', ja: '（なし）');
  }
  final sorted = [...tags]..sort();
  return sorted.map((tag) => '#$tag').join('  ');
}

String _conflictAttachmentsLabel(
  AppStrings strings,
  List<NoteAttachment> attachments,
) {
  if (attachments.isEmpty) {
    return strings.localized(en: '(None)', ja: '（なし）');
  }
  return attachments
      .map((attachment) {
        return _conflictAttachmentDetailLabel(strings, attachment);
      })
      .join('\n');
}

typedef _ConflictAttachmentSignature = (
  AttachmentType,
  String,
  String?,
  int?,
  int?,
  String?,
);

_ConflictAttachmentSignature _conflictAttachmentSignature(
  NoteAttachment attachment,
) => (
  attachment.type,
  attachment.label,
  attachment.syncAttachmentContentHash,
  attachment.localPayloadSizeBytes,
  attachment.durationMs,
  attachment.syncAttachmentContentHash == null
      ? attachment.previewBytesBase64
      : null,
);

(NoteBlockType, String?, _ConflictAttachmentSignature?) _conflictBlockSignature(
  NoteBlock block,
) => (
  block.type,
  block.text,
  block.attachment == null
      ? null
      : _conflictAttachmentSignature(block.attachment!),
);

String _conflictBlocksLabel(AppStrings strings, List<NoteBlock> blocks) {
  if (blocks.isEmpty) {
    return strings.localized(en: '(No blocks)', ja: '（ブロックなし）');
  }
  return [
    for (var index = 0; index < blocks.length; index++)
      _conflictBlockLabel(strings, blocks[index], index + 1),
  ].join('\n');
}

String _conflictBlockLabel(AppStrings strings, NoteBlock block, int position) {
  if (block.type == NoteBlockType.paragraph) {
    return strings.localized(
      en: '$position. Paragraph: ${_conflictEmptyLabel(strings, block.text ?? '')}',
      ja: '$position. 段落: ${_conflictEmptyLabel(strings, block.text ?? '')}',
    );
  }
  final attachment = block.attachment;
  final type = switch (block.type) {
    NoteBlockType.photo => strings.localized(en: 'Photo block', ja: '写真ブロック'),
    NoteBlockType.video => strings.localized(en: 'Video block', ja: '動画ブロック'),
    NoteBlockType.audio => strings.localized(en: 'Audio block', ja: '音声ブロック'),
    NoteBlockType.file => strings.localized(en: 'File block', ja: 'ファイルブロック'),
    NoteBlockType.paragraph => strings.localized(en: 'Paragraph', ja: '段落'),
  };
  return attachment == null
      ? '$position. $type'
      : '$position. $type: '
            '${_conflictAttachmentDetailLabel(strings, attachment)}';
}

String _conflictAttachmentDetailLabel(
  AppStrings strings,
  NoteAttachment attachment,
) {
  final name = attachment.label.trim().isEmpty
      ? strings.localized(en: '(Unnamed)', ja: '（名称なし）')
      : attachment.label;
  final details = <String>[];
  final size = attachment.localPayloadSizeBytes;
  if (size != null) {
    details.add(
      strings.localized(
        en: 'size ${_conflictByteSizeLabel(size)}',
        ja: 'サイズ ${_conflictByteSizeLabel(size)}',
      ),
    );
  }
  final duration = attachment.durationMs;
  if (duration != null) {
    details.add(
      strings.localized(
        en: 'duration ${_conflictDurationLabel(duration)}',
        ja: '長さ ${_conflictDurationLabel(duration)}',
      ),
    );
  }
  final contentId = _conflictAttachmentContentId(attachment);
  if (contentId != null) {
    details.add(
      strings.localized(en: 'content ID $contentId', ja: '内容ID $contentId'),
    );
  }
  final detailSuffix = details.isEmpty ? '' : ' (${details.join(' / ')})';
  return '${_conflictAttachmentTypeLabel(strings, attachment.type)}: '
      '$name$detailSuffix';
}

String _conflictByteSizeLabel(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _conflictDurationLabel(int durationMs) {
  final totalSeconds = math.max(0, durationMs ~/ 1000);
  final minutes = totalSeconds ~/ 60;
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String? _conflictAttachmentContentId(NoteAttachment attachment) {
  final hash = attachment.syncAttachmentContentHash;
  if (hash != null && hash.isNotEmpty) {
    return hash.substring(0, math.min(8, hash.length));
  }
  final preview = attachment.previewBytesBase64;
  if (preview == null || preview.isEmpty) {
    return null;
  }
  return sha256.convert(utf8.encode(preview)).toString().substring(0, 8);
}

String _conflictAttachmentTypeLabel(AppStrings strings, AttachmentType type) =>
    switch (type) {
      AttachmentType.photo => strings.localized(en: 'Photo', ja: '写真'),
      AttachmentType.video => strings.localized(en: 'Video', ja: '動画'),
      AttachmentType.audio => strings.localized(en: 'Audio', ja: '音声'),
      AttachmentType.file => strings.localized(en: 'File', ja: 'ファイル'),
    };

String _conflictBooleanLabel(AppStrings strings, bool value) => value
    ? strings.localized(en: 'Yes', ja: 'あり')
    : strings.localized(en: 'No', ja: 'なし');

String _conflictNoteStateLabel(AppStrings strings, bool deleted) => deleted
    ? strings.localized(en: 'In Trash', ja: 'ゴミ箱')
    : strings.localized(en: 'Active note', ja: '通常のメモ');

String _conflictOptionalDateLabel(AppStrings strings, DateTime? value) =>
    value == null
    ? strings.localized(en: 'Not archived', ja: '未アーカイブ')
    : _formatConflictDateTime(value);

String _conflictEditorModeLabel(AppStrings strings, NoteEditorMode mode) =>
    switch (mode) {
      NoteEditorMode.quick => strings.localized(en: 'Quick memo', ja: 'クイックメモ'),
      NoteEditorMode.rich => strings.localized(en: 'Rich memo', ja: 'リッチメモ'),
    };

bool _sameConflictDate(DateTime? left, DateTime? right) {
  if (left == null || right == null) {
    return left == right;
  }
  return left.isAtSameMomentAs(right);
}

bool _sameConflictLocation(NoteLocation? left, NoteLocation? right) {
  if (left == null || right == null) {
    return left == right;
  }
  return left.latitude == right.latitude &&
      left.longitude == right.longitude &&
      left.accuracyMeters == right.accuracyMeters &&
      left.address == right.address &&
      _sameConflictDate(left.capturedAt, right.capturedAt);
}

String _conflictLocationLabel(AppStrings strings, NoteLocation? location) {
  if (location == null) {
    return strings.localized(en: '(None)', ja: '（なし）');
  }
  final coordinates = '${location.latitude}, ${location.longitude}';
  final address = location.address?.trim();
  final details = <String>[
    if (address != null && address.isNotEmpty) address,
    coordinates,
    if (location.accuracyMeters != null)
      strings.localized(
        en: 'Accuracy: ${location.accuracyMeters} m',
        ja: '精度: ${location.accuracyMeters} m',
      ),
    if (location.capturedAt != null)
      strings.localized(
        en: 'Captured: ${_formatConflictDateTime(location.capturedAt!)}',
        ja: '取得日時: ${_formatConflictDateTime(location.capturedAt!)}',
      ),
  ];
  return details.join('\n');
}

String _formatConflictDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  final fractional =
      '${local.millisecond.toString().padLeft(3, '0')}'
      '${(local.microsecond % 1000).toString().padLeft(3, '0')}';
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.$fractional';
}

class _ConflictVersionSummary extends StatelessWidget {
  const _ConflictVersionSummary({
    required this.label,
    required this.note,
    required this.isDeleted,
  });

  final String label;
  final NoteEntry note;
  final bool isDeleted;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colorScheme = Theme.of(context).colorScheme;
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
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (isDeleted) ...[
            const SizedBox(height: 6),
            DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  strings.localized(en: 'Deleted', ja: '削除済み'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            note.title.trim().isEmpty
                ? isDeleted
                      ? strings.localized(
                          en: 'Remote deletion record',
                          ja: 'リモートの削除記録',
                        )
                      : strings.localized(
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
            body.isEmpty
                ? isDeleted
                      ? strings.localized(
                          en: 'No remote body is included in a deletion record.',
                          ja: '削除記録にはリモート本文が含まれません。',
                        )
                      : '-'
                : body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            strings.localized(
              en: 'Revision ${note.revision} / $timeLabel / ${note.attachments.length} attachments',
              ja: 'リビジョン ${note.revision} / $timeLabel / 添付 ${note.attachments.length} 件',
            ),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: _mutedTextColor(context)),
          ),
        ],
      ),
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

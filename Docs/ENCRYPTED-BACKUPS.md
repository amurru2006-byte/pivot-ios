# Backup portabili cifrati — formato 1

## Confine

I nuovi backup manuali e automatici sono archivi `.pivotbackup`, non JSON in
chiaro. Prima della cifratura passa sempre il filtro che esclude dati importati
da Salute, profilo forza e rank derivati. Cifrare non autorizza a copiare dati
HealthKit in iCloud. Note, chat e documenti scelti dall'utente sono personali e
restano all'interno dell'archivio cifrato.

## Formato e librerie

- Header fisso `PivotEncryptedBackup1\n`, salt casuale di 16 byte, poi il combined
  box CryptoKit AES-256-GCM (nonce casuale, ciphertext, tag). Header e salt sono
  autenticati come associated data.
- Chiave derivata da password tramite CommonCrypto PBKDF2-HMAC-SHA256,
  600.000 iterazioni. Parametri fissi del formato: un file non può imporre un
  numero enorme di iterazioni o scegliere un algoritmo più debole.
- La password usa normalizzazione Unicode NFC, da 12 a 256 caratteri, massimo
  1.024 byte UTF-8. Spazi significativi conservati; stringhe vuote, solo spazi o
  con NUL rifiutate. Non si utilizza il codice breve di attivazione AI.
- Salt e chiave derivata sono conservati soltanto in un elemento Keychain
  `WhenUnlockedThisDeviceOnly`, non sincronizzato, legato all'UUID installazione.
  La password non viene salvata in AppData, UserDefaults, log, file o cloud.
- Le copie automatiche riusano la chiave nel portachiavi ma hanno un nuovo nonce
  GCM per ogni archivio. La derivazione costosa non si ripete a ogni salvataggio.
- Limite di 80 MiB, lettura a blocchi e validazione del contenuto dopo la verifica
  crittografica. Nessuna deserializzazione di plaintext non autenticato.

## Scrittura e recupero

La configurazione richiede due inserimenti e la conferma di aver conservato la
password fuori da Pivot. La derivazione avviene fuori dal thread UI. Se viene
annullata prima del commit Keychain, non configura una nuova protezione.

Nessun fallback in chiaro quando il dispositivo è bloccato o il portachiavi non
è disponibile. La copia corrente del budget resta sul telefono e il backup
esterno segnala l'errore. La configurazione del backup esterno resta sospesa
finché non viene impostata una password.

Le copie automatiche hanno nome `Backup Pivot-<salt>.pivotbackup`, con una copia
precedente della stessa configurazione. Nuova configurazione/password = nuovo
salt e nuovo nome, così le copie protette dalla vecchia password restano intatte.
Una copia esistente illeggibile non viene sovrascritta. I file JSON preesistenti
non vengono cancellati, sostituiti o presentati come retroattivamente cifrati.

Il ripristino accetta sia gli archivi cifrati sia i vecchi JSON. Controlla prima
password/autenticazione, schema, dati e PDF, poi salva conservando la copia locale
precedente. Password errata, corruzione e file non supportato non sostituiscono
il registro. Dopo ripristino su un nuovo telefono può essere necessario
configurare nuovamente la protezione delle future copie: la chiave del vecchio
iPhone non migra tramite iCloud.

Se si perde la password, non esiste un recupero remoto del backup. Le copie
precedenti al cambio password richiedono ancora la loro password precedente.
I documenti aperti/esportati separatamente dall'utente non vengono protetti
automaticamente da questo formato.

## Prove e fonti

Fixture esclusivamente sintetiche: round-trip, mancanza di plaintext, nonce e
salt distinti, password errata, assente/debole/non coincidente, Unicode, NUL,
header/ciphertext/tag alterati, JSON legacy, file invariato e chiave invalida.
Il test non va presentato come un audit crittografico indipendente.

Fonti primarie consultate:
- https://developer.apple.com/documentation/cryptokit/aes/gcm
- https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly
- https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html

PBKDF2 è una scelta di compatibilità con le librerie di sistema disponibili,
non una dichiarazione di certificazione FIPS dell'app o una garanzia assoluta.

# Verifica Serie 7

## Esito conclusivo simulatore e pacchetto

Run GitHub Actions 38548362555, tentativo 2, job 115855660448, sorgente remota `5e319695607503b808a9854abcf0b62875818ad4`: **successo**.

- Core: 303 eseguiti, 0 fallimenti.
- UI: 28 eseguiti, 0 fallimenti.
- Release: compilazione riuscita.
- IPA: confezionamento e caricamento riusciti.
- Anteprime/log: caricamento riuscito.

Il primo tentativo della stessa revisione aveva superato 303 Core e 27 UI su 28; l'unico errore era un timeout dell'automazione mentre leggeva la gerarchia prima di eseguire il vecchio flusso Calendario/allievo. Un solo nuovo tentativo identico ha eseguito anche quel test fino in fondo. Nessun requisito o controllo è stato rimosso.

## Artefatti del tentativo riuscito

- IPA ZIP, ID 11900877834: SHA256 `2065B2AE6BEFCC5A9189A7F087331C4CB62F616DD2C56C0734985B58D9ADE748`.
- Anteprime, ID 11900613383: SHA256 `F7F1948F2E6405DEB0DA174834E0E4BC7AECD70E3F0E5BF5381A3E00BAC55E2A`.
- Log/PDF, ID 11900403423: SHA256 `9CEC738ACE2DF86EB5840B9D1CDF9908566EF76D76D5485407A99EDAABC2E168`.

Gli ID e le date distinguono questi artefatti da quelli del primo tentativo, che GitHub conserva sotto gli stessi nomi.

## Integrità IPA

File `Pivot-0.7.6-20-Serie7-5e31969.ipa`, 16.336.565 byte, SHA256 `55E40F57BDDAC02CD4FEDBCA16F764359E35CCFE6D6794FA8102FCF03A9BAE6A`.

Controlli read-only superati: CRC ZIP; bundle `app.pivot.personal`; estensione `app.pivot.personal.workout`; versione 0.7.6 build 20; configurazione Live Activity e descrizione lettura Salute; CodeResources per app ed estensione; entitlement confezionati HealthKit e background delivery. La firma è ad-hoc: `iphone_resigning_verified` è false finché AltStore non rifirma e installa sul dispositivo.

## Ispezione visuale

Esaminati gli artefatti più recenti associandoli tramite il manifest del risultato UI:

- recupero al Cable Crunch/ottavo esercizio, ultima serie, barra persistente e controlli grandi;
- anteprima layout Live Activity per pesi, isometria bilaterale e recupero;
- finalizzazione e anteprima automatica del PDF;
- cronologia, eliminazione e correzione di un carico concluso a 50 kg senza timer nuovo;
- segnalazione collegata a due movimenti, avviso su entrambi, risoluzione e persistenza;
- fase della scheda, override della giornata, nuova sessione e storico con fase precedente invariata;
- Obiettivo e andamento sopra l'immagine, serie confermate, confronto +6 e avviso ancora presente;
- galleria completa dei rank 1-7, con titoli e stemmi interi e leggibili.

Non sono emersi tagli o controlli essenziali coperti. Le immagini Live Activity sono una preview condivisa e non sostituiscono il blocco schermo reale.

## PDF reali prodotti dall'app

Sette pagine renderizzate e viste individualmente:

- riepilogo settimanale, 4 pagine/52.850 byte: fasi Carico e Scarico, tipi serie, cedimento, superserie, isometrie per lato, recuperi, stato e note lunghe correttamente paginate;
- report di finalizzazione, 3 pagine/43.561 byte: otto esercizi, una serie Cable Crunch svolta, serie residue, orari, recupero previsto/effettivo e fine automatica.

Nessun clipping, sovrapposizione, glifo rotto o intestazione orfana. I marcatori sanitari sintetici privati non compaiono nel testo dei PDF.

## Collaudo non sostituibile

Questa verifica chiude codice, regressione, interfaccia simulata, PDF e pacchetto. Non dimostra rifirma AltStore HK Test, permessi HealthKit, scrittura EventKit, ActivityKit/blocco schermo, notifiche/background o conservazione dei dati sul dispositivo reale. Baseline 0.7.5 (19) invariata fino al collaudo descritto in `Docs/SERIE7-COLLAUDO-IPHONE.md`.

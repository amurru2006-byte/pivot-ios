# AltStore HealthKit — esperimento separato da Pivot

Copia NON ufficiale di AltStore Classic 2.3 per una prova personale con AltServer su Windows. Non è una soluzione già verificata sul dispositivo, non è affiliata ad AltStore e non sostituisce una firma Apple valida.

## Sorgenti fissati

- AltStore: `https://github.com/altstoreio/AltStore`, commit `04311c072d3f587a93335235d324a9fafca8ecf9` (tag v2.3).
- AltSign: submodule ufficiale `0d3c1a3cac608e724ca0c8d7404253cd5fee9495`.
- Patch HealthKit: `capabilities.patch`, ispirata alla proposta pubblica https://github.com/rileytestut/AltSign/pull/45 ; contesto https://github.com/altstoreio/AltStore/pull/1762 . Quelle proposte non costituiscono una conferma del funzionamento sul telefono.

La patch aggiunge la mappatura bidirezionale del solo entitlement Booleano HealthKit alla feature Apple `HK421J6T7P`. Non modifica autenticazione, servizi Apple, certificati, controlli dei permessi o algoritmo di firma. Il profilo ricevuto da Apple resta il limite dei permessi firmabili.

Un controllo aggiuntivo ferma la preparazione di Pivot se il profilo ricevuto non comprende HealthKit o background delivery richiesti dall'IPA. Nessuna capacità mancante viene inventata o forzata nella firma.

## Verifica automatica

Il workflow separato controlla il commit AltStore e il submodule AltSign, applica la patch senza scaricare codice dal ramo mobile di una proposta, esegue i test Objective-C sulla mappatura, compila la copia per iPhone senza credenziali Apple e prepara una firma ad hoc solo per consentire all'installatore di leggere gli entitlements originali. Non interroga il portale Apple né accede a dati sanitari.

L'IPA è etichettato `AltStore HK Test`, build 6501. Mantiene il bundle ID ufficiale per poter essere valutato come aggiornamento dall'AltStore esistente; la compatibilità dell'aggiornamento va verificata con l'utente prima dell'installazione. Gli identificativi di esempio del dispositivo e del server vengono svuotati nella copia compilata: l'AltStore esistente li inserisce durante la propria rifirma.

## Prima della prova sul telefono

1. Esportare il backup di Pivot e verificare che sia leggibile; non disinstallare Pivot.
2. Verificare versione AltStore installata, spazio/slot disponibili, stesso Apple ID e collegamento ad AltServer. Non inserire password in chat o in GitHub.
3. Soltanto dopo build verificata e spiegazione della procedura: valutare l'aggiornamento di AltStore da dentro AltStore esistente, senza rimuovere la copia attuale o cambiare account/bundle ID.
4. Rifirmare/aggiornare Pivot con la copia modificata e leggere il risultato della verifica del profilo. Se fallisce, fermarsi: non usare reinstallazioni ripetute, nuovi account o acquisti come tentativi alla cieca.
5. Il successo della firma non è ancora prova dell'importazione: verificare richiesta di autorizzazione Apple e dati effettivi; gli aggiornamenti automatici sono comunque gestiti da iOS.

Per tornare alla versione ufficiale occorre valutare l'aggiornamento tramite AltServer con lo stesso account, non una cancellazione. Una futura versione ufficiale potrebbe sovrascrivere la patch: non dichiarare definitivo questo percorso.

## Licenze e sorgenti corrispondenti

AltStore e la copia modificata seguono la licenza upstream AGPL-3.0 e le licenze delle dipendenze. Il pacchetto prodotto dal workflow include LICENSE upstream, patch, test, workflow di compilazione, manifest delle revisioni e archivio completo dei sorgenti modificati con le dipendenze e le loro licenze. Questi strumenti sono separati dal codice/app Pivot.

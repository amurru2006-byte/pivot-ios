# Stato Pivot V8

Aggiornato: 8 ottobre 2026. Primo blocco autorizzato direttamente dall’utente («vai pure avanti»).

Baseline immutata: Pivot 0.7.5 build 19, commit 930d17fd292310cc3161bdd0a556619f1c0a43b6. Ramo di lavoro: codex/pivot-v8-ai-foundation.

Vincoli: budget aggiuntivo 0 euro; dati online ammessi se protetti; offline essenziale conservato; eventuale vendita futura, senza credenziali condivise nell’IPA. Nessuna riscrittura.

Preparato: contesto minimo con cronologia pertinente e memorie esplicite, alias eventi, risposta strutturata, anteprima pranzo/palestra mediante Planner e CoachPlanner esistenti. Nessuna scrittura calendario o cambiamento alla UI. Gateway Groq Free + Workers Free predisposto, autenticato e senza log dei prompt, non distribuito. Nessun account creato e nessun segreto ottenuto.

Verificato localmente: 10 test gateway passati con trasporto sintetico; git diff --check. Actions completata con successo: 204/204 test Core (193 esistenti + 11 V8), 10/10 gateway e compilazione iOS Release senza firma. Run: https://github.com/amurru2006-byte/pivot-ios/actions/runs/37770534027. Revisione verificata: 2a1f7e294fd5b2fb11f0c909f77ce560350b294d. Non dedurre qualità del modello da risposte simulate.

Da completare: collegamento al Coach con credenziali nel Keychain e modalità offline; verifica delle conferme per più eventi; account Free, ZDR verificato e prova reale di comprensione/velocità. Nessuna nuova IPA o release.

Contratto: Docs/Pivot-V8-first-block.md. Configurazione gateway: Backend/coach-gateway/README.md. Questo checkpoint va aggiornato a ogni blocco verificato.

Primo tentativo CI: Core/gateway passati, iOS fallita perché il nuovo workflow ometteva la selezione Xcode della baseline (16.4 invece di 26.3). Corretto il workflow riusando la selezione esistente, senza modificare la libreria AI. Ultimo run interamente passato. UI invariata: test UI e collaudo reale iPhone rinviati al collegamento/release, senza attribuire alla compilazione equivalenza al collaudo.

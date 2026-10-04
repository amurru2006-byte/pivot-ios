# Revisione Coach: specifica v0.1 rispetto a Pivot 0.5.0

## Verdetto

La proposta è una specifica dichiaratamente senza codice. Ha potenziale come roadmap,
non costituisce una seconda AI installabile né una dimostrazione di superiorità.
Pivot 0.5.1 adotta controlli circoscritti, mantenendo modello e runtime della 0.5.0.
Non sono state misurate le prestazioni dei modelli proposti sul dispositivo reale.

## Problemi di progettazione da correggere prima di un'implementazione completa

1. Priorità: la tabella tratta amici, partner e palestra diversamente. Occorre mantenere
   le priorità concordate dall'utente, con override espliciti; non introdurre una nuova
   gerarchia dalla specifica. “Altro” non significa eliminabile.
2. Tempi: solo `hh:mm` non identifica una data, un passaggio di mezzanotte, una fascia
   di ora legale ambigua o un evento di più giorni. Usare Date/istanti completi e il fuso
   per presentazione; non convertire un orario ambiguo senza chiarimento.
3. L'esempio PlanDiff riduce la palestra da 60 a 45 minuti pur chiamando l'operazione
   soltanto “move”. Separare spostamento e taglio, verificare il minimo e l'autorizzazione.
   Un taglio non è giustificato dalla sola preferenza o dall'inferenza del modello.
4. Tragitti: distanza in linea d'aria moltiplicata per una velocità non copre strade,
   attese, cambi, parcheggio o trasporto pubblico. Non usarla come tragitto verificato.
   In assenza di routing attendibile usare tempi confermati, oppure bloccare la proposta.
5. Memorie: un ricordo più recente ma non confermato non deve prevalere su una regola
   confermata. Aggiungere provenienza, stato, scadenza e revisione prima dell'apprendimento.
6. Snapshot: titolo, inizio, fine e modifica non bastano per le verifiche dei conflitti.
   Conservare anche identità, calendario, luogo, note e stato a giornata intera. Pivot
   mantiene già controlli più ampi e rilegge prima di una scrittura confermata.
7. Modelli: SmolLM3-3B è più grande del 2B; non è automaticamente un ripiego in caso
   di memoria insufficiente. Velocità e memoria non sono deducibili dal numero di parametri.
   Il riferimento A16 citato usa Phi-2 nel 2023, non misura Qwen3.5 nel contesto di Pivot.
8. Sideloading: non assumere rinnovo da telefono o sopravvivenza dei dati alla cancellazione.
   Verificare la versione effettiva, la modalità installata e mantenere backup esterni.
9. Architettura ibrida e JSON sono buone idee, ma schema valido non significa intenzione
   corretta. Il modello non può attribuirsi autorizzazioni o modificare la contabilità.

## Fonti primarie verificate

- Qwen3.5-2B esiste, licenza Apache-2.0. La scheda non dimostra prestazioni su iPhone 15:
  https://huggingface.co/Qwen/Qwen3.5-2B
- SmolLM3-3B supporta nativamente italiano; non è una garanzia di qualità sul compito:
  https://huggingface.co/HuggingFaceTB/SmolLM3-3B
- Core AI e integrazione di modelli custom sono reali. Restano necessarie conversione,
  compatibilità OS/toolchain e verifiche sul dispositivo. Nessuna migrazione introdotta:
  https://developer.apple.com/videos/play/wwdc2026/324/
- `xcode-27` è un'immagine GitHub documentata in preview, non un nome inventato.
  Non è necessario migrare per i controlli della 0.5.1:
  https://github.com/actions/runner-images/issues/14404
- Benchmark A16 storico, con modelli differenti:
  https://github.com/ggml-org/llama.cpp/discussions/4508

## Adottato nella 0.5.1

- Selezione esplicita dell'occorrenza, chiarimento dei bersagli ambigui e negazioni conservative.
- Recuperi confinati a oggi/domani/dopodomani se indicato, senza spostamenti silenziosi.
- Risposta AI stretta `{version, option_id, tone}` validata dopo generazione.
  Testo, orari e conseguenze provengono esclusivamente dalle proposte del motore.
- Scarto dei suggerimenti tardivi diventati obsoleti. Fallback al motore senza AI.
- Test regressione aggiuntivi. Nessuna nuova dipendenza, entitlement o schema di backup.

## Non adottato / non verificato

Parser LLM generale, compressioni multiple, memoria automatica a livelli, apprendimento
statistico, HealthKit, nuovi runtime Core AI/MLX, modello 2B/3B e backup cifrato con
passphrase. Richiedono implementazione e test propri; non si considerano completati
perché sono descritti nella proposta. La validazione dei JSON non è una grammatica
che vincola la generazione; la frequenza di JSON corretti sul telefono non è misurata.

# Catalogo e illustrazioni

Catalogo offline: 876 record da [free-exercise-db](https://github.com/yuhonas/free-exercise-db), revisione `f00c92c7dcf1216a928a52c3706c7ce8e2f71ed5`. Licenza originale in `Exercise-catalog-license.txt`. Nomi più comuni, muscoli e attrezzi tradotti; molti nomi restano in inglese. Non è un repertorio esaustivo di tutte le varianti. Nessun programma o carico viene prescritto dal catalogo.

Illustrazioni: 302 esercizi e 906 pose da [Workout Guide](https://github.com/bryllim/workout-guide), revisione `aac599224bb9780305239607ef98540b7e0ce389`. Le immagini sono disegni tecnici, non fotografie di persone reali, e sono CC BY-SA 4.0; attribuzione e licenza sono conservate in `Workout-guide-attribution.md` e `Workout-guide-assets-license.txt`. Pivot include soltanto il manifesto compatto e carica la posa da GitHub quando serve, per non appesantire l’IPA. Le varianti non abbinate conservano un segnaposto neutro, anziché mostrare una tecnica potenzialmente sbagliata. Il fornitore riceve la normale richiesta dell’immagine ma non lo storico dell’utente.

Illustrazione originale della panca piana: `Pivot/Assets.xcassets/ExerciseBenchPress.imageset/bench-press.png`, generata con lo strumento integrato imagegen. Non si usa per panca inclinata, manubri o altri movimenti. Muscoli dal record `Barbell_Bench_Press_-_Medium_Grip`: pettorali principali, spalle e tricipiti secondari. Il rosso rappresenta gruppi coinvolti, non una misurazione individuale di attivazione; una figura generata non sostituisce la verifica tecnica del coach. Le altre illustrazioni anatomiche potranno essere aggiunte per gli esercizi effettivamente presenti nella scheda personale, che non è ancora stata fornita.

## Prompt finale

```
Use case: scientific-educational
Asset type: original exercise recognition thumbnail for an iOS training diary, square composition.
Primary request: an anatomical fitness illustration of a person performing a flat barbell bench press, recognizable at small size. One athlete and one flat horizontal bench with barbell and rack, full body and apparatus visible from a three-quarter side view. Athlete lies on the bench, feet on floor, hands symmetrically gripping the single straight barbell above chest, bent elbows during the lowering phase. Gray anatomical muscle shading and dark gray shorts, chest muscles highlighted muted red with anterior shoulders and triceps subtle red. White plain background, restrained grayscale equipment, crisp professional raster illustration, generous edge spacing.
Constraints: original composition, not a reproduction of a commercial exercise diagram. Correct continuous barbell with plates attached at both ends; natural paired hands and arms; no extra limbs, no text, labels, logos, watermark or border. This is an identification image, not a step-by-step coaching diagram.
```

## Statistiche

Solo serie segnate fatte, con carico finito non negativo e ripetizioni positive. Storico delle sessioni terminate; la sessione in corso si include solo quando si apre dal suo diario, senza duplicarla. Varianti/identificativi diversi non vengono uniti automaticamente. Correggere una vecchia sessione ricalcola le statistiche.

Volume = somma di carico inserito × ripetizioni; per manubri mantenere sempre la stessa convenzione. La stima Epley usa `kg × (1 + reps/30)` soltanto da 1 a 10 ripetizioni (a 1 ripetizione mostra il carico fatto); non è una prescrizione di carico né un massimale misurato. Senza informazioni sulla vicinanza al cedimento resta un riferimento teorico. Fonti primarie: [equazione](https://pmc.ncbi.nlm.nih.gov/articles/PMC6318920/), [accuratezza dipendente dalle ripetizioni](https://pubmed.ncbi.nlm.nih.gov/16937972/).

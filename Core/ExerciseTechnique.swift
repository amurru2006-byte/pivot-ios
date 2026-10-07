import Foundation

struct ExerciseTechnique {
    var execution: [String]
    var mistakes: [String]
    static func forExercise(_ exercise: TrainingExercise, catalog: CatalogExercise?) -> ExerciseTechnique? {
        let key = EventCoalescer.normalized(exercise.name)
        let explicitAliases = ["barbell squat": "Barbell_Squat", "romanian deadlift": "Romanian_Deadlift", "seated leg curl": "Seated_Leg_Curl", "leg extensions": "Leg_Extensions"]
        let id = catalog?.id ?? exercise.catalogID ?? ExerciseCatalog.legacyAliases[key] ?? explicitAliases[key]
        if key == "copenhagen plank" {
            return .init(execution: ["Concorda con il PT l'appoggio e la variante (ginocchio o piede), che cambiano la difficoltà.", "Mantieni il bacino stabile e registra la tenuta separatamente a sinistra e a destra.", "Termina la tenuta quando non riesci più a mantenere la posizione indicata dal PT."],
                         mistakes: ["Ruotare o lasciar scendere il bacino.", "Usare la variante con leva lunga quando è stata prescritta quella corta.", "Registrare i secondi come carico."])
        }
        switch id {
        case "Barbell_Bench_Press_-_Medium_Grip":
            return .init(execution: ["Piedi stabili, glutei sulla panca e parte alta della schiena ben appoggiata.", "Impugna il bilanciere in modo simmetrico, mantenendo i polsi allineati agli avambracci.", "Scendi in controllo e spingi senza rimbalzi; concorda traiettoria e presa con il PT. Usa sicurezze o assistenza adatte."],
                         mistakes: ["Rimbalzare sul torace.", "Perdere l'appoggio o piegare eccessivamente i polsi.", "Cambiare presa o ampiezza per completare le ultime Reps."])
        case "Barbell_Squat", "Barbell_Full_Squat":
            return .init(execution: ["Sistema il bilanciere e i supporti del rack secondo la variante del PT.", "Mantieni piedi stabili e tronco controllato; scendi piegando anche e ginocchia.", "Le ginocchia seguono la direzione dei piedi. Risali senza perdere l'assetto concordato."],
                         mistakes: ["Sollevare i talloni o perdere equilibrio.", "Far cedere improvvisamente le ginocchia verso l'interno.", "Aumentare profondità o carico sacrificando il controllo."])
        case "Romanian_Deadlift":
            return .init(execution: ["Parti in piedi, con ginocchia leggermente flesse e carico vicino alle gambe.", "Porta le anche indietro mantenendo il tronco stabile; scendi solo finché controlli la posizione.", "Ritorna in piedi estendendo le anche senza inarcare la schiena alla fine."],
                         mistakes: ["Trasformare il movimento in uno squat.", "Allontanare il carico dalle gambe.", "Cercare il pavimento perdendo il controllo del tronco."])
        case "Barbell_Deadlift":
            return .init(execution: ["Sistema piedi, presa e bilanciere secondo la variante convenzionale prescritta.", "Prima di staccare crea tensione, mantenendo il bilanciere vicino alle gambe.", "Estendi anche e ginocchia in controllo e riappoggia senza lasciar perdere l'assetto."],
                         mistakes: ["Strappare il carico senza preparare la posizione.", "Allontanare il bilanciere dal corpo.", "Iperestendere il tronco alla chiusura."])
        case "Leg_Extensions":
            return .init(execution: ["Regola sedile e perno con il PT; annota i livelli della macchina.", "Estendi le ginocchia in controllo mantenendo il bacino appoggiato.", "Rientra senza lasciar cadere il pacco pesi; registra se il carico è mono o bilaterale."],
                         mistakes: ["Sollevare il bacino per aiutare il movimento.", "Usare slancio o urtare il pacco pesi.", "Cambiare macchina o impostazioni senza annotarlo."])
        case "Seated_Leg_Curl":
            return .init(execution: ["Allinea ginocchia e perno, stabilizza le cosce e annota le regolazioni.", "Fletti le ginocchia in controllo, mantenendo l'appoggio sul sedile.", "Ritorna gradualmente senza lasciar risalire il carico di colpo."],
                         mistakes: ["Spostare il bacino per completare la serie.", "Usare slancio.", "Cambiare le regolazioni senza registrarle."])
        case "Standing_Calf_Raises", "Seated_Calf_Raise":
            return .init(execution: ["Regola gli appoggi della variante scelta e mantieni il piede stabile.", "Sali sulle punte in controllo; scendi nell'ampiezza concordata con il PT.", "Usa la stessa convenzione di carico nelle sessioni successive."],
                         mistakes: ["Rimbalzare invece di controllare la salita e la discesa.", "Perdere l'appoggio del piede.", "Confondere la variante in piedi con quella seduta."])
        case "Dumbbell_Bench_Press", "Incline_Dumbbell_Press":
            return .init(execution: ["Regola la panca in base alla variante e annota l'inclinazione.", "Stabilizza piedi e schiena, con manubri e polsi ben controllati.", "Scendi e spingi in modo simmetrico, nell'ampiezza indicata dal PT."],
                         mistakes: ["Perdere stabilità o far divergere i due lati.", "Forzare la discesa oltre l'ampiezza controllata.", "Alternare carico per manubrio e carico totale nello storico."])
        case "Side_Lateral_Raise":
            return .init(execution: ["Parti stabile con i manubri ai lati e una leggera flessione dei gomiti.", "Solleva le braccia lateralmente nella traiettoria indicata dal PT.", "Riporta i manubri in basso in controllo."],
                         mistakes: ["Slanciare il tronco.", "Sollevare eccessivamente le spalle.", "Usare un peso che impedisce una discesa controllata."])
        case "Standing_Military_Press":
            return .init(execution: ["Parti stabile, con bilanciere davanti alle spalle e tronco controllato.", "Spingi sopra la testa lungo la traiettoria concordata.", "Rientra in controllo mantenendo l'assetto, senza trasformarla in una spinta con le gambe."],
                         mistakes: ["Inarcare eccessivamente il tronco.", "Usare slancio delle gambe in una serie prescritta rigorosa.", "Perdere allineamento dei polsi."])
        case "Hammer_Curls":
            return .init(execution: ["Mantieni la presa neutra, con i palmi rivolti verso il corpo.", "Fletti i gomiti senza muovere il tronco e senza trascinare le spalle.", "Scendi in controllo nell'ampiezza indicata."],
                         mistakes: ["Dondolare il tronco.", "Cambiare presa durante la serie.", "Far cadere i manubri nella fase di ritorno."])
        case "Triceps_Pushdown":
            return .init(execution: ["Stabilisci con il PT attacco, presa e posizione del corpo.", "Estendi i gomiti mantenendo le braccia controllate vicino al tronco.", "Rientra senza lasciarti trascinare dal cavo."],
                         mistakes: ["Spingere con tutto il corpo.", "Muovere le spalle invece di controllare i gomiti.", "Lasciar urtare il pacco pesi."])
        case "Cable_Crossover":
            return .init(execution: ["Regola altezza dei cavi e posizione come prescritto.", "Con gomiti leggermente flessi, avvicina le mani mantenendo il tronco stabile.", "Riapri in controllo senza forzare l'allungamento."],
                         mistakes: ["Trasformare le croci in una spinta.", "Cambiare altezza dei cavi senza annotarlo.", "Usare slancio e perdere la posizione delle spalle."])
        case "Plank":
            return .init(execution: ["Sistema gli appoggi della variante prescritta.", "Mantieni tronco e bacino stabili e continua a respirare.", "Registra i secondi effettivi e termina quando perdi l'assetto concordato."],
                         mistakes: ["Lasciar scendere o sollevare troppo il bacino.", "Prolungare la tenuta perdendo la posizione.", "Registrare la durata come kg o Reps."])
        default: return nil
        }
    }
}

import Foundation
import NaturalLanguage

/// Query-only equivalents of the existing English policies; passage recipes stay unchanged.
enum HistoryQueryVocabulary {
    static let genericNouns: [NLLanguage: Set<String>] = [
        .german: Set([
            "aktualisierung", "aktualisierungen", "alles", "anruf", "anrufe", "anrufen", "art", "arten", "besprechung",
            "besprechungen", "bisschen", "ding", "dinge", "dingen", "etwas", "frage", "fragen", "gestern", "heute", "hm", "hmm",
            "idee", "ideen", "irgendetwas", "irgendjemand", "ja", "jahr", "jahre", "jahren", "jahres", "jede", "jedem", "jeden",
            "jeder", "jedes", "jemand", "jemandem", "jemanden", "leute", "leuten", "mal", "male", "malen", "menge", "mengen",
            "minute", "minuten", "monat", "monate", "monaten", "monats", "morgen", "nachmittag", "nachmittage", "nichts", "ok",
            "okay", "person", "personen", "plan", "planes", "plans", "pläne", "plänen", "projekt", "projekte", "projekten",
            "projekts", "punkt", "punkte", "punkten", "sache", "sachen", "sitzung", "sitzungen", "status", "stunde", "stunden",
            "tag", "tage", "tagen", "tags", "team", "teams", "treffen", "vormittag", "vormittage", "weise", "weisen", "woche",
            "wochen", "zeit", "zeiten", "zeug", "äh", "ähm"
        ]),
        .spanish: Set([
            "actualizaciones", "actualización", "algo", "alguien", "ayer", "año", "años", "clase", "clases", "cosa", "cosas",
            "cualquier", "cualquiera", "día", "días", "eh", "em", "equipo", "equipos", "estado", "estados", "gente", "hmm",
            "hora", "horas", "hoy", "idea", "ideas", "llamada", "llamadas", "manera", "maneras", "mañana", "mes", "meses",
            "minuto", "minutos", "montones", "montón", "nada", "ok", "okay", "persona", "personas", "plan", "planes", "poco",
            "pocos", "pregunta", "preguntas", "proyecto", "proyectos", "punto", "puntos", "reuniones", "reunión", "semana",
            "semanas", "sí", "tarde", "tardes", "tiempo", "tiempos", "tipo", "tipos", "todas", "todo", "todos", "vale", "veces",
            "vez"
        ]),
    ]

    // Ask retains its narrower literal-term policy, including question/project and decided terms.
    static let askStopWords: [NLLanguage: Set<String>] = [
        .german: Set([
            "alle", "allem", "allen", "aller", "am", "auf", "aus", "besprechung", "besprechungen", "bin", "bist", "da", "das",
            "dem", "den", "der", "des", "dich", "die", "dies", "diese", "diesem", "diesen", "dieser", "dieses", "ding", "dinge",
            "dingen", "dir", "dort", "du", "erzähle", "erzählen", "erzählt", "erzählte", "erzählten", "es", "euch", "euer",
            "eure", "eurem", "euren", "eurer", "eures", "für", "habe", "haben", "habt", "hast", "hat", "hatte", "hatten",
            "hattest", "hattet", "ihnen", "ihr", "ihre", "ihrem", "ihren", "ihrer", "ihres", "im", "ins", "irgendein",
            "irgendeine", "irgendeinem", "irgendeinen", "irgendeiner", "ist", "jene", "jenem", "jenen", "jener", "jenes",
            "kann", "kannst", "konnte", "konnten", "können", "könnt", "könnte", "könnten", "letzte", "letztem", "letzten",
            "letzter", "letztes", "mal", "male", "mich", "mir", "mit", "nach", "nächste", "nächstem", "nächsten", "nächster",
            "nächstes", "plan", "planes", "plans", "pläne", "plänen", "sache", "sachen", "sage", "sagen", "sagst", "sagt",
            "sagte", "sagten", "seid", "sein", "sie", "sind", "sitzung", "sitzungen", "soll", "sollen", "sollst", "sollt",
            "sollte", "sollten", "tat", "taten", "tatest", "tatet", "team", "teams", "treffen", "tue", "tun", "tust", "tut",
            "und", "uns", "unser", "unsere", "unserem", "unseren", "unserer", "unseres", "von", "wann", "war", "waren", "warst",
            "wart", "warum", "was", "welche", "welchem", "welchen", "welcher", "welches", "wem", "wen", "wer", "werde",
            "werden", "werdet", "wie", "wir", "wird", "wirst", "wo", "woche", "wochen", "würde", "würden", "würdest", "würdet",
            "zeit", "zeiten", "zu", "zum", "zur", "über"
        ]),
        .spanish: Set([
            "ahí", "al", "allí", "aquel", "aquella", "aquellas", "aquello", "aquellos", "como", "con", "cosa", "cosas",
            "cuales", "cualesquiera", "cualquier", "cualquiera", "cuando", "cuál", "cuáles", "cuándo", "cómo", "de", "debe",
            "debemos", "deben", "debería", "deberían", "debes", "debo", "debéis", "decimos", "decir", "decís", "del", "desde",
            "dice", "dicen", "dices", "digo", "dije", "dijeron", "dijimos", "dijiste", "dijisteis", "dijo", "donde", "dónde",
            "e", "el", "ellas", "ello", "ellos", "en", "equipo", "equipos", "era", "erais", "eran", "eras", "eres", "es", "esa",
            "esas", "ese", "eso", "esos", "esta", "estaba", "estabais", "estaban", "estabas", "estamos", "estar", "estas",
            "este", "esto", "estos", "estoy", "está", "estábamos", "estáis", "están", "estás", "fue", "fueron", "fui", "fuimos",
            "fuiste", "fuisteis", "ha", "haber", "habéis", "había", "habíais", "habíamos", "habían", "habías", "hace",
            "hacemos", "hacen", "hacer", "haces", "hacéis", "hago", "han", "has", "he", "hemos", "hice", "hicieron", "hicimos",
            "hiciste", "hicisteis", "hizo", "la", "las", "le", "les", "lo", "los", "me", "mí", "nos", "nosotras", "nosotros",
            "nuestra", "nuestras", "nuestro", "nuestros", "para", "pasada", "pasadas", "pasado", "pasados", "plan", "planes",
            "podemos", "poder", "podría", "podrían", "podéis", "podía", "podían", "por", "porqué", "próxima", "próximas",
            "próximo", "próximos", "puede", "pueden", "puedes", "puedo", "que", "quienes", "quién", "quiénes", "qué",
            "reuniones", "reunión", "semana", "semanas", "ser", "siguiente", "siguientes", "sobre", "sois", "somos", "son",
            "soy", "su", "sus", "tenemos", "tener", "tengo", "tenéis", "tenía", "teníais", "teníamos", "tenían", "tenías",
            "tiempo", "tiempos", "tiene", "tienen", "tienes", "toda", "todas", "todo", "todos", "tu", "tus", "tú", "usted",
            "ustedes", "veces", "vez", "vosotras", "vosotros", "vuestra", "vuestras", "vuestro", "vuestros", "y", "yo",
            "éramos", "última", "últimas", "último", "últimos"
        ]),
    ].mapValues { Set($0.map(SessionSearch.fold)) }

}

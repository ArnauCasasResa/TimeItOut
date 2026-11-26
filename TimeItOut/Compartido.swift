import SwiftUI
import SwiftData

// Este archivo se comparte entre la app y el widget:
// en Xcode, marca los DOS targets en "Target Membership".

// MARK: - Almacén compartido (App Group)

enum Almacen {
    /// Debe ser IGUAL al App Group marcado en los targets de la app y del widget.
    static let grupo = "group.com.arnaucasasresapersonalteam.TimeItOut"

    /// ¿Tiene este proceso acceso a la carpeta compartida del App Group?
    static var grupoDisponible: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grupo) != nil
    }

    static func crear() throws -> ModelContainer {
        let config = ModelConfiguration(groupContainer: .identifier(grupo))
        return try ModelContainer(for: Pago.self, configurations: config)
    }

    static let contenedor: ModelContainer = {
        do {
            return try crear()
        } catch {
            fatalError("No se pudo crear el contenedor: \(error)")
        }
    }()
}

// MARK: - Frecuencia

enum Frecuencia: String, CaseIterable, Identifiable {
    case mensual, trimestral, anual
    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .mensual: return "Mensual"
        case .trimestral: return "Trimestral"
        case .anual: return "Anual"
        }
    }
}

// MARK: - Iconos

let iconosDisponibles = [
    "creditcard", "icloud", "house", "car", "bolt", "drop", "wifi", "iphone",
    "tv", "music.note", "gamecontroller", "cart", "heart", "graduationcap",
    "dumbbell", "shield", "fuelpump", "airplane", "book", "gift"
]

// MARK: - Modelo

@Model
final class Pago {
    var id: UUID = UUID()
    var nombre: String = ""
    var importe: Double = 0
    var diaDelMes: Int = 1            // 1...28
    var frecuenciaRaw: String = "mensual"
    var mes: Int = 1                  // 1...12: mes del primer pago (trimestral) o mes del pago (anual)
    var repetir: Bool = true          // false = pago único en fechaUnica
    var fechaUnica: Date = Date()
    var icono: String = "creditcard"
    var colorIcono: String = "azul"
    var fechaCreacion: Date = Date()

    init(nombre: String, importe: Double, diaDelMes: Int,
         frecuencia: Frecuencia, mes: Int,
         repetir: Bool = true, fechaUnica: Date = Date(),
         icono: String = "creditcard", colorIcono: String = "azul") {
        self.id = UUID()
        self.nombre = nombre
        self.importe = importe
        self.diaDelMes = diaDelMes
        self.frecuenciaRaw = frecuencia.rawValue
        self.mes = mes
        self.repetir = repetir
        self.fechaUnica = fechaUnica
        self.icono = icono
        self.colorIcono = colorIcono
    }

    /// Pago único cuya fecha ya ha pasado.
    var vencido: Bool { !repetir && diasRestantes < 0 }

    var frecuencia: Frecuencia {
        Frecuencia(rawValue: frecuenciaRaw) ?? .mensual
    }

    /// Meses del año en los que se paga (vacío = todos los meses).
    var mesesActivos: [Int] {
        switch frecuencia {
        case .mensual: return []
        case .trimestral: return (0..<4).map { ((mes - 1 + 3 * $0) % 12) + 1 }
        case .anual: return [mes]
        }
    }

    /// Próxima fecha de pago (hoy cuenta como "hoy").
    var proximaFecha: Date {
        if !repetir { return fechaUnica }
        let cal = Calendar.current
        let ayer = cal.startOfDay(for: .now).addingTimeInterval(-1)

        if frecuencia == .mensual {
            return cal.nextDate(after: ayer,
                                matching: DateComponents(day: diaDelMes),
                                matchingPolicy: .nextTime) ?? .now
        }
        let candidatas = mesesActivos.compactMap { m in
            cal.nextDate(after: ayer,
                         matching: DateComponents(month: m, day: diaDelMes),
                         matchingPolicy: .nextTime)
        }
        return candidatas.min() ?? .now
    }

    var diasRestantes: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: .now),
                                  to: cal.startOfDay(for: proximaFecha)).day ?? 0
    }

    /// Duración en días del ciclo actual (del pago anterior al próximo).
    var cicloTotalDias: Int {
        let cal = Calendar.current
        let fin = cal.startOfDay(for: proximaFecha)
        let inicio: Date
        if !repetir {
            inicio = cal.startOfDay(for: fechaCreacion)
        } else {
            switch frecuencia {
            case .mensual:    inicio = cal.date(byAdding: .month, value: -1, to: fin) ?? fin
            case .trimestral: inicio = cal.date(byAdding: .month, value: -3, to: fin) ?? fin
            case .anual:      inicio = cal.date(byAdding: .year,  value: -1, to: fin) ?? fin
            }
        }
        return max(1, cal.dateComponents([.day], from: inicio, to: fin).day ?? 1)
    }

    /// 1 = falta mucho (barra llena), 0 = toca pagar (barra vacía).
    var progreso: Double {
        min(1, max(0, Double(diasRestantes) / Double(cicloTotalDias)))
    }

    /// Lo que supone al mes, para el total.
    var importeMensualEquivalente: Double {
        if !repetir { return 0 }
        switch frecuencia {
        case .mensual: return importe
        case .trimestral: return importe / 3
        case .anual: return importe / 12
        }
    }
}

// MARK: - Resumen ligero para el widget

struct PagoResumen: Identifiable {
    let id: UUID
    let nombre: String
    let importe: Double
    let icono: String
    let colorIcono: String
    let diasRestantes: Int
    let progreso: Double
    let vencido: Bool

    init(_ p: Pago) {
        id = p.id
        nombre = p.nombre
        importe = p.importe
        icono = p.icono
        colorIcono = p.colorIcono
        diasRestantes = p.diasRestantes
        progreso = p.progreso
        vencido = p.vencido
    }

    init(id: UUID = UUID(), nombre: String, importe: Double, icono: String,
         diasRestantes: Int, progreso: Double, colorIcono: String = "azul") {
        self.id = id
        self.nombre = nombre
        self.importe = importe
        self.icono = icono
        self.colorIcono = colorIcono
        self.diasRestantes = diasRestantes
        self.progreso = progreso
        self.vencido = false
    }

    var diasTexto: String {
        if vencido { return "Pasado" }
        switch diasRestantes {
        case 0: return "Hoy"
        case 1: return "1 día"
        default: return "\(diasRestantes) días"
        }
    }
}

// MARK: - Color y anillo (estilo batería)

// MARK: - Paleta de colores para los iconos

let paletaColores: [(nombre: String, color: Color)] = [
    ("rojo", .red), ("naranja", .orange), ("amarillo", .yellow), ("verde", .green),
    ("menta", .mint), ("azul", .blue), ("indigo", .indigo), ("morado", .purple),
    ("rosa", .pink), ("gris", .gray)
]

func colorDeNombre(_ nombre: String) -> Color {
    paletaColores.first { $0.nombre == nombre }?.color ?? .blue
}

func colorProgreso(_ progreso: Double, vencido: Bool = false) -> Color {
    if vencido { return .gray }
    if progreso <= 0.15 { return .red }
    if progreso <= 0.40 { return .orange }
    return .green
}

struct IconoProgreso: View {
    let icono: String
    let progreso: Double
    var vencido: Bool = false
    var tamano: CGFloat = 46
    var grosor: CGFloat = 5
    var colorIcono: Color? = nil   // color propio del icono (el anillo sigue el progreso)

    var body: some View {
        let color = colorProgreso(progreso, vencido: vencido)
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: grosor)
            Circle()
                .trim(from: 0, to: vencido ? 0 : progreso)
                .stroke(color, style: StrokeStyle(lineWidth: grosor, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: icono)
                .font(.system(size: tamano * 0.4, weight: .semibold))
                .foregroundStyle(colorIcono ?? color)
        }
        .frame(width: tamano, height: tamano)
    }
}

import WidgetKit
import SwiftUI
import SwiftData

// Este archivo va SOLO en el target del widget.
// Necesita también Compartido.swift en el target del widget.

// MARK: - Datos

struct Entrada: TimelineEntry {
    let date: Date
    let pagos: [PagoResumen]
    var error: String? = nil   // mensaje de diagnóstico (temporal)
}

struct Proveedor: TimelineProvider {

    func placeholder(in context: Context) -> Entrada {
        Entrada(date: .now, pagos: Self.ejemplo)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entrada) -> Void) {
        if context.isPreview {
            completion(Entrada(date: .now, pagos: Self.ejemplo))
        } else {
            let r = cargar()
            completion(Entrada(date: .now, pagos: r.pagos, error: r.error))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entrada>) -> Void) {
        let r = cargar()
        let entrada = Entrada(date: .now, pagos: r.pagos, error: r.error)
        // Se refresca cada día a medianoche, que es cuando cambian los días restantes.
        let cal = Calendar.current
        let manana = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        completion(Timeline(entries: [entrada], policy: .after(manana)))
    }

    private func cargar() -> (pagos: [PagoResumen], error: String?) {
        // Si el widget no tiene el App Group, SwiftData se cerraría solo: lo comprobamos antes.
        guard Almacen.grupoDisponible else {
            return ([], "Sin acceso al App Group. Revisa Signing & Capabilities del widget.")
        }
        do {
            let contexto = ModelContext(try Almacen.crear())
            let pagos = try contexto.fetch(FetchDescriptor<Pago>())
            let resumenes = pagos
                .map { PagoResumen($0) }
                .sorted { ($0.vencido ? 1 : 0, $0.diasRestantes) < ($1.vencido ? 1 : 0, $1.diasRestantes) }
            return (resumenes, resumenes.isEmpty ? "Leído: 0 pagos" : nil)
        } catch {
            return ([], "Error: \(error.localizedDescription)")
        }
    }

    static let ejemplo = [
        PagoResumen(nombre: "iCloud", importe: 0.99, icono: "icloud", diasRestantes: 3, progreso: 0.1),
        PagoResumen(nombre: "Internet", importe: 35, icono: "wifi", diasRestantes: 12, progreso: 0.4),
        PagoResumen(nombre: "Seguro coche", importe: 280, icono: "car", diasRestantes: 200, progreso: 0.55)
    ]
}

// MARK: - Vistas

struct VistaWidget: View {
    @Environment(\.widgetFamily) private var familia
    let entrada: Entrada

    var body: some View {
        switch familia {
        case .systemMedium:
            VistaMediana(pagos: Array(entrada.pagos.prefix(3)), mensaje: entrada.error)
        case .accessoryCircular:
            VistaBloqueo(pago: entrada.pagos.first)
        default:
            VistaPequena(pago: entrada.pagos.first, mensaje: entrada.error)
        }
    }
}

struct VistaPequena: View {
    let pago: PagoResumen?
    var mensaje: String? = nil

    var body: some View {
        if let p = pago {
            VStack(spacing: 8) {
                IconoProgreso(icono: p.icono, progreso: p.progreso,
                              vencido: p.vencido, tamano: 64, grosor: 7,
                              colorIcono: colorDeNombre(p.colorIcono))
                VStack(spacing: 2) {
                    Text(p.nombre)
                        .font(.headline)
                        .lineLimit(1)
                    Text(p.diasTexto)
                        .font(.subheadline.bold())
                        .foregroundStyle(colorProgreso(p.progreso, vencido: p.vencido))
                    Text(p.importe.formatted(.currency(code: "EUR")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "calendar.badge.plus").font(.title)
                Text(mensaje ?? "Sin pagos")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(.secondary)
        }
    }
}

struct VistaMediana: View {
    let pagos: [PagoResumen]
    var mensaje: String? = nil

    var body: some View {
        if pagos.isEmpty {
            Text(mensaje ?? "Añade un pago en la app")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 10) {
                ForEach(pagos) { p in
                    FilaBateria(pago: p)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Fila con barra tipo batería: llena = falta mucho, vacía = toca pagar.
struct FilaBateria: View {
    let pago: PagoResumen

    var body: some View {
        let color = colorProgreso(pago.progreso, vencido: pago.vencido)
        HStack(spacing: 10) {
            Image(systemName: pago.icono)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colorDeNombre(pago.colorIcono))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(pago.nombre)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(pago.diasTexto)
                        .font(.caption.bold())
                        .foregroundStyle(color)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule()
                            .fill(color)
                            .frame(width: max(6, geo.size.width * (pago.vencido ? 0 : pago.progreso)))
                    }
                }
                .frame(height: 8)
            }
        }
    }
}

struct VistaBloqueo: View {
    let pago: PagoResumen?

    var body: some View {
        if let p = pago {
            Gauge(value: p.vencido ? 0 : p.progreso) {
                Image(systemName: p.icono)
            } currentValueLabel: {
                Text("\(max(p.diasRestantes, 0))")
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            Image(systemName: "calendar")
        }
    }
}

// MARK: - Widget

@main
struct PagosWidget: Widget {
    let kind = "PagosWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Proveedor()) { entrada in
            VistaWidget(entrada: entrada)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Próximos pagos")
        .description("Cuenta atrás de tus pagos, con barra tipo batería.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

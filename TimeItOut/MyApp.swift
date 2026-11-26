import SwiftUI
import SwiftData
import UserNotifications
import WidgetKit

// MARK: - Notificaciones

enum Recordatorios {
    static func pedirPermiso() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private static func identificadores(_ pago: Pago) -> [String] {
        (0..<4).map { "\(pago.id.uuidString)-\($0)" }
    }

    /// Notificaciones repetidas a las 9:00 del día de pago.
    static func programar(_ pago: Pago) {
        let contenido = UNMutableNotificationContent()
        contenido.title = "Hoy toca pagar: \(pago.nombre)"
        contenido.body = pago.importe.formatted(.currency(code: "EUR"))
        contenido.sound = .default

        // Pago único: un solo aviso, sin repetición.
        if !pago.repetir {
            let cal = Calendar.current
            var f = cal.dateComponents([.year, .month, .day], from: pago.fechaUnica)
            f.hour = 9
            guard let fecha = cal.date(from: f), fecha > .now else { return }
            let trigger = UNCalendarNotificationTrigger(dateMatching: f, repeats: false)
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "\(pago.id.uuidString)-0",
                                      content: contenido,
                                      trigger: trigger))
            return
        }

        // Mensual: un solo aviso con solo día. Trimestral: 4 avisos. Anual: 1 aviso.
        let meses: [Int?] = pago.frecuencia == .mensual ? [nil] : pago.mesesActivos.map { Optional($0) }

        for (i, mes) in meses.enumerated() {
            var fecha = DateComponents()
            fecha.day = pago.diaDelMes
            fecha.hour = 9
            if let mes { fecha.month = mes }

            let trigger = UNCalendarNotificationTrigger(dateMatching: fecha, repeats: true)
            let peticion = UNNotificationRequest(identifier: "\(pago.id.uuidString)-\(i)",
                                                 content: contenido,
                                                 trigger: trigger)
            UNUserNotificationCenter.current().add(peticion)
        }
    }

    static func cancelar(_ pago: Pago) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identificadores(pago))
    }
}

// MARK: - App

@main
struct PagosMensualesApp: App {
    var body: some Scene {
        WindowGroup {
            ListaPagosView()
                .onAppear { Recordatorios.pedirPermiso() }
        }
        .modelContainer(Almacen.contenedor)
    }
}

// MARK: - Lista

struct ListaPagosView: View {
    @Environment(\.modelContext) private var contexto
    @Query private var pagos: [Pago]
    @State private var mostrandoNuevo = false
    @State private var mostrandoAjustes = false
    @AppStorage("sueldoMensual") private var sueldo: Double = 0

    /// Un trozo de arco por cada pago que se cobra este mes, con el color de su icono.
    private var segmentos: [SegmentoGasto] {
        ordenados.compactMap { p in
            let importe = p.importeEnMesActual()
            return importe > 0
                ? SegmentoGasto(id: p.id, color: colorDeNombre(p.colorIcono), importe: importe)
                : nil
        }
    }

    private var ordenados: [Pago] {
        pagos.sorted { ($0.vencido ? 1 : 0, $0.diasRestantes) < ($1.vencido ? 1 : 0, $1.diasRestantes) }
    }
    private var totalMensual: Double { pagos.reduce(0) { $0 + $1.importeMensualEquivalente } }

    var body: some View {
        NavigationStack {
            List {
                if !pagos.isEmpty {
                    Section {
                        ResumenSueldo(sueldo: sueldo, segmentos: segmentos) {
                            mostrandoAjustes = true
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                Section {
                    ForEach(ordenados) { pago in
                        FilaPago(pago: pago)
                    }
                    .onDelete { indices in
                        let lista = ordenados
                        for i in indices {
                            Recordatorios.cancelar(lista[i])
                            contexto.delete(lista[i])
                        }
                        try? contexto.save()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                } header: {
                    Text("Pagos")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                        .textCase(nil)
                } footer: {
                    if !pagos.isEmpty {
                        Text("Coste medio al mes: \(totalMensual.formatted(.currency(code: "EUR")))")
                    }
                }
            }
            .overlay {
                if pagos.isEmpty {
                    ContentUnavailableView("Sin pagos",
                                           systemImage: "calendar.badge.clock",
                                           description: Text("Toca + para añadir tu primer pago."))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { mostrandoAjustes = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { mostrandoNuevo = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $mostrandoNuevo) { NuevoPagoView() }
            .sheet(isPresented: $mostrandoAjustes) { AjustesView() }
        }
    }
}

struct FilaPago: View {
    let pago: Pago

    var body: some View {
        HStack(spacing: 12) {
            IconoProgreso(icono: pago.icono, progreso: pago.progreso, vencido: pago.vencido,
                          colorIcono: colorDeNombre(pago.colorIcono))
            VStack(alignment: .leading, spacing: 4) {
                Text(pago.nombre).font(.headline)
                Text("\(pago.repetir ? pago.frecuencia.titulo : "Una vez") · \(pago.importe.formatted(.currency(code: "EUR")))")
                    .foregroundStyle(.secondary)
                Text(pago.proximaFecha.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                if pago.vencido {
                    Text("Pasado").font(.headline).foregroundStyle(.secondary)
                } else {
                    Text(pago.diasRestantes == 0 ? "Hoy" : "\(pago.diasRestantes)")
                        .font(.title.bold())
                        .foregroundStyle(pago.diasRestantes <= 3 ? .red : .primary)
                    if pago.diasRestantes != 0 {
                        Text(pago.diasRestantes == 1 ? "día" : "días")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Importe que cae en el mes actual

extension Pago {
    /// Lo que se cobra este mes natural (mensual: siempre; trimestral/anual: solo en sus meses).
    func importeEnMesActual() -> Double {
        let cal = Calendar.current
        if !repetir {
            return cal.isDate(fechaUnica, equalTo: .now, toGranularity: .month) ? importe : 0
        }
        switch frecuencia {
        case .mensual:
            return importe
        case .trimestral, .anual:
            let mesActual = cal.component(.month, from: .now)
            return mesesActivos.contains(mesActual) ? importe : 0
        }
    }
}

// MARK: - Resumen del sueldo

struct SegmentoGasto: Identifiable {
    let id: UUID
    let color: Color
    let importe: Double
}

struct ResumenSueldo: View {
    let sueldo: Double
    let segmentos: [SegmentoGasto]
    let abrirAjustes: () -> Void

    private let tamano: CGFloat = 250
    private let grosor: CGFloat = 24
    private let arco = 0.75                      // el arco abarca 270° del círculo
    private let solapeEntrePagos = 0.002         // cada trozo se mete un pelín bajo el siguiente: sin línea entre ellos
    private let verdeAhorro = Color(red: 0.11, green: 0.55, blue: 0.24)   // verde más oscuro que el .green del sistema

    private var radio: CGFloat { (tamano - grosor) / 2 }
    private var gastado: Double { segmentos.reduce(0) { $0 + $1.importe } }
    private var fraccion: Double { sueldo > 0 ? min(1, gastado / sueldo) : 0 }
    private var ahorro: Double { sueldo - gastado }

    /// Trozos medidos desde el extremo derecho: inicio y fin entre 0 y 1.
    private var trozos: [(inicio: Double, fin: Double, color: Color)] {
        var acumulado = 0.0
        var resultado: [(inicio: Double, fin: Double, color: Color)] = []
        for segmento in segmentos {
            guard acumulado < 1 else { break }
            let f = min(segmento.importe / sueldo, 1 - acumulado)
            resultado.append((acumulado, acumulado + f, segmento.color))
            acumulado += f
        }
        return resultado
    }

    var body: some View {
        if sueldo <= 0 {
            Button(action: abrirAjustes) {
                Label("Añade tu sueldo mensual para ver cuánto ahorras",
                      systemImage: "eurosign.circle")
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 10) {
                ZStack {
                    // Verde: lo que te queda (ahorro). Arco abierto por abajo.
                    Circle()
                        .trim(from: 0, to: arco)
                        .stroke(verdeAhorro, style: StrokeStyle(lineWidth: grosor, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .padding(grosor / 2)

                    // Un trozo por pago, desde el extremo derecho hacia la izquierda.
                    ForEach(Array(trozos.enumerated()), id: \.offset) { i, t in
                        let solape = i < trozos.count - 1 ? solapeEntrePagos : 0
                        let desde = max(0, arco * (1 - t.fin) - solape)
                        Circle()
                            .trim(from: desde, to: arco * (1 - t.inicio))
                            .stroke(t.color, style: StrokeStyle(lineWidth: grosor, lineCap: .butt))
                            .rotationEffect(.degrees(135))
                            .padding(grosor / 2)
                    }

                    // Punta redondeada derecha (45° abajo-derecha) con el color del primer pago.
                    if let primero = trozos.first {
                        Circle()
                            .fill(primero.color)
                            .frame(width: grosor, height: grosor)
                            .offset(x: radio * 0.7071, y: radio * 0.7071)
                    }
                    // Punta redondeada izquierda cuando los pagos llenan todo el arco.
                    if fraccion >= 0.999, let ultimo = trozos.last {
                        Circle()
                            .fill(ultimo.color)
                            .frame(width: grosor, height: grosor)
                            .offset(x: -radio * 0.7071, y: radio * 0.7071)
                    }

                    VStack(spacing: 2) {
                        Text((gastado / sueldo).formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                        Text("del sueldo en pagos")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: tamano, height: tamano)
                .frame(maxWidth: .infinity)
                .frame(height: tamano * 0.88, alignment: .top)

                Text("Pagos del mes: \(gastado.formatted(.currency(code: "EUR"))) de \(sueldo.formatted(.currency(code: "EUR")))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if ahorro >= 0 {
                    Text("Este mes estás ahorrando \(ahorro.formatted(.currency(code: "EUR")))")
                        .font(.title3.bold())
                        .foregroundStyle(verdeAhorro)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Este mes te pasas \(abs(ahorro).formatted(.currency(code: "EUR")))")
                        .font(.title3.bold())
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Ajustes

struct AjustesView: View {
    @AppStorage("sueldoMensual") private var sueldo: Double = 0
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Sueldo mensual")
                        Spacer()
                        TextField("0", value: $sueldo, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                        Text("€")
                    }
                } footer: {
                    Text("Se usa para calcular qué parte de tu sueldo se llevan los pagos del mes. Se guarda solo en este iPhone.")
                }
            }
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }
                }
            }
        }
    }
}

// MARK: - Nuevo pago

struct NuevoPagoView: View {
    @Environment(\.modelContext) private var contexto
    @Environment(\.dismiss) private var cerrar

    @State private var nombre = ""
    @State private var importe = 1.0
    @State private var dia = 1
    @State private var frecuencia: Frecuencia = .mensual
    @State private var repetir = true
    @State private var fecha = Date()
    @State private var icono = "creditcard"
    @State private var colorIcono = "azul"
    @State private var mes = Calendar.current.component(.month, from: .now)

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre (ej. Almacenamiento iCloud)", text: $nombre)

                HStack {
                    Text("Importe")
                    Spacer()
                    TextField("0", value: $importe, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("€")
                }

                Section("Icono") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(iconosDisponibles, id: \.self) { nombreIcono in
                            Button {
                                icono = nombreIcono
                            } label: {
                                Image(systemName: nombreIcono)
                                    .font(.title3)
                                    .foregroundStyle(colorDeNombre(colorIcono))
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle().fill(icono == nombreIcono
                                                      ? Color.accentColor.opacity(0.25)
                                                      : Color.clear)
                                    )
                                    .overlay(
                                        Circle().stroke(icono == nombreIcono
                                                        ? Color.accentColor
                                                        : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))], spacing: 12) {
                        ForEach(paletaColores, id: \.nombre) { c in
                            Button {
                                colorIcono = c.nombre
                            } label: {
                                Circle()
                                    .fill(c.color)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: colorIcono == c.nombre ? 3 : 0)
                                            .padding(-4)
                                    )
                                    .frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Toggle("Repetir", isOn: $repetir)

                if repetir {
                Picker("Frecuencia", selection: $frecuencia) {
                    ForEach(Frecuencia.allCases) { f in
                        Text(f.titulo).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                if frecuencia != .mensual {
                    Picker(frecuencia == .anual ? "Mes" : "Mes del primer pago", selection: $mes) {
                        ForEach(1...12, id: \.self) { m in
                            Text(Calendar.current.monthSymbols[m - 1].capitalized).tag(m)
                        }
                    }
                }

                Stepper("Día: \(dia)", value: $dia, in: 1...28)

                if frecuencia == .trimestral {
                    Text("Se avisará cada 3 meses a partir de \(Calendar.current.monthSymbols[mes - 1]).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                } else {
                    DatePicker("Fecha", selection: $fecha, in: Date.now..., displayedComponents: .date)
                }
            }
            .navigationTitle("Nuevo pago")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let pago = Pago(nombre: nombre, importe: importe,
                                        diaDelMes: dia, frecuencia: frecuencia, mes: mes,
                                        repetir: repetir, fechaUnica: fecha, icono: icono,
                                        colorIcono: colorIcono)
                        contexto.insert(pago)
                        Recordatorios.programar(pago)
                        try? contexto.save()
                        WidgetCenter.shared.reloadAllTimelines()
                        cerrar()
                    }
                    .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

import SwiftUI
import SwiftData
import UserNotifications

// MARK: - Modelo

@Model
final class Pago {
    var id: UUID
    var nombre: String
    var importe: Double
    var diaDelMes: Int   // 1...28

    init(nombre: String, importe: Double, diaDelMes: Int) {
        self.id = UUID()
        self.nombre = nombre
        self.importe = importe
        self.diaDelMes = diaDelMes
    }

    /// Próxima fecha de cobro (hoy cuenta como "hoy").
    var proximaFecha: Date {
        let cal = Calendar.current
        let ayer = cal.startOfDay(for: .now).addingTimeInterval(-1)
        return cal.nextDate(after: ayer,
                            matching: DateComponents(day: diaDelMes),
                            matchingPolicy: .nextTime) ?? .now
    }

    var diasRestantes: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: .now),
                                  to: cal.startOfDay(for: proximaFecha)).day ?? 0
    }
}

// MARK: - Notificaciones

enum Recordatorios {
    static func pedirPermiso() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Notificación mensual repetida a las 9:00 del día de pago.
    static func programar(_ pago: Pago) {
        let contenido = UNMutableNotificationContent()
        contenido.title = "Hoy toca pagar: \(pago.nombre)"
        contenido.body = pago.importe.formatted(.currency(code: "EUR"))
        contenido.sound = .default

        var fecha = DateComponents()
        fecha.day = pago.diaDelMes
        fecha.hour = 9

        let trigger = UNCalendarNotificationTrigger(dateMatching: fecha, repeats: true)
        let peticion = UNNotificationRequest(identifier: pago.id.uuidString,
                                             content: contenido,
                                             trigger: trigger)
        UNUserNotificationCenter.current().add(peticion)
    }

    static func cancelar(_ pago: Pago) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [pago.id.uuidString])
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
        .modelContainer(for: Pago.self)
    }
}

// MARK: - Lista

struct ListaPagosView: View {
    @Environment(\.modelContext) private var contexto
    @Query(sort: \Pago.diaDelMes) private var pagos: [Pago]
    @State private var mostrandoNuevo = false

    private var total: Double { pagos.reduce(0) { $0 + $1.importe } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(pagos.sorted { $0.diasRestantes < $1.diasRestantes }) { pago in
                        FilaPago(pago: pago)
                    }
                    .onDelete { indices in
                        let ordenados = pagos.sorted { $0.diasRestantes < $1.diasRestantes }
                        for i in indices {
                            Recordatorios.cancelar(ordenados[i])
                            contexto.delete(ordenados[i])
                        }
                    }
                } footer: {
                    if !pagos.isEmpty {
                        Text("Total al mes: \(total.formatted(.currency(code: "EUR")))")
                    }
                }
            }
            .overlay {
                if pagos.isEmpty {
                    ContentUnavailableView("Sin pagos",
                                           systemImage: "calendar.badge.clock",
                                           description: Text("Toca + para añadir tu primer pago mensual."))
                }
            }
            .navigationTitle("Pagos mensuales")
            .toolbar {
                Button { mostrandoNuevo = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $mostrandoNuevo) { NuevoPagoView() }
        }
    }
}

struct FilaPago: View {
    let pago: Pago

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(pago.nombre).font(.headline)
                Text(pago.importe.formatted(.currency(code: "EUR")))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(pago.diasRestantes == 0 ? "Hoy" : "\(pago.diasRestantes)")
                    .font(.title.bold())
                    .foregroundStyle(pago.diasRestantes <= 3 ? .red : .primary)
                if pago.diasRestantes != 0 {
                    Text(pago.diasRestantes == 1 ? "día" : "días")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Nuevo pago

struct NuevoPagoView: View {
    @Environment(\.modelContext) private var contexto
    @Environment(\.dismiss) private var cerrar

    @State private var nombre = ""
    @State private var importe = 1.0
    @State private var dia = 1

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
                Stepper("Día del mes: \(dia)", value: $dia, in: 1...28)
            }
            .navigationTitle("Nuevo pago")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let pago = Pago(nombre: nombre, importe: importe, diaDelMes: dia)
                        contexto.insert(pago)
                        Recordatorios.programar(pago)
                        cerrar()
                    }
                    .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

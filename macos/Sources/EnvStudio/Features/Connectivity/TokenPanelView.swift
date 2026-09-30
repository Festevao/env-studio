import EnvStudioConnectivity
import EnvStudioCore
import SwiftUI
import AppKit

struct TokenPanelView: View {
    @EnvironmentObject private var connectivity: ConnectivityStore
    @EnvironmentObject private var documentStore: DocumentStore
    let tunnel: TunnelDefinition
    @Environment(\.dismiss) private var dismiss

    private var session: RdsTokenSession? {
        connectivity.tokenSession(for: tunnel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Token RDS — \(tunnel.title)")
                .font(.title2)
            HStack {
                Button("Gerar token") {
                    Task { await connectivity.generateToken(for: tunnel) }
                }
                .disabled(connectivity.isBusy || !connectivity.isTunnelListening(for: tunnel))
                Button("Testar senha") {
                    Task { await connectivity.testPassword(for: tunnel) }
                }
                .disabled(testDisabled)
                Spacer()
                Button("Fechar") { dismiss() }
            }
            if let session {
                countdownView(session)
                Group {
                    Text("Senha (cliente visual)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Workbench, Beekeeper, DBeaver e outros clientes com tela. Não cole em .env nem na linha de comando.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(session.rawToken)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Group {
                    Text("Senha escapada (variável de ambiente)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(DatabaseURLBuilder.encodeURIComponent(session.rawToken))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Group {
                    Text("Linha .env")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(session.envVarName)=\"\(session.databaseURL)\"")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Copiar senha (cliente visual)") {
                        copy(session.rawToken)
                    }
                    Button("Copiar senha escapada") {
                        copy(DatabaseURLBuilder.encodeURIComponent(session.rawToken))
                    }
                    Button("Copiar URL") {
                        copy(session.databaseURL)
                    }
                    Button("Copiar linha .env") {
                        copy("\(session.envVarName)=\"\(session.databaseURL)\"")
                    }
                }
                HStack {
                    Button("Aplicar no .env") {
                        applyToDocument(session)
                    }
                    .disabled(documentStore.folderURL == nil)
                    Spacer()
                }
                passwordTestStatus
            } else {
                Text("Gere um token com o túnel aberto. Validade ~15 min (countdown local).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 760, height: 560)
    }

    private var testDisabled: Bool {
        guard let session else { return true }
        return session.isExpired || connectivity.isBusy
            || !connectivity.isTunnelListening(for: tunnel)
    }

    @ViewBuilder
    private var passwordTestStatus: some View {
        switch connectivity.passwordTest(for: tunnel) {
        case .none:
            EmptyView()
        case .success(let date):
            Text("Último teste: sucesso em \(formatted(date))")
                .font(.caption)
                .foregroundStyle(.green)
        case .failure(let message, let date):
            Text("Último teste: falhou em \(formatted(date)) — \(message)")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func countdownView(_ session: RdsTokenSession) -> some View {
        let remaining = session.remainingSeconds
        let label = session.isExpired
            ? "Expirado"
            : "Expira em \(remaining / 60):\(String(format: "%02d", remaining % 60))"
        return Text(label)
            .font(.headline)
            .foregroundStyle(session.isExpired ? .orange : .primary)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func applyToDocument(_ session: RdsTokenSession) {
        guard let stage = connectivity.selectedEnvironment.envStage else { return }
        documentStore.applyConnectionString(
            envVarName: session.envVarName,
            url: session.databaseURL,
            environment: stage
        )
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}

extension TunnelEnvironment {
    var envStage: EnvStage? {
        switch self {
        case .dev: return .dev
        case .hom: return .hom
        case .prod: return .prod
        }
    }
}

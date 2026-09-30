import EnvStudioConnectivity
import SwiftUI

struct EnvironmentConfigSheet: View {
    @EnvironmentObject private var connectivity: ConnectivityStore
    @Binding var isPresented: Bool
    @State private var draft: AwsEnvironmentConfig = AwsEnvironmentConfig(
        awsProfileName: "",
        region: "",
        ssmTargetInstanceId: ""
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configurar \(connectivity.selectedEnvironment.displayName)")
                .font(.title2)
            Text("Esta configuração é global e não depende da pasta do .env.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Salvo em: \(ConnectivityPersistence.storageLocationHint)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Form {
                TextField("Profile AWS", text: $draft.awsProfileName)
                TextField("Região", text: $draft.region)
                TextField("Instance ID (SSM target)", text: $draft.ssmTargetInstanceId)
                TextField("Usuário RDS IAM", text: $draft.rdsIamUsername)
                TextField("Caminho certificado RDS", text: $draft.rdsCaPath)
                Picker("Profile existente", selection: Binding(
                    get: { draft.awsProfileName },
                    set: { draft.awsProfileName = $0 }
                )) {
                    Text("—").tag("")
                    ForEach(connectivity.awsProfiles, id: \.self) { profile in
                        Text(profile).tag(profile)
                    }
                }
            }
            HStack {
                Button("Restaurar defaults") {
                    draft = ConnectivityDefaults.restoreEnvironment(connectivity.selectedEnvironment)
                }
                Spacer()
                Button("Cancelar") { isPresented = false }
                Button("Salvar") {
                    connectivity.updateEnvironmentConfig(draft)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
        .onAppear {
            draft = connectivity.currentEnvironmentConfig
                ?? ConnectivityDefaults.restoreEnvironment(connectivity.selectedEnvironment)
            connectivity.reloadProfiles()
        }
    }
}

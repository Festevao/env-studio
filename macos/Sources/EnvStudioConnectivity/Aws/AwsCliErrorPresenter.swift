import Foundation

public enum AwsCliErrorPresenter {
    public static func friendlyMessage(raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Comando AWS falhou sem detalhes."
        }
        if trimmed.contains("ForbiddenException"),
            trimmed.contains("GetRoleCredentials")
        {
            return """
            A AWS recusou a role do profile (GetRoleCredentials: No access).
            Isso é configuração/permissão na AWS, não do Mac.

            Confira em ~/.aws/config se sso_role_name bate com o permission set do portal
            (ex.: DeveloperAccess vs PowerUserAccess).

            1. Ajuste sso_role_name no profile ou peça o permission set correto no IAM Identity Center.
            2. aws sso login --profile <nome>
            3. Teste: aws sts get-caller-identity --profile <nome>

            Detalhe AWS: \(singleLine(trimmed))
            """
        }
        if trimmed.contains("ExpiredToken") || trimmed.contains("Token has expired") {
            return """
            Credencial AWS expirada. Faça «Login SSO» e tente novamente.

            Detalhe AWS: \(singleLine(trimmed))
            """
        }
        return trimmed
    }

    private static func singleLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }
}

public enum AwsCommandEnvironment {
    public static func merge(
        base: [String: String],
        profile: String,
        region: String
    ) -> [String: String] {
        var env = base
        let home = base["HOME"] ?? NSHomeDirectory()
        env["HOME"] = home
        env["AWS_PROFILE"] = profile
        env["AWS_DEFAULT_REGION"] = region
        env["AWS_REGION"] = region
        if env["AWS_CONFIG_FILE"] == nil {
            env["AWS_CONFIG_FILE"] = "\(home)/.aws/config"
        }
        if env["AWS_SHARED_CREDENTIALS_FILE"] == nil {
            env["AWS_SHARED_CREDENTIALS_FILE"] = "\(home)/.aws/credentials"
        }
        return env
    }

    public static func shellEscape(_ argument: String) -> String {
        "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func loginShellCommand(awsExecutable: String, arguments: [String]) -> String {
        let parts = ([awsExecutable] + arguments).map(shellEscape)
        return parts.joined(separator: " ")
    }
}

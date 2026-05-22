import SwiftUI

struct LoginView: View {
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 140)
                    .padding(.horizontal)

                Text("Iniciar sesión")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    usernameField

                    SecureField("Contraseña", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if isLoading { ProgressView().tint(.white) }
                        Text(isLoading ? "Ingresando..." : "Ingresar")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSubmit ? Color.accentColor : Color.gray)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!canSubmit || isLoading)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.vertical)
        }
    }

    private var usernameField: some View {
        let field = TextField("Correo", text: $username)
            .textContentType(.username)
            .autocorrectionDisabled()
            .padding()
            .background(Color.gray.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        #if os(iOS) || os(visionOS)
        return field
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
        #else
        return field
        #endif
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    private func submit() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.login(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password
            )
            guard let jwt = response.jwt, !jwt.isEmpty else {
                errorMessage = response.message ?? "Credenciales inválidas"
                return
            }
            AuthManager.shared.setSession(
                token: jwt,
                username: response.username,
                name: response.name,
                role: response.role
            )
        } catch let APIError.http(status, body) where status == 401 || status == 403 {
            errorMessage = body.isEmpty ? "Credenciales inválidas" : body
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    LoginView()
}

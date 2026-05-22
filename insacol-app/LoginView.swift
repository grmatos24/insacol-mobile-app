import SwiftUI

struct LoginView: View {
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.navy.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 120)
                    .padding(.horizontal)

                Text("Iniciar sesión")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))

                VStack(spacing: 12) {
                    usernameField
                    SecureField("Contraseña", text: $password)
                        .textContentType(.password)
                        .foregroundStyle(.white)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                }
                .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(Color(hex: "#FF453A"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if isLoading { ProgressView().tint(.black) }
                        Text(isLoading ? "Ingresando..." : "Ingresar")
                            .font(.headline)
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSubmit ? Theme.amberGradient : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canSubmit || isLoading)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.vertical)
        }
    }

    private var usernameField: some View {
        let field = TextField("Correo / Usuario", text: $username)
            .textContentType(.username)
            .autocorrectionDisabled()
            .foregroundStyle(.white)
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
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

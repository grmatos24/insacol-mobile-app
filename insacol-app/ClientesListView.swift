import SwiftUI

struct ClientesListView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Clientes", systemImage: "person.2")
                .navigationTitle("Clientes")
        }
    }
}

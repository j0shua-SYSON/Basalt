import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List(selection: $appModel.destination) {
            Section {
                Button(action: appModel.newConversation) {
                    Label("New conversation", systemImage: "square.and.pencil")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("new-conversation")
            }

            Section("Conversations") {
                ForEach(appModel.conversations) { conversation in
                    NavigationLink(value: AppDestination.conversation(conversation.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text(conversation.preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            appModel.deleteConversation(conversation)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            Section {
                NavigationLink(value: AppDestination.models) {
                    Label("Models", systemImage: "shippingbox")
                }
                .accessibilityIdentifier("models-navigation")

                NavigationLink(value: AppDestination.settings) {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("settings-navigation")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Basalt")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appModel.isImportSheetPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add model")
                .accessibilityIdentifier("sidebar-add-model")
            }
        }
    }
}

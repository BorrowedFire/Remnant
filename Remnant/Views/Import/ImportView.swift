import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var transactions: [ImportedTransaction] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingFilePicker = true
    @State private var showingReview = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Parsing file...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    VStack(spacing: Spacing.lg) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(Color.Theme.warning)
                        Text(error)
                            .font(.body)
                            .foregroundStyle(Color.Theme.textSecondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            errorMessage = nil
                            showingFilePicker = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(Spacing.xl)
                } else {
                    Color.clear
                }
            }
            .background(Color.Theme.background)
            .navigationTitle("Import Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .init(filenameExtension: "ofx")!, .init(filenameExtension: "qfx")!],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .sheet(isPresented: $showingReview) {
                ImportReviewView(transactions: $transactions)
            }
            .onChange(of: showingReview) { _, isShowing in
                if !isShowing && transactions.isEmpty {
                    dismiss()
                }
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isLoading = true
            errorMessage = nil

            Task {
                do {
                    guard url.startAccessingSecurityScopedResource() else {
                        throw ImportService.ImportError.parsingFailed("Cannot access this file.")
                    }
                    defer { url.stopAccessingSecurityScopedResource() }

                    let importService = ImportService()
                    var parsed = try importService.parseFile(at: url)

                    // Match against existing bills
                    let bills = (try? environment.billService.fetchAll()) ?? []
                    let matcher = TransactionMatcher()
                    parsed = matcher.match(transactions: parsed, against: bills)

                    transactions = parsed
                    isLoading = false
                    showingReview = true
                } catch {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }

        case .failure:
            dismiss()
        }
    }
}

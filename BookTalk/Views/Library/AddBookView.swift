import SwiftUI
import PhotosUI

struct AddBookView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""
    @State private var isbn = ""
    @State private var coverImage: UIImage?
    @State private var showingScanner = false
    @State private var showingImagePicker = false
    @State private var isLookingUp = false
    @State private var scannedISBN: String?
    @State private var selectedPhotoItem: PhotosPickerItem?

    var onSave: (Book) -> Void

    var body: some View {
        NavigationStack {
            Form {
                coverImageSection
                bookDetailsSection
                scannerSection
            }
            .navigationTitle("Add Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveBook()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView(scannedCode: $scannedISBN, isPresented: $showingScanner)
            }
            .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: scannedISBN) { newValue in
                if let code = newValue {
                    isbn = code
                    lookupISBN()
                }
            }
            .onChange(of: selectedPhotoItem) { newValue in
                Task {
                    if let data = try? await newValue?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            coverImage = image
                        }
                    }
                }
            }
        }
    }

    private var coverImageSection: some View {
        Section {
            HStack {
                Spacer()
                coverImageView
                    .onTapGesture {
                        showingImagePicker = true
                    }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var coverImageView: some View {
        if let image = coverImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(2/3, contentMode: .fill)
                .frame(width: 120, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 120, height: 180)
                .overlay {
                    VStack {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("Add Cover")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
        }
    }

    private var bookDetailsSection: some View {
        Section("Book Details") {
            TextField("Title", text: $title)
            TextField("Author", text: $author)
            TextField("ISBN (optional)", text: $isbn)
                .keyboardType(.numberPad)
        }
    }

    private var scannerSection: some View {
        Section {
            Button {
                showingScanner = true
            } label: {
                HStack {
                    Image(systemName: "barcode.viewfinder")
                    Text("Scan Barcode")
                }
            }

            if !isbn.isEmpty {
                Button {
                    lookupISBN()
                } label: {
                    HStack {
                        if isLookingUp {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Text(isLookingUp ? "Looking up..." : "Look Up ISBN")
                    }
                }
                .disabled(isLookingUp)
            }
        }
    }

    private func lookupISBN() {
        guard !isbn.isEmpty else { return }
        isLookingUp = true

        Task {
            if let metadata = await BookLookupService.shared.lookup(isbn: isbn) {
                await MainActor.run {
                    title = metadata.title
                    author = metadata.author ?? ""
                }

                if let coverURL = metadata.coverURL {
                    if let filename = await BookLookupService.shared.downloadCover(from: coverURL) {
                        let localURL = DatabaseManager.coversDirectory.appendingPathComponent(filename)
                        if let image = UIImage(contentsOfFile: localURL.path) {
                            await MainActor.run {
                                coverImage = image
                            }
                        }
                    }
                }
            }
            await MainActor.run {
                isLookingUp = false
            }
        }
    }

    private func saveBook() {
        var coverPath: String?

        // Save cover image if exists
        if let image = coverImage,
           let data = image.jpegData(compressionQuality: 0.8) {
            let filename = "\(UUID().uuidString).jpg"
            let url = DatabaseManager.coversDirectory.appendingPathComponent(filename)
            try? data.write(to: url)
            coverPath = filename
        }

        let book = Book(
            title: title,
            author: author.isEmpty ? nil : author,
            coverImagePath: coverPath,
            isbn: isbn.isEmpty ? nil : isbn
        )

        do {
            try book.save()
            onSave(book)
            dismiss()
        } catch {
            print("Failed to save book: \(error)")
        }
    }
}

import SwiftUI
import PhotosUI

struct AddBookView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""
    @State private var isbn = ""
    @State private var coverImage: UIImage?
    @State private var showingImagePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var onSave: (Book) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
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
                
                Section("Book Details") {
                    TextField("Title", text: $title)
                    TextField("Author (optional)", text: $author)
                    TextField("ISBN (optional)", text: $isbn)
                        .keyboardType(.numberPad)
                }
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
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhotoItem, matching: .images)
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
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
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
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .background(Circle().fill(.white))
                        .offset(x: 8, y: 8)
                }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 120, height: 180)
                .overlay {
                    VStack(spacing: 8) {
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
    
    private func saveBook() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        var book = Book(
            title: trimmedTitle,
            author: author.isEmpty ? nil : author,
            isbn: isbn.isEmpty ? nil : isbn
        )
        
        // Save cover image if present
        if let image = coverImage, let data = image.jpegData(compressionQuality: 0.8) {
            let filename = "\(book.id)_cover.jpg"
            let url = DatabaseManager.coversDirectory.appendingPathComponent(filename)
            do {
                try data.write(to: url)
                book.coverImagePath = filename
            } catch {
                errorMessage = "Failed to save cover image."
                showingError = true
                return
            }
        }
        
        do {
            try book.save()
            onSave(book)
            dismiss()
        } catch {
            errorMessage = "Failed to save book. Please try again."
            showingError = true
        }
    }
}

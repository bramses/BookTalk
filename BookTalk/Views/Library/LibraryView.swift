import SwiftUI

import SwiftUI

struct LibraryView: View {
    @State private var books: [Book] = []
    @State private var showingAddBook = false
    @State private var showingArchived = false
    @State private var showingAbout = false
    @State private var selectedBook: Book?
    @State private var bookToDelete: Book?
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var searchText = ""

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    private var filteredBooks: [Book] {
        if searchText.isEmpty {
            return books
        }
        let query = searchText.lowercased()
        return books.filter { book in
            book.title.lowercased().contains(query) ||
            (book.author?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if books.isEmpty {
                    emptyLibraryState
                } else if filteredBooks.isEmpty {
                    emptySearchState
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filteredBooks) { book in
                            NavigationLink(value: book) {
                                BookCoverView(book: book)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    archiveBook(book)
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                Button(role: .destructive) {
                                    bookToDelete = book
                                    showingDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search by title or author")
            .navigationDestination(for: Book.self) { book in
                BookDetailView(book: book)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button {
                            showingArchived = true
                        } label: {
                            Label("Archived Books", systemImage: "archivebox")
                        }

                        Divider()

                        Button {
                            showingAbout = true
                        } label: {
                            Label("About & How to Use", systemImage: "info.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddBook = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddBook) {
                AddBookView { newBook in
                    books.insert(newBook, at: 0)
                }
            }
            .sheet(isPresented: $showingArchived) {
                ArchivedBooksView { restoredBook in
                    loadBooks()
                }
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .confirmationDialog(
                "Delete Book?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let book = bookToDelete {
                        deleteBook(book)
                    }
                }
                Button("Cancel", role: .cancel) {
                    bookToDelete = nil
                }
            } message: {
                if let book = bookToDelete {
                    Text("This will permanently delete \"\(book.title)\" and all its annotations. This cannot be undone.")
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .onAppear {
                loadBooks()
            }
        }
    }

    private func loadBooks() {
        do {
            books = try Book.all(archived: false)
        } catch {
            errorMessage = "Failed to load your books. Please try again."
            showingError = true
        }
    }

    private func deleteBook(_ book: Book) {
        do {
            try book.delete()
            books.removeAll { $0.id == book.id }
            bookToDelete = nil
        } catch {
            errorMessage = "Failed to delete \"\(book.title)\". Please try again."
            showingError = true
        }
    }

    private func archiveBook(_ book: Book) {
        var mutableBook = book
        do {
            try mutableBook.toggleArchived()
            loadBooks()
        } catch {
            errorMessage = "Failed to archive \"\(book.title)\". Please try again."
            showingError = true
        }
    }
    
    // MARK: - Empty States
    
    private var emptyLibraryState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "books.vertical")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.blue)
                    .symbolRenderingMode(.hierarchical)
            }
            
            VStack(spacing: 8) {
                Text("No Books Yet")
                    .font(.title2.weight(.semibold))
                Text("Tap the + button to add your first book")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var emptySearchState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.orange)
                    .symbolRenderingMode(.hierarchical)
            }
            
            VStack(spacing: 8) {
                Text("No Results")
                    .font(.title2.weight(.semibold))
                Text("No books match \"\(searchText)\"")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct ArchivedBooksView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var archivedBooks: [Book] = []
    @State private var selectedBook: Book?
    @State private var bookToRestore: Book?
    @State private var bookToDelete: Book?
    @State private var showingRestoreConfirmation = false
    @State private var showingDeleteConfirmation = false
    var onRestore: (Book) -> Void

    var body: some View {
        NavigationStack {
            List {
                if archivedBooks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 50, weight: .light))
                            .foregroundColor(.secondary)
                            .symbolRenderingMode(.hierarchical)
                        Text("No Archived Books")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(archivedBooks) { book in
                        Button {
                            selectedBook = book
                        } label: {
                            HStack(spacing: 12) {
                                // Book cover thumbnail
                                if let coverURL = book.coverImageURL,
                                   let uiImage = UIImage(contentsOfFile: coverURL.path) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 44, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .shadow(color: .black.opacity(0.15), radius: 3, y: 2)
                                } else {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.gray.opacity(0.15))
                                        .frame(width: 44, height: 64)
                                        .overlay {
                                            Image(systemName: "book.closed.fill")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                                .symbolRenderingMode(.hierarchical)
                                        }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    if let author = book.author {
                                        Text(author)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color(.tertiaryLabel))
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                bookToRestore = book
                                showingRestoreConfirmation = true
                            } label: {
                                Label("Restore", systemImage: "arrow.uturn.backward")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                bookToDelete = book
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Archived")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadArchivedBooks()
            }
            .sheet(item: $selectedBook) { book in
                ArchivedBookDetailView(book: book, onRestore: {
                    bookToRestore = book
                    selectedBook = nil
                    showingRestoreConfirmation = true
                }, onDelete: {
                    bookToDelete = book
                    selectedBook = nil
                    showingDeleteConfirmation = true
                })
            }
            .confirmationDialog(
                "Restore Book?",
                isPresented: $showingRestoreConfirmation,
                titleVisibility: .visible
            ) {
                Button("Restore to Library") {
                    if let book = bookToRestore {
                        restoreBook(book)
                    }
                }
                Button("Cancel", role: .cancel) {
                    bookToRestore = nil
                }
            } message: {
                if let book = bookToRestore {
                    Text("Move \"\(book.title)\" back to your library?")
                }
            }
            .confirmationDialog(
                "Delete Book Permanently?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Permanently", role: .destructive) {
                    if let book = bookToDelete {
                        deleteBook(book)
                    }
                }
                Button("Cancel", role: .cancel) {
                    bookToDelete = nil
                }
            } message: {
                if let book = bookToDelete {
                    Text("This will permanently delete \"\(book.title)\" and all its annotations. This cannot be undone.")
                }
            }
        }
    }

    private func loadArchivedBooks() {
        do {
            archivedBooks = try Book.all(archived: true)
        } catch {
            print("Failed to load archived books: \(error)")
        }
    }

    private func restoreBook(_ book: Book) {
        var mutableBook = book
        do {
            try mutableBook.toggleArchived()
            onRestore(mutableBook)
            loadArchivedBooks()
            bookToRestore = nil
        } catch {
            print("Failed to restore book: \(error)")
        }
    }

    private func deleteBook(_ book: Book) {
        do {
            try book.delete()
            loadArchivedBooks()
            bookToDelete = nil
        } catch {
            print("Failed to delete book: \(error)")
        }
    }
}

// MARK: - Archived Book Detail View (Read-Only)

struct ArchivedBookDetailView: View {
    let book: Book
    var onRestore: () -> Void
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var annotations: [Annotation] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if annotations.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(annotations) { annotation in
                            AnnotationRow(
                                annotation: annotation,
                                audioPlayer: audioPlayer,
                                isHighlighted: false,
                                onDelete: {},
                                onUpdate: { _, _ in }
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onRestore()
                            }
                        } label: {
                            Label("Restore to Library", systemImage: "arrow.uturn.backward")
                        }
                        Button(role: .destructive) {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onDelete()
                            }
                        } label: {
                            Label("Delete Permanently", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                loadAnnotations()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "text.bubble")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            
            Text("No Annotations")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }

    private func loadAnnotations() {
        do {
            annotations = try Annotation.forBook(book.id)
        } catch {
            print("Failed to load annotations: \(error)")
        }
    }
}

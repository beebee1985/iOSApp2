import SwiftUI
import UIKit
import Foundation

struct ScavengerItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var clue: String
    var found: Bool
    var photoData: Data?

    init(id: UUID = UUID(), title: String, clue: String, found: Bool = false, photoData: Data? = nil) {
        self.id = id
        self.title = title
        self.clue = clue
        self.found = found
        self.photoData = photoData
    }

    var photo: UIImage? {
        guard let data = photoData else { return nil }
        return UIImage(data: data)
    }
}

final class ScavengerViewModel: ObservableObject {
    @Published var items: [ScavengerItem] = []
    @Published var isSubmitting = false
    @Published var lastSubmissionMessage: String?

    private let persistenceKey = "ScavengerHunt.Items.v1"

    init() {
        load()
        if items.isEmpty {
            seedItems()
            save()
        }
    }

    private func seedItems() {
        items = [
            ScavengerItem(title: "Red Coffee Mug", clue: "Found at Java House counter."),
            ScavengerItem(title: "Vintage Bookmark", clue: "Corner shelf at Book Nook."),
            ScavengerItem(title: "Movie Ticket Stub", clue: "Ask at the cinema box office."),
            ScavengerItem(title: "Restaurant Coaster", clue: "Table at The Diner."),
            ScavengerItem(title: "Green Plant Tag", clue: "Outside Florals & More."),
            ScavengerItem(title: "Yellow Button", clue: "At Tailor Tim's counter."),
            ScavengerItem(title: "Toy Car", clue: "Window display at Tiny Toys."),
            ScavengerItem(title: "Coffee Coupon", clue: "Café register at Brew & Co."),
            ScavengerItem(title: "Museum Postcard", clue: "Gift shop near the entrance."),
            ScavengerItem(title: "Old Film Poster", clue: "At Retro Reel Theater.")
        ]
    }

    func markFound(itemID: UUID, image: UIImage) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].found = true
        items[idx].photoData = image.jpegData(compressionQuality: 0.7)
        save()
    }

    func clearFound(itemID: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].found = false
        items[idx].photoData = nil
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let decoded = try? JSONDecoder().decode([ScavengerItem].self, from: data) {
            items = decoded
        }
    }

    func resetAll() {
        for i in items.indices {
            items[i].found = false
            items[i].photoData = nil
        }
        save()
    }

    var foundCount: Int { items.filter { $0.found }.count }

    var reward: (code: String, desc: String)? {
        if foundCount >= 10 {
            return ("DISCOUNT20+DRAW", "20% discount + entry to grand draw")
        } else if foundCount >= 7 {
            return ("DISCOUNT20", "20% discount")
        } else if foundCount >= 5 {
            return ("DISCOUNT10", "10% discount")
        } else {
            return nil
        }
    }

    func submitAllResults(completion: @escaping (Bool, String) -> Void) {
        guard foundCount == items.count else {
            completion(false, "You must find all items before submitting.")
            return
        }

        isSubmitting = true

        let payload: [String: Any] = [
            "foundCount": foundCount,
            "items": items.map { item in
                [
                    "title": item.title,
                    "photoBase64": item.photoData?.base64EncodedString() ?? ""
                ]
            }
        ]

        guard let url = URL(string: "https://httpbin.org/post") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: req) { _, _, err in
            DispatchQueue.main.async {
                self.isSubmitting = false
                if let e = err {
                    self.lastSubmissionMessage = "Failed: \(e.localizedDescription)"
                    completion(false, self.lastSubmissionMessage ?? "")
                } else {
                    self.lastSubmissionMessage = "Submission successful!"
                    completion(true, self.lastSubmissionMessage ?? "")
                }
            }
        }.resume()
    }
}

@main
struct ScavengerHuntApp: App {
    @StateObject private var vm = ScavengerViewModel()

    var body: some Scene {
        WindowGroup {
            MainListView()
                .environmentObject(vm)
        }
    }
}

struct MainListView: View {
    @EnvironmentObject private var vm: ScavengerViewModel
    @State private var pickerFor: UUID? = nil
    @State private var showRewardCard = false
    @State private var showSubmissionAlert = false
    @State private var showResetConfirm = false

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Text("Found: \(vm.foundCount)/\(vm.items.count)")
                        .font(.headline)
                    Spacer()
                    if let reward = vm.reward {
                        Button(action: { showRewardCard = true }) {
                            Label(reward.code, systemImage: "gift.fill")
                                .padding(8)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()

                List {
                    ForEach(vm.items) { item in
                        ScavengerRowView(
                            item: item,
                            onTakePhoto: { pickerFor = item.id },
                            onClearPhoto: { vm.clearFound(itemID: item.id) }
                        )
                    }
                }

                HStack(spacing: 12) {
                    Button("Reset", role: .destructive) {
                        showResetConfirm = true
                    }
                    .confirmationDialog("Reset all progress?", isPresented: $showResetConfirm) {
                        Button("Reset All", role: .destructive) { vm.resetAll() }
                        Button("Cancel", role: .cancel) {}
                    }

                    Button {
                        if vm.foundCount == vm.items.count {
                            vm.submitAllResults { _, _ in showSubmissionAlert = true }
                        } else {
                            vm.lastSubmissionMessage = "Find all items before submitting."
                            showSubmissionAlert = true
                        }
                    } label: {
                        if vm.isSubmitting {
                            ProgressView()
                        } else {
                            Text("Submit")
                        }
                    }
                    .disabled(vm.isSubmitting)
                }
                .padding()
            }
            .navigationTitle("Scavenger Hunt")
            .toolbar {
                NavigationLink(destination: HelpCardView()) {
                    Image(systemName: "questionmark.circle")
                }
            }
            // ✅ FIXED: using isPresented sheet binding (UUID not Identifiable)
            .sheet(isPresented: Binding(
                get: { pickerFor != nil },
                set: { if !$0 { pickerFor = nil } }
            )) {
                if let id = pickerFor {
                    PhotoPickerView { image in
                        if let img = image { vm.markFound(itemID: id, image: img) }
                        pickerFor = nil
                    }
                }
            }
            .sheet(isPresented: $showRewardCard) {
                if let reward = vm.reward {
                    RewardFlipCardView(code: reward.code, description: reward.desc)
                }
            }
            .alert(vm.lastSubmissionMessage ?? "", isPresented: $showSubmissionAlert) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

struct ScavengerRowView: View {
    let item: ScavengerItem
    let onTakePhoto: () -> Void
    let onClearPhoto: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.headline)
                Text(item.clue).font(.caption).foregroundColor(.secondary)
                if item.found {
                    Text("Found ✅").font(.caption2).foregroundColor(.green)
                }
            }
            Spacer()
            if let img = item.photo {
                NavigationLink(destination: PhotoDetailView(image: img, title: item.title, onClear: onClearPhoto)) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 70, height: 55)
                        .clipped()
                        .cornerRadius(6)
                }
            } else {
                Button(action: onTakePhoto) {
                    Label("Take", systemImage: "camera.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
    }
}

struct PhotoDetailView: View {
    let image: UIImage
    let title: String
    let onClear: () -> Void
    @State private var showConfirm = false

    var body: some View {
        VStack {
            Spacer()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding()
            Spacer()
            Button("Remove Photo", role: .destructive) { showConfirm = true }
                .confirmationDialog("Remove this photo?", isPresented: $showConfirm) {
                    Button("Remove", role: .destructive) { onClear() }
                    Button("Cancel", role: .cancel) {}
                }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PhotoPickerView: UIViewControllerRepresentable {
    var completion: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        #if targetEnvironment(simulator)
        picker.sourceType = .photoLibrary
        #else
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        #endif
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: PhotoPickerView
        init(_ parent: PhotoPickerView) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.completion(nil)
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            parent.completion(image)
        }
    }
}

struct HelpCardView: View {
    @State private var flipped = false
    var body: some View {
        VStack {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(flipped ? Color.blue : Color.gray)
                    .frame(width: 320, height: 220)
                    .overlay(
                        Group {
                            if flipped {
                                VStack {
                                    Text("How to Play").font(.title2).bold().foregroundColor(.white)
                                    Text("Find all items using the clues. Take photos and submit to earn rewards!")
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .padding()
                                }
                            } else {
                                Text("Tap to flip for instructions")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                    )
                    .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.6)) { flipped.toggle() }
                    }
            }
            Spacer()
        }
        .navigationTitle("Help")
    }
}

struct RewardFlipCardView: View {
    let code: String
    let description: String
    @State private var flipped = false

    var body: some View {
        VStack {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(flipped ? Color.green : Color.orange)
                    .frame(width: 340, height: 220)
                    .overlay(
                        Group {
                            if flipped {
                                VStack {
                                    Text("🎉 Congratulations!").font(.title2).bold().foregroundColor(.white)
                                    Text(code).font(.system(size: 30, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.top, 4)
                                    Text(description).font(.caption).foregroundColor(.white)
                                }.padding()
                            } else {
                                VStack {
                                    Image(systemName: "gift.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.white)
                                    Text("Tap to reveal reward")
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    )
                    .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                    .onTapGesture { withAnimation(.spring()) { flipped.toggle() } }
            }
            Spacer()
        }
        .padding()
    }
}

struct ScavengerHunt_Previews: PreviewProvider {
    static var previews: some View {
        MainListView().environmentObject(ScavengerViewModel())
    }
}
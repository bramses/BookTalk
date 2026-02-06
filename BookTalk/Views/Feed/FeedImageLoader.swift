import Foundation
import UIKit

final class FeedImageLoader {
    static let shared = FeedImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "dev.bramadams.BookTalk.FeedImageLoader", qos: .userInitiated)

    private init() {
        cache.countLimit = 200
    }

    func loadImage(path: String, completion: @escaping (UIImage?) -> Void) {
        if let cached = cache.object(forKey: path as NSString) {
            completion(cached)
            return
        }

        queue.async { [weak self] in
            let image = UIImage(contentsOfFile: path)
            if let image {
                self?.cache.setObject(image, forKey: path as NSString)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}

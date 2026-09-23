import Foundation
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?
    private var downloadTask: URLSessionDataTask?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        NSLog("[PushExt] ===== didReceive ENTRY =====")
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        let userInfo = request.content.userInfo
        logPayload(userInfo)

        guard let bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        attachImage(to: bestAttemptContent, userInfo: userInfo) { [weak self] finished in
            self?.finish(with: finished)
        }
    }

    private func finish(with content: UNNotificationContent) {
        NSLog("[PushExt] Delivering notification with %d attachment(s).", content.attachments.count)
        contentHandler?(content)
        contentHandler = nil
    }

    private func attachImage(
        to content: UNMutableNotificationContent,
        userInfo: [AnyHashable: Any],
        completion: @escaping (UNNotificationContent) -> Void
    ) {
        guard let imageAddress = imageAddress(from: userInfo) else {
            NSLog("[PushExt] No image URL in payload — delivering text-only notification.")
            completion(content)
            return
        }

        NSLog("[PushExt] Downloading image from %@", imageAddress.absoluteString)
        downloadAttachment(from: imageAddress) { attachment in
            if let attachment {
                content.attachments = [attachment]
                NSLog("[PushExt] Attachment added successfully.")
            } else {
                NSLog("[PushExt] Attachment download or creation failed.")
            }
            completion(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        NSLog("[PushExt] serviceExtensionTimeWillExpire — delivering notification without image.")
        downloadTask?.cancel()
        if let bestAttemptContent {
            finish(with: bestAttemptContent)
        }
    }

    private func logPayload(_ userInfo: [AnyHashable: Any]) {
        var safe: [String: Any] = [:]
        for (key, value) in userInfo {
            guard let stringKey = key as? String else { continue }
            safe[stringKey] = jsonSafeValue(value)
        }
        let aps = userInfo["aps"] as? [AnyHashable: Any]
        let mutableContentValue = aps?["mutable-content"]
        let hasMutableContent = mutableContentValue != nil
        let resolvedImage = imageAddress(from: userInfo)?.absoluteString ?? "<none>"
        let topLevelKeys = userInfo.keys.compactMap { $0 as? String }.sorted().joined(separator: ", ")

        NSLog("[PushExt] top-level keys: %@", topLevelKeys.isEmpty ? "<none>" : topLevelKeys)
        if hasMutableContent {
            NSLog("[PushExt] mutable-content: %@ (present)", String(describing: mutableContentValue!))
        } else {
            NSLog("[PushExt] mutable-content: MISSING — extension will not run on iOS")
        }
        NSLog("[PushExt] resolved image address: %@", resolvedImage)
        if JSONSerialization.isValidJSONObject(safe),
           let data = try? JSONSerialization.data(withJSONObject: safe, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            NSLog("[PushExt] Push payload JSON:\n%@", json)
        }
    }

    private func jsonSafeValue(_ value: Any) -> Any {
        if let dict = value as? [AnyHashable: Any] {
            var result: [String: Any] = [:]
            for (key, value) in dict {
                guard let stringKey = key as? String else { continue }
                result[stringKey] = jsonSafeValue(value)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { jsonSafeValue($0) }
        }
        if value is NSNull { return NSNull() }
        if value is NSNumber || value is String || value is Bool {
            return value
        }
        if JSONSerialization.isValidJSONObject([value]) {
            return value
        }
        return "\(value)"
    }

    private func imageAddress(from userInfo: [AnyHashable: Any]) -> URL? {
        let keys = [
            "image",
            "image_url",
            "imageUrl",
            "picture",
            "thumbnail",
            "media_url",
            "media-url",
            "banner",
            "banner_url",
            "bannerUrl",
            "img",
            "attachment-url",
            "attachment_url",
            "gcm.n.image",
            "gcm.notification.image",
            "google.c.a.c_image"
        ]

        for key in keys {
            if let address = validAddress(userInfo[key]) {
                return address
            }
        }

        if let fcmOptions = parsedDictionary(userInfo["fcm_options"]) {
            if let address = validAddress(fcmOptions["image"]) ?? validAddress(fcmOptions["imageUrl"]) {
                return address
            }
        }

        if let data = userInfo["data"] as? [AnyHashable: Any] {
            for key in keys {
                if let address = validAddress(data[key]) {
                    return address
                }
            }
        }

        return recursiveImageAddress(from: userInfo)
    }

    private func parsedDictionary(_ value: Any?) -> [AnyHashable: Any]? {
        if let dictionary = value as? [AnyHashable: Any] {
            return dictionary
        }
        if let jsonString = value as? String,
           let data = jsonString.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let dictionary = json as? [AnyHashable: Any] {
            return dictionary
        }
        return nil
    }

    private func recursiveImageAddress(from value: Any) -> URL? {
        if let dictionary = value as? [AnyHashable: Any] {
            for (key, nestedValue) in dictionary {
                if let key = key as? String,
                   isImageKey(key),
                   let address = validAddress(nestedValue) {
                    return address
                }
                if let address = recursiveImageAddress(from: nestedValue) {
                    return address
                }
            }
        }

        if let array = value as? [Any] {
            for item in array {
                if let address = recursiveImageAddress(from: item) {
                    return address
                }
            }
        }

        return nil
    }

    private func isImageKey(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        return lowercased.contains("image")
            || lowercased.contains("picture")
            || lowercased.contains("thumbnail")
            || lowercased.contains("banner")
            || lowercased.contains("media")
    }

    private func validAddress(_ value: Any?) -> URL? {
        guard let string = value as? String,
              !string.isEmpty,
              let address = URL(string: string),
              let scheme = address.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return address
    }

    private func downloadAttachment(from address: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        downloadAttachment(from: address, attempt: 1, maxAttempts: 3, completion: completion)
    }

    private func downloadAttachment(
        from address: URL,
        attempt: Int,
        maxAttempts: Int,
        completion: @escaping (UNNotificationAttachment?) -> Void
    ) {
        var request = URLRequest(url: address, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.timeoutInterval = 8
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/jpeg,image/png,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")

        NSLog("[PushExt] Download attempt %d/%d", attempt, maxAttempts)
        downloadTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else {
                completion(nil)
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

            if let error {
                NSLog("[PushExt] Download error (attempt %d): %@", attempt, error.localizedDescription)
            } else {
                NSLog("[PushExt] Download status: %d, bytes: %d (attempt %d)", statusCode, data?.count ?? 0, attempt)
            }

            if let data, !data.isEmpty, (200...299).contains(statusCode) {
                completion(self.attachment(from: data, response: response, sourceAddress: address))
                return
            }

            guard attempt < maxAttempts else {
                NSLog("[PushExt] All %d download attempts failed.", maxAttempts)
                completion(nil)
                return
            }

            let delay = 0.6 * Double(attempt)
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                self.downloadAttachment(from: address, attempt: attempt + 1, maxAttempts: maxAttempts, completion: completion)
            }
        }
        downloadTask?.resume()
    }

    private func attachment(from data: Data, response: URLResponse?, sourceAddress: URL) -> UNNotificationAttachment? {
        let fileExtension = resolvedFileExtension(response: response, sourceAddress: sourceAddress)
        let typeHint = typeHint(forExtension: fileExtension)

        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PushAttachments", isDirectory: true)
        let fileAddress = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileAddress, options: [.atomic])
            NSLog("[PushExt] Wrote %d bytes to %@ (type=%@)", data.count, fileAddress.lastPathComponent, typeHint)
            return try UNNotificationAttachment(
                identifier: "image",
                url: fileAddress,
                options: [UNNotificationAttachmentOptionsTypeHintKey: typeHint]
            )
        } catch {
            NSLog("[PushExt] Attachment creation failed: %@", error.localizedDescription)
            return nil
        }
    }

    private func resolvedFileExtension(response: URLResponse?, sourceAddress: URL) -> String {
        let pathExtension = sourceAddress.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "heic", "heif"].contains(pathExtension) {
            return pathExtension == "jpeg" ? "jpg" : pathExtension
        }

        switch response?.mimeType?.lowercased() {
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        case "image/heic", "image/heif":
            return "heic"
        default:
            return "jpg"
        }
    }

    private func typeHint(forExtension fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "png":
            return "public.png"
        case "gif":
            return "public.gif"
        case "heic", "heif":
            return "public.heic"
        default:
            return "public.jpeg"
        }
    }
}

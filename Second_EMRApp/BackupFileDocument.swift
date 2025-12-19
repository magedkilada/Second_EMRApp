import Foundation
import UniformTypeIdentifiers
import SwiftUI

// ✅ Custom file type
extension UTType {
    static let emrEncryptedBackup = UTType(exportedAs: "com.magedkilada.neuroemr.encrypted-backup")
}

// ✅ FileDocument used by fileExporter
struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.emrEncryptedBackup, .data] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

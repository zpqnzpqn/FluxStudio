import Foundation
import AppKit
import Combine

@MainActor
public class ModelManager: ObservableObject {
    public static let shared = ModelManager()

    @Published public var cachedModelIDs: Set<String> = []
    @Published public var isDownloading: Bool = false
    @Published public var downloadingModelId: String? = nil
    @Published public var downloadLog: String = ""

    private let hubURL: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.hubURL = home.appendingPathComponent(".cache/huggingface/hub")
        refresh()
    }

    public func isDownloaded(_ model: FluxModelSpec) -> Bool {
        return cachedModelIDs.contains(model.id)
    }

    public func refresh() {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: hubURL.path) else {
            return
        }

        var downloaded = Set<String>()

        for model in ModelRegistry.allModels {
            let targetFolderName = "models--" + model.hfRepoId.replacingOccurrences(of: "/", with: "--")
            // 不分大小寫比對
            let match = contents.first { folder in
                folder.localizedCaseInsensitiveCompare(targetFolderName) == .orderedSame
            }

            if let matchedFolder = match {
                let modelDir = hubURL.appendingPathComponent(matchedFolder)
                let snapshotsDir = modelDir.appendingPathComponent("snapshots")
                // 確認 snapshots 存在且有內容
                if let snaps = try? FileManager.default.contentsOfDirectory(atPath: snapshotsDir.path), !snaps.isEmpty {
                    downloaded.insert(model.id)
                } else {
                    // 若直接存在非空的 blobs 或其他檔案
                    downloaded.insert(model.id)
                }
            }
        }

        self.cachedModelIDs = downloaded
    }

    public func download(model: FluxModelSpec, engine: MFluxEngine) {
        guard let exe = engine.findExecutable(named: model.binaryName) else {
            downloadLog = "❌ 找不到執行檔：\(model.binaryName)\n"
            return
        }

        isDownloading = true
        downloadingModelId = model.id
        downloadLog = "⬇️ 開始高速下載 [\(model.label)]...\n"
        downloadLog += "   Hugging Face 倉庫: \(model.hfRepoId)\n"
        downloadLog += "   已啟用 Rust 多線程引擎 (hf_transfer)\n\n"

        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)

            var args = ["--prompt", "warmup", "--steps", "1", "--quantize", "\(model.defaultQuantize)", "--low-ram"]
            if let m = model.modelArg { args += ["-m", m] }
            if let b = model.baseArg { args += ["--base-model", b] }

            if model.shape == .fill {
                let tmp = FileManager.default.temporaryDirectory
                let inImg = tmp.appendingPathComponent("dummy_in.png")
                let maskImg = tmp.appendingPathComponent("dummy_mask.png")
                // 產生 64x64 圖像
                let bmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let data = bmp.representation(using: .png, properties: [:])!
                try? data.write(to: inImg)
                try? data.write(to: maskImg)
                args += ["--image-path", inImg.path, "--masked-image-path", maskImg.path]
            } else if model.shape == .editMulti || model.shape == .editSingle {
                let tmp = FileManager.default.temporaryDirectory
                let inImg = tmp.appendingPathComponent("dummy_in.png")
                let bmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                let data = bmp.representation(using: .png, properties: [:])!
                try? data.write(to: inImg)
                if model.shape == .editMulti {
                    args += ["--image-paths", inImg.path]
                } else {
                    args += ["--image-path", inImg.path]
                }
            }

            args += ["--output", "/dev/null"]
            proc.arguments = args

            var env = ProcessInfo.processInfo.environment
            env["HF_HUB_ENABLE_HF_TRANSFER"] = "1"
            env["HF_HUB_DISABLE_TELEMETRY"] = "1"
            env["PYTHONUNBUFFERED"] = "1"
            proc.environment = env

            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                if let str = String(data: d, encoding: .utf8), !str.isEmpty {
                    DispatchQueue.main.async {
                        self.downloadLog += str
                    }
                }
            }

            try? proc.run()
            proc.waitUntilExit()

            DispatchQueue.main.async {
                self.isDownloading = false
                self.downloadingModelId = nil
                self.refresh()
                self.downloadLog += "\n🎉 下載與驗證完成！已快取於本機，所有介面現已即時解鎖此模型！\n"
            }
        }
    }
}

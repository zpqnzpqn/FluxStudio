import Foundation
import Combine

public struct GenerationRequest: Sendable {
    public let model: FluxModelSpec
    public let prompt: String
    public let negativePrompt: String?
    public let width: Int
    public let height: Int
    public let steps: Int
    public let guidance: Double
    public let quantize: Int
    public let seed: Int?
    public let lowRam: Bool
    public let inputImagePath: String?
    public let maskImagePath: String?
    public let outputPath: String

    public init(
        model: FluxModelSpec,
        prompt: String,
        negativePrompt: String? = nil,
        width: Int = 1024,
        height: Int = 1024,
        steps: Int,
        guidance: Double,
        quantize: Int = 4,
        seed: Int? = nil,
        lowRam: Bool = true,
        inputImagePath: String? = nil,
        maskImagePath: String? = nil,
        outputPath: String
    ) {
        self.model = model
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.width = width
        self.height = height
        self.steps = steps
        self.guidance = guidance
        self.quantize = quantize
        self.seed = seed
        self.lowRam = lowRam
        self.inputImagePath = inputImagePath
        self.maskImagePath = maskImagePath
        self.outputPath = outputPath
    }
}

public enum ProcessStatus: Equatable {
    case idle
    case running(step: Int, total: Int, message: String)
    case completed(outputImageURL: URL)
    case failed(error: String)
}

@MainActor
public class MFluxEngine: ObservableObject {
    public static let shared = MFluxEngine()

    @Published public var status: ProcessStatus = .idle
    @Published public var consoleLogs: String = ""
    @Published public var activeProcess: Process?

    private var binPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
    }

    public init() {}

    public func findExecutable(named name: String) -> String? {
        let fileManager = FileManager.default
        for folder in binPaths {
            let fullPath = (folder as NSString).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }

    public func cancel() {
        if let proc = activeProcess, proc.isRunning {
            proc.terminate()
            status = .failed(error: "使用者手動中斷生成")
            activeProcess = nil
        }
    }

    public func generate(request: GenerationRequest) async {
        guard let executablePath = findExecutable(named: request.model.binaryName) else {
            self.status = .failed(error: "找不到執行檔：\(request.model.binaryName)。請確認已安裝 mflux。")
            return
        }

        self.status = .running(step: 0, total: request.steps, message: "準備啟動模型...")
        self.consoleLogs = ""

        var args: [String] = []

        if let m = request.model.modelArg {
            args += ["-m", m]
        }
        if let b = request.model.baseArg {
            args += ["--base-model", b]
        }

        args += ["--prompt", request.prompt]

        if request.model.supportsNegativePrompt, let neg = request.negativePrompt, !neg.trimmingCharacters(in: .whitespaces).isEmpty {
            args += ["--negative-prompt", neg]
        }

        args += ["--width", "\(request.width)"]
        args += ["--height", "\(request.height)"]
        args += ["--steps", "\(request.steps)"]
        args += ["--guidance", "\(request.guidance)"]

        if request.quantize > 0 {
            args += ["--quantize", "\(request.quantize)"]
        }
        if request.lowRam {
            args += ["--low-ram"]
        }

        if let seed = request.seed {
            args += ["--seed", "\(seed)"]
        }

        switch request.model.shape {
        case .fill:
            if let inImg = request.inputImagePath, let maskImg = request.maskImagePath {
                args += ["--image-path", inImg, "--masked-image-path", maskImg]
            }
        case .editMulti:
            if let inImg = request.inputImagePath {
                args += ["--image-paths", inImg]
            }
        case .editSingle:
            if let inImg = request.inputImagePath {
                args += ["--image-path", inImg]
            }
        case .editMask:
            if let inImg = request.inputImagePath {
                args += ["--image-path", inImg]
                if let maskImg = request.maskImagePath {
                    args += ["--mask-path", maskImg]
                }
            }
        case .txt2img:
            break
        }

        args += ["--output", request.outputPath]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = args

        // 配置環境變數（啟用 hf_transfer 高速下載，並鎖定無緩衝輸出）
        var env = ProcessInfo.processInfo.environment
        env["HF_HUB_ENABLE_HF_TRANSFER"] = "1"
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        env["PATH"] = (binPaths + [env["PATH"] ?? ""]).joined(separator: ":")
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        self.activeProcess = process

        let totalSteps = request.steps

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let outHandle = stdoutPipe.fileHandleForReading
                let errHandle = stderrPipe.fileHandleForReading

                outHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    DispatchQueue.main.async {
                        self.consoleLogs += text
                        self.parseProgress(from: text, totalSteps: totalSteps)
                    }
                }

                errHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    DispatchQueue.main.async {
                        self.consoleLogs += text
                        self.parseProgress(from: text, totalSteps: totalSteps)
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    outHandle.readabilityHandler = nil
                    errHandle.readabilityHandler = nil

                    DispatchQueue.main.async {
                        self.activeProcess = nil
                        if process.terminationStatus == 0 {
                            let outUrl = URL(fileURLWithPath: request.outputPath)
                            self.status = .completed(outputImageURL: outUrl)
                        } else {
                            self.status = .failed(error: "進程退出碼異常：\(process.terminationStatus)\n\(self.consoleLogs)")
                        }
                        continuation.resume()
                    }
                } catch {
                    outHandle.readabilityHandler = nil
                    errHandle.readabilityHandler = nil
                    DispatchQueue.main.async {
                        self.activeProcess = nil
                        self.status = .failed(error: "啟動失敗：\(error.localizedDescription)")
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func parseProgress(from text: String, totalSteps: Int) {
        // 解析常見進度格式，如 1/4 或 50%
        let pattern = #"(\d+)/(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            if let lastMatch = matches.last, lastMatch.numberOfRanges >= 3 {
                let currentStr = nsText.substring(with: lastMatch.range(at: 1))
                let totalStr = nsText.substring(with: lastMatch.range(at: 2))
                if let cur = Int(currentStr), let tot = Int(totalStr) {
                    self.status = .running(step: cur, total: tot, message: "生成中... \(cur)/\(tot)")
                    return
                }
            }
        }
    }
}

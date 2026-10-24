import Foundation
import Combine
import AppKit

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

public struct DetailedProgress: Equatable, Sendable {
    public let phaseTitle: String
    public let detailMessage: String
    public let currentStep: Int
    public let totalSteps: Int
    public let percent: Double
    public let speedText: String?

    public init(
        phaseTitle: String,
        detailMessage: String,
        currentStep: Int = 0,
        totalSteps: Int = 0,
        percent: Double = 0.0,
        speedText: String? = nil
    ) {
        self.phaseTitle = phaseTitle
        self.detailMessage = detailMessage
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.percent = percent
        self.speedText = speedText
    }
}

public enum ProcessStatus: Equatable, Sendable {
    case idle
    case running(progress: DetailedProgress)
    case completed(outputImageURL: URL, memoryUsed: String?)
    case failed(error: String)
}

@MainActor
public class MFluxEngine: ObservableObject {
    public static let shared = MFluxEngine()

    @Published public var status: ProcessStatus = .idle
    @Published public var consoleLogs: String = ""
    @Published public var activeProcess: Process?

    private var currentPhase: String = "📦 [1/4] 載入模型權重"
    private var detectedMemory: String? = nil

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

        self.currentPhase = "📦 [1/4] 載入模型權重與編譯著色器"
        self.detectedMemory = nil
        self.status = .running(progress: DetailedProgress(
            phaseTitle: self.currentPhase,
            detailMessage: "正在載入 \(request.model.label) 至 Apple Silicon 統一記憶體...",
            currentStep: 0,
            totalSteps: request.steps,
            percent: 0.05
        ))
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
                            self.status = .completed(outputImageURL: outUrl, memoryUsed: self.detectedMemory)
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
        // 1. 偵測 Peak Memory
        if text.contains("Peak MLX memory:") {
            let parts = text.components(separatedBy: "Peak MLX memory:")
            if parts.count >= 2 {
                let memStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").first ?? ""
                self.detectedMemory = memStr
            }
        }

        // 2. 階段判斷
        if text.contains("Loading") || text.contains("Initializing") || text.contains("Fetching") {
            self.currentPhase = "📦 [1/4] 載入模型權重與編譯著色器"
        } else if text.contains("Tokenizing") || text.contains("Encoding prompt") {
            self.currentPhase = "🧠 [2/4] 文字特徵編碼處理中"
        } else if text.contains("Decoding") || text.contains("Saving") || text.contains("Metadata embedded") {
            self.currentPhase = "🖼️ [4/4] VAE 影像解碼與寫入元數據"
        }

        // 3. 步數與速度進度解析 (tqdm 格式: 1/4 [00:15<00:45, 15.2s/it])
        let pattern = #"(\d+)/(\d+)(?:\s*\[([^\]]+)\])?"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            if let lastMatch = matches.last, lastMatch.numberOfRanges >= 3 {
                let currentStr = nsText.substring(with: lastMatch.range(at: 1))
                let totalStr = nsText.substring(with: lastMatch.range(at: 2))

                var speedInfo: String? = nil
                if lastMatch.numberOfRanges >= 4 && lastMatch.range(at: 3).location != NSNotFound {
                    speedInfo = nsText.substring(with: lastMatch.range(at: 3))
                }

                if let cur = Int(currentStr), let tot = Int(totalStr), tot > 0 {
                    let progressPercent = min(1.0, max(0.05, Double(cur) / Double(tot)))
                    var detail = "正在進行去噪迭代: 第 \(cur) / \(tot) 步 (\(Int(progressPercent * 100))%)"

                    if let sp = speedInfo {
                        detail += " · [\(sp)]"
                    }

                    self.currentPhase = "🎨 [3/4] 擴散去噪生成中"
                    self.status = .running(progress: DetailedProgress(
                        phaseTitle: self.currentPhase,
                        detailMessage: detail,
                        currentStep: cur,
                        totalSteps: tot,
                        percent: progressPercent,
                        speedText: speedInfo
                    ))
                    return
                }
            }
        }

        // 如果目前沒有步數匹配，但處於運行階段，更新階段標題
        if case .running(let old) = self.status {
            self.status = .running(progress: DetailedProgress(
                phaseTitle: self.currentPhase,
                detailMessage: old.detailMessage,
                currentStep: old.currentStep,
                totalSteps: old.totalSteps,
                percent: old.percent,
                speedText: old.speedText
            ))
        }
    }
}

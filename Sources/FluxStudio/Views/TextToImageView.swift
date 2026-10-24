import SwiftUI
import AppKit

public struct TextToImageView: View {
    @ObservedObject var engine = MFluxEngine.shared
    @ObservedObject var modelManager = ModelManager.shared

    @State private var prompt: String = "A serene Japanese zen garden with cherry blossoms, morning mist, 8k resolution, photorealistic"
    @State private var negativePrompt: String = "blurry, low quality, deformed, artifacts"
    @State private var selectedModel: FluxModelSpec = ModelRegistry.allModels.first { $0.id == "z-image-turbo" }!
    @State private var width: Int = 1024
    @State private var height: Int = 1024
    @State private var steps: Int = 9
    @State private var guidance: Double = 0.0
    @State private var quantize: Int = 4
    @State private var seed: String = ""
    @State private var lowRam: Bool = true

    @State private var generatedImage: NSImage?
    @State private var isCopiedNotification: Bool = false
    @State private var isSavedNotification: Bool = false

    public init() {}

    private var availableTxt2ImgModels: [FluxModelSpec] {
        ModelRegistry.allModels.filter { $0.shape == .txt2img }
    }

    public var body: some View {
        HSplitView {
            // 左側參數配置面板
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("📝 文字生成 (Text-to-Image)")
                        .font(.headline)

                    GroupBox(label: Text("模型選擇")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("模型", selection: $selectedModel) {
                                let ready = availableTxt2ImgModels.filter { modelManager.isDownloaded($0) }
                                if !ready.isEmpty {
                                    Section(header: Text("🟢 已就緒 (本機已下載)")) {
                                        ForEach(ready, id: \.self) { m in
                                            Text("✅ \(m.label) \(m.hardwareTag)").tag(m)
                                        }
                                    }
                                }

                                let m2NotDownloaded = availableTxt2ImgModels.filter { $0.isM2Recommended && !modelManager.isDownloaded($0) }
                                if !m2NotDownloaded.isEmpty {
                                    Section(header: Text("⭐ Apple M2 推薦 (首次需下載)")) {
                                        ForEach(m2NotDownloaded, id: \.self) { m in
                                            Text("⬇️ \(m.label) \(m.hardwareTag)").tag(m)
                                        }
                                    }
                                }

                                let others = availableTxt2ImgModels.filter { !$0.isM2Recommended && !modelManager.isDownloaded($0) }
                                if !others.isEmpty {
                                    Section(header: Text("💎 進階與大記憶體 (首次需下載)")) {
                                        ForEach(others, id: \.self) { m in
                                            Text("⬇️ \(m.label) \(m.hardwareTag)").tag(m)
                                        }
                                    }
                                }
                            }
                            .onChange(of: selectedModel) { _, newModel in
                                steps = newModel.defaultSteps
                                guidance = newModel.defaultGuidance
                                quantize = newModel.defaultQuantize
                            }

                            HStack {
                                if modelManager.isDownloaded(selectedModel) {
                                    Label("權重已在本地快取，可秒速載入", systemImage: "bolt.fill")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                } else {
                                    Label("尚未下載權重，點擊生成時將自動啟動高速下載", systemImage: "arrow.down.circle")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                Spacer()
                            }

                            Text(selectedModel.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(6)
                    }

                    GroupBox(label: Text("提示詞 (Prompt)")) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextEditor(text: $prompt)
                                .frame(height: 80)
                                .border(Color.gray.opacity(0.3))

                            if selectedModel.supportsNegativePrompt {
                                Text("反向提示詞 (Negative):")
                                    .font(.caption)
                                TextField("例如：blurry, distorted...", text: $negativePrompt)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(6)
                    }

                    GroupBox(label: Text("尺寸與推論設定")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("尺寸:")
                                Picker("", selection: Binding(
                                    get: { "\(width)x\(height)" },
                                    set: { val in
                                        let parts = val.split(separator: "x").compactMap { Int($0) }
                                        if parts.count == 2 {
                                            width = parts[0]
                                            height = parts[1]
                                        }
                                    }
                                )) {
                                    Text("1024 x 1024 (正方形 1:1)").tag("1024x1024")
                                    Text("1280 x 768 (橫式 16:9)").tag("1280x768")
                                    Text("768 x 1280 (直式 9:16)").tag("768x1280")
                                    Text("896 x 1152 (經典 3:4)").tag("896x1152")
                                }
                            }

                            HStack {
                                Text("步數 (Steps): \(steps)")
                                    .font(.caption)
                                Slider(value: Binding(
                                    get: { Double(steps) },
                                    set: { steps = Int($0) }
                                ), in: 1...50, step: 1)
                            }

                            if selectedModel.defaultGuidance > 0.0 {
                                HStack {
                                    Text("引導值 (Guidance): \(String(format: "%.1f", guidance))")
                                        .font(.caption)
                                    Slider(value: $guidance, in: 1.0...10.0, step: 0.5)
                                }
                            }

                            Picker("量化等級", selection: $quantize) {
                                Text("4-bit (推薦 M2 16GB)").tag(4)
                                Text("8-bit (高品質)").tag(8)
                                Text("6-bit").tag(6)
                                Text("3-bit (超省記憶體)").tag(3)
                                Text("Off (不量化 / 需32GB+)").tag(0)
                            }

                            Toggle("啟用低記憶體模式 (--low-ram)", isOn: $lowRam)
                                .font(.caption)

                            HStack {
                                Text("隨機種子 (Seed):")
                                    .font(.caption)
                                TextField("空白為隨機", text: $seed)
                                    .textFieldStyle(.roundedBorder)

                                Button(action: randomizeSeed) {
                                    Image(systemName: "dice")
                                }
                                .help("隨機生成一個種子數值")
                            }
                        }
                        .padding(6)
                    }

                    Spacer()

                    // 生成按鈕
                    Button(action: generateImage) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(modelManager.isDownloaded(selectedModel) ? "立即生成圖片" : "下載並生成圖片")
                        }
                        .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || engine.activeProcess != nil)

                    if engine.activeProcess != nil {
                        Button(action: { engine.cancel() }) {
                            Text("中斷生成")
                                .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if case .running(let step, let total, let msg) = engine.status {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: Double(step), total: Double(total))
                            Text(msg).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .frame(minWidth: 320, maxWidth: 380)

            // 右側影像預覽區
            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                if let img = generatedImage {
                    VStack(spacing: 14) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                            .shadow(radius: 6)
                            .padding()

                        HStack(spacing: 16) {
                            Button(action: saveImageToDisk) {
                                Label("儲存至圖片資料夾", systemImage: "square.and.arrow.down")
                            }

                            Button(action: copyImageToClipboard) {
                                Label("複製到剪貼簿", systemImage: "doc.on.doc")
                            }
                        }
                        .padding(.bottom, 12)

                        if isCopiedNotification {
                            Text("✅ 已複製到剪貼簿！")
                                .font(.caption)
                                .foregroundColor(.green)
                                .transition(.opacity)
                        }
                        if isSavedNotification {
                            Text("✅ 已儲存至 Pictures/FluxStudio/ 並在 Finder 顯示！")
                                .font(.caption)
                                .foregroundColor(.green)
                                .transition(.opacity)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("完成的圖片將在此高解析度呈現")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func randomizeSeed() {
        seed = "\(Int.random(in: 100000...99999999))"
    }

    private func generateImage() {
        let tempDir = FileManager.default.temporaryDirectory
        let outFile = tempDir.appendingPathComponent("flux_out_\(UUID().uuidString).png").path
        let s = Int(seed.trimmingCharacters(in: .whitespaces))

        let req = GenerationRequest(
            model: selectedModel,
            prompt: prompt,
            negativePrompt: negativePrompt,
            width: width,
            height: height,
            steps: steps,
            guidance: guidance,
            quantize: quantize,
            seed: s,
            lowRam: lowRam,
            outputPath: outFile
        )

        Task {
            await engine.generate(request: req)
            if case .completed(let url) = engine.status, let img = NSImage(contentsOf: url) {
                self.generatedImage = img
                modelManager.refresh() // 確保快取狀態同步更新
            }
        }
    }

    private func saveImageToDisk() {
        guard let img = generatedImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }

        let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        let fluxDir = picturesURL.appendingPathComponent("FluxStudio")
        try? FileManager.default.createDirectory(at: fluxDir, withIntermediateDirectories: true)

        let target = fluxDir.appendingPathComponent("Flux_\(Int(Date().timeIntervalSince1970)).png")
        try? pngData.write(to: target)
        NSWorkspace.shared.activateFileViewerSelecting([target])

        isSavedNotification = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            isSavedNotification = false
        }
    }

    private func copyImageToClipboard() {
        guard let img = generatedImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])

        isCopiedNotification = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopiedNotification = false
        }
    }
}

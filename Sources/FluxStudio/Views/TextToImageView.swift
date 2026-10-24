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
    @State private var currentSavedURL: URL?
    @State private var showConsoleLogs: Bool = false
    @State private var toastMessage: String? = nil

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

                    // 生成控制按鈕
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
                            Label("中斷生成", systemImage: "xmark.circle")
                                .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // 豐富的推論進度即時展示區
                    if case .running(let prog) = engine.status {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(prog.phaseTitle)
                                    .font(.subheadline)
                                    .bold()
                                    .foregroundColor(.accentColor)
                                Spacer()
                                Text("\(Int(prog.percent * 100))%")
                                    .font(.subheadline)
                                    .bold()
                                    .monospacedDigit()
                            }

                            ProgressView(value: prog.percent, total: 1.0)
                                .progressViewStyle(.linear)

                            Text(prog.detailMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button(action: { showConsoleLogs.toggle() }) {
                                HStack {
                                    Text(showConsoleLogs ? "隱藏推論日誌" : "查看即時推論日誌")
                                    Image(systemName: showConsoleLogs ? "chevron.up" : "chevron.down")
                                }
                                .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)

                            if showConsoleLogs {
                                ScrollView {
                                    Text(engine.consoleLogs)
                                        .font(.system(.caption2, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(height: 80)
                                .background(Color.black.opacity(0.85))
                                .foregroundColor(.green)
                                .cornerRadius(6)
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .frame(minWidth: 330, maxWidth: 390)

            // 右側影像預覽與檔案儲存管理區
            ZStack {
                Color(nsColor: .underPageBackgroundColor)

                if let img = generatedImage {
                    VStack(spacing: 12) {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                            .shadow(radius: 6)
                            .padding([.top, .horizontal])

                        // 檔案儲存資訊條與說明
                        if let url = currentSavedURL {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("檔案已自動存檔於：")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(url.path)
                                    .font(.caption)
                                    .monospaced()
                                    .bold()
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(.horizontal)
                        }

                        // 功能按鍵列：另存新檔、在Finder開啟、預覽、複製
                        HStack(spacing: 12) {
                            Button(action: saveAs) {
                                Label("另存新檔...", systemImage: "square.and.arrow.down.on.square")
                            }
                            .buttonStyle(.borderedProminent)
                            .help("自訂檔名與儲存目錄")

                            Button(action: openInFinder) {
                                Label("在 Finder 開啟", systemImage: "folder")
                            }
                            .help("打開所在圖片資料夾")

                            Button(action: openInPreview) {
                                Label("系統預覽", systemImage: "eye")
                            }
                            .help("在 macOS 預覽程式中打開檢視")

                            Button(action: copyImageToClipboard) {
                                Label("複製圖片", systemImage: "doc.on.doc")
                            }
                            .help("複製到剪貼簿以便直接貼上")
                        }
                        .padding(.bottom, 12)

                        if let toast = toastMessage {
                            Text(toast)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.75))
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .transition(.opacity)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.artframe")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("完成的圖片將在此高解析度呈現")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("預設自動儲存於系統圖片目錄：~/Pictures/FluxStudio/")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                }
            }
        }
    }

    private func randomizeSeed() {
        seed = "\(Int.random(in: 100000...99999999))"
    }

    private func generateImage() {
        let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
        let fluxDir = picturesURL.appendingPathComponent("FluxStudio")
        try? FileManager.default.createDirectory(at: fluxDir, withIntermediateDirectories: true)

        let targetFile = fluxDir.appendingPathComponent("Flux_\(selectedModel.id)_\(width)x\(height)_\(Int(Date().timeIntervalSince1970)).png")
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
            outputPath: targetFile.path
        )

        Task {
            await engine.generate(request: req)
            if case .completed(let url, let mem) = engine.status, let img = NSImage(contentsOf: url) {
                self.generatedImage = img
                self.currentSavedURL = url
                modelManager.refresh()

                var msg = "🎉 生成成功！檔案已儲存。"
                if let m = mem {
                    msg += " (Metal記憶體: \(m))"
                }
                showToast(msg)
            }
        }
    }

    private func saveAs() {
        guard let img = generatedImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "FluxStudio_\(selectedModel.id)_\(Int(Date().timeIntervalSince1970)).png"
        panel.title = "另存圖片新檔"
        panel.message = "請選擇儲存目的地與自訂檔案名稱"

        if panel.runModal() == .OK, let url = panel.url {
            try? pngData.write(to: url)
            self.currentSavedURL = url
            showToast("💾 另存新檔成功：\(url.lastPathComponent)")
        }
    }

    private func openInFinder() {
        if let url = currentSavedURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            let fluxDir = picturesURL.appendingPathComponent("FluxStudio")
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fluxDir.path)
        }
    }

    private func openInPreview() {
        guard let url = currentSavedURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyImageToClipboard() {
        guard let img = generatedImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        showToast("📋 已複製圖片到剪貼簿！")
    }

    private func showToast(_ text: String) {
        toastMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if toastMessage == text {
                toastMessage = nil
            }
        }
    }
}

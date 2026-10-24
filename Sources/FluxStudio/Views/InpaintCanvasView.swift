import SwiftUI
import AppKit

public struct DrawStroke: Identifiable, Equatable {
    public let id = UUID()
    public var points: [CGPoint]
    public var width: CGFloat
    public var isEraser: Bool

    public init(points: [CGPoint], width: CGFloat, isEraser: Bool = false) {
        self.points = points
        self.width = width
        self.isEraser = isEraser
    }
}

public enum CanvasTool: String, CaseIterable {
    case brush = "畫筆遮罩"
    case eraser = "橡皮擦"
    case eyedropper = "吸色筆"
    case pan = "移動畫布"
}

@MainActor
public class CanvasState: ObservableObject {
    @Published public var baseImage: NSImage?
    @Published public var strokes: [DrawStroke] = []
    @Published public var undoStack: [[DrawStroke]] = []
    @Published public var redoStack: [[DrawStroke]] = []

    @Published public var currentTool: CanvasTool = .brush
    @Published public var brushSize: CGFloat = 36.0
    @Published public var maskOpacity: Double = 0.65
    @Published public var pickedColor: NSColor = .white
    @Published public var pickedColorHex: String = "#FFFFFF"

    @Published public var scale: CGFloat = 1.0
    @Published public var offset: CGSize = .zero

    public init() {}

    public func pushState() {
        undoStack.append(strokes)
        redoStack.removeAll()
    }

    public func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = last
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
    }

    public func clearMask() {
        guard !strokes.isEmpty else { return }
        pushState()
        strokes.removeAll()
    }

    public func resetTransform() {
        scale = 1.0
        offset = .zero
    }

    public func pickColor(at point: CGPoint, in size: CGSize) {
        guard let img = baseImage,
              let cgImage = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let imgWidth = CGFloat(cgImage.width)
        let imgHeight = CGFloat(cgImage.height)

        let normX = max(0, min(1, point.x / size.width))
        let normY = max(0, min(1, point.y / size.height))

        let pixelX = Int(normX * imgWidth)
        let pixelY = Int(normY * imgHeight)

        guard let colorSpace = cgImage.colorSpace,
              let context = CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }

        context.draw(cgImage, in: CGRect(x: -pixelX, y: -pixelY, width: Int(imgWidth), height: Int(imgHeight)))
        if let data = context.data {
            let p = data.bindMemory(to: UInt8.self, capacity: 4)
            let r = CGFloat(p[0]) / 255.0
            let g = CGFloat(p[1]) / 255.0
            let b = CGFloat(p[2]) / 255.0
            let a = CGFloat(p[3]) / 255.0
            let col = NSColor(red: r, green: g, blue: b, alpha: a)
            self.pickedColor = col
            self.pickedColorHex = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        }
    }

    public func exportMaskImage(size: CGSize) -> NSImage? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep = rep else { return nil }

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = ctx

        // 背景全黑
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()

        // 白色遮罩
        for stroke in strokes {
            let path = NSBezierPath()
            guard let first = stroke.points.first else { continue }
            path.move(to: NSPoint(x: first.x, y: size.height - first.y))
            for pt in stroke.points.dropFirst() {
                path.line(to: NSPoint(x: pt.x, y: size.height - pt.y))
            }
            path.lineWidth = stroke.width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            if stroke.isEraser {
                NSColor.black.setStroke()
            } else {
                NSColor.white.setStroke()
            }
            path.stroke()
        }

        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: size)
        result.addRepresentation(rep)
        return result
    }
}

public struct InpaintCanvasView: View {
    @ObservedObject var state: CanvasState
    @ObservedObject var engine = MFluxEngine.shared
    @ObservedObject var modelManager = ModelManager.shared

    @State private var prompt: String = "remove the object and fill smoothly with the background"
    @State private var selectedModel: FluxModelSpec = ModelRegistry.allModels.first { $0.id == "fill-dev" }!
    @State private var currentDrawingPoints: [CGPoint] = []
    @State private var isTargetedForDrop: Bool = false

    public init(state: CanvasState) {
        self.state = state
    }

    private var availableEditModels: [FluxModelSpec] {
        ModelRegistry.allModels.filter { $0.isEditOrInpaint }
    }

    public var body: some View {
        HSplitView {
            // 左側修圖設定面板
            VStack(alignment: .leading, spacing: 14) {
                Text("🎨 影像重繪 (Inpaint) 控制台")
                    .font(.headline)

                GroupBox(label: Text("底圖與工具箱")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Button(action: selectBaseImage) {
                                Label(state.baseImage == nil ? "載入原圖" : "更換底圖", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }

                            if state.baseImage != nil {
                                Button("重設視角", action: { state.resetTransform() })
                                    .help("將畫布平移與縮放復原")
                            }
                        }

                        Picker("工具", selection: $state.currentTool) {
                            ForEach(CanvasTool.allCases, id: \.self) { tool in
                                Text(tool.rawValue).tag(tool)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Text("筆刷大小: \(Int(state.brushSize))px")
                                .font(.caption)
                            Slider(value: $state.brushSize, in: 8...120)
                        }

                        HStack {
                            Text("遮罩透明度: \(Int(state.maskOpacity * 100))%")
                                .font(.caption)
                            Slider(value: $state.maskOpacity, in: 0.1...1.0)
                        }

                        // Undo / Redo 按鈕列
                        HStack(spacing: 8) {
                            Button(action: { state.undo() }) {
                                Label("復原", systemImage: "arrow.uturn.backward")
                            }
                            .disabled(state.undoStack.isEmpty)
                            .keyboardShortcut("z", modifiers: .command)

                            Button(action: { state.redo() }) {
                                Label("重做", systemImage: "arrow.uturn.forward")
                            }
                            .disabled(state.redoStack.isEmpty)
                            .keyboardShortcut("z", modifiers: [.command, .shift])

                            Spacer()

                            Button("清除遮罩", action: { state.clearMask() })
                                .disabled(state.strokes.isEmpty)
                        }

                        if state.currentTool == .eyedropper {
                            HStack {
                                Text("取色結果：")
                                    .font(.caption)
                                Circle()
                                    .fill(Color(state.pickedColor))
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                                Text(state.pickedColorHex)
                                    .font(.caption)
                                    .monospaced()
                                Spacer()
                                Button("複製HEX") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(state.pickedColorHex, forType: .string)
                                }
                                .font(.caption2)
                            }
                        }
                    }
                    .padding(6)
                }

                GroupBox(label: Text("修圖模型與指令")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("模型", selection: $selectedModel) {
                            let ready = availableEditModels.filter { modelManager.isDownloaded($0) }
                            if !ready.isEmpty {
                                Section(header: Text("🟢 已就緒 (本機已下載)")) {
                                    ForEach(ready, id: \.self) { m in
                                        Text("✅ \(m.label) \(m.hardwareTag)").tag(m)
                                    }
                                }
                            }

                            let notReady = availableEditModels.filter { !modelManager.isDownloaded($0) }
                            if !notReady.isEmpty {
                                Section(header: Text("⬇️ 尚未下載 (首次將自動下載)")) {
                                    ForEach(notReady, id: \.self) { m in
                                        Text("⬇️ \(m.label) \(m.hardwareTag)").tag(m)
                                    }
                                }
                            }
                        }

                        HStack {
                            if modelManager.isDownloaded(selectedModel) {
                                Label("模型已就緒", systemImage: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            } else {
                                Label("尚未下載模型權重，重繪時將自動下載", systemImage: "arrow.down.circle")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                        }

                        Text("修改要求 (Prompt):")
                            .font(.caption)
                        TextEditor(text: $prompt)
                            .frame(height: 70)
                            .border(Color.gray.opacity(0.3))
                    }
                    .padding(6)
                }

                Spacer()

                // 啟動重繪按鈕
                Button(action: startInpaint) {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text(modelManager.isDownloaded(selectedModel) ? "開始局部重繪 (Inpaint)" : "下載並局部重繪")
                    }
                    .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.baseImage == nil || engine.activeProcess != nil)

                if engine.activeProcess != nil {
                    Button(action: { engine.cancel() }) {
                        Text("中斷修圖")
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
            .frame(minWidth: 320, maxWidth: 380)
            .padding()

            // 右側畫布主視圖
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                if let img = state.baseImage {
                    GeometryReader { geo in
                        let canvasSize = calculateFittedSize(imageSize: img.size, containerSize: geo.size)

                        ZStack {
                            // 1. 底圖
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: canvasSize.width, height: canvasSize.height)

                            // 2. 遮罩繪製層
                            Canvas { context, size in
                                for stroke in state.strokes {
                                    var path = Path()
                                    guard let first = stroke.points.first else { continue }
                                    path.move(to: first)
                                    for pt in stroke.points.dropFirst() {
                                        path.addLine(to: pt)
                                    }
                                    let style = StrokeStyle(lineWidth: stroke.width, lineCap: .round, lineJoin: .round)
                                    if stroke.isEraser {
                                        context.stroke(path, with: .color(.black.opacity(0.8)), style: style)
                                    } else {
                                        context.stroke(path, with: .color(.white.opacity(state.maskOpacity)), style: style)
                                    }
                                }

                                if !currentDrawingPoints.isEmpty {
                                    var path = Path()
                                    path.move(to: currentDrawingPoints[0])
                                    for pt in currentDrawingPoints.dropFirst() {
                                        path.addLine(to: pt)
                                    }
                                    let style = StrokeStyle(lineWidth: state.brushSize, lineCap: .round, lineJoin: .round)
                                    let isEraser = state.currentTool == .eraser
                                    let color: Color = isEraser ? .black.opacity(0.8) : .white.opacity(state.maskOpacity)
                                    context.stroke(path, with: .color(color), style: style)
                                }
                            }
                            .frame(width: canvasSize.width, height: canvasSize.height)
                        }
                        .scaleEffect(state.scale)
                        .offset(state.offset)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    handleDragChanged(value: value, canvasSize: canvasSize)
                                }
                                .onEnded { value in
                                    handleDragEnded(value: value, canvasSize: canvasSize)
                                }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "plus.square.dashed")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("將圖片拖曳至此，或點選左側「載入原圖」")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isTargetedForDrop ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                    .onDrop(of: ["public.file-url"], isTargeted: $isTargetedForDrop) { providers in
                        handleDrop(providers: providers)
                    }
                }
            }
        }
    }

    private func calculateFittedSize(imageSize: CGSize, containerSize: CGSize) -> CGSize {
        let wRatio = containerSize.width / imageSize.width
        let hRatio = containerSize.height / imageSize.height
        let ratio = min(wRatio, hRatio) * 0.95
        return CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
    }

    private func handleDragChanged(value: DragGesture.Value, canvasSize: CGSize) {
        if state.currentTool == .pan {
            state.offset.width += value.translation.width * 0.1
            state.offset.height += value.translation.height * 0.1
            return
        }

        if state.currentTool == .eyedropper {
            state.pickColor(at: value.location, in: canvasSize)
            return
        }

        currentDrawingPoints.append(value.location)
    }

    private func handleDragEnded(value: DragGesture.Value, canvasSize: CGSize) {
        if state.currentTool == .eyedropper {
            state.pickColor(at: value.location, in: canvasSize)
            return
        }

        if !currentDrawingPoints.isEmpty {
            state.pushState()
            let newStroke = DrawStroke(
                points: currentDrawingPoints,
                width: state.brushSize,
                isEraser: state.currentTool == .eraser
            )
            state.strokes.append(newStroke)
            currentDrawingPoints.removeAll()
        }
    }

    private func selectBaseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            state.baseImage = img
            state.strokes.removeAll()
            state.undoStack.removeAll()
            state.redoStack.removeAll()
            state.resetTransform()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first else { return false }
        p.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  let img = NSImage(contentsOf: url) else { return }
            DispatchQueue.main.async {
                self.state.baseImage = img
                self.state.strokes.removeAll()
                self.state.undoStack.removeAll()
                self.state.redoStack.removeAll()
                self.state.resetTransform()
            }
        }
        return true
    }

    private func startInpaint() {
        guard let base = state.baseImage else { return }
        let tempDir = FileManager.default.temporaryDirectory
        let baseFile = tempDir.appendingPathComponent("input_\(UUID().uuidString).png")
        let maskFile = tempDir.appendingPathComponent("mask_\(UUID().uuidString).png")
        let outFile = tempDir.appendingPathComponent("out_\(UUID().uuidString).png")

        // 儲存 baseImage
        if let tiff = base.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: baseFile)
        }

        // 儲存 maskImage
        if let maskImg = state.exportMaskImage(size: base.size),
           let tiff = maskImg.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: maskFile)
        }

        let req = GenerationRequest(
            model: selectedModel,
            prompt: prompt,
            steps: selectedModel.defaultSteps,
            guidance: selectedModel.defaultGuidance,
            quantize: selectedModel.defaultQuantize,
            lowRam: true,
            inputImagePath: baseFile.path,
            maskImagePath: maskFile.path,
            outputPath: outFile.path
        )

        Task {
            await engine.generate(request: req)
            if case .completed(let url) = engine.status, let newImg = NSImage(contentsOf: url) {
                state.baseImage = newImg
                state.strokes.removeAll()
                modelManager.refresh() // 同步更新快取狀態
            }
        }
    }
}

import Foundation

public enum GenerationShape: String, Codable, CaseIterable, Sendable {
    case txt2img = "txt2img"
    case editMulti = "edit_multi"
    case editSingle = "edit_single"
    case editMask = "edit_mask"
    case fill = "fill"
}

public struct FluxModelSpec: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let label: String
    public let binaryName: String
    public let modelArg: String?
    public let baseArg: String?
    public let hfRepoId: String
    public let shape: GenerationShape
    public let defaultSteps: Int
    public let defaultGuidance: Double
    public let defaultQuantize: Int
    public let supportsNegativePrompt: Bool
    public let isM2Recommended: Bool
    public let hardwareTag: String
    public let description: String

    public init(
        id: String,
        label: String,
        binaryName: String,
        modelArg: String? = nil,
        baseArg: String? = nil,
        hfRepoId: String,
        shape: GenerationShape,
        defaultSteps: Int,
        defaultGuidance: Double,
        defaultQuantize: Int = 4,
        supportsNegativePrompt: Bool = true,
        isM2Recommended: Bool,
        hardwareTag: String,
        description: String
    ) {
        self.id = id
        self.label = label
        self.binaryName = binaryName
        self.modelArg = modelArg
        self.baseArg = baseArg
        self.hfRepoId = hfRepoId
        self.shape = shape
        self.defaultSteps = defaultSteps
        self.defaultGuidance = defaultGuidance
        self.defaultQuantize = defaultQuantize
        self.supportsNegativePrompt = supportsNegativePrompt
        self.isM2Recommended = isM2Recommended
        self.hardwareTag = hardwareTag
        self.description = description
    }

    public var isEditOrInpaint: Bool {
        return shape == .fill || shape == .editMulti || shape == .editSingle || shape == .editMask
    }
}

public struct ModelRegistry {
    public static let allModels: [FluxModelSpec] = [
        // MARK: - M2 推薦首選 (生圖)
        FluxModelSpec(
            id: "z-image-turbo",
            label: "Z-Image Turbo",
            binaryName: "mflux-generate-z-image-turbo",
            hfRepoId: "Tongyi-MAI/Z-Image-Turbo",
            shape: .txt2img,
            defaultSteps: 9,
            defaultGuidance: 0.0,
            defaultQuantize: 4,
            isM2Recommended: true,
            hardwareTag: "⚡ [M2 首選 · 9步極速]",
            description: "6B DMD蒸餾模型，生圖質量高且寫實，16GB M2 僅需 ~3.5GB 記憶體"
        ),
        FluxModelSpec(
            id: "klein-4b",
            label: "FLUX.2 Klein-4B",
            binaryName: "mflux-generate-flux2",
            modelArg: "flux2-klein-4b",
            baseArg: "flux2-klein-4b",
            hfRepoId: "black-forest-labs/FLUX.2-klein-4B",
            shape: .txt2img,
            defaultSteps: 4,
            defaultGuidance: 1.0,
            defaultQuantize: 4,
            supportsNegativePrompt: false,
            isM2Recommended: true,
            hardwareTag: "⚡ [M2 首選 · 4步極速]",
            description: "4步蒸餾極速模型，構圖優異，實測 16GB M2 峰值記憶體僅 10GB"
        ),
        FluxModelSpec(
            id: "lens-turbo",
            label: "Lens (3.8B Turbo)",
            binaryName: "mflux-generate-lens",
            hfRepoId: "Comfy-Org/Lens",
            shape: .txt2img,
            defaultSteps: 4,
            defaultGuidance: 1.0,
            defaultQuantize: 4,
            isM2Recommended: true,
            hardwareTag: "⚡ [M2 推薦 · 輕量雙流]",
            description: "微軟雙流 MMDiT 架構，輕巧省記憶體，提示詞理解精確"
        ),
        FluxModelSpec(
            id: "boogu-turbo",
            label: "Boogu (10B Turbo 中英雙語)",
            binaryName: "mflux-generate-boogu",
            hfRepoId: "Boogu/Boogu-Image-0.1-Turbo",
            shape: .txt2img,
            defaultSteps: 4,
            defaultGuidance: 1.0,
            defaultQuantize: 4,
            isM2Recommended: true,
            hardwareTag: "🔤 [M2 推薦 · 雙語文字]",
            description: "DMD蒸餾4步模型，中英文字渲染能力極強，適合海報與文字排版"
        ),

        // MARK: - M2 推薦 (修圖 & Inpaint)
        FluxModelSpec(
            id: "fill-dev",
            label: "FLUX.1 Fill (局部重繪)",
            binaryName: "mflux-generate-fill",
            modelArg: "dev",
            baseArg: "dev",
            hfRepoId: "black-forest-labs/FLUX.1-Fill-dev",
            shape: .fill,
            defaultSteps: 20,
            defaultGuidance: 30.0,
            defaultQuantize: 4,
            isM2Recommended: true,
            hardwareTag: "🎨 [M2 推薦 · 修圖專用]",
            description: "專業局部填補模型，可依遮罩無縫修復與替換畫布指定區域"
        ),
        FluxModelSpec(
            id: "klein-4b-edit",
            label: "FLUX.2 Klein-4B Edit (圖片編輯)",
            binaryName: "mflux-generate-flux2-edit",
            modelArg: "flux2-klein-4b",
            baseArg: "flux2-klein-4b",
            hfRepoId: "black-forest-labs/FLUX.2-klein-4B",
            shape: .editMulti,
            defaultSteps: 4,
            defaultGuidance: 1.0,
            defaultQuantize: 4,
            supportsNegativePrompt: false,
            isM2Recommended: true,
            hardwareTag: "🎨 [M2 推薦 · 4步修圖]",
            description: "使用自然語言指令對原圖進行全域或指定風格修改"
        ),
        FluxModelSpec(
            id: "qwen-edit",
            label: "Qwen-Image-Edit (語意編輯)",
            binaryName: "mflux-generate-qwen-edit",
            hfRepoId: "Qwen/Qwen-Image-Edit-2509",
            shape: .editMulti,
            defaultSteps: 20,
            defaultGuidance: 4.0,
            defaultQuantize: 4,
            isM2Recommended: false,
            hardwareTag: "🎨 [修圖 · 阿里通義]",
            description: "阿里強大影像修圖模型，精通物件新增、移除與風格替換"
        ),
        FluxModelSpec(
            id: "kontext",
            label: "FLUX.1 Kontext (風格編輯)",
            binaryName: "mflux-generate-kontext",
            hfRepoId: "black-forest-labs/FLUX.1-Kontext-dev",
            shape: .editSingle,
            defaultSteps: 28,
            defaultGuidance: 2.5,
            defaultQuantize: 4,
            isM2Recommended: false,
            hardwareTag: "🎨 [修圖 · BFL官方]",
            description: "Black Forest Labs 出品的官方原創影像編輯模型"
        ),
        FluxModelSpec(
            id: "fibo-edit",
            label: "Bria FIBO Edit (遮罩修圖)",
            binaryName: "mflux-generate-fibo-edit",
            modelArg: "fibo-edit",
            baseArg: "fibo-edit",
            hfRepoId: "briaai/Fibo-Edit",
            shape: .editMask,
            defaultSteps: 20,
            defaultGuidance: 3.5,
            defaultQuantize: 4,
            isM2Recommended: false,
            hardwareTag: "🎨 [修圖 · 遮罩指令]",
            description: "支援自然語言與遮罩雙重控制的影像精確修飾"
        ),

        // MARK: - 進階與大記憶體機型模型 (32GB ~ 128GB)
        FluxModelSpec(
            id: "flux3-klein",
            label: "FLUX.3 Image Klein",
            binaryName: "mflux-generate-flux3",
            hfRepoId: "black-forest-labs/flux-3-image-klein",
            shape: .txt2img,
            defaultSteps: 16,
            defaultGuidance: 3.5,
            defaultQuantize: 4,
            isM2Recommended: false,
            hardwareTag: "💎 [進階 · 建議 32GB+]",
            description: "支援多參考圖引導與邊界框佈局，文字渲染強烈"
        ),
        FluxModelSpec(
            id: "krea2",
            label: "Krea 2 (12B Turbo)",
            binaryName: "mflux-generate-krea2",
            hfRepoId: "krea/Krea-2-Turbo",
            shape: .txt2img,
            defaultSteps: 4,
            defaultGuidance: 1.0,
            defaultQuantize: 4,
            isM2Recommended: false,
            hardwareTag: "💎 [進階 · 建議 32GB+]",
            description: "12B 大型藝術模型，支援多種藝術流派與高品質探索"
        ),
        FluxModelSpec(
            id: "flux-schnell",
            label: "FLUX.1 Schnell",
            binaryName: "mflux-generate",
            modelArg: "schnell",
            baseArg: "schnell",
            hfRepoId: "black-forest-labs/FLUX.1-schnell",
            shape: .txt2img,
            defaultSteps: 4,
            defaultGuidance: 0.0,
            defaultQuantize: 4,
            isM2Recommended: false,
            hardwareTag: "💎 [進階 · 建議 32GB+]",
            description: "官方經典4步開源基石模型"
        ),
        FluxModelSpec(
            id: "flux-dev",
            label: "FLUX.1 Dev",
            binaryName: "mflux-generate",
            modelArg: "dev",
            baseArg: "dev",
            hfRepoId: "black-forest-labs/FLUX.1-dev",
            shape: .txt2img,
            defaultSteps: 20,
            defaultGuidance: 3.5,
            defaultQuantize: 4,
            isM2Recommended: false,
            hardwareTag: "🚀 [高階 · 建議 32~64GB]",
            description: "經典 12B 原創非商業高品質生圖標竿"
        ),
        FluxModelSpec(
            id: "qwen-2.1",
            label: "Qwen Image 2.1 (Turbo)",
            binaryName: "mflux-generate-qwen-2.1",
            hfRepoId: "Qwen/Qwen-Image-2.1-Turbo",
            shape: .txt2img,
            defaultSteps: 8,
            defaultGuidance: 1.0,
            defaultQuantize: 4,
            isM2Recommended: false,
            hardwareTag: "🚀 [高階 · 建議 32GB+]",
            description: "單流區塊因果 DiT，搭載 Qwen3-VL 視覺語言編碼器"
        ),
        FluxModelSpec(
            id: "qwen-20b",
            label: "Qwen Image (20B)",
            binaryName: "mflux-generate-qwen",
            hfRepoId: "Qwen/Qwen-Image-2512",
            shape: .txt2img,
            defaultSteps: 20,
            defaultGuidance: 4.0,
            defaultQuantize: 4,
            isM2Recommended: false,
            hardwareTag: "🔥 [旗艦 · 建議 64~128GB]",
            description: "20B 龐大模型，世界常識極豐富，需充足統一記憶體"
        ),
        FluxModelSpec(
            id: "ideogram4",
            label: "Ideogram 4",
            binaryName: "mflux-generate-ideogram4",
            hfRepoId: "ideogram-ai/ideogram-4-fp8",
            shape: .txt2img,
            defaultSteps: 20,
            defaultGuidance: 3.5,
            defaultQuantize: 4,
            isM2Recommended: false,
            hardwareTag: "💎 [進階 · 建議 32GB+]",
            description: "專注於標籤佈局與精緻字體設計"
        )
    ]
}

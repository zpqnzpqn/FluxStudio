import SwiftUI
import AppKit

public struct ModelHubView: View {
    @ObservedObject var engine = MFluxEngine.shared
    @ObservedObject var modelManager = ModelManager.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("📦 模型倉庫與高速下載管理")
                        .font(.title2)
                        .bold()
                    Text("整合 Rust 多線程引擎 (hf_transfer)，下載完成後會即時同步解鎖至「文字生成」與「修圖」介面。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { modelManager.refresh() }) {
                    Label("重新整理快取", systemImage: "arrow.clockwise")
                }
            }
            .padding([.top, .horizontal])

            Divider()

            List {
                Section(header: Text("⭐ Apple M2 推薦模型（低記憶體 / 4-bit 量化秒產）").font(.headline)) {
                    ForEach(ModelRegistry.allModels.filter { $0.isM2Recommended }, id: \.self) { model in
                        modelRow(for: model)
                    }
                }

                Section(header: Text("🎨 專用修圖與局部重繪模型 (Inpaint & Edit)").font(.headline)) {
                    ForEach(ModelRegistry.allModels.filter { $0.isEditOrInpaint && !$0.isM2Recommended }, id: \.self) { model in
                        modelRow(for: model)
                    }
                }

                Section(header: Text("💎 進階與大記憶體機型模型（32GB~128GB）").font(.headline)) {
                    ForEach(ModelRegistry.allModels.filter { !$0.isM2Recommended && !$0.isEditOrInpaint }, id: \.self) { model in
                        modelRow(for: model)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            if !modelManager.downloadLog.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("下載進度日誌:")
                            .font(.caption)
                            .bold()
                        if modelManager.isDownloading {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }
                    ScrollView {
                        Text(modelManager.downloadLog)
                            .font(.system(.caption2, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 100)
                    .background(Color.black.opacity(0.85))
                    .foregroundColor(.green)
                    .cornerRadius(6)
                }
                .padding([.horizontal, .bottom])
            }
        }
        .onAppear {
            modelManager.refresh()
        }
    }

    private func modelRow(for model: FluxModelSpec) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.label)
                        .font(.body)
                        .bold()
                    Text(model.hardwareTag)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(model.isM2Recommended ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                        .cornerRadius(4)
                }
                Text("Hugging Face: \(model.hfRepoId) · \(model.description)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            let isDownloaded = modelManager.isDownloaded(model)
            let isCurrentDownloading = modelManager.downloadingModelId == model.id

            if isCurrentDownloading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("下載中...")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            } else if isDownloaded {
                Label("已就緒 (已下載)", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                    .bold()
            } else {
                Button(action: {
                    modelManager.download(model: model, engine: engine)
                }) {
                    Label("高速預載", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .disabled(modelManager.isDownloading)
            }
        }
        .padding(.vertical, 4)
    }
}

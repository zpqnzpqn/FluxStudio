#!/bin/bash
# FluxStudio 高速模型下載腳本 (已整合 Rust hf_transfer 多線程下載引擎)
set -euo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_HUB_DISABLE_TELEMETRY=1
export PYTHONUNBUFFERED=1

echo "=========================================================="
echo "   🚀 FluxStudio 高速模型下載器 (Apple Silicon MLX)     "
echo "   已自動啟用 hf_transfer 多線程並行加速下載              "
echo "=========================================================="
echo ""
echo "1) [M2 推薦] Z-Image Turbo (6B · 9步秒產，寫實度極高)"
echo "2) [M2 推薦] FLUX.2 Klein-4B (4B · 4步極速生圖/修圖)"
echo "3) [M2 推薦] FLUX.1 Fill (12B · 專業局部重繪修圖核心)"
echo "4) [M2 推薦] Lens (3.8B · 微軟雙流 MMDiT 極速輕量)"
echo "5) [M2 推薦] Boogu (10B · 4步中英雙語文字渲染)"
echo "6) [熱門修圖] Qwen-Image-Edit (阿里通義 語意級修圖)"
echo "7) [進階 32GB+] FLUX.3 Klein (多圖參考與精準佈局)"
echo "8) [進階 32GB+] Krea 2 (12B Turbo 藝術創作)"
echo "9) 一鍵下載所有 M2 推薦模型 (項目 1, 2, 3, 4, 5)"
echo "q) 退出"
echo ""
read -rp "請輸入欲下載的項目編號 [1-9]: " choice

case "$choice" in
  1)
    echo "⬇️ 正在下載 Z-Image Turbo..."
    mflux-generate-z-image-turbo --prompt "warmup" --steps 1 --quantize 4 --low-ram --output /dev/null
    ;;
  2)
    echo "⬇️ 正在下載 FLUX.2 Klein-4B..."
    mflux-generate-flux2 --model flux2-klein-4b --prompt "warmup" --steps 1 --quantize 4 --low-ram --output /dev/null
    ;;
  3)
    echo "⬇️ 正在下載 FLUX.1 Fill..."
    TMP_DIR="$(mktemp -d)"
    python3 -c "from PIL import Image; Image.new('RGB', (64,64)).save('$TMP_DIR/in.png'); Image.new('RGB', (64,64), 'white').save('$TMP_DIR/m.png')"
    mflux-generate-fill --prompt "warmup" --image-path "$TMP_DIR/in.png" --masked-image-path "$TMP_DIR/m.png" --steps 1 --quantize 4 --low-ram --output /dev/null
    rm -rf "$TMP_DIR"
    ;;
  4)
    echo "⬇️ 正在下載 Lens..."
    mflux-generate-lens --prompt "warmup" --steps 1 --quantize 4 --low-ram --output /dev/null
    ;;
  5)
    echo "⬇️ 正在下載 Boogu..."
    mflux-generate-boogu --prompt "warmup" --steps 1 --quantize 4 --low-ram --output /dev/null
    ;;
  6)
    echo "⬇️ 正在下載 Qwen-Image-Edit..."
    TMP_DIR="$(mktemp -d)"
    python3 -c "from PIL import Image; Image.new('RGB', (64,64)).save('$TMP_DIR/in.png')"
    mflux-generate-qwen-edit --prompt "warmup" --image-paths "$TMP_DIR/in.png" --steps 1 --quantize 4 --low-ram --output /dev/null
    rm -rf "$TMP_DIR"
    ;;
  7)
    echo "⬇️ 正在下載 FLUX.3 Klein..."
    mflux-generate-flux3 --prompt "warmup" --steps 1 --quantize 4 --low-ram --output /dev/null
    ;;
  8)
    echo "⬇️ 正在下載 Krea 2..."
    mflux-generate-krea2 --prompt "warmup" --steps 1 --quantize 4 --low-ram --output /dev/null
    ;;
  9)
    echo "⬇️ 開始批次下載所有 M2 推薦模型..."
    mflux-generate-z-image-turbo --prompt "warmup" --steps 1 --quantize 4 --low-ram --output /dev/null
    mflux-generate-flux2 --model flux2-klein-4b --prompt "warmup" --steps 1 --quantize 4 --low-ram --output /dev/null
    TMP_DIR="$(mktemp -d)"
    python3 -c "from PIL import Image; Image.new('RGB', (64,64)).save('$TMP_DIR/in.png'); Image.new('RGB', (64,64), 'white').save('$TMP_DIR/m.png')"
    mflux-generate-fill --prompt "warmup" --image-path "$TMP_DIR/in.png" --masked-image-path "$TMP_DIR/m.png" --steps 1 --quantize 4 --low-ram --output /dev/null
    rm -rf "$TMP_DIR"
    mflux-generate-lens --prompt "warmup" --steps 1 --quantize 4 --low-ram --output /dev/null
    mflux-generate-boogu --prompt "warmup" --steps 1 --quantize 4 --low-ram --output /dev/null
    ;;
  [qQ])
    echo "已退出。"
    exit 0
    ;;
  *)
    echo "無效輸入。"
    exit 1
    ;;
esac

echo ""
echo "🎉 模型權重下載/驗證完成！已快取於 ~/.cache/huggingface/hub/"

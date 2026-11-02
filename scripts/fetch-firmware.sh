#!/usr/bin/env bash
# Fetch stock DSL-N55U firmware images (+ optional GPL tarball) from ASUS's CDN.
#   scripts/fetch-firmware.sh          # firmware images only (~55 MB)
#   scripts/fetch-firmware.sh --gpl    # also the 585 MB GPL source
# Each file lands in its own directory under firmware/dl/ (untrusted input).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DL=$ROOT/firmware/dl
C=https://dlcdnets.asus.com/pub/ASUS/wireless

FILES=(
  DSL-N55U/FW_DSL_N55U_90043803925.zip            # A, 9.0.0.4.380_3925 beta (final)
  DSL-N55U/FW_DSL_N55U-30043762736_Annex_A.zip    # A, 3.0.0.4.376_2736
  DSL-N55U/Rescue_DSL_N55U_30043762736.zip        # A, rescue image
  DSL-N55U_B1/FW_DSL_N55U_B_90043803925.zip       # B, 9.0.0.4.380_3925 beta (final)
  DSL-N55U_B1/FW_DSL-N55U_B-30043762736_Annex_B.zip
  DSL-N55U_B1/Rescue_DSL_N55U-B_30043762736.zip
  DSL-N55U_B1/Rescue_DSL_N55U_3004374159_Annex_B.zip
)
[[ ${1:-} == --gpl ]] && FILES+=(DSL-N55U/GPL_DSL_N55U_30043762736.zip)

for f in "${FILES[@]}"; do
  name=$(basename "$f" .zip)
  mkdir -p "$DL/$name"
  [[ -s $DL/$name/$name.zip ]] && { echo "have $name"; continue; }
  echo "get  $name"
  curl -fL --retry 3 -C - -o "$DL/$name/$name.zip" "$C/$f"
done
(cd "$DL" && sha256sum */*.zip > SHA256SUMS)

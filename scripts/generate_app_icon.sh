#!/bin/bash
# Generate macOS App Icon set from minimal premium SVG template
set -e

SVG_TEMP_FILE="/tmp/new_logo.svg"
ASSET_DIR="/Users/rohan/repos/diffuse/diffuse/Assets.xcassets/AppIcon.appiconset"

echo "Creating minimal premium SVG logo..."
cat << 'EOF' > "$SVG_TEMP_FILE"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <!-- Background Gradient -->
    <linearGradient id="bg-grad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#141824"/>
      <stop offset="100%" stop-color="#070a10"/>
    </linearGradient>

    <!-- Border Glow/Highlight Gradient -->
    <linearGradient id="border-grad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.12"/>
      <stop offset="100%" stop-color="#00f5f5" stop-opacity="0.02"/>
    </linearGradient>

    <!-- Logo Gradient -->
    <linearGradient id="logo-grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#00f5f5"/>
      <stop offset="100%" stop-color="#009cff"/>
    </linearGradient>

    <!-- Shadow for the main icon container (macOS standard) -->
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="16" stdDeviation="24" flood-color="#000000" flood-opacity="0.55"/>
      <feDropShadow dx="0" dy="4" stdDeviation="8" flood-color="#000000" flood-opacity="0.30"/>
    </filter>

    <!-- Clean, subtle logo glow -->
    <filter id="logo-glow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="0" stdDeviation="12" flood-color="#00f5f5" flood-opacity="0.25"/>
    </filter>
  </defs>

  <!-- Background Canvas (Transparent) -->
  <!-- Main Rounded Rectangle macOS Icon Container -->
  <rect x="100" y="100" width="824" height="824" rx="182" ry="182" fill="url(#bg-grad)" filter="url(#shadow)"/>
  
  <!-- Subtle top-down bevel stroke -->
  <rect x="100.75" y="100.75" width="822.5" height="822.5" rx="181.25" ry="181.25" fill="none" stroke="url(#border-grad)" stroke-width="1.5"/>

  <!-- Logo Group -->
  <g filter="url(#logo-glow)">
    <path fill="url(#logo-grad)" fill-rule="evenodd" d="M4.0 4.0 L645.0 4.0 L820.0 165.0 L156.0 882.0 L4.0 881.0 Z M830.0 260.0 L1028.0 260.0 L1028.0 816.0 L1016.0 830.0 L793.0 1068.0 L81.0 1068.0 Z M76.0 75.0 L75.0 811.0 L127.0 811.0 L186.0 748.0 L187.0 180.0 L545.0 179.0 L596.0 226.0 L548.0 280.0 L515.0 250.0 L257.0 250.0 L258.0 669.0 L720.0 169.0 L616.0 75.0 Z M861.0 330.0 L846.0 345.0 L846.0 755.0 L840.0 762.0 L716.0 893.0 L401.0 891.0 L465.0 822.0 L687.0 822.0 L774.0 730.0 L774.0 423.0 L241.0 997.0 L763.0 997.0 L946.0 802.0 L957.0 789.0 L956.0 331.0 Z" transform="translate(296.12, 287.04) scale(0.42)"/>
  </g>
</svg>
EOF

echo "Generating PNG sizes using rsvg-convert..."
rsvg-convert -w 16 -h 16 "$SVG_TEMP_FILE" -o "$ASSET_DIR/app-icon-16.png"
rsvg-convert -w 32 -h 32 "$SVG_TEMP_FILE" -o "$ASSET_DIR/app-icon-16@2x.png"
rsvg-convert -w 32 -h 32 "$SVG_TEMP_FILE" -o "$ASSET_DIR/app-icon-32.png"
rsvg-convert -w 64 -h 64 "$SVG_TEMP_FILE" -o "$ASSET_DIR/app-icon-32@2x.png"
rsvg-convert -w 128 -h 128 "$SVG_TEMP_FILE" -o "$ASSET_DIR/app-icon-128.png"
rsvg-convert -w 256 -h 256 "$SVG_TEMP_FILE" -o "$ASSET_DIR/app-icon-128@2x.png"
rsvg-convert -w 256 -h 256 "$SVG_TEMP_FILE" -o "$ASSET_DIR/app-icon-256.png"
rsvg-convert -w 512 -h 512 "$SVG_TEMP_FILE" -o "$ASSET_DIR/app-icon-256@2x.png"
rsvg-convert -w 512 -h 512 "$SVG_TEMP_FILE" -o "$ASSET_DIR/app-icon-512.png"
rsvg-convert -w 1024 -h 1024 "$SVG_TEMP_FILE" -o "$ASSET_DIR/app-icon-512@2x.png"

rm "$SVG_TEMP_FILE"
echo "App icon generation completed successfully!"

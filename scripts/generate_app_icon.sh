#!/bin/bash
# Generate macOS App Icon set from minimal premium SVG template
set -e

SVG_TEMP_FILE="/tmp/new_logo.svg"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ASSET_DIR="$REPO_ROOT/Chobi/Assets.xcassets/AppIcon.appiconset"

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
  <g filter="url(#logo-glow)" transform="translate(92, 172) scale(0.41)">
    <g transform="translate(0.000000,2048.000000) scale(0.100000,-0.100000)" fill="url(#logo-grad)" stroke="none">
      <path d="M7003 17498 c-140 -144 -443 -460 -993 -1038 -217 -228 -453 -476 -525 -550 -114 -118 -322 -338 -483 -511 l-52 -56 0 -3080 0 -3080 333 -320 c522 -502 829 -793 837 -793 6 0 118 129 432 499 26 31 94 110 151 176 57 66 152 179 212 250 60 72 132 157 161 190 142 164 362 425 388 459 16 22 48 60 70 86 23 26 88 102 146 170 58 67 166 194 240 280 74 86 180 210 235 275 55 65 189 222 298 349 109 127 357 418 550 646 194 228 408 480 477 559 69 79 166 192 215 251 50 59 239 279 420 490 182 211 413 480 513 599 101 119 272 319 380 445 109 126 224 261 257 301 33 40 129 152 214 251 85 98 188 219 230 268 42 49 96 113 121 141 25 29 91 105 147 171 55 65 175 205 265 310 89 105 222 260 293 344 72 85 150 177 175 205 44 51 117 136 260 305 137 162 276 324 380 444 58 67 128 148 155 181 28 33 113 132 190 221 330 380 575 669 575 678 0 3 -1608 6 -3573 6 l-3573 0 -121 -122z m6041 -460 c-5 -7 -130 -155 -278 -328 -357 -415 -982 -1145 -1026 -1196 -19 -23 -84 -98 -144 -168 l-108 -126 -1708 0 -1707 0 -139 -147 c-76 -82 -189 -200 -249 -263 -61 -63 -181 -190 -268 -281 l-157 -166 0 -2050 0 -2051 -226 -263 c-124 -145 -256 -300 -293 -344 -38 -44 -178 -209 -312 -367 -134 -157 -266 -314 -293 -347 -27 -34 -52 -61 -57 -59 -4 2 -132 122 -283 267 l-276 264 0 2862 0 2861 31 30 c39 36 743 772 899 939 63 68 210 223 325 346 116 122 289 307 385 410 l175 188 2858 0 c2284 1 2857 -2 2851 -11z m-2056 -2405 c-8 -10 -71 -83 -139 -163 -69 -80 -152 -177 -185 -216 -32 -39 -140 -164 -239 -279 -99 -115 -209 -243 -245 -285 -36 -43 -103 -122 -150 -176 -47 -55 -218 -254 -380 -444 -162 -190 -365 -426 -450 -526 -85 -99 -186 -218 -225 -264 -161 -192 -231 -274 -377 -444 -84 -98 -169 -198 -188 -221 -67 -81 -507 -590 -553 -640 l-46 -50 -1 1605 0 1606 243 256 242 257 1354 0 c1289 1 1353 0 1339 -16z M14665 16268 c-15 -18 -96 -109 -180 -203 -84 -93 -234 -262 -335 -375 -100 -113 -251 -281 -335 -375 -84 -93 -215 -240 -292 -326 -76 -86 -230 -259 -343 -385 -113 -126 -241 -269 -285 -319 -80 -91 -158 -179 -476 -534 -339 -379 -648 -725 -854 -956 -94 -105 -244 -274 -335 -375 -91 -101 -190 -211 -220 -245 -30 -34 -181 -204 -335 -376 -155 -173 -368 -413 -475 -534 -107 -120 -276 -309 -375 -420 -99 -110 -275 -306 -390 -435 -115 -129 -288 -323 -385 -430 -97 -107 -270 -301 -385 -430 -115 -129 -290 -325 -390 -434 -219 -243 -334 -372 -810 -906 -203 -228 -430 -483 -505 -566 -324 -360 -461 -513 -516 -576 -33 -36 -108 -121 -167 -187 l-108 -121 3607 0 3607 0 67 68 c36 37 178 186 315 332 137 146 299 317 360 380 60 63 205 216 321 340 116 124 352 376 525 560 173 184 370 394 437 465 l122 130 0 973 0 972 -1067 -1 -1068 -1 -275 -285 c-151 -156 -291 -301 -310 -322 -19 -20 -147 -152 -284 -294 -137 -141 -264 -277 -284 -302 l-35 -45 -1315 0 -1315 0 34 39 c19 22 113 127 210 233 168 185 272 302 369 413 25 28 101 114 170 191 69 77 253 284 410 460 276 310 644 720 975 1089 89 99 378 424 643 723 l482 542 1330 0 1330 0 0 1032 0 1031 -412 408 c-227 225 -416 409 -420 409 -3 0 -18 -15 -33 -32z m178 -896 l117 -117 -2 -635 -3 -635 -782 -3 c-431 -2 -783 -1 -783 2 0 7 147 177 334 387 70 79 193 216 271 304 79 88 202 228 275 310 73 83 165 186 204 230 39 44 110 124 156 178 46 53 87 97 90 97 3 0 58 -53 123 -118z m117 -5228 c0 -145 -3 -264 -6 -264 -3 0 -49 40 -102 88 -54 48 -140 123 -192 166 -52 43 -143 122 -201 175 l-106 96 296 5 c163 3 299 4 304 2 4 -2 7 -122 7 -268z m-1344 158 c66 -59 354 -312 548 -481 99 -86 225 -197 280 -246 56 -50 162 -142 236 -206 74 -64 153 -135 174 -157 l39 -41 -155 -163 c-85 -90 -195 -206 -244 -258 -48 -52 -260 -275 -469 -495 -208 -220 -456 -481 -549 -580 -94 -99 -207 -219 -253 -267 l-83 -88 -2850 0 c-1567 0 -2850 4 -2850 8 0 5 30 42 66 83 37 41 115 128 174 194 59 66 174 194 255 285 376 422 724 810 824 920 42 47 132 147 199 223 l123 137 1672 0 1673 0 60 63 c406 418 1011 1050 1035 1081 27 35 46 32 95 -12z"/>
    </g>
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

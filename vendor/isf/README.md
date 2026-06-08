# Vendored: interactive-shader-format (ISF.js)

MIT-licensed ISF WebGL renderer by msfeldstein (npm `interactive-shader-format`, v2.8.1).

To re-bundle after `npm install interactive-shader-format`:

    npx esbuild isf-entry.js --bundle --format=iife \
      --outfile=../../App/ShadertoyISF/Resources/isf.bundle.js

The committed bundle lives at `App/ShadertoyISF/Resources/isf.bundle.js`; the upstream
license at `App/ShadertoyISF/Resources/isf.LICENSE.txt`. `node_modules/` is gitignored.

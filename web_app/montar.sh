#!/bin/bash
# Monta o webapp em web_app/dist (o que vai para o link). Gerado — não editar dist à mão.
#   dist/index.html            página (pagina.html + logica.js + app.js inline)
#   dist/ocr_worker.js         worker do isolamento de dígitos
#   dist/prumo_ocr.js          lib/digitos.dart compilado com dart2js
#   dist/tesseract-*.js, eng.traineddata   motor e dados do Tesseract.js 5.1.1 (a biblioteca vem do jsDelivr)
set -euo pipefail
cd "$(dirname "$0")/.."
D=web_app/dist
V="${XDG_CACHE_HOME:-$HOME/.cache}/prumo-web-vendor"
rm -rf "$D" && mkdir -p "$D" "$V"

# 1. pipeline do app → JS
dart compile js -O2 --no-source-maps -o "$D/prumo_ocr.js" web_app/src/prumo_ocr.dart >/dev/null
rm -f "$D/prumo_ocr.js.deps" "$D/prumo_ocr.js.map"

# 2. Tesseract (cache local; baixa do npm só na primeira vez)
if [ ! -f "$V/ok-5.1.1" ]; then
  (cd "$V" && rm -rf p && mkdir p && cd p \
    && npm pack --silent tesseract.js@5.1.1 tesseract.js-core@5.1.1 @tesseract.js-data/eng@1.0.0 >/dev/null \
    && for f in *.tgz; do mkdir -p "${f%.tgz}" && tar xzf "$f" -C "${f%.tgz}"; done)
  touch "$V/ok-5.1.1"
fi
cp "$V/p/tesseract.js-5.1.1/package/dist/worker.min.js" "$D/tesseract-worker.min.js"
cp "$V/p/tesseract.js-core-5.1.1/package/tesseract-core-simd-lstm.wasm.js" "$D/"
cp "$V/p/tesseract.js-core-5.1.1/package/tesseract-core-lstm.wasm.js" "$D/"
gunzip -c "$V/p/tesseract.js-data-eng-1.0.0/package/4.0.0_best_int/eng.traineddata.gz" > "$D/eng.traineddata"

# 3. página: logica.js e app.js entram inline (o link não carrega script próprio por <script src>)
python3 - "$D/index.html" <<'EOF'
import sys
p = open('web_app/pagina.html', encoding='utf-8').read()
for marca, arq in (('/*LOGICA*/', 'web_app/logica.js'), ('/*SEMENTES*/', 'web_app/sementes.js'), ('/*APP*/', 'web_app/app.js')):
    assert marca in p, marca
    p = p.replace(marca, open(arq, encoding='utf-8').read())
open(sys.argv[1], 'w', encoding='utf-8').write(p)
EOF
cp web_app/ocr_worker.js "$D/"
find "$D" -name '.DS_Store' -delete
echo "MONTADO $D ($(du -sh "$D" | cut -f1))"

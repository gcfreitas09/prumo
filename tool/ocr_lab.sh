#!/bin/zsh
# Roda o caminho de OCR de produção com o ML Kit real no iPhone, sobre os prints
# de test/fixtures (variações de escala, luz, desfoque e giro), e mostra o placar.
# Uso: tool/ocr_lab.sh [UDID]   (iPhone conectado, desbloqueado, modo desenvolvedor)
set -e
cd "$(dirname "$0")/.."
DEV=${1:-00008130-000A5C110C32001C}
APP=br.com.leituras.leiturasPredio
cp pubspec.yaml /tmp/pubspec.prumo.bak
trap 'cp /tmp/pubspec.prumo.bak pubspec.yaml' EXIT
python3 -c "p='pubspec.yaml'; s=open(p).read(); open(p,'w').write(s.replace('    - assets/\n', '    - assets/\n    - test/fixtures/\n', 1))"
flutter build ios --release -t tool/ocr_lab.dart | grep -E "error|✓ Built"
cp /tmp/pubspec.prumo.bak pubspec.yaml
xcrun devicectl device install app --device $DEV build/ios/iphoneos/Runner.app >/dev/null
xcrun devicectl device process launch --terminate-existing --device $DEV $APP >/dev/null
rm -f /tmp/ocr_results.txt
for i in $(seq 1 90); do
  xcrun devicectl device copy from --device $DEV --domain-type appDataContainer --domain-identifier $APP \
    --source Documents/ocr_results.txt --destination /tmp/ocr_results.txt >/dev/null 2>&1 || true
  grep -q CERTOS /tmp/ocr_results.txt 2>/dev/null && break
  sleep 3
done
cat /tmp/ocr_results.txt
echo "Lembrete: reinstale o app normal (flutter build ios --release + devicectl install)."

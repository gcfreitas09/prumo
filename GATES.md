# Gates: Etapa 1

OWNS: lib/**, test/**, pubspec.yaml, assets/**, android/**, ios/**

Scope: projeto, tema, banco, configuração, tela do mês, histórico, ícone, splash e abertura (sem câmera).

- [x] G1: análise estática limpa
  CHECK: flutter analyze
  EXPECT: No issues found!
  EVIDENCE: automatic-evidence=v1; definition-sha256=def4733d44e1b7c2406874433590e3d5501747f52462a5c0701134d34ced6732; exit=0; EXPECT=matched; output-sha256=cd9da1f449fa9b9e7822dd80b27ce4c4e7bfbbea796eab6d135d36a7af7a21ac; output-bytes=96; shell=/bin/sh; cwd=/Users/guilhermefreitas/Documents/leituras; path=d8381a8b3eef/16 entries

- [x] G2: formatação de números/meses coberta por teste
  CHECK: flutter test
  EXPECT: All tests passed!
  EVIDENCE: automatic-evidence=v1; definition-sha256=b0c5c7eac1cebd97a444c8321c184da087193670732e19682190d1f059dae84e; exit=0; EXPECT=matched; output-sha256=165607d06855199fb248a2941c2618b99976af529c7dbf4e98ba6b9da1d70717; output-bytes=209; shell=/bin/sh; cwd=/Users/guilhermefreitas/Documents/leituras; path=d8381a8b3eef/16 entries

- [x] G3: nenhum fontFamily definido no código
  CHECK: node -e "const fs=require('fs');const f=fs.readdirSync('lib',{recursive:true}).filter(x=>x.endsWith('.dart'));const bad=f.filter(x=>fs.readFileSync('lib/'+x,'utf8').includes('fontFamily'));if(bad.length){process.exit(1)}console.log('sem fontFamily em '+f.length+' arquivos')"
  EXPECT: sem fontFamily em
  EVIDENCE: automatic-evidence=v1; definition-sha256=b7d4bd747b9e19bc2543602a1e3418dd83f199dc681ebe7322888821ea204dc7; exit=0; EXPECT=matched; output-sha256=d4fcd26a35bc7f6097020b5d0eebafaf7cf5164394f335679fe793a77f5cdbb0; output-bytes=30; shell=/bin/sh; cwd=/Users/guilhermefreitas/Documents/leituras; path=d8381a8b3eef/16 entries

- [ ] G4: app roda e telas conferidas visualmente (config, mês, histórico, abertura)
  EVIDENCE: pending

## Rodada: Prumo + OCR de roletes (2026-10-20)

- [x] G5: nome do app é "Prumo" no iOS e no Android
  CHECK: node -e "const fs=require('fs');const p=fs.readFileSync('ios/Runner/Info.plist','utf8');const m=fs.readFileSync('android/app/src/main/AndroidManifest.xml','utf8');const ok=/<key>CFBundleDisplayName<\/key>\s*<string>Prumo<\/string>/.test(p)&&/android:label=\"Prumo\"/.test(m);if(!ok)process.exit(1);console.log('nome Prumo nas duas plataformas')"
  EXPECT: nome Prumo nas duas plataformas
  EVIDENCE: automatic-evidence=v1; definition-sha256=d25f73ece6f5ab742ed11a66fe474594bc990653b4587bc7568b7a7a8033a5bc; exit=0; EXPECT=matched; output-sha256=a9a3da681f754c9ab6306f09e9302bad36465f759396c9264f5eb705c219487d; output-bytes=32; shell=/bin/sh; cwd=/Users/guilhermefreitas/Documents/leituras; path=d8381a8b3eef/16 entries

- [x] G6: isolamento dos dígitos acha 0763 (4 dígitos pretos) em todos os cenários dos prints reais
  CHECK: flutter test test/digitos_test.dart
  EXPECT: All tests passed!
  EVIDENCE: automatic-evidence=v1; definition-sha256=4205c423cb0c68817183302c08103bcdc6bcd27be61bed39d7ee12e3ca382ab5; exit=0; EXPECT=matched; output-sha256=41f1f3ec1a05a5b977114ffc4f8b3ebf15bd8d6d23f1ce004e07a8c01589b08f; output-bytes=4460; shell=/bin/sh; cwd=/Users/guilhermefreitas/Documents/leituras; path=d8381a8b3eef/16 entries

- [x] G7: ML Kit real no iPhone lê "0763" na maioria dos cenários do laboratório (tool/ocr_lab.sh), sem nenhuma leitura errada aceita
  EVIDENCE: 2026-10-20 tool/ocr_lab.sh no iPhone 15 Pro: "CERTOS 32/32", todas via linha escura E4 "0763"; ~115 ms isolamento + ~23 ms OCR por quadro.

- [ ] G8: app normal reinstalado no iPhone abre como "Prumo", ícone novo, vídeo curto
  EVIDENCE: pending — instalado e aberto em 2026-10-20; devicectl lista "Prumo 1.0.0"; falta o usuário confirmar ícone, vídeo e leitura no medidor real

## Rodada: webapp para o iPhone do pai, sem cabo (2026-11-10)

Pedido: "faça como um webapp também, para que ele consiga abrir no celular dele, pq ele não tem cabo". Mesmo app (config, mês, leitura por foto com OCR, revisão/PDF, histórico), mesmo PDF e e-mail.

- [x] W1: webapp monta (dart2js do isolamento + Tesseract local + página com tudo inline)
  CHECK: bash web_app/montar.sh
  EXPECT: MONTADO web_app/dist
  EVIDENCE: automatic-evidence=v1; definition-sha256=0a582676bff90238c87bd74c0269b70d4549a668c4f54bd20c885d88ab1bc3ff; exit=0; EXPECT=matched; output-sha256=f836505fd3104df0d359ce9ebf827c96796a259f1c8258f5fe712451a7ba7d5a; output-bytes=28; shell=/bin/sh; cwd=/Users/guilhermefreitas/Documents/leituras; path=d8381a8b3eef/16 entries

- [x] W2: OCR web (mesmo pipeline compilado para JS + Tesseract) lê 076360 nos dois prints da água e acha a fileira do gás começando em 01461
  CHECK: node web_app/teste_ocr.mjs
  EXPECT: OCR WEB OK
  EVIDENCE: automatic-evidence=v1; definition-sha256=ce10603edc30dbea6770bcc4a8bfc4a2fb96acda5ef920833c5d70522b01bba5; exit=0; EXPECT=matched; output-sha256=8ba384a6761e61646a9e7c987f95ab7f496ca8df358d0517a2033a564be7158d; output-bytes=481; shell=/bin/sh; cwd=/Users/guilhermefreitas/Documents/leituras; path=d8381a8b3eef/16 entries

- [x] W3: lógica web (números, mês, análise, plausível, PDF sem consumo, e-mail) igual ao app
  CHECK: node web_app/teste_logica.mjs
  EXPECT: LOGICA WEB OK
  EVIDENCE: automatic-evidence=v1; definition-sha256=651003c1535ef91730f77f25d19e50c8df923a4919ed05965ea2c0a168a019b6; exit=0; EXPECT=matched; output-sha256=444810477eaa48e8988c8aa1ff962dd5f838441b934100459f865c28b25df924; output-bytes=14; shell=/bin/sh; cwd=/Users/guilhermefreitas/Documents/leituras; path=d8381a8b3eef/16 entries

- [x] W4: app Flutter continua limpo
  CHECK: flutter analyze
  EXPECT: No issues found!
  EVIDENCE: automatic-evidence=v1; definition-sha256=def4733d44e1b7c2406874433590e3d5501747f52462a5c0701134d34ced6732; exit=0; EXPECT=matched; output-sha256=3440e4a5a32f82f08585799a3acd06fb4019d8413475618730a3d0008e5cdfee; output-bytes=1841; shell=/bin/sh; cwd=/Users/guilhermefreitas/Documents/leituras; path=d8381a8b3eef/16 entries

- [x] W5: entregável cabe no limite do link (≤ 16 MB por arquivo, ≤ 20 MB no total)
  CHECK: node -e "const fs=require('fs'),p=require('path');const d='web_app/dist';let t=0,m=0;for(const f of fs.readdirSync(d)){const s=fs.statSync(p.join(d,f)).size;t+=s;m=Math.max(m,s)}if(t>20e6||m>16e6)process.exit(1);console.log('PESO OK',(t/1e6).toFixed(1)+' MB')"
  EXPECT: PESO OK
  EVIDENCE: automatic-evidence=v1; definition-sha256=7419ecaab3aa4502eddc4c185ae06a5d456c650efb19cabe3a8f4f1e51e0b39c; exit=0; EXPECT=matched; output-sha256=2ccc848163ccf2bf36a5e70b17b8b27aea1c811cc5e927dfcec18d0b8d8d29c2; output-bytes=16; shell=/bin/sh; cwd=/Users/guilhermefreitas/Documents/leituras; path=d8381a8b3eef/16 entries

- [x] W6: telas conferidas no navegador a 390 px (config, mês, leitura com foto do medidor, revisão, histórico), sem erro de console
  EVIDENCE: 2026-11-10 servidor local (web_app/dist) a 390×844, claro e escuro: entrada, config em 4 passos (6 andares × 4, 102 desligado, ordem mudada, e-mail), mês (mapa + lista), leitura do print medidor_agua_escuro → "076 360" com a caixa sobre os dígitos, confirmar → vai ao próximo e "Leitura salva · Desfazer", gás pelo Tesseract no navegador (leu "1461855": errado, o 0 inicial sumiu), revisão com prévia, prédio com cópia de segurança, histórico. scrollWidth−clientWidth = 0 em todas; console sem erro.

- [ ] W7: link publicado abre e o OCR roda dentro dele (Tesseract carrega sob a CSP do link)
  EVIDENCE: pending

- [x] W8: entrada do webapp refeita (prumo desce, amortece e para sobre a marca; o mapa do prédio acende), conferida a 390 px no claro e no escuro, sem erro de console
  EVIDENCE: 2026-11-10 servidor local: quadros a 1,2 s (prumo descendo/balançando), 2,8 s (assentando) e no fim (22 de 24 acesos, cruz e eco no lugar), claro e escuro; console sem erro. Republicado no link (versão 2).

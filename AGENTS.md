# Prumo — especificação (fonte da verdade)

App Flutter (Android + iOS) chamado **Prumo** (pacote Dart `leituras_predio`, bundle `br.com.leituras.leiturasPredio` — não mudar: o iPhone do usuário perderia os dados). Síndico lê mensalmente medidores de água e gás de cada apartamento pela câmera (OCR) e envia tudo por e-mail. Leituras 100% offline e só no aparelho; o ÚNICO uso de rede é o login (Firebase Auth, e-mail + senha, decisão do usuário em 2026-10-21). UI em pt-BR.

## Dados (sqflite) — lib/db.dart
- predio(id, nome, emails_destino, incluir_consumo)
- apartamento(id, numero "201", andar, ordem_apto, ordem_leitura, ativo)
- mes_leitura(id, ano, mes, criado_em, enviado_em; único ano+mes)
- leitura(id, mes_id, apartamento_id, tipo agua|gas, valor TEXTO, foto_path, lido_em, editado_manual; único mes+apto+tipo)

## Telas
0. Entrada (`telas/entrada.dart`, serviço em `conta.dart`): fio de prumo animado (peso de latão oscila, amortece e para sobre a marca no chão; ~3 s; respeita disableAnimations) e depois o formulário: Entrar · Criar conta (nome, e-mail, senha 8+ com letra e número) · Confirmar e-mail (link do Firebase; "Já confirmei"; reenviar com espera de 30 s) · Esqueci a senha. Só entra conta CONFIRMADA; a sessão fica salva (vale offline). Erros em português (`mensagemErroAuth`); login/senha errados dão a mesma mensagem (não revela se o e-mail existe). "Sair da conta" fica em Configuração. Sem Firebase configurado (`lib/firebase_config.dart` vazio) cai na entrada local (nome + e-mail, sem senha) — ver FIREBASE.md. Tabela `usuario` guarda nome/e-mail para sugerir o 1º destinatário.
1. Configuração (1ª abertura, passos curtos): nome → gerador de andares/aptos (andar inicial, final, aptos/andar; depois editar, desativar, renomear) → ordem física de leitura (arrastar) → e-mails de destino: até DOIS, distintos (1º obrigatório, sugerido com o e-mail da entrada; 2º opcional).
2. Mês atual = inicial. Título 34 bold com o mês + "19 de 22 medidores lidos"; segmentado Água|Gás com contador; mapa em grade (linha por andar, quadrado 13 px por apto, cor do medidor se lido); lista por andar com leitura+consumo à direita ou link "Ler"; botão fixo embaixo com próximo pendente na ordem física ("Ler 601"). Ícones histórico, prédio e enviar na barra. Mês novo criado automaticamente.
3. Leitura: câmera cheia, OCR ao vivo (~4/s), moldura fina onde o usuário encaixa os dígitos, caixa sobre os dígitos achados. Captura automática por votação entre quadros (vibração média). Lanterna automática com pouca luz. Bottom sheet: leitura 44 pt, mês anterior, consumo, "na média"/aviso. Consumo negativo ou > 2× média de 3 meses pede toque extra. "Editar" e "Confirmar". Após confirmar: "Leitura salva · Desfazer" 4 s e vai ao próximo apto. Deslizar troca de apto. Guarda foto recortada. Botões: Capturar (disparo manual), zoom 1×/2×/3×, teclado, lanterna.
4. Revisão e envio: prévia do PDF, pendentes no topo, botão Enviar.
5. Histórico: meses com total de consumo.

## Relatório
PDF A4 (pacote pdf), SEM CONSUMO (usuário, 2026-11-09): cabeçalho "LEITURA DE ÁGUA E GÁS" + prédio (24 bold) + mês + fio na cor ação; linha "N apartamentos · X de Y medidores lidos" e data; tabela APTO · ÁGUA · GÁS (marcador azul/laranja), listras leves, fios finos, números à direita; "-" = sem leitura com nota; rodapé "Responsável: Alex Freitas" e página. A opção "incluir consumo" saiu da Configuração (a coluna do banco ficou, sem uso). SÓ PDF (usuário, 2026-10-28: tirar tudo que não é PDF — sem CSV). E-mail com flutter_email_sender (plano B share_plus): assunto "Leituras de água e gás – Outubro/2026 – <prédio>", 1 anexo (o PDF), corpo fixo: "Segue em anexo a leitura." + "Atenciosamente," + "Alex Freitas" (`assinaturaEmail` em relatorio.dart; sem tabela de consumos no texto). PDF usa fontes padrão (só Latin-1): espaço fino vira nbsp, "—" e "−" viram "-".

## Design
Nativo e sóbrio (nível Apple Wallet). Fonte do sistema (NUNCA definir fontFamily). Listas com separador 0,5 px, sem cartões/sombras/gradientes/emoji. Números SEMPRE com FontFeature.tabularFigures(), grupos de 3 com espaço fino (1 316 967); consumo "+ 1 247 m³". Tipos: título 34 bold · leitura 44 semibold · corpo 17 · legenda 13. Movimento 150–300 ms, discreto; respeitar disableAnimations. Alvos ≥ 44 pt.
Cores claro/escuro (lib/tema.dart): fundo #FFFFFF/#0B0B0C · fundo2 #EFEFED/#1C1C1E · fio #E6E6E3/#2C2C2E · texto #111111/#F5F5F4 · texto2 #6E6E73/#98989F · ação #1F4647/#7FBFB4 · água #2B7BD6/#4C9BFF · gás #DD6B2B/#FF8C4A · vazio #E7E7E4/#2C2C2E · ok #2E9D5B/#3CCB7A · aviso #C98A0B/#F2BD45 · erro #D93A3A/#FF6961.

## Abertura e ícone
- assets/abertura_splash.mp4: vídeo do usuário (10 s) CORTADO para 1,0–6,8 s com `avconvert` e tocado a 1,3× (~4,5 s). video_player, mudo, 85% da largura, fundo #17191B (o fundo do vídeo é #151819, igual a olho), toque pula, fade 300 ms, só em abertura a frio. Splash nativo liso #17191B.
- Ícone: arte do usuário (tile 3D com prédio, gota e lâmpada). `assets/icon/icon_ios_1024.png` = recorte quadrado sobre o fundo escuro da própria arte; `icon_android_foreground_1024.png` = tile com alfa a 78%; adaptive background **#17181A** (cor do fundo da arte; #2F3439 da especificação original destoava). Regerar: `dart run flutter_launcher_icons`.

## Permissões
Câmera (Android+iOS, texto pt-BR), queries mailto no Android, versões mínimas do ML Kit (Android minSdk 24, iOS 15.5).

## Leitura de medidor — como funciona e por quê (não simplificar)
Medidores de roletes têm sombras/divisórias entre os dígitos; o ML Kit lendo a faixa inteira inventa dígitos ("047636" para 0763). Por isso:
1. `ocr.dart › faixaDoQuadro`: recorta a MOLDURA (faixaX0..Y1) do quadro do sensor, em pé, em cinza + máscara de vermelho.
2. `digitos.dart › acharLinhas`: contraste esticado → top-hat morfológico (k = 1,5–4,5% da altura da faixa; com leitura anterior, k = 0,2 × altura do dígito) → componentes → fileira com mesma altura (±15%), alinhada vizinho a vizinho (aceita celular inclinado) e passo regular. Rejeita manchas sólidas (espessura > 14% da altura) e tudo na zona vermelha. Pontua altura × √quantidade (a fileira de dígitos é a de letras maiores). Duas polaridades: dígitos escuros primeiro, claros (rolete preto) depois.
3. Os dígitos são recompostos limpos lado a lado (~56 px) e SÓ ESSA imagem vai ao ML Kit; `digitosDaLinha` aceita apenas se vier exatamente um dígito por componente.
4. Votação entre quadros (`Votacao`) + `plausivel` (≥ mês anterior e sem salto absurdo) antes da captura.
- Dígitos VERMELHOS: LIDOS e juntados aos pretos num NÚMERO SÓ, sem vírgula (usuário, 2026-10-20: "essa vírgula não existe, é um número só" → 306075). Achados na máscara de vermelho, à direita da fileira preta, no passo dos roletes. Com vermelhos, só vale a leitura completa (só os pretos seria outro número). Rolete girando (cortado/deslocado) entra também; o OCR dá o vizinho. Fileira preta com vão de 2 passos (dígito sumido) é descartada.
- GÁS (medidor LAO do usuário; fixtures: `medidor_gas_lao.jpg` = foto de longe, `medidor_gas_camera.png` = print da câmera do app, 2026-10-22): 5 roletes PRETOS com dígito CLARO + 3 VERMELHOS (fundo vermelho, dígito claro), o último girando — tudo na polaridade "claro", sem suprimir o vermelho. Mudanças que fizeram os 8 dígitos entrarem: (a) `_podar` só apara as PONTAS por altura (antes removia o pior de qualquer posição e comia dígito bom do meio; quem garante que é dígito é o passo regular); (b) `_completarFileira` acha pelos PIXELS, no passo dos roletes, os dígitos que não viraram componente (colados na moldura) — vão interno, direita e esquerda — e `_separarColados` corta componente bem mais largo que os outros; (c) a fileira completada passa de novo por `_podar`/`_pontos`, e a fileira SEM completar também é emitida como alternativa (`_Linha.alternativa`), então o OCR tem duas chances; (d) limiar frouxo vence o rigoroso sempre que achar mais dígitos; (e) variantes de traço engrossado (ML Kit lê dígito fino de gás como letra: "UI461R0" = 0146180).
- VELOCIDADE (2026-11-09): a busca completa (2 polaridades × 5 kernels × 2 limiares) leva ~0,4 s; cada linha achada traz uma `Dica` (polaridade, k, limiar) e o próximo quadro roda SÓ ela (~45 ms, mesmo resultado — teste em digitos_test). A dica cai após 2 quadros sem leitura (volta à busca completa). Quadros a cada 120 ms (~8/s). Captura rápida: mesmo número em 2 quadros seguidos quando já há mês anterior (plausível e com o nº de dígitos esperado); sem histórico, 3 iguais (`Votacao`). Leitura com menos dígitos que o medidor tem (pelas leituras confirmadas do mês, `_digitosEsperados`) ou que o máximo já visto no apto é ignorada.
- FLUIDEZ (2026-11-10): cada linha sai em VARIANTES marcadas (`variante`: cinza, mascara, alternativa, grossa1/2); a câmera tenta primeiro a que leu da última vez e faz no máximo 4 OCRs por quadro (o Capturar tenta todas). Votação por dígito já com 3 quadros (antes 4). Comprimento "certo" do apto só depois de 2 aparições (`_vistos`): leitura espúria mais longa não trava mais a captura.
- Plausibilidade na escala do medidor: até 8× a média; sem média, até 20% da leitura anterior.
- "Capturar": foto → mesma faixa (mapeada pelo aspecto prévia×foto em `_naFoto`) reduzida a 864 px de largura → mesmo pipeline. Sem resultado, abre a edição vazia (nunca chutar número).
- Armadilha: o iPhone entrega o quadro JÁ EM PÉ (BGRA 1080×1920, 4352 bytes/linha) apesar de sensorOrientation=90; girar de novo lia a faixa errada (canos em vez do medidor). Rotação sai de `rotacaoDoQuadro` (pelo formato do buffer), nunca só do sensor.
- Armadilha: `Isolate.run` com closure criado DENTRO de método do State leva o State (e a câmera) junto e falha sempre, em silêncio. Chamar só pelas funções de topo do fim de camera.dart (`acharLinhasIsolado` etc.); test/isolado_test.dart vigia isso.
- Armadilha: no pacote `image`, `adjustColor` e `gaussianBlur` alteram a imagem de entrada — usar `.clone()`.
- Armadilha: ML Kit não tem arm64 para simulador iOS 26 — OCR real só no iPhone. Laboratório: `tool/ocr_lab.sh` (iPhone no cabo) roda o caminho de produção sobre test/fixtures com 16 variações por print e imprime `CERTOS n/48` (3 prints; 2026-10-20: 33/48 — 0763: 31/32; 701, com rolete girando e print escurecido, é o caso difícil). Depois reinstalar o app normal.

## Mapa
lib/main.dart (app, rota inicial) · tema.dart · formato.dart (números/meses) · analise.dart (consumo/média/plausível) · ocr.dart (faixa do quadro, votação, linha → dígitos) · digitos.dart (isolamento dos dígitos, puro Dart) · db.dart · relatorio.dart (PDF/CSV/e-mail) · telas/camera.dart (câmera, captura, foto) · telas/folha_leitura.dart · telas/revisao.dart · telas/*.dart · test/fixtures/ (prints reais do medidor do usuário).

## Webapp (web_app/) — para o iPhone do pai, sem cabo (2026-11-10)
Pedido: "faça como um webapp também, para que ele consiga abrir no celular dele". Publicado como Artifact do Claude: https://claude.ai/artifact/Bph48kix23BLeAHfn1SoUC. O link é PRIVADO até o usuário compartilhar pelo menu Share. Publicar de novo sempre por esse mesmo link.
- Fontes: `pagina.html` (CSS + casca), `logica.js` (puro, espelha formato/analise/relatorio + OCR por faixas), `app.js` (telas), `ocr_worker.js`, `src/prumo_ocr.dart` (ponte: o MESMO lib/digitos.dart compilado com dart2js), `sementes.js` (gerado por `gerar_sementes.mjs`). `dist/` é gerado por `bash web_app/montar.sh`: nunca editar à mão.
- Publicar: `dist/index.html` como página, mais os arquivos `ocr_worker.js`, `prumo_ocr.js`, `tesseract-worker.min.js`, `tesseract-core-simd-lstm.wasm.js` e `tesseract-core-lstm.wasm.js`. Publicar também `eng.traineddata` com contentType `application/wasm`: o link recusa `application/octet-stream`, e o Tesseract pede exatamente esse nome. Declarar a capacidade `{downloads: true}`.
- O link do Claude só carrega scripts de cdnjs, jsdelivr e unpkg. O resto vai inline (montar.sh junta tudo) ou como arquivo publicado. O link também não tem câmera ao vivo nem compartilhar, e mailto não é garantido. Por isso:
  - a leitura é por FOTO, com `<input capture>`;
  - o PDF sai pela capacidade downloads;
  - o e-mail tem botões de copiar e o pai anexa o PDF salvo.
  - Fora do link (site próprio), "Enviar PDF" usa a folha de compartilhar.
- OCR: a foto vai até 2000 px. As faixas têm o formato da moldura (≈2:1) e são reduzidas a 864 px. Sem toque, a busca vai do meio para fora; tocar nos números lê ali.
  - Para cada linha, o resultado só vale com consenso dígito a dígito (`consensoPosicional`). Os palpites vêm de três fontes:
    1. modelos de forma (`glifo` 16×24 + semelhança ≥ 0,82 com folga de 0,15; vale 2 votos);
    2. Tesseract na linha inteira (psm 13 e 7);
    3. Tesseract em grupos de 2, 3 e 4 dígitos.
  - Por dígito isolado o Tesseract erra muito; não usar.
- APRENDE: cada leitura confirmada (ou corrigida no teclado) guarda os dígitos da foto como modelos (`aprender`, até 8 por dígito). As sementes vêm dos prints da água e cobrem 0 2 3 5 6 7 8 9; o gás começa só no Tesseract.
- Limites medidos: água 076360 certo nos prints. Gás pelo Tesseract erra o 1º/últimos dígitos ("0146185"/"1461855"). A foto de longe (medidor_gas_lao.jpg, dígitos com ~35 px) não lê. Sempre mostrar "Confira com o medidor".
- Dados: localStorage `prumo.web.v1` (só naquele navegador; o Safari pode apagar). Por isso há "Salvar cópia"/"Restaurar" (JSON) em Prédio. Sem login no web.
- Entrada (usuário 2026-11-10: "deixe essa intro mais bonita, está fraca"):
  - O fio de prumo desce do topo da tela, balança amortecido (θ = 7°·e^(−3,1t)·cos(2π·2,15t)·(1−t), em 2,6 s) e para sobre a cruz no chão, com um eco.
  - Embaixo fica o mapa do prédio (o mesmo da tela do mês, 6×4), que acende andar por andar: 22 de 24.
  - A cena é feita com GSAP 3.12.5 (cdnjs) dentro de `gsap.matchMedia`. O HTML já é o estado final, o que vale para movimento reduzido e para quando não há JS.
  - O giro usa `svgOrigin`: o `transform-origin` do CSS não vale em tween de SVG.
- Testes: `node web_app/teste_logica.mjs` (LOGICA WEB OK) e `node web_app/teste_ocr.mjs` (OCR WEB OK). Eles usam jimp/pngjs/tesseract.js/jspdf de `~/.claude/tools/qa`, nunca do projeto.

## Repositório
GitHub: `git@github.com:gcfreitas09/prumo.git` (branch main, SSH já autenticado neste Mac). Fica fora do repositório o que é gerado: `build/`, `.dart_tool/`, `ios/Pods/`, `web_app/dist/`, `.claude/`, `.unlazy/`.

## Comandos
`flutter pub get` · `flutter analyze` · `flutter test` (inclui test/digitos_test.dart: 38 cenários dos prints — escala, escuro, desfoque, giro 3°) · `dart run flutter_launcher_icons` · `dart run flutter_native_splash:create` · instalar no iPhone: `flutter build ios --release` + `xcrun devicectl device install app --device <UDID> build/ios/iphoneos/Runner.app` (debug não abre pelo ícone no iOS 14+).

## Definição de pronto
`flutter analyze` sem issues · `flutter test` todo verde · OCR conferido no iPhone com medidor real (ou com o laboratório) · `GATES.md` sem gate pendente.

## Pendências do usuário
Webapp: compartilhar o link pelo menu Share e abrir no iPhone do pai. O OCR dentro do link (Tesseract sob a CSP do claude.ai) ainda não foi conferido: o navegador do Claude estava deslogado. Isso é o gate W7.
Criar o projeto Firebase e mandar GoogleService-Info.plist + google-services.json (FIREBASE.md); sem isso o login com senha NÃO está ativo (o app usa a entrada local).

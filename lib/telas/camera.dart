import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../analise.dart';
import '../db.dart';
import '../diag.dart';
import '../digitos.dart';
import '../formato.dart';
import '../ocr.dart';
import '../tema.dart';
import 'folha_leitura.dart';

/// Leitura pela câmera: OCR ao vivo, captura automática após 3 leituras iguais.
class TelaCamera extends StatefulWidget {
  final Mes mes;
  final List<Apto> aptos; // na ordem física de leitura
  final int indice;
  final String tipo;
  final Leituras leituras;
  final Map<String, List<int>> anteriores;
  const TelaCamera({super.key, required this.mes, required this.aptos, required this.indice, required this.tipo, required this.leituras, required this.anteriores});
  @override
  State<TelaCamera> createState() => _TelaCameraState();
}

class _TelaCameraState extends State<TelaCamera> with WidgetsBindingObserver {
  CameraController? _cam;
  final _rec = TextRecognizer(script: TextRecognitionScript.latin);
  late int _i = widget.indice;
  late final Leituras _lei = Map.of(widget.leituras);
  String? _erro;

  DateTime _ultimo = DateTime.fromMillisecondsSinceEpoch(0);
  bool _ocupado = false;
  bool _travado = false; // true enquanto captura/folha
  Candidato? _cand;
  Size _tam = const Size(720, 1280);

  Dica? _dica; // polaridade/kernel/limiar que acharam a fileira no último quadro
  String? _ultimoLido;
  /// Quantas vezes cada comprimento de leitura apareceu neste apto. Um
  /// comprimento só passa a valer como "o certo" depois de 2 aparições: uma
  /// leitura espúria mais longa (sujeira contada como dígito) não trava o resto.
  final Map<int, int> _vistos = {};
  int _comprimentoFirme() {
    var m = 0;
    _vistos.forEach((n, c) {
      if (c >= 2 && n > m) m = n;
    });
    return m;
  }

  /// Quantos dígitos o medidor deste tipo tem, pelas leituras já confirmadas no
  /// mês (o comprimento mais comum). Null antes da primeira.
  int? get _digitosEsperados {
    final cont = <int, int>{};
    _lei.forEach((k, l) {
      if (l.tipo == widget.tipo) cont[l.valor.length] = (cont[l.valor.length] ?? 0) + 1;
    });
    if (cont.isEmpty) return null;
    return cont.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  int? _hPrev; // altura do dígito no último quadro lido (estreita a busca)
  int _falhas = 0;
  bool _lendoFoto = false;
  double _zoom = 1, _zmin = 1, _zmax = 1;
  final _voto = Votacao();
  String? _rejeitada;

  bool _lanterna = false;
  bool _lanternaManual = false;
  int _escuro = 0;

  Apto get _apto => widget.aptos[_i];
  String get _chave => chave(_apto.id!, widget.tipo);
  List<int> get _ant => widget.anteriores[_chave] ?? const [];
  String get _nomeTipo => widget.tipo == 'agua' ? 'Água' : 'Gás';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Diag.iniciar().then((_) => Diag.log('tela da câmera aberta'));
    _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('semCamera', 'Nenhuma câmera encontrada.');
      final desc = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final cam = CameraController(
        desc, ResolutionPreset.veryHigh, enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await cam.initialize();
      await cam.setFlashMode(_lanterna ? FlashMode.torch : FlashMode.off);
      try {
        await cam.setFocusMode(FocusMode.auto);
        await cam.setExposureMode(ExposureMode.auto);
        _zmin = await cam.getMinZoomLevel();
        _zmax = await cam.getMaxZoomLevel();
        await cam.setZoomLevel(_zoom.clamp(_zmin, _zmax));
      } catch (_) {}
      if (!mounted) {
        await cam.dispose();
        return;
      }
      _cam = cam;
      Diag.log('câmera pronta: preview=${cam.value.previewSize} sensor=${desc.sensorOrientation} zoom=$_zmin..$_zmax');
      await cam.startImageStream(_quadro);
      Diag.log('stream iniciado');
      setState(() => _erro = null);
    } on CameraException catch (e) {
      if (!mounted) return;
      final negada = e.code.contains('Denied') || e.code.contains('denied');
      setState(() => _erro = negada
          ? 'O acesso à câmera está desligado. Ative em Ajustes do aparelho para ler pelos medidores, ou digite a leitura.'
          : 'Não foi possível abrir a câmera. Você pode digitar a leitura.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
      final c = _cam;
      _cam = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (s == AppLifecycleState.resumed && _cam == null && _erro == null) {
      _iniciar();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    _rec.close();
    super.dispose();
  }

  // ---------- OCR ao vivo
  int _nq = 0;
  Future<void> _quadro(CameraImage f) async {
    if (_nq < 3) Diag.log('quadro recebido (travado=$_travado ocupado=$_ocupado)');
    if (_travado || _ocupado || _cam == null) return;
    final agora = DateTime.now();
    // com a dica a busca leva ~50 ms: dá para olhar ~8 quadros por segundo
    if (agora.difference(_ultimo).inMilliseconds < 120) return;
    _ultimo = agora;
    _ocupado = true;
    try {
      _verLuz(f);
      final rot = rotacaoDoQuadro(f.width, f.height, _cam!.description.sensorOrientation);
      final girado = rot == 90 || rot == 270;
      final tam = girado ? Size(f.height.toDouble(), f.width.toDouble()) : Size(f.width.toDouble(), f.height.toDouble());
      final pl = f.planes.first;
      final fq = faixaDoQuadro(bytes: pl.bytes, width: f.width, height: f.height, bytesPerRow: pl.bytesPerRow, bgra: Platform.isIOS, rot: rot);
      if (fq == null) {
        Diag.log('faixaDoQuadro = null (rot=$rot ${f.width}x${f.height})');
        return;
      }
      final faixa = fq.faixa, hPrev = _hPrev, dica = _dica;
      final nq = ++_nq;
      final logar = nq <= 40 || nq % 10 == 0;
      if (logar) {
        Diag.log('#$nq ${f.width}x${f.height} planos=${f.planes.length} bpr=${pl.bytesPerRow} bytes=${pl.bytes.length} fmt=${f.format.raw} rot=$rot faixa=${faixa.w}x${faixa.h} verm=${faixa.vermelho.where((v) => v == 1).length} hPrev=$hPrev');
      }
      if (nq == 6 || nq == 30) Diag.cinza('faixa_$nq', faixa.cinza, faixa.w, faixa.h);
      final linhas = await acharLinhasIsolado(faixa, hPrev, dica);
      if (logar) Diag.log('   linhas: ${linhas.map((l) => '${l.claro ? 'C' : 'E'}${l.n}h${l.alturaDigito}').join(' ')}');
      if (!mounted || _travado) return;
      final achado = await _lerLinhas(linhas);
      if (logar) Diag.log('   ocr: ${achado?.valor}');
      if (achado != null && nq < 400) Diag.cinza('linha_$nq', achado.linha.imagem, achado.linha.largura, achado.linha.altura);
      if (!mounted || _travado) return;
      final ant = _ant;
      Candidato? c;
      _rejeitada = null;
      if (achado != null) {
        _hPrev = achado.linha.alturaDigito;
        _dica = achado.linha.dica;
        _falhas = 0;
        final cx = achado.linha.caixa;
        final box = Rect.fromLTRB((cx.x0 + fq.x0).toDouble(), (cx.y0 + fq.y0).toDouble(), (cx.x1 + fq.x0).toDouble(), (cx.y1 + fq.y0).toDouble());
        final n = achado.valor.length;
        final esperado = _digitosEsperados;
        if (esperado != null && n != esperado) {
          // o medidor deste tipo tem [esperado] roletes (leituras já confirmadas):
          // fileira com dígito a menos ou a mais não vale
        } else if (n < _comprimentoFirme()) {
          // a fileira mais longa já apareceu 2× neste apto: a curta perdeu dígito da ponta
        } else if (plausivel(parteInteira(achado.valor)!, ant)) {
          _vistos[n] = (_vistos[n] ?? 0) + 1;
          c = Candidato(achado.valor, box);
        } else {
          _rejeitada = achado.valor;
        }
      } else {
        _falhas++;
        // a combinação lembrada parou de achar: volta à busca completa
        if (_falhas >= 2) _dica = null;
        if (_falhas >= 4) _hPrev = null; // perdeu a linha: volta a procurar em todos os tamanhos
      }
      _voto.add(c?.valor);
      // captura rápida: o mesmo número em 2 quadros seguidos E coerente com o mês
      // anterior (plausível e com a mesma quantidade de dígitos). Sem histórico,
      // vale a votação normal (3 iguais).
      final rapido = c != null && c.valor == _ultimoLido && _ant.isNotEmpty;
      _ultimoLido = c?.valor;
      final cons = rapido ? c.valor : _voto.consenso();
      setState(() { _cand = c; _tam = tam; });
      if (c != null && cons != null) {
        final v = parteInteira(cons);
        if (v != null && plausivel(v, ant)) unawaited(_capturar(Candidato(cons, c.box), tam));
      }
    } catch (e, st) {
      Diag.log('ERRO no quadro: $e\n${st.toString().split('\n').take(6).join('\n')}');
      debugPrint('OCR: quadro perdido: $e'); // segue para o próximo
    } finally {
      _ocupado = false;
    }
  }

  /// OCR das linhas recompostas (dígitos escuros primeiro). Só aceita quando o
  /// texto tem exatamente um dígito por componente encontrado.
  String? _varianteBoa; // variante da linha que o OCR leu certo da última vez

  /// OCR das linhas recompostas. Começa pela variante que leu da última vez e
  /// para no máximo em [limite] chamadas por quadro: o ML Kit custa ~25 ms cada,
  /// e tentar todas as variantes em todo quadro deixava a câmera lenta.
  Future<({String valor, LinhaDigitos linha})?> _lerLinhas(List<LinhaDigitos> linhas, {int limite = 4}) async {
    final android = Platform.isAndroid;
    final ordem = [...linhas];
    final boa = _varianteBoa;
    if (boa != null) {
      ordem.sort((a, b) => (a.variante == boa ? 0 : 1).compareTo(b.variante == boa ? 0 : 1));
    }
    for (final l in ordem.take(limite)) {
      final r = await _rec.processImage(InputImage.fromBytes(
        bytes: android ? cinzaParaNv21(l.imagem, l.largura, l.altura) : cinzaParaBgra(l.imagem, l.largura, l.altura),
        metadata: InputImageMetadata(
          size: Size(l.largura.toDouble(), l.altura.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: android ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
          bytesPerRow: android ? l.largura : l.largura * 4,
        ),
      ));
      final ls = [for (final b in r.blocks) ...b.lines]..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
      // pretos + vermelhos formam UM número só, como no visor (306075)
      final d = digitosDaLinha(ls.map((x) => x.text).join(), l.n);
      Diag.log('   ml kit ${l.variante}: "${ls.map((x) => x.text).join('|')}" n=${l.n} → $d');
      if (d != null) {
        _varianteBoa = l.variante;
        return (valor: d, linha: l);
      }
    }
    return null;
  }


  void _verLuz(CameraImage f) {
    if (_lanterna || _lanternaManual) return;
    final l = luminancia(f.planes.first.bytes, bgra: Platform.isIOS);
    _escuro = l < 45 ? _escuro + 1 : 0;
    if (_escuro >= 4) _definirLanterna(true);
  }

  Future<void> _focar(Offset pos) async {
    final cam = _cam;
    if (cam == null || _travado) return;
    final tam = MediaQuery.of(context).size;
    final o = Offset((pos.dx / tam.width).clamp(0.0, 1.0), (pos.dy / tam.height).clamp(0.0, 1.0));
    try {
      await cam.setFocusPoint(o);
      await cam.setExposurePoint(o);
    } catch (_) {}
  }

  Future<void> _aplicarZoom(double z) async {
    try {
      await _cam?.setZoomLevel(z.clamp(_zmin, _zmax));
      if (mounted) setState(() => _zoom = z.clamp(_zmin, _zmax));
    } catch (_) {}
  }

  Future<void> _definirLanterna(bool v) async {
    try {
      await _cam?.setFlashMode(v ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _lanterna = v);
    } catch (_) {}
  }

  // ---------- captura e conferência
  Future<void> _capturar(Candidato c, Size tam) async {
    _travado = true;
    HapticFeedback.mediumImpact();
    XFile? foto;
    try {
      await _cam!.stopImageStream();
      foto = await _cam!.takePicture();
    } catch (_) {}
    final norm = Rect.fromLTRB(c.box.left / tam.width, c.box.top / tam.height, c.box.right / tam.width, c.box.bottom / tam.height);
    await _abrirFolha(c.valor, foto: foto, norm: norm);
  }

  /// Disparo manual: foto, mesma busca de dígitos na moldura e conferência.
  Future<void> _capturarAgora() async {
    if (_travado || _cam == null) return;
    _travado = true;
    HapticFeedback.mediumImpact();
    setState(() => _lendoFoto = true);
    XFile? foto;
    try {
      await _cam!.stopImageStream();
      foto = await _cam!.takePicture();
    } catch (_) {}
    const moldura = Rect.fromLTRB(faixaX0, faixaY0, faixaX1, faixaY1);
    var valor = '';
    Rect? norm;
    Diag.log('Capturar: foto=${foto?.path} tam=$_tam');
    if (foto != null) {
      try {
        final origem = foto.path;
        final aspecto = _tam.width / _tam.height;
        final r = await _linhasDaFotoIsolado(origem, aspecto);
        Diag.log('Capturar: faixa ${r.w}x${r.h} linhas: ${r.linhas.map((l) => '${l.claro ? 'C' : 'E'}${l.n}h${l.alturaDigito}').join(' ')}');
        final achado = await _lerLinhas(r.linhas, limite: 99); // foto única: tenta todas
        Diag.log('Capturar: ocr = ${achado?.valor}');
        if (achado != null) {
          valor = achado.valor;
          final c = achado.linha.caixa;
          double nx(int x) => faixaX0 + x / r.w * (faixaX1 - faixaX0);
          double ny(int y) => faixaY0 + y / r.h * (faixaY1 - faixaY0);
          norm = Rect.fromLTRB(nx(c.x0), ny(c.y0), nx(c.x1), ny(c.y1));
        }
      } catch (e, st) {
        Diag.log('Capturar ERRO: $e\n${st.toString().split('\n').take(6).join('\n')}');
      }
    }
    if (!mounted) return;
    setState(() => _lendoFoto = false);
    await _abrirFolha(valor, foto: foto, norm: norm ?? moldura, editando: valor.isEmpty);
  }

  Future<void> _digitar() async {
    if (_travado) return;
    _travado = true;
    try {
      await _cam?.stopImageStream();
    } catch (_) {}
    await _abrirFolha(_lei[_chave]?.valor ?? '', editando: true);
  }

  Future<void> _abrirFolha(String valor, {XFile? foto, Rect? norm, bool editando = false}) async {
    final r = await showModalBottomSheet<ResultadoFolha>(
      context: context,
      isScrollControlled: true,
      elevation: 0,
      backgroundColor: context.p.fundo,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => FolhaLeitura(apto: _apto, tipo: widget.tipo, valor: valor, anteriores: _ant, iniciarEditando: editando),
    );
    if (!mounted) return;
    if (r == null) {
      if (foto != null) File(foto.path).delete().ignore();
      await _retomar();
      return;
    }
    await _salvar(r, foto, norm);
  }

  Future<String?> _guardarFoto(XFile foto, Rect norm) async {
    try {
      final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'fotos'));
      await dir.create(recursive: true);
      final dest = p.join(dir.path, '${widget.mes.ano}-${widget.mes.mes}-${_apto.numero}-${widget.tipo}.jpg');
      final origem = foto.path;
      final aspecto = _tam.width / _tam.height;
      await _recortarIsolado(origem, norm, dest, aspecto);
      return dest;
    } catch (_) {
      return null;
    }
  }

  Future<void> _salvar(ResultadoFolha r, XFile? foto, Rect? norm) async {
    final i = _i;
    final apto = _apto;
    final tipo = widget.tipo;
    final foiEditada = r.editado || foto == null;
    final caminho = (foto != null && norm != null) ? await _guardarFoto(foto, norm) : null;
    if (foto != null) File(foto.path).delete().ignore();
    final antes = _lei[_chave];
    await Db.i.salvarLeitura(widget.mes.id, apto.id!, tipo, r.valor, fotoPath: caminho, editadoManual: foiEditada);
    _lei[chave(apto.id!, tipo)] = Leitura(apto.id!, tipo, r.valor, caminho, foiEditada);
    if (!mounted) return;

    final msg = ScaffoldMessenger.of(context);
    msg.hideCurrentSnackBar();
    msg.showSnackBar(SnackBar(
      duration: const Duration(seconds: 4),
      content: Text('Leitura salva · Apto ${apto.numero}'),
      action: SnackBarAction(label: 'Desfazer', onPressed: () => _desfazer(i, apto, tipo, antes)),
    ));

    final prox = _proximoPendente();
    if (prox == null) {
      Navigator.pop(context);
      return;
    }
    setState(() => _i = prox);
    await _retomar();
  }

  Future<void> _desfazer(int i, Apto apto, String tipo, Leitura? antes) async {
    final atual = _lei[chave(apto.id!, tipo)];
    if (atual?.fotoPath != null) File(atual!.fotoPath!).delete().ignore();
    if (antes != null) {
      await Db.i.salvarLeitura(widget.mes.id, apto.id!, tipo, antes.valor, fotoPath: antes.fotoPath, editadoManual: antes.editadoManual);
      _lei[chave(apto.id!, tipo)] = antes;
    } else {
      await Db.i.removerLeitura(widget.mes.id, apto.id!, tipo);
      _lei.remove(chave(apto.id!, tipo));
    }
    if (mounted) setState(() => _i = i);
  }

  int? _proximoPendente() {
    final n = widget.aptos.length;
    for (var k = 1; k <= n; k++) {
      final idx = (_i + k) % n;
      if (!_lei.containsKey(chave(widget.aptos[idx].id!, widget.tipo))) return idx;
    }
    return null;
  }

  Future<void> _retomar() async {
    _voto.limpar();
    _vistos.clear();
    _ultimoLido = null;
    _rejeitada = null;
    _cand = null;
    _travado = false;
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) return;
    try {
      await cam.startImageStream(_quadro);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _trocar(int d) {
    if (_travado) return;
    setState(() {
      _i = (_i + d) % widget.aptos.length;
      if (_i < 0) _i += widget.aptos.length;
      _voto.limpar();
      _vistos.clear();
      _ultimoLido = null;
      _rejeitada = null;
      _cand = null;
    });
  }

  // ---------- interface
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final cam = _cam;
    final pronto = cam != null && cam.value.isInitialized;
    final cor = p.doTipo(widget.tipo);
    const branco = Color(0xFFFFFFFF);
    const faixa = Color(0x8C000000);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -250) _trocar(1);
          if (v > 250) _trocar(-1);
        },
        onTapUp: pronto ? (d) => _focar(d.localPosition) : null,
        child: Stack(children: [
          if (pronto)
            Positioned.fill(
              child: LayoutBuilder(builder: (ctx, bc) {
                final ps = cam.value.previewSize!; // paisagem; em pé = invertido
                final w = ps.height, h = ps.width;
                return Stack(children: [
                  ClipRect(
                    child: SizedBox.expand(
                      child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: w, height: h, child: CameraPreview(cam))),
                    ),
                  ),
                  if (!_travado)
                    CustomPaint(size: bc.biggest, painter: _CaixaPainter(const Rect.fromLTRB(0, 0, 0, 0), _tam, cor, guia: Rect.fromLTRB(faixaX0 * _tam.width, faixaY0 * _tam.height, faixaX1 * _tam.width, faixaY1 * _tam.height), achou: _cand != null)),
                  if (_cand != null && !_travado)
                    CustomPaint(size: bc.biggest, painter: _CaixaPainter(_cand!.box, _tam, cor)),
                ]);
              }),
            ),
          if (_erro != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_erro!, textAlign: TextAlign.center, style: const TextStyle(color: branco, fontSize: 17)),
                  const SizedBox(height: 20),
                  SizedBox(width: 220, child: BotaoAcao('Tentar de novo', onTap: () { setState(() => _erro = null); _iniciar(); })),
                  const SizedBox(height: 12),
                  SizedBox(width: 220, child: BotaoAcao('Digitar leitura', onTap: _digitar)),
                ]),
              ),
            ),
          // barra superior
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: faixa,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 56,
                  child: Row(children: [
                    _botao(Icons.close, 'Fechar', () => Navigator.pop(context)),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: context.dur,
                        child: Column(
                          key: ValueKey(_i),
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Apto ${_apto.numero}', style: const TextStyle(color: branco, fontSize: 17, fontWeight: FontWeight.w600)),
                            Text('$_nomeTipo · ${_lei.containsKey(_chave) ? 'já lido' : '${_i + 1} de ${widget.aptos.length}'}',
                                style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13, fontFeatures: [FontFeature.tabularFigures()])),
                          ],
                        ),
                      ),
                    ),
                    _botao(Icons.keyboard_outlined, 'Digitar leitura', _digitar),
                    _botao(_lanterna ? Icons.flashlight_on : Icons.flashlight_off, 'Lanterna', () {
                      _lanternaManual = true;
                      _definirLanterna(!_lanterna);
                    }),
                  ]),
                ),
              ),
            ),
          ),
          // dica inferior
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              color: faixa,
              child: SafeArea(
                top: false,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (pronto)
                    SizedBox(
                      height: 44,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        GestureDetector(
                          onTap: _capturarAgora,
                          child: Container(
                            height: 44, padding: const EdgeInsets.symmetric(horizontal: 16), alignment: Alignment.center,
                            child: const Text('Capturar', style: TextStyle(color: branco, fontSize: 15, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        for (final z in [1.0, 2.0, 3.0].where((z) => z <= _zmax + 0.01))
                          GestureDetector(
                            onTap: () => _aplicarZoom(z),
                            child: Container(
                              width: 52, height: 44, alignment: Alignment.center,
                              child: Text('${z.toInt()}×', style: TextStyle(color: (_zoom - z).abs() < 0.1 ? cor : branco, fontSize: 15, fontWeight: FontWeight.w600)),
                            ),
                          ),
                      ]),
                    ),
                  SizedBox(
                    height: 56,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          _lendoFoto
                              ? 'Lendo a foto…'
                              : _cand != null
                              ? fmtNum(_cand!.valor)
                              : _rejeitada != null
                                  ? 'Fora do esperado: ${fmtNum(_rejeitada)} · se estiver certo, use o teclado'
                                  : (pronto ? 'Encaixe os dígitos pretos na moldura · toque para focar' : ''),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _cand == null && _rejeitada != null ? p.aviso : branco, fontSize: _cand != null ? 22 : 13, fontWeight: _cand != null ? FontWeight.w600 : FontWeight.w400, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _botao(IconData i, String dica, VoidCallback f) => SizedBox(
        width: 48, height: 48,
        child: IconButton(icon: Icon(i, color: Colors.white), tooltip: dica, onPressed: f),
      );
}

class _CaixaPainter extends CustomPainter {
  final Rect box;
  final Size img;
  final Color cor;
  final Rect? guia; // moldura fixa de leitura
  final bool achou;
  _CaixaPainter(this.box, this.img, this.cor, {this.guia, this.achou = false});

  @override
  void paint(Canvas canvas, Size s) {
    final k = (s.width / img.width) > (s.height / img.height) ? s.width / img.width : s.height / img.height;
    final dx = (s.width - img.width * k) / 2, dy = (s.height - img.height * k) / 2;
    if (guia != null) {
      final g = Rect.fromLTRB(guia!.left * k + dx, guia!.top * k + dy, guia!.right * k + dx, guia!.bottom * k + dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(g, const Radius.circular(10)),
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = achou ? cor : const Color(0x99FFFFFF),
      );
      return;
    }
    final r = Rect.fromLTRB(box.left * k + dx, box.top * k + dy, box.right * k + dx, box.bottom * k + dy).inflate(6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r, const Radius.circular(4)),
      Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = cor,
    );
  }

  @override
  bool shouldRepaint(_CaixaPainter o) => o.box != box || o.img != img || o.cor != cor || o.achou != achou;
}

// Trabalho pesado em outro isolate. Ficam em funções de topo DE PROPÓSITO:
// um closure criado dentro de um método do State leva o State junto (com a
// câmera, que não pode ir para outro isolate) e o Isolate.run falha sempre.
Future<List<LinhaDigitos>> acharLinhasIsolado(Faixa faixa, int? alturaPrevista, [Dica? dica]) =>
    Isolate.run(() => acharLinhas(faixa, alturaPrevista: alturaPrevista, dica: dica));

Future<({List<LinhaDigitos> linhas, int w, int h})> _linhasDaFotoIsolado(String origem, double aspecto) =>
    Isolate.run(() => _linhasDaFoto(origem, aspecto));

Future<void> _recortarIsolado(String origem, Rect norm, String dest, double aspecto) =>
    Isolate.run(() => _recortar(origem, norm, dest, aspecto));

/// Retângulo [norm] (frações do quadro em pé da prévia) em pixels da foto.
/// O quadro da prévia é um recorte central da foto quando os formatos diferem
/// (ex.: prévia 16:9, foto 4:3).
Rect _naFoto(Rect norm, int fw, int fh, double aspecto) {
  var vw = fw.toDouble(), vh = fh.toDouble();
  if (fw / fh > aspecto) {
    vw = fh * aspecto;
  } else {
    vh = fw / aspecto;
  }
  final ox = (fw - vw) / 2, oy = (fh - vh) / 2;
  return Rect.fromLTRB(ox + norm.left * vw, oy + norm.top * vh, ox + norm.right * vw, oy + norm.bottom * vh);
}

img.Image _abrirFoto(String origem) {
  final bruta = img.decodeImage(File(origem).readAsBytesSync());
  if (bruta == null) throw StateError('foto ilegível');
  return img.bakeOrientation(bruta);
}

/// Largura da faixa no quadro ao vivo (1080 × 0,8): a foto é reduzida a ela
/// para os dígitos terem o mesmo tamanho em pixels nos dois caminhos.
const _larguraFaixa = 864;

({List<LinhaDigitos> linhas, int w, int h}) _linhasDaFoto(String origem, double aspecto) {
  final foto = _abrirFoto(origem);
  final r = _naFoto(const Rect.fromLTRB(faixaX0, faixaY0, faixaX1, faixaY1), foto.width, foto.height, aspecto);
  var band = img.copyCrop(foto, x: r.left.round(), y: r.top.round(), width: r.width.round(), height: r.height.round());
  band = img.copyResize(band, width: _larguraFaixa, interpolation: img.Interpolation.linear);
  final rgba = band.convert(numChannels: 4).getBytes(order: img.ChannelOrder.rgba);
  return (linhas: acharLinhas(faixaDeRgba(rgba, band.width, band.height)), w: band.width, h: band.height);
}

/// Recorta a foto em volta dos dígitos (frações do quadro da prévia) e grava em JPEG.
void _recortar(String origem, Rect norm, String dest, double aspecto) {
  final foto = _abrirFoto(origem);
  final w = foto.width, h = foto.height;
  final folga = Rect.fromLTRB(norm.left - norm.width * 0.12, norm.top - norm.height * 0.35, norm.right + norm.width * 0.12, norm.bottom + norm.height * 0.35);
  final r = _naFoto(folga, w, h, aspecto);
  final x0 = r.left.round().clamp(0, w - 1), y0 = r.top.round().clamp(0, h - 1);
  final x1 = r.right.round().clamp(x0 + 1, w), y1 = r.bottom.round().clamp(y0 + 1, h);
  var rec = img.copyCrop(foto, x: x0, y: y0, width: x1 - x0, height: y1 - y0);
  if (rec.width > 800) rec = img.copyResize(rec, width: 800);
  File(dest).writeAsBytesSync(img.encodeJpg(rec, quality: 82));
}

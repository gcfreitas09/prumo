// Laboratório de OCR no iPhone (rodar com tool/ocr_lab.sh). Simula quadros da câmera a partir
// dos prints em assets/ocr_teste/, roda o caminho de produção (faixaDoQuadro →
// acharLinhas → ML Kit → digitosDaLinha) e grava Documents/ocr_results.txt.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'package:leituras_predio/digitos.dart';
import 'package:leituras_predio/ocr.dart';

/// Quadro como o iPhone entrega (medido no aparelho): BGRA em pé, 1080×1920,
/// 4352 bytes por linha.
Uint8List _quadroDoPrint(img.Image print, double escala) {
  const w = 1080, h = 1920, bpr = 4352;
  final r = img.copyResize(print, width: (print.width / (escala * 1.331)).round(), interpolation: img.Interpolation.linear);
  final dx = (w - r.width) ~/ 2, dy = (0.47 * h - 0.455 * r.height).round();
  final out = Uint8List(bpr * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = x - dx, py = y - dy;
      final o = y * bpr + x * 4;
      if (px < 0 || py < 0 || px >= r.width || py >= r.height) {
        out[o] = out[o + 1] = out[o + 2] = 128;
      } else {
        final p = r.getPixel(px, py);
        out[o] = p.b.toInt();
        out[o + 1] = p.g.toInt();
        out[o + 2] = p.r.toInt();
      }
      out[o + 3] = 255;
    }
  }
  return out;
}

/// Quadro do iPhone com a [foto] posta de modo que o ponto ([cx], [cy]) caia no
/// centro da moldura, ampliada [zoom]× (medidor de gás: foto real, sem prints).
Uint8List _quadroDeFoto(img.Image foto, double cx, double cy, double zoom) {
  const w = 1080, h = 1920, bpr = 4352;
  final r = img.copyResize(foto, width: (foto.width * zoom).round(), interpolation: img.Interpolation.linear);
  final dx = (w / 2 - cx * r.width).round(), dy = (0.47 * h - cy * r.height).round();
  final out = Uint8List(bpr * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = x - dx, py = y - dy;
      final o = y * bpr + x * 4;
      if (px < 0 || py < 0 || px >= r.width || py >= r.height) {
        out[o] = out[o + 1] = out[o + 2] = 30;
      } else {
        final p = r.getPixel(px, py);
        out[o] = p.b.toInt();
        out[o + 1] = p.g.toInt();
        out[o + 2] = p.r.toInt();
      }
      out[o + 3] = 255;
    }
  }
  return out;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('rodando OCR…')))));
  final dir = await getApplicationDocumentsDirectory();
  final resultado = File('${dir.path}/ocr_results.txt');
  if (resultado.existsSync()) resultado.deleteSync();
  final rec = TextRecognizer(script: TextRecognitionScript.latin);
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final nomes = manifest.listAssets().where((a) => a.startsWith('test/fixtures/')).toList()..sort();
  final out = StringBuffer();
  var ok = 0, total = 0;
  for (final n in nomes) {
   try {
    final ehGas = n.contains('gas_lao');
    final ehGasCamera = n.contains('gas_camera');
    final ehGasCamera2 = n.contains('gas_camera2');
    final bytesImg = (await rootBundle.load(n)).buffer.asUint8List();
    final base = ehGas ? img.decodeJpg(bytesImg)! : img.decodePng(bytesImg)!;
    // o 2º print do app é menor (738 px): usa o posicionamento por foto
    final variantes = <String, img.Image>{
      'base': base.clone(),
      'escuro': img.adjustColor(base.clone(), brightness: 0.5),
      'blur': img.gaussianBlur(base.clone(), radius: 2),
      'giro3': img.copyRotate(base.clone(), angle: 3, interpolation: img.Interpolation.linear),
    };
    for (final v in variantes.entries) {
      for (final esc in (ehGas ? [1.3, 1.2, 1.15] : ehGasCamera ? [1.0, 1.1, 0.9] : [1.6, 1.33, 1.0, 0.8])) { // água: >1 = dígitos menores; gás: zoom da foto
        total++;
        final quadro = ehGas ? _quadroDeFoto(v.value, 0.475, 0.327, esc) : ehGasCamera2 ? _quadroDeFoto(v.value, 0.45, 0.347, esc * 1.2) : _quadroDoPrint(v.value, esc);
        final t0 = DateTime.now();
        final fq = faixaDoQuadro(bytes: quadro, width: 1080, height: 1920, bytesPerRow: 4352, bgra: true, rot: rotacaoDoQuadro(1080, 1920, 90))!;
        final t1 = DateTime.now();
        final faixa = fq.faixa;
        final linhas = await Isolate.run(() => acharLinhas(faixa));
        final t2 = DateTime.now();
        String? lido;
        final textos = <String>[];
        for (final l in linhas) {
          final r = await rec.processImage(InputImage.fromBytes(
            bytes: cinzaParaBgra(l.imagem, l.largura, l.altura),
            metadata: InputImageMetadata(size: Size(l.largura.toDouble(), l.altura.toDouble()), rotation: InputImageRotation.rotation0deg, format: InputImageFormat.bgra8888, bytesPerRow: l.largura * 4),
          ));
          final ls = [for (final b in r.blocks) ...b.lines]..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
          final txt = ls.map((x) => x.text).join();
          textos.add('${l.claro ? 'C' : 'E'}${l.n}:"$txt"');
          lido = digitosDaLinha(txt, l.n);
          if (lido != null) break;
        }
        final t3 = DateTime.now();
        // 701: último rolete parado entre 8 e 9 — qualquer um dos dois está certo
        final certos = n.contains('701') ? const ['268958', '268959'] : const ['076360'];
        final certo = ehGas
            ? (lido != null && lido.startsWith('0146180'))
            : ehGasCamera2
                ? (lido != null && lido.length == 8 && lido.startsWith('0146404'))
                : ehGasCamera
                ? (lido != null && lido.length == 8 && lido.startsWith('0146185'))
                : certos.contains(lido);
        if (certo) ok++;
        out.writeln('${n.split('/').last} ${v.key} esc=$esc → ${lido ?? '—'}  [${textos.join(' ')}]  faixa ${t1.difference(t0).inMilliseconds}ms · linhas ${t2.difference(t1).inMilliseconds}ms · ocr ${t3.difference(t2).inMilliseconds}ms');
      }
    }
   } catch (e, st) {
    out.writeln('${n.split('/').last} ERRO $e ${st.toString().split('\n').take(3).join(' | ')}');
   }
  }
  out.writeln('CERTOS $ok/$total');
  await rec.close();
  resultado.writeAsStringSync(out.toString());
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text('feito $ok/$total')))));
}

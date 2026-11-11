// TEMPORÁRIO: registro de diagnóstico da câmera em Documents/camlog.txt
// (puxar com `xcrun devicectl device copy from ... --source Documents/camlog.txt`).
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class Diag {
  static File? _f;
  static Directory? _d;
  static int _n = 0;

  static Future<void> iniciar() async {
    _d = await getApplicationDocumentsDirectory();
    _f = File('${_d!.path}/camlog.txt')..writeAsStringSync('--- ${DateTime.now()}\n');
    _n = 0;
  }

  static void log(String m) {
    final f = _f;
    if (f == null || _n++ > 600) return;
    final t = DateTime.now().toIso8601String().substring(11, 23);
    f.writeAsStringSync('$t $m\n', mode: FileMode.append);
  }

  static void cinza(String nome, Uint8List g, int w, int h) {
    final d = _d;
    if (d == null) return;
    final im = img.Image.fromBytes(width: w, height: h, bytes: g.buffer, numChannels: 1);
    File('${d.path}/$nome.png').writeAsBytesSync(img.encodePng(im));
  }
}

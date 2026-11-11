import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Paleta nomeada pelo que a cor é (claro/escuro).
class Paleta extends ThemeExtension<Paleta> {
  final Color fundo, fundo2, fio, texto, texto2, acao, agua, gas, vazio, ok, aviso, erro, latao;
  const Paleta({
    required this.fundo, required this.fundo2, required this.fio, required this.texto,
    required this.texto2, required this.acao, required this.agua, required this.gas,
    required this.vazio, required this.ok, required this.aviso, required this.erro, required this.latao,
  });

  static const claro = Paleta(
    fundo: Color(0xFFFFFFFF), fundo2: Color(0xFFEFEFED), fio: Color(0xFFE6E6E3),
    texto: Color(0xFF111111), texto2: Color(0xFF6E6E73), acao: Color(0xFF1F4647),
    agua: Color(0xFF2B7BD6), gas: Color(0xFFDD6B2B), vazio: Color(0xFFE7E7E4),
    ok: Color(0xFF2E9D5B), aviso: Color(0xFFC98A0B), erro: Color(0xFFD93A3A), latao: Color(0xFFB8893A),
  );
  static const escuro = Paleta(
    fundo: Color(0xFF0B0B0C), fundo2: Color(0xFF1C1C1E), fio: Color(0xFF2C2C2E),
    texto: Color(0xFFF5F5F4), texto2: Color(0xFF98989F), acao: Color(0xFF7FBFB4),
    agua: Color(0xFF4C9BFF), gas: Color(0xFFFF8C4A), vazio: Color(0xFF2C2C2E),
    ok: Color(0xFF3CCB7A), aviso: Color(0xFFF2BD45), erro: Color(0xFFFF6961), latao: Color(0xFFD9B060),
  );

  Color doTipo(String tipo) => tipo == 'agua' ? agua : gas;

  @override
  Paleta copyWith() => this;
  @override
  Paleta lerp(ThemeExtension<Paleta>? other, double t) => this;
}

const fundoAbertura = Color(0xFF17191B);
const _tab = [FontFeature.tabularFigures()];

extension TemaCtx on BuildContext {
  Paleta get p => Theme.of(this).extension<Paleta>()!;
  bool get semAnimacao => MediaQuery.of(this).disableAnimations;
  Duration get dur => semAnimacao ? Duration.zero : const Duration(milliseconds: 200);

  TextStyle get titulo => TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: p.texto, height: 1.12, fontFeatures: _tab);
  TextStyle get leitura => TextStyle(fontSize: 44, fontWeight: FontWeight.w600, color: p.texto, fontFeatures: _tab);
  TextStyle get corpo => TextStyle(fontSize: 17, color: p.texto, fontFeatures: _tab);
  TextStyle get legenda => TextStyle(fontSize: 13, color: p.texto2, fontFeatures: _tab);
}

ThemeData montarTema(Brightness b) {
  final p = b == Brightness.dark ? Paleta.escuro : Paleta.claro;
  return ThemeData(
    brightness: b,
    useMaterial3: true,
    scaffoldBackgroundColor: p.fundo,
    colorScheme: ColorScheme.fromSeed(seedColor: p.acao, brightness: b).copyWith(
      primary: p.acao, surface: p.fundo, onSurface: p.texto, error: p.erro,
    ),
    extensions: [p],
    splashFactory: NoSplash.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: p.fundo, foregroundColor: p.texto, elevation: 0,
      scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating, elevation: 0, backgroundColor: p.texto,
      contentTextStyle: TextStyle(color: p.fundo, fontSize: 15),
      actionTextColor: p.fundo,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: p.fio, thickness: 0.5, space: 0.5),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: p.fundo2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}

/// Botão principal: largo, 52 de altura, sem sombra.
class BotaoAcao extends StatelessWidget {
  final String texto;
  final VoidCallback? onTap;
  const BotaoAcao(this.texto, {super.key, this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return SizedBox(
      height: 52, width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: onTap == null ? p.vazio : p.acao,
          foregroundColor: p.fundo,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(texto, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: onTap == null ? p.texto2 : p.fundo)),
      ),
    );
  }
}

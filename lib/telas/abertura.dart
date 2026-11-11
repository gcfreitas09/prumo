import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../tema.dart';

/// Vídeo de abertura sobre o app, só na abertura a frio. Toque pula.
class Abertura extends StatefulWidget {
  final Widget child;
  const Abertura({super.key, required this.child});
  @override
  State<Abertura> createState() => _AberturaState();
}

class _AberturaState extends State<Abertura> {
  static bool _jaTocou = false; // sobrevive a rebuilds; zera só em nova abertura a frio
  VideoPlayerController? _c;
  bool _ativa = !_jaTocou;
  bool _some = false;

  @override
  void initState() {
    super.initState();
    _jaTocou = true;
    if (_ativa) _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      final c = VideoPlayerController.asset('assets/abertura_splash.mp4');
      _c = c;
      await c.initialize();
      await c.setVolume(0);
      c.addListener(() {
        if (c.value.isInitialized && !c.value.isPlaying && c.value.position >= c.value.duration) _fim();
      });
      if (!mounted) return;
      setState(() {});
      await c.setPlaybackSpeed(1.3); // vídeo já cortado (5,8 s) → ~4,5 s
      await c.play();
    } catch (_) {
      _fim(imediato: true); // asset ausente ou erro: segue direto para o app
    }
  }

  void _fim({bool imediato = false}) {
    if (!mounted || _some) return;
    setState(() => _some = true);
    if (imediato) setState(() => _ativa = false);
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ativa) return widget.child;
    final c = _c;
    final pronto = c != null && c.value.isInitialized;
    final dur = context.semAnimacao ? Duration.zero : const Duration(milliseconds: 300);
    return Stack(children: [
      widget.child,
      Positioned.fill(
        child: AnimatedOpacity(
          opacity: _some ? 0 : 1,
          duration: dur,
          onEnd: () {
            if (_some && mounted) setState(() => _ativa = false);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _fim,
            child: ColoredBox(
              color: fundoAbertura,
              child: pronto
                  ? LayoutBuilder(builder: (ctx, bc) {
                      // proporção original do vídeo (sem esticar), levemente ampliado;
                      // as bordas esmaecem no fundo, então não sobra moldura quadrada
                      final w = bc.maxWidth, h = w / c.value.aspectRatio;
                      return Center(
                        child: Transform.scale(
                          scale: 1.15,
                          child: SizedBox(width: w, height: h, child: _Esfumado(child: VideoPlayer(c))),
                        ),
                      );
                    })
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Esmaece as quatro bordas do vídeo no fundo da abertura: sem moldura quadrada.
class _Esfumado extends StatelessWidget {
  final Widget child;
  const _Esfumado({required this.child});

  static ShaderMask _faixa(Widget filho, Axis eixo, double borda) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => LinearGradient(
          begin: eixo == Axis.horizontal ? Alignment.centerLeft : Alignment.topCenter,
          end: eixo == Axis.horizontal ? Alignment.centerRight : Alignment.bottomCenter,
          colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
          stops: [0, borda, 1 - borda, 1],
        ).createShader(r),
        child: filho,
      );

  @override
  Widget build(BuildContext context) => _faixa(_faixa(child, Axis.horizontal, 0.2), Axis.vertical, 0.26);
}

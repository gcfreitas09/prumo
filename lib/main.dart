import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'conta.dart';
import 'db.dart';
import 'tema.dart';
import 'telas/abertura.dart';
import 'telas/config.dart';
import 'telas/entrada.dart';
import 'telas/mes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await Db.i.abrir();
    try {
      await Conta.i.iniciar();
    } catch (e) {
      debugPrint('Firebase não iniciou: $e');
    }
    final predio = await Db.i.predio();
    final usuario = await Db.i.usuario();
    final conta = Conta.i.atual;
    // com Firebase: logado = conta confirmada (a sessão fica salva e vale offline);
    // sem Firebase: basta a entrada local
    final logado = Conta.i.configurada ? (conta?.verificado ?? false) : usuario != null;
    if (logado && conta != null && usuario == null) {
      await Db.i.salvarUsuario(Usuario(conta.nome.isEmpty ? conta.email.split('@').first : conta.nome, conta.email));
    }
    final aVerificar = Conta.i.configurada && conta != null && !conta.verificado;
    runApp(LeiturasApp(configurado: predio != null, logado: logado, modoInicial: aVerificar ? Modo.verificar : Modo.entrar));
  } catch (_) {
    runApp(const _ErroInicial());
  }
}

class LeiturasApp extends StatelessWidget {
  final bool configurado, logado;
  final Modo modoInicial;
  const LeiturasApp({super.key, required this.configurado, required this.logado, this.modoInicial = Modo.entrar});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prumo',
      debugShowCheckedModeBanner: false,
      theme: montarTema(Brightness.light),
      darkTheme: montarTema(Brightness.dark),
      themeMode: ThemeMode.system,
      builder: (context, child) => Abertura(child: child!),
      home: !logado
          ? TelaEntrada(temPredio: configurado, modoInicial: modoInicial)
          : configurado ? const TelaMes() : const TelaConfig(primeiraVez: true),
    );
  }
}

class _ErroInicial extends StatelessWidget {
  const _ErroInicial();
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: montarTema(Brightness.light),
        darkTheme: montarTema(Brightness.dark),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Não foi possível abrir o banco de dados do aparelho. Feche e abra o app de novo; se continuar, libere espaço no aparelho.',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
            ),
          ),
        ),
      );
}

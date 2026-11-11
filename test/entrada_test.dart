import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leituras_predio/tema.dart';
import 'package:leituras_predio/telas/entrada.dart';

void main() {
  for (final escuro in [false, true]) {
    testWidgets('entrada ${escuro ? 'escuro' : 'claro'}: prumo se acomoda e o formulário aparece', (t) async {
      t.view.physicalSize = const Size(780, 1688);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: montarTema(escuro ? Brightness.dark : Brightness.light),
        home: const TelaEntrada(temPredio: false),
      ));
      for (final ms in [150, 450, 900, 1500]) {
        await t.pump(Duration(milliseconds: ms == 150 ? 150 : ms == 450 ? 300 : ms == 900 ? 450 : 600));
      }
      await t.pumpAndSettle();
      expect(find.text('Começar'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });
  }

  testWidgets('entrada valida nome e e-mail antes de seguir', (t) async {
    await t.pumpWidget(MaterialApp(theme: montarTema(Brightness.light), home: const TelaEntrada(temPredio: false)));
    await t.pumpAndSettle();
    await t.tap(find.text('Começar'));
    await t.pump();
    expect(find.text('Digite o seu nome.'), findsOneWidget);
    await t.enterText(find.byType(TextField).first, 'Ana');
    await t.enterText(find.byType(TextField).last, 'ana@');
    await t.tap(find.text('Começar'));
    await t.pump();
    expect(find.textContaining('E-mail inválido'), findsOneWidget);
  });

  testWidgets('sem animação (acessibilidade): já entra no estado final', (t) async {
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(theme: montarTema(Brightness.light), home: const TelaEntrada(temPredio: false)),
    ));
    await t.pump();
    expect(find.text('Prumo'), findsOneWidget);
  });
}

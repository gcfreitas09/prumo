import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class Predio {
  final String nome;
  final String emails;
  final bool incluirConsumo;
  const Predio(this.nome, this.emails, this.incluirConsumo);
  /// No máximo 2 destinatários distintos (o relatório vai para até dois e-mails).
  List<String> get listaEmails {
    final vistos = <String>{};
    return [
      for (final e in emails.split(RegExp(r'[,;\s]+')))
        if (e.contains('@') && vistos.add(e.toLowerCase())) e,
    ].take(2).toList();
  }
}

/// Quem usa o app (síndico). Fica só neste aparelho.
class Usuario {
  final String nome, email;
  const Usuario(this.nome, this.email);
}

class Apto {
  final int? id;
  final String numero;
  final int andar;
  final int ordemApto;
  final int ordemLeitura;
  final bool ativo;
  const Apto({this.id, required this.numero, required this.andar, required this.ordemApto, required this.ordemLeitura, this.ativo = true});

  Apto copiar({String? numero, int? ordemLeitura, bool? ativo}) => Apto(
        id: id, numero: numero ?? this.numero, andar: andar, ordemApto: ordemApto,
        ordemLeitura: ordemLeitura ?? this.ordemLeitura, ativo: ativo ?? this.ativo);

  factory Apto.doMapa(Map<String, Object?> m) => Apto(
        id: m['id'] as int, numero: m['numero'] as String, andar: m['andar'] as int,
        ordemApto: m['ordem_apto'] as int, ordemLeitura: m['ordem_leitura'] as int,
        ativo: (m['ativo'] as int) == 1);

  Map<String, Object?> paraMapa() => {
        'numero': numero, 'andar': andar, 'ordem_apto': ordemApto,
        'ordem_leitura': ordemLeitura, 'ativo': ativo ? 1 : 0,
      };
}

class Mes {
  final int id, ano, mes;
  final DateTime? enviadoEm;
  const Mes(this.id, this.ano, this.mes, this.enviadoEm);
}

class Leitura {
  final int aptoId;
  final String tipo;
  final String valor;
  final String? fotoPath;
  final bool editadoManual;
  const Leitura(this.aptoId, this.tipo, this.valor, this.fotoPath, this.editadoManual);
  int? get numero => int.tryParse(valor.split(',').first); // m³ inteiros
}

typedef Leituras = Map<String, Leitura>;
String chave(int aptoId, String tipo) => '$aptoId|$tipo';

class ResumoMes {
  final Mes mes;
  final int agua, gas;
  final int lidas, total;
  const ResumoMes(this.mes, this.agua, this.gas, this.lidas, this.total);
}

class Db {
  Db._();
  static final Db i = Db._();
  late Database _db;
  /// Muda a cada gravação/remoção de leitura; telas abertas recarregam.
  final versao = ValueNotifier<int>(0);

  Future<void> abrir() async {
    _db = await openDatabase(
      p.join(await getDatabasesPath(), 'leituras.db'),
      version: 2,
      onUpgrade: (d, antiga, _) async {
        if (antiga < 2) await _criarUsuario(d);
      },
      onCreate: (d, _) async {
        await _criarUsuario(d);
        await d.execute('CREATE TABLE predio(id INTEGER PRIMARY KEY, nome TEXT NOT NULL, emails_destino TEXT NOT NULL DEFAULT "", incluir_consumo INTEGER NOT NULL DEFAULT 1)');
        await d.execute('CREATE TABLE apartamento(id INTEGER PRIMARY KEY AUTOINCREMENT, numero TEXT NOT NULL, andar INTEGER NOT NULL, ordem_apto INTEGER NOT NULL, ordem_leitura INTEGER NOT NULL, ativo INTEGER NOT NULL DEFAULT 1)');
        await d.execute('CREATE TABLE mes_leitura(id INTEGER PRIMARY KEY AUTOINCREMENT, ano INTEGER NOT NULL, mes INTEGER NOT NULL, criado_em TEXT NOT NULL, enviado_em TEXT, UNIQUE(ano, mes))');
        await d.execute('CREATE TABLE leitura(id INTEGER PRIMARY KEY AUTOINCREMENT, mes_id INTEGER NOT NULL, apartamento_id INTEGER NOT NULL, tipo TEXT NOT NULL, valor TEXT NOT NULL, foto_path TEXT, lido_em TEXT NOT NULL, editado_manual INTEGER NOT NULL DEFAULT 0, UNIQUE(mes_id, apartamento_id, tipo))');
      },
    );
  }

  static Future<void> _criarUsuario(Database d) => d.execute('CREATE TABLE IF NOT EXISTS usuario(id INTEGER PRIMARY KEY, nome TEXT NOT NULL, email TEXT NOT NULL)');

  // ---- usuário
  Future<Usuario?> usuario() async {
    final r = await _db.query('usuario', limit: 1);
    return r.isEmpty ? null : Usuario(r.first['nome'] as String, r.first['email'] as String);
  }

  Future<void> removerUsuario() => _db.delete('usuario');

  Future<void> salvarUsuario(Usuario u) => _db.insert('usuario', {'id': 1, 'nome': u.nome, 'email': u.email}, conflictAlgorithm: ConflictAlgorithm.replace);

  // ---- prédio
  Future<Predio?> predio() async {
    final r = await _db.query('predio', limit: 1);
    if (r.isEmpty) return null;
    final m = r.first;
    return Predio(m['nome'] as String, m['emails_destino'] as String, (m['incluir_consumo'] as int) == 1);
  }

  Future<void> salvarPredio(Predio pr) => _db.insert('predio',
      {'id': 1, 'nome': pr.nome, 'emails_destino': pr.emails, 'incluir_consumo': pr.incluirConsumo ? 1 : 0},
      conflictAlgorithm: ConflictAlgorithm.replace);

  // ---- apartamentos
  Future<List<Apto>> aptos({bool soAtivos = true}) async {
    final r = await _db.query('apartamento',
        where: soAtivos ? 'ativo = 1' : null, orderBy: 'ordem_leitura, ordem_apto');
    return r.map(Apto.doMapa).toList();
  }

  Future<void> salvarAptos(List<Apto> lista) => _db.transaction((t) async {
        for (final a in lista) {
          if (a.id == null) {
            await t.insert('apartamento', a.paraMapa());
          } else {
            await t.update('apartamento', a.paraMapa(), where: 'id = ?', whereArgs: [a.id]);
          }
        }
      });

  // ---- meses
  Future<Mes> mesAtual() async {
    final n = DateTime.now();
    final r = await _db.query('mes_leitura', where: 'ano = ? AND mes = ?', whereArgs: [n.year, n.month]);
    if (r.isEmpty) {
      await _db.insert('mes_leitura', {'ano': n.year, 'mes': n.month, 'criado_em': n.toIso8601String()});
      return mesAtual();
    }
    return _mes(r.first);
  }

  Mes _mes(Map<String, Object?> m) => Mes(m['id'] as int, m['ano'] as int, m['mes'] as int,
      m['enviado_em'] == null ? null : DateTime.parse(m['enviado_em'] as String));

  Future<void> marcarEnviado(int mesId) => _db.update('mes_leitura',
      {'enviado_em': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [mesId]);

  // ---- leituras
  Leitura _leitura(Map<String, Object?> m) => Leitura(m['apartamento_id'] as int, m['tipo'] as String,
      m['valor'] as String, m['foto_path'] as String?, (m['editado_manual'] as int) == 1);

  Future<Leituras> leituras(int mesId) async {
    final r = await _db.query('leitura', where: 'mes_id = ?', whereArgs: [mesId]);
    return {for (final m in r) chave(m['apartamento_id'] as int, m['tipo'] as String): _leitura(m)};
  }

  Future<void> salvarLeitura(int mesId, int aptoId, String tipo, String valor,
      {String? fotoPath, bool editadoManual = false}) async {
    await _db.insert('leitura', {
        'mes_id': mesId, 'apartamento_id': aptoId, 'tipo': tipo, 'valor': valor,
        'foto_path': fotoPath, 'lido_em': DateTime.now().toIso8601String(),
        'editado_manual': editadoManual ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    versao.value++;
  }

  Future<void> removerLeitura(int mesId, int aptoId, String tipo) async {
    await _db.delete('leitura',
        where: 'mes_id = ? AND apartamento_id = ? AND tipo = ?', whereArgs: [mesId, aptoId, tipo]);
    versao.value++;
  }

  /// Leituras (valor inteiro) dos meses anteriores ao informado, mais recente primeiro.
  Future<List<int>> anteriores(int aptoId, String tipo, Mes mes, {int limite = 4}) async {
    final r = await _db.rawQuery(
        'SELECT l.valor FROM leitura l JOIN mes_leitura m ON m.id = l.mes_id '
        'WHERE l.apartamento_id = ? AND l.tipo = ? AND (m.ano * 12 + m.mes) < ? '
        'ORDER BY m.ano DESC, m.mes DESC LIMIT ?',
        [aptoId, tipo, mes.ano * 12 + mes.mes, limite]);
    return r.map((m) => int.tryParse((m['valor'] as String).split(',').first)).whereType<int>().toList();
  }

  /// Mapa "aptoId|tipo" → leituras anteriores (mais recente primeiro).
  Future<Map<String, List<int>>> historicoAnterior(Mes mes, List<Apto> aptos) async {
    final out = <String, List<int>>{};
    for (final a in aptos) {
      for (final t in const ['agua', 'gas']) {
        out[chave(a.id!, t)] = await anteriores(a.id!, t, mes);
      }
    }
    return out;
  }

  // ---- histórico
  Future<List<ResumoMes>> resumos() async {
    final meses = (await _db.query('mes_leitura', orderBy: 'ano DESC, mes DESC')).map(_mes).toList();
    final totalAptos = (await aptos()).length * 2;
    final linhas = await _db.query('leitura');
    final porMes = <int, Leituras>{};
    for (final m in linhas) {
      (porMes[m['mes_id'] as int] ??= {})[chave(m['apartamento_id'] as int, m['tipo'] as String)] = _leitura(m);
    }
    final out = <ResumoMes>[];
    for (var i = 0; i < meses.length; i++) {
      final atual = porMes[meses[i].id] ?? {};
      final prev = i + 1 < meses.length ? (porMes[meses[i + 1].id] ?? {}) : <String, Leitura>{};
      var agua = 0, gas = 0;
      atual.forEach((k, l) {
        final a = prev[k]?.numero, b = l.numero;
        if (a == null || b == null) return;
        if (l.tipo == 'agua') {
          agua += b - a;
        } else {
          gas += b - a;
        }
      });
      out.add(ResumoMes(meses[i], agua, gas, atual.length, totalAptos));
    }
    return out;
  }
}

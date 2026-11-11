# Prumo

App de leitura mensal dos medidores de água e gás de um prédio. O síndico fotografa cada medidor, o app lê os números e monta o PDF que vai por e-mail.

- **App (Flutter, iOS e Android):** `lib/`. A câmera lê ao vivo, com ML Kit, e funciona sem internet.
- **Webapp:** `web_app/`. Abre no navegador do iPhone, sem instalar: lê pela foto e usa o mesmo detector de dígitos do app, compilado para JavaScript.

Decisões, comandos e armadilhas estão em [AGENTS.md](AGENTS.md).

```bash
flutter pub get && flutter test      # app
bash web_app/montar.sh               # webapp → web_app/dist
node web_app/teste_logica.mjs && node web_app/teste_ocr.mjs
```

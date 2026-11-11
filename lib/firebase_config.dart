// Valores do projeto Firebase "Prumo" (console.firebase.google.com → Configurações
// do projeto → Seus apps). São identificadores públicos do app, não segredos.
// Enquanto estiverem vazios, o app usa a entrada local (nome + e-mail, sem senha).
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';

// iOS (GoogleService-Info.plist): API_KEY, GOOGLE_APP_ID, GCM_SENDER_ID, PROJECT_ID
const _iosApiKey = '';
const _iosAppId = '';
const _iosSenderId = '';
// Android (google-services.json): current_key, mobilesdk_app_id, project_number, project_id
const _androidApiKey = '';
const _androidAppId = '';
const _androidSenderId = '';
const _projectId = '';

const bundleIos = 'br.com.leituras.leiturasPredio';

/// Opções do Firebase para esta plataforma, ou null se ainda não configurado.
FirebaseOptions? opcoesFirebase() {
  if (Platform.isIOS && _iosApiKey.isNotEmpty && _iosAppId.isNotEmpty && _projectId.isNotEmpty) {
    return const FirebaseOptions(apiKey: _iosApiKey, appId: _iosAppId, messagingSenderId: _iosSenderId, projectId: _projectId, iosBundleId: bundleIos);
  }
  if (Platform.isAndroid && _androidApiKey.isNotEmpty && _androidAppId.isNotEmpty && _projectId.isNotEmpty) {
    return const FirebaseOptions(apiKey: _androidApiKey, appId: _androidAppId, messagingSenderId: _androidSenderId, projectId: _projectId);
  }
  return null;
}

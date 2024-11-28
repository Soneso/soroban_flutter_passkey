import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soroban_flutter_passkey/home_screen.dart';
import 'package:soroban_flutter_passkey/model/user_model.dart';
import 'package:soroban_flutter_passkey/services/auth_service.dart';
import 'package:soroban_flutter_passkey/services/navigation_service.dart';

import 'auth_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AuthService.credentialManager.isSupportedPlatform) {
    await AuthService.credentialManager.init(
      preferImmediatelyAvailableCredentials: true,
    );
  }

  await dotenv.load(fileName: ".env");

  UserModel? user;
  final prefs = await SharedPreferences.getInstance();
  final username = prefs.getString('sp:username');
  final contractId = prefs.getString('sp:contractId');
  final credentialsId = prefs.getString('sp:credentialsId');

  if (username != null && contractId != null && credentialsId != null) {
    user = UserModel(username: username,
        credentialsId: credentialsId,
        contractId: contractId);
  }
  runApp(MyApp(user));
}

class MyApp extends StatelessWidget {
  final UserModel? user;
  const MyApp(this.user, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: NavigationService.navigatorKey,
      home: user == null ?
      AuthScreen(
        key: Key('auth_screen'),
      ) : HomeScreen(user: user!),
    );
  }
}

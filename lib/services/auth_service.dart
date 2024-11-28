import 'dart:convert';

import 'package:credential_manager/credential_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'soroban_service.dart';
import 'package:stellar_flutter_sdk/stellar_flutter_sdk.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../model/user_model.dart';

class AuthService {

  static const String _challengeStr = "createchallenge";
  static final Codec<String, String> _stringToBase64Url = utf8.fuse(base64Url);

  static CredentialManager credentialManager = CredentialManager();

  static Future<UserModel> passKeyRegister(
      {required String username}) async {

    final authenticatorSelectionCriteria = AuthenticatorSelectionCriteria(
        requireResidentKey: false,
        residentKey: "preferred",
        userVerification: "discouraged",
        authenticatorAttachment: "platform");

    final user = User(
        id: _stringToBase64Url.encode(username),
        name: username,
        displayName: username);

    final credentialCreationOptions = CredentialCreationOptions(
      challenge: _stringToBase64Url.encode(_challengeStr),
      rp: Rp(name: "SoroPass", id: getRpId()),
      user: user,
      authenticatorSelection: authenticatorSelectionCriteria,
      pubKeyCredParams: [
        PublicKeyCredentialParameters(alg: -7, type: "public-key")
      ],
      attestation: "none",
      excludeCredentials: [],
    );

    final savedCredentials = await credentialManager
        .savePasskeyCredentials(request: credentialCreationOptions);

    if (savedCredentials.id == null) {
      throw Exception("Saved credentials have no id");
    }

    final credentialsId = savedCredentials.id!;

    if (savedCredentials.response == null) {
      return throw Exception("Could not extract attestation response from saved credentials");
    }

    final attestationResponse = AuthenticatorAttestationResponse.fromJson(savedCredentials.response!.toJson());

    final contractId = await SorobanService.handleDeploy(
        credentialsId: credentialsId,
        attestationResponse: attestationResponse);

    final userModel = UserModel(
        username: username,
        credentialsId: credentialsId,
        contractId: contractId);

    await save(userModel);
    return userModel;
  }

  static Future<UserModel> passKeyLogin() async {

    final credResponse =
    await credentialManager.getCredentials(
      passKeyOption: CredentialLoginOptions(
        challenge: _stringToBase64Url.encode(_challengeStr),
        rpId: getRpId(),
        userVerification: "discouraged",
      ),
      fetchOptions: FetchOptionsAndroid(
          passKey: true
      ),
    );

    if (credResponse.publicKeyCredential?.id == null) {
      throw Exception('Invalid passkey login response: publicKeyCredential.id not found');
    }

    final credentialsId = credResponse.publicKeyCredential!.id!;
    final contractId = await SorobanService.handleSignIn(credentialsId:credentialsId);
    var username = 'Friend';
    var userHandleB64 = credResponse.publicKeyCredential?.response?.userHandle;
    if (userHandleB64 != null) {
      username = _stringToBase64Url.decode(base64Url.normalize(userHandleB64));
    }
    final user = UserModel(
        username: username,
        credentialsId: credentialsId,
        contractId: contractId);

    await save(user);
    return user;
  }

  static String getRpId() {
    final value = dotenv.env['rp_id'];
    if (value == null) {
      throw Exception(".env file must contain rp_id");
    }
    return value;
  }

  static Future<void> logout() async {
    var prefs = await SharedPreferences.getInstance();
    prefs.remove('sp:bundler');
    prefs.remove('sp:contractId');
    prefs.remove('sp:credentialsId');
    prefs.remove('sp:username');
  }

  static Future<void> save(UserModel user) async {
    var prefs = await SharedPreferences.getInstance();
    prefs.setString('sp:credentialsId', user.credentialsId);
    prefs.setString('sp:username', user.username);
    prefs.setString('sp:contractId', user.contractId);
  }
}

import 'dart:developer';
import 'dart:convert';
import 'package:credential_manager/credential_manager.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soroban_flutter_passkey/auth_screen.dart';
import 'package:soroban_flutter_passkey/services/auth_service.dart';
import 'package:soroban_flutter_passkey/services/soroban_service.dart';

class VotingScreen extends StatefulWidget {
  const VotingScreen({super.key});

  @override
  State<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen> {

  bool isSigning = false;
  bool isChicken = true;
  bool isEgg = false;
  String? errorMessage;
  Votes? votes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vote',
            style: TextStyle(color: Colors.white)),
        actions: [
          ElevatedButton.icon(
            onPressed: () async {
              AuthService.logout();
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                      builder: (builder) => const AuthScreen(key: Key('auth_screen'))),
                      (predicate) => false);
            },
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.deepPurple,
              padding: const EdgeInsets.symmetric(
                  vertical: 12.0, horizontal: 24.0),
              textStyle: const TextStyle(fontSize: 20.0),
            ),
          ),
        ],
        backgroundColor: Colors.deepPurple,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text(
                'Which came first?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.deepPurple),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: chicken,
                    label: const Text('Chicken 🐔'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: isChicken ? Colors.white : Colors.black,
                      backgroundColor: isChicken ? Colors.deepPurple : Colors.grey,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12.0, horizontal: 24.0),
                      textStyle: const TextStyle(fontSize: 16.0),
                    ),
                  ),
                  const Text(
                    'OR',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.deepPurple),
                  ),
                  ElevatedButton.icon(
                    onPressed: egg,
                    label: const Text('Egg 🥚'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: isEgg ? Colors.white : Colors.black,
                      backgroundColor: isEgg ? Colors.deepPurple : Colors.grey,
                      padding: const EdgeInsets.symmetric(
                          vertical: 12.0, horizontal: 24.0),
                      textStyle: const TextStyle(fontSize: 16.0),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 60),
              if (isChicken || isEgg)
              ElevatedButton.icon(
                onPressed: sign,
                icon: isSigning
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(Icons.account_balance_wallet_sharp),
                label: isSigning
                    ? const SizedBox.shrink()
                    : const Text('Sign'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(
                      vertical: 12.0, horizontal: 24.0),
                  textStyle: const TextStyle(fontSize: 16.0),
                ),
              ),
              const SizedBox(height: 16),
              if (errorMessage != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
              const SizedBox(height: 60),
              if (votes != null)
                Column(
                  children: [
                    Text(
                      'All votes: ${votes!.allChicken} 🐔 and ${votes!.allEgg} 🥚',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.deepPurple),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your votes: ${votes!.sourceChicken} 🐔 and ${votes!.sourceEgg} 🥚',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.deepPurple),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> chicken() async {
    if (isSigning) {
      return;
    }

    setState(() {
      isChicken = !isChicken;
      isEgg = !isChicken;
      errorMessage = null;
    });
  }

  Future<void> egg() async {

    if (isSigning) {
      return;
    }

    setState(() {
      isEgg = !isEgg;
      isChicken = !isEgg;
      errorMessage = null;
    });
  }

  Future<void> sign() async {
    setState(() {
      isSigning = true;
      errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final contractId = prefs.getString('sp:contractId');
      if (contractId == null) {
        throw Exception("no contract found");
      }

      final voteBuildRes = await SorobanService.handleVoteBuild(
          accountContractId: contractId,
          vote: isChicken);

      final credResponse =
      await AuthService.credentialManager.getCredentials(
        passKeyOption: CredentialLoginOptions(
          challenge: base64UrlEncode(voteBuildRes.authHash.toList()),
          rpId: AuthService.getRpId(),
          userVerification: "discouraged",
        ),
        fetchOptions: FetchOptionsAndroid(
            passKey: true
        ),
      );

      if (credResponse.publicKeyCredential == null) {
        setState(() {
          isSigning = false;
          errorMessage = 'No credentials received from authenticator.';
        });
        return;
      }

      await SorobanService.handleVoteSend(
          authTxn: voteBuildRes.authTxn,
          lastLedger: voteBuildRes.lastLedger,
          signRes: credResponse.publicKeyCredential!);

      // wait a couple of seconds for the ledger to close
      await Future.delayed(Duration(seconds: 5));

      votes = await SorobanService.getVotes(
          accountContractId: contractId);

    } on CredentialException catch (e) {
      log("Error: ${e.message} ${e.code} ${e.details} ");
      setState(() {
        errorMessage = 'Error: ${e.message}';
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        isSigning = false;
      });
    }
  }
}

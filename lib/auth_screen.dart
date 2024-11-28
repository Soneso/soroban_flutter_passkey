import 'dart:developer';
import 'package:credential_manager/credential_manager.dart';
import 'package:flutter/material.dart';
import 'package:soroban_flutter_passkey/services/auth_service.dart';
import 'package:soroban_flutter_passkey/services/navigation_service.dart';

import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  String? username;
  bool isRegistering = false;
  bool isLoggingIn = false;
  String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SoroPass',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.deepPurple,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text(
                'Welcome to a passkey powered blockchain experience',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.deepPurple),
              ),
              const SizedBox(height: 24),
              TextField(
                onChanged: (value) {
                  setState(() {
                    username = value;
                    errorMessage = null;
                  });
                },
                decoration: const InputDecoration(
                  hintText: 'Enter your username',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person, color: Colors.deepPurple),
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
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: isRegistering ? null : register,
                icon: isRegistering
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(Icons.person_add),
                label: isRegistering
                    ? const SizedBox.shrink()
                    : const Text('Register'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(
                      vertical: 12.0, horizontal: 24.0),
                  textStyle: const TextStyle(fontSize: 16.0),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: isLoggingIn ? null : login,
                icon: isLoggingIn
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.white),
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(Icons.login),
                label:
                isLoggingIn ? const SizedBox.shrink() : const Text('Login'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(
                      vertical: 12.0, horizontal: 24.0),
                  textStyle: const TextStyle(fontSize: 16.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> register() async {
    if (username == null || username?.isEmpty == true) {
      setState(() {
        errorMessage = 'Please enter a username';
      });
      return;
    }

    // start registration
    setState(() {
      isRegistering = true;
      errorMessage = null;
    });

    try {
      final user = await AuthService.passKeyRegister(username: username!);
      Navigator.of(NavigationService.navigatorKey.currentContext!).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            user: user,
          ),
        ),
      );
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
        isRegistering = false;
      });
    }
  }

  Future<void> login() async {
    setState(() {
      isLoggingIn = true;
      errorMessage = null;
    });
    try {
      final user = await AuthService.passKeyLogin();
      Navigator.of(NavigationService.navigatorKey.currentContext!).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomeScreen(
            user: user,
          ),
        ),
      );
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        isLoggingIn = false;
      });
    }
  }
}

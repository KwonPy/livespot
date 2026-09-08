import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  // Dummy implementation for now since Firebase isn't initialized yet
  // final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> signInAnonymously() async {
    // await _auth.signInAnonymously();
    await Future.delayed(const Duration(seconds: 1));
  }

  Future<void> signOut() async {
    // await _auth.signOut();
  }
}

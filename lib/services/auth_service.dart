import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final FirebaseService _firebaseService = FirebaseService();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Sign up with email and password
  Future<UserCredential> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      print('Starting signup process...');
      print('Email: $email');
      print('Username: $username');

      // Validate input
      if (email.isEmpty || password.isEmpty || username.isEmpty) {
        throw Exception('All fields are required');
      }

      if (password.length < 6) {
        throw Exception('Password must be at least 6 characters');
      }

      if (username.length < 3) {
        throw Exception('Username must be at least 3 characters');
      }

      // Create user account
      print('Creating Firebase Auth user...');
      final UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user == null) {
        throw Exception('Failed to create user account');
      }

      final user = userCredential.user!;
      print('Firebase Auth user created with ID: ${user.uid}');

      // Update display name in Firebase Auth first
      print('Updating Firebase Auth display name...');
      await user.updateDisplayName(username);
      print('Firebase Auth display name updated');

      // Create user profile in Realtime Database
      print('Creating user profile in Realtime Database...');
      final userRef = _database.child('users').child(user.uid);
      print('Database reference path: ${userRef.path}');

      final Map<String, dynamic> userData = {
        'username': username,
        'email': email,
        'profileImageUrl': '',
        'bio': '',
        'createdAt': DateTime.now().toIso8601String(),
      };

      print('User data to be saved: $userData');

      // Set user data in Realtime Database
      print('Attempting to set user data...');
      await userRef.set(userData);
      print('User data set successfully');

      // Verify the user profile was created
      print('Verifying user profile creation...');
      final snapshot = await userRef.get();
      print('Snapshot exists: ${snapshot.exists}');
      print('Snapshot data: ${snapshot.value}');

      if (!snapshot.exists) {
        print('Error: User profile not found after creation attempt');
        throw Exception('Failed to create user profile in database');
      }

      print('User profile created successfully in Realtime Database');
      print('Signup process completed successfully');
      return userCredential;
    } on FirebaseAuthException catch (e) {
      print('Firebase Auth Exception: ${e.code} - ${e.message}');
      String message;
      switch (e.code) {
        case 'weak-password':
          message = 'The password provided is too weak.';
          break;
        case 'email-already-in-use':
          message = 'An account already exists for that email.';
          break;
        case 'invalid-email':
          message = 'The email address is not valid.';
          break;
        default:
          message = 'An error occurred during sign up: ${e.message}';
      }
      throw Exception(message);
    } catch (e) {
      print('Error during signup: $e');
      print('Error type: ${e.runtimeType}');
      print('Error stack trace: ${e.toString()}');
      throw Exception('Failed to create account: ${e.toString()}');
    }
  }

  // Sign in with email and password
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      print('Error signing in: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      // Clean up all database listeners
      await _firebaseService.cleanup();

      // Sign out from Firebase Auth
      await _auth.signOut();

      // Clear any cached data
      FirebaseDatabase.instance.goOffline();
      await Future.delayed(const Duration(milliseconds: 100));
      FirebaseDatabase.instance.goOnline();
    } catch (e) {
      print('Error signing out: $e');
      rethrow;
    }
  }

  // Update user profile
  Future<void> updateProfile({
    String? username,
    String? bio,
  }) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user logged in');

      // Update Realtime Database user document
      final updates = <String, dynamic>{};
      if (username != null) updates['username'] = username;
      if (bio != null) updates['bio'] = bio;

      await _database.child('users/${user.uid}').update(updates);

      // Update Firebase Auth display name if username changed
      if (username != null) {
        await user.updateDisplayName(username);
      }
    } catch (e) {
      print('Error updating profile: $e');
      rethrow;
    }
  }

  // Get user profile data
  Stream<DatabaseEvent> getUserProfile(String userId) {
    return _database.child('users/$userId').onValue;
  }
}

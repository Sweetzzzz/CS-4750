import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';

class AdminService {
  final FirebaseService _firebaseService = FirebaseService();
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  // Check if user is admin
  Future<bool> isAdmin(String userId) async {
    try {
      final snapshot = await _database.child('users/$userId/isAdmin').get();
      return snapshot.exists && snapshot.value == true;
    } catch (e) {
      debugPrint('Error checking admin status: $e');
      return false;
    }
  }

  // Make a user admin
  Future<bool> makeAdmin(String userId) async {
    try {
      // Check if current user is admin
      final currentUser = _firebaseService.currentUser;
      if (currentUser == null) return false;

      final isCurrentUserAdmin = await isAdmin(currentUser.uid);
      if (!isCurrentUserAdmin) return false;

      // Make user admin
      await _database.child('users/$userId/isAdmin').set(true);
      return true;
    } catch (e) {
      debugPrint('Error making user admin: $e');
      return false;
    }
  }

  // Remove admin status
  Future<bool> removeAdmin(String userId) async {
    try {
      // Check if current user is admin
      final currentUser = _firebaseService.currentUser;
      if (currentUser == null) return false;

      final isCurrentUserAdmin = await isAdmin(currentUser.uid);
      if (!isCurrentUserAdmin) return false;

      // Remove admin status
      await _database.child('users/$userId/isAdmin').remove();
      return true;
    } catch (e) {
      debugPrint('Error removing admin status: $e');
      return false;
    }
  }

  // Delete user account
  Future<bool> deleteUser(String userId) async {
    try {
      // Check if current user is admin
      final currentUser = _firebaseService.currentUser;
      if (currentUser == null) return false;

      final isCurrentUserAdmin = await isAdmin(currentUser.uid);
      if (!isCurrentUserAdmin) return false;

      // Delete user data
      await _database.child('users/$userId').remove();

      // Delete user's posts
      final postsSnapshot = await _database
          .child('posts')
          .orderByChild('userId')
          .equalTo(userId)
          .get();

      if (postsSnapshot.exists) {
        for (final child in postsSnapshot.children) {
          await _database.child('posts/${child.key}').remove();
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error deleting user: $e');
      return false;
    }
  }

  // Ban user
  Future<bool> banUser(String userId) async {
    try {
      // Check if current user is admin
      final currentUser = _firebaseService.currentUser;
      if (currentUser == null) return false;

      final isCurrentUserAdmin = await isAdmin(currentUser.uid);
      if (!isCurrentUserAdmin) return false;

      // Set user as banned
      await _database.child('users/$userId/isBanned').set(true);
      return true;
    } catch (e) {
      debugPrint('Error banning user: $e');
      return false;
    }
  }

  // Unban user
  Future<bool> unbanUser(String userId) async {
    try {
      // Check if current user is admin
      final currentUser = _firebaseService.currentUser;
      if (currentUser == null) return false;

      final isCurrentUserAdmin = await isAdmin(currentUser.uid);
      if (!isCurrentUserAdmin) return false;

      // Remove ban status
      await _database.child('users/$userId/isBanned').remove();
      return true;
    } catch (e) {
      debugPrint('Error unbanning user: $e');
      return false;
    }
  }

  // Delete post
  Future<bool> deletePost(String postId) async {
    try {
      // Check if current user is admin
      final currentUser = _firebaseService.currentUser;
      if (currentUser == null) return false;

      final isCurrentUserAdmin = await isAdmin(currentUser.uid);
      if (!isCurrentUserAdmin) return false;

      // Delete post
      await _database.child('posts/$postId').remove();
      return true;
    } catch (e) {
      debugPrint('Error deleting post: $e');
      return false;
    }
  }

  // Delete comment
  Future<bool> deleteComment(String postId, String commentId) async {
    try {
      // Check if current user is admin
      final currentUser = _firebaseService.currentUser;
      if (currentUser == null) return false;

      final isCurrentUserAdmin = await isAdmin(currentUser.uid);
      if (!isCurrentUserAdmin) return false;

      // Delete comment
      await _database.child('posts/$postId/comments/$commentId').remove();
      return true;
    } catch (e) {
      debugPrint('Error deleting comment: $e');
      return false;
    }
  }
}

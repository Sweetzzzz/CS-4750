import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/post.dart';
import 'content_moderation_service.dart';
import 'config_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;

  FirebaseService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final List<StreamSubscription> _listeners = [];
  final ContentModerationService _moderationService =
      ContentModerationService();
  final ConfigService _configService = ConfigService();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      // Make sure Firebase is initialized first
      if (Firebase.apps.isEmpty) {
        debugPrint(
            'FirebaseService: Firebase is not initialized, cannot proceed');
        return;
      }

      debugPrint('FirebaseService: Initializing database settings');
      try {
        // Enable disk persistence
        FirebaseDatabase.instance.setPersistenceEnabled(true);
      } catch (e) {
        debugPrint(
            'FirebaseService: Error setting persistence, continuing anyway: $e');
      }

      try {
        // Keep user data synced
        _database.ref().child('users').keepSynced(true);
      } catch (e) {
        debugPrint(
            'FirebaseService: Error setting keepSynced, continuing anyway: $e');
      }

      _initialized = true;
      debugPrint('FirebaseService: Database settings initialized');
    } catch (e) {
      debugPrint('Error initializing FirebaseService: $e');
      // Continue without initialization if there's an error
    }
  }

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Get database reference
  DatabaseReference get database => _database.ref();

  // Clean up all listeners
  Future<void> cleanup() async {
    try {
      debugPrint('FirebaseService: Starting cleanup');

      // Cancel all tracked listeners
      for (final listener in _listeners) {
        await listener.cancel();
      }
      _listeners.clear();
      debugPrint(
          'FirebaseService: Cancelled ${_listeners.length} active listeners');

      // Explicitly detach listeners from common paths
      try {
        _database.ref().child('users').keepSynced(false);
        _database.ref().child('posts').keepSynced(false);
        debugPrint('FirebaseService: Disabled keepSynced for common paths');
      } catch (e) {
        debugPrint('FirebaseService: Error disabling keepSynced: $e');
      }

      // Clear any pending operations
      try {
        await Future.delayed(const Duration(milliseconds: 100));
        debugPrint('FirebaseService: Cleanup completed');
      } catch (e) {
        debugPrint('FirebaseService: Error during final cleanup: $e');
      }
    } catch (e, stack) {
      debugPrint('FirebaseService: Error during cleanup: $e\n$stack');
    }
  }

  // Add listener to tracking list
  void _trackListener(StreamSubscription listener) {
    _listeners.add(listener);
    debugPrint(
        'FirebaseService: Tracking new listener (total: ${_listeners.length})');
  }

  // Helper method to create tracked listeners
  StreamSubscription<T> _createTrackedListener<T>(
    Stream<T> stream,
    void Function(T event) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    _trackListener(subscription);
    return subscription;
  }

  // Upload image to ImgBB
  Future<String> uploadImage(XFile imageFile) async {
    try {
      final apiKey = _configService.imgbbApiKey;
      final url = Uri.parse('https://api.imgbb.com/1/upload');

      final request = http.MultipartRequest('POST', url)
        ..fields['key'] = apiKey
        ..files.add(await http.MultipartFile.fromPath('image', imageFile.path));

      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final jsonData = json.decode(responseData);

      if (jsonData['success'] == true) {
        return jsonData['data']['url'];
      } else {
        throw Exception('Failed to upload image to ImgBB');
      }
    } catch (e) {
      debugPrint('Error uploading image: $e');
      rethrow;
    }
  }

  // Upload a new post
  Future<void> uploadPost({
    required XFile imageFile,
    required String caption,
  }) async {
    try {
      final user = currentUser;
      if (user == null) {
        print('Error: No user logged in');
        throw Exception('No user logged in');
      }

      // Check for offensive content
      if (!_moderationService.moderatePost(
        caption: caption,
        userId: user.uid,
        postId: 'pending', // Will be replaced with actual post ID
      )) {
        throw Exception('Post contains inappropriate content');
      }

      print('Current user ID: ${user.uid}');
      print('Current user displayName: ${user.displayName}');

      // Upload image to ImgBB
      final imageUrl = await uploadImage(imageFile);
      print('Image uploaded successfully: $imageUrl');

      // Get user data from Realtime Database
      final userRef = _database.ref().child('users').child(user.uid);
      print('Checking user profile at path: users/${user.uid}');

      final userSnapshot = await userRef.get();
      print('User snapshot exists: ${userSnapshot.exists}');

      if (!userSnapshot.exists) {
        print('Error: User profile not found in database');
        print('Creating new user profile...');

        // Create user profile if it doesn't exist
        final userData = {
          'username': user.displayName ?? 'Unknown User',
          'email': user.email ?? '',
          'profileImageUrl': user.photoURL ?? '',
          'bio': '',
          'createdAt': DateTime.now().toIso8601String(),
        };

        await userRef.set(userData);
        print('New user profile created');
      }

      final userData = userSnapshot.value as Map<dynamic, dynamic>? ?? {};
      print('User data: $userData');

      // Get username from user profile, fallback to displayName if not found
      final username = userData['username'] as String?;
      if (username == null || username.isEmpty) {
        print('Warning: Username not found in user profile');
        throw Exception('Username not found in user profile');
      }
      print('Using username: $username');

      final postRef = _database.ref().child('posts').push();
      final postData = {
        'userId': user.uid,
        'username': username,
        'userProfileImage': user.photoURL ?? '',
        'imageUrl': imageUrl,
        'caption': caption,
        'likes': 0,
        'timestamp': ServerValue.timestamp,
        'createdAt': DateTime.now().toIso8601String(),
      };

      print('Creating post with data: $postData');
      await postRef.set(postData);
      print('Post created successfully');
    } catch (e) {
      print('Error uploading post: $e');
      print('Error type: ${e.runtimeType}');
      print('Error stack trace: ${e.toString()}');
      rethrow;
    }
  }

  // Get all posts with pagination
  Future<List<DataSnapshot>> getInitialPosts({int limit = 10}) async {
    try {
      debugPrint('FirebaseService: Fetching initial posts');
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        debugPrint('FirebaseService: No current user found');
        return [];
      }

      // Get posts from users you're following
      final followingSnapshot = await _database
          .ref()
          .child('users/${currentUser.uid}/following')
          .get();

      Set<String> followingUsers = {};
      if (followingSnapshot.exists) {
        followingUsers = (followingSnapshot.value as Map<dynamic, dynamic>)
            .keys
            .cast<String>()
            .toSet();
      }

      // Add current user to following set
      followingUsers.add(currentUser.uid);

      debugPrint(
          'FirebaseService: Following users: ${followingUsers.toList()}');

      // Get posts from following users and current user
      final posts = <DataSnapshot>[];

      // First, try to get all the user's own posts
      try {
        final userPostsSnapshot = await _database
            .ref()
            .child('posts')
            .orderByChild('userId')
            .equalTo(currentUser.uid)
            .limitToLast(limit)
            .get();

        if (userPostsSnapshot.exists) {
          debugPrint(
              'FirebaseService: Found ${userPostsSnapshot.children.length} posts for current user');
          posts.addAll(userPostsSnapshot.children);
        } else {
          debugPrint('FirebaseService: No posts found for current user');
        }
      } catch (e) {
        debugPrint('FirebaseService: Error fetching current user posts: $e');
      }

      // Then get posts from followed users
      for (final userId
          in followingUsers.where((id) => id != currentUser.uid)) {
        try {
          final userPostsSnapshot = await _database
              .ref()
              .child('posts')
              .orderByChild('userId')
              .equalTo(userId)
              .limitToLast(limit)
              .get();

          if (userPostsSnapshot.exists) {
            debugPrint(
                'FirebaseService: Found ${userPostsSnapshot.children.length} posts for user $userId');
            posts.addAll(userPostsSnapshot.children);
          }
        } catch (e) {
          debugPrint(
              'FirebaseService: Error fetching posts for user $userId: $e');
          // Continue with other users
          continue;
        }
      }

      // Sort all posts by timestamp
      posts.sort((a, b) {
        final aTimestamp =
            (a.value as Map<dynamic, dynamic>)['timestamp'] as num? ?? 0;
        final bTimestamp =
            (b.value as Map<dynamic, dynamic>)['timestamp'] as num? ?? 0;
        return bTimestamp.compareTo(aTimestamp);
      });

      debugPrint('FirebaseService: Fetched ${posts.length} posts');
      debugPrint(
          'FirebaseService: Post keys: ${posts.map((p) => p.key).toList()}');
      return posts;
    } catch (e, stack) {
      debugPrint('FirebaseService: Error fetching posts: $e');
      debugPrint('Stack trace: $stack');
      rethrow;
    }
  }

  // Get posts stream with pagination
  Stream<DatabaseEvent> getPostsStream({int limit = 10}) {
    debugPrint('FirebaseService: Setting up posts stream');
    try {
      // Using a more basic query to avoid Firebase view issues
      return _database
          .ref()
          .child('posts')
          .orderByChild('timestamp')
          .limitToLast(limit)
          .onValue;
    } catch (e) {
      debugPrint('FirebaseService: Error setting up posts stream: $e');
      return Stream.empty();
    }
  }

  // Get user's posts with pagination
  Future<List<DataSnapshot>> getInitialUserPosts(String userId,
      {int limit = 10}) async {
    try {
      debugPrint('FirebaseService: Fetching initial user posts');
      final snapshot = await _database
          .ref()
          .child('posts')
          .orderByChild('userId')
          .equalTo(userId)
          .limitToLast(limit)
          .get();

      if (!snapshot.exists) {
        debugPrint('FirebaseService: No user posts found');
        return [];
      }

      final posts = snapshot.children.toList();
      debugPrint('FirebaseService: Fetched ${posts.length} user posts');
      return posts;
    } catch (e, stack) {
      debugPrint('FirebaseService: Error fetching user posts: $e');
      debugPrint('Stack trace: $stack');
      rethrow;
    }
  }

  // Get user's posts stream with pagination
  Stream<DatabaseEvent> getUserPostsStream(String userId, {int limit = 10}) {
    debugPrint('FirebaseService: Setting up user posts stream');
    return _database
        .ref()
        .child('posts')
        .orderByChild('userId')
        .equalTo(userId)
        .limitToLast(limit)
        .onValue;
  }

  // Like a post
  Future<void> likePost(String postId) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user logged in');

      // Get post data to check if it's the user's own post
      final postSnapshot = await _database.ref().child('posts/$postId').get();
      if (!postSnapshot.exists) {
        throw Exception('Post not found');
      }

      final postData = postSnapshot.value as Map<dynamic, dynamic>;
      final postOwnerId = postData['userId'] as String;

      // Prevent users from liking their own posts
      if (postOwnerId == user.uid) {
        throw Exception('You cannot like your own post');
      }

      // Check if user already liked the post
      final likeRef = _database.ref().child('posts/$postId/likes/${user.uid}');
      final snapshot = await likeRef.get();

      if (snapshot.exists) {
        throw Exception('You already liked this post');
      }

      // Add like
      await likeRef.set(true);

      // Send notification to post owner
      await addNotification(
        recipientId: postOwnerId,
        senderId: user.uid,
        type: 'like',
        message: 'liked your post',
        postId: postId,
      );
    } catch (e) {
      print('Error liking post: $e');
      rethrow;
    }
  }

  // Unlike a post
  Future<void> unlikePost(String postId) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user logged in');

      await _database.ref().child('posts/$postId/likes/${user.uid}').remove();
    } catch (e) {
      print('Error unliking post: $e');
      rethrow;
    }
  }

  // Check if current user liked a post
  Future<bool> hasLikedPost(String postId) async {
    try {
      final user = currentUser;
      if (user == null) return false;

      final snapshot =
          await _database.ref().child('posts/$postId/likes/${user.uid}').get();
      return snapshot.exists;
    } catch (e) {
      print('Error checking like status: $e');
      return false;
    }
  }

  // Delete a post
  Future<void> deletePost(String postId) async {
    try {
      await _database.ref().child('posts/$postId').remove();
    } catch (e) {
      print('Error deleting post: $e');
      rethrow;
    }
  }

  // Get user profile data
  Stream<DatabaseEvent> getUserProfile(String userId) {
    return _database.ref().child('users/$userId').onValue;
  }

  // Update user profile
  Future<void> updateUserProfile({
    required String username,
    String? bio,
  }) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user logged in');

      // Update Realtime Database user document
      final updates = <String, dynamic>{
        'username': username,
      };
      if (bio != null) updates['bio'] = bio;

      await _database.ref().child('users/${user.uid}').update(updates);

      // Update Firebase Auth display name
      await user.updateDisplayName(username);
    } catch (e) {
      print('Error updating user profile: $e');
      rethrow;
    }
  }

  // Update user profile picture
  Future<void> updateProfilePicture(XFile imageFile) async {
    try {
      final user = currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      // Upload image to ImgBB
      final imageUrl = await uploadImage(imageFile);
      print('Profile picture uploaded successfully: $imageUrl');

      // Update user profile in Realtime Database
      await _database
          .ref()
          .child('users/${user.uid}/profileImageUrl')
          .set(imageUrl);

      // Update Firebase Auth photoURL
      await user.updatePhotoURL(imageUrl);

      // Update profile image in all user's posts
      final postsSnapshot = await _database
          .ref()
          .child('posts')
          .orderByChild('userId')
          .equalTo(user.uid)
          .get();

      if (postsSnapshot.exists) {
        final posts = postsSnapshot.value as Map<dynamic, dynamic>;
        for (final postId in posts.keys) {
          await _database
              .ref()
              .child('posts/$postId/userProfileImage')
              .set(imageUrl);
        }
      }
    } catch (e) {
      print('Error updating profile picture: $e');
      rethrow;
    }
  }

  // Follow a user
  Future<void> followUser(String userId) async {
    try {
      final currentUserId = currentUser?.uid;
      if (currentUserId == null) throw Exception('No user logged in');

      await _database
          .ref()
          .child('users/$currentUserId/following/$userId')
          .set(true);
      await _database
          .ref()
          .child('users/$userId/followers/$currentUserId')
          .set(true);

      // Add notification
      await addNotification(
        recipientId: userId,
        senderId: currentUserId,
        type: 'follow',
        message: 'started following you',
      );
    } catch (e) {
      print('Error following user: $e');
      rethrow;
    }
  }

  // Unfollow a user
  Future<void> unfollowUser(String userId) async {
    try {
      final currentUserId = currentUser?.uid;
      if (currentUserId == null) throw Exception('No user logged in');

      await _database
          .ref()
          .child('users/$currentUserId/following/$userId')
          .remove();
      await _database
          .ref()
          .child('users/$userId/followers/$currentUserId')
          .remove();
    } catch (e) {
      print('Error unfollowing user: $e');
      rethrow;
    }
  }

  // Get followers count
  Stream<DatabaseEvent> getFollowersCount(String userId) {
    return _database.ref().child('users/$userId/followers').onValue;
  }

  // Get following count
  Stream<DatabaseEvent> getFollowingCount(String userId) {
    return _database.ref().child('users/$userId/following').onValue;
  }

  // Check if current user is following another user
  Future<bool> isFollowing(String userId) async {
    try {
      final currentUserId = currentUser?.uid;
      if (currentUserId == null) return false;

      final snapshot = await _database
          .ref()
          .child('users/$currentUserId/following/$userId')
          .get();
      return snapshot.exists;
    } catch (e) {
      print('Error checking follow status: $e');
      return false;
    }
  }

  // Add a comment to a post
  Future<void> addComment(String postId, String text) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user logged in');

      // Check for offensive content
      if (!_moderationService.moderateComment(
        text: text,
        userId: user.uid,
        commentId: 'pending', // Will be replaced with actual comment ID
      )) {
        throw Exception('Comment contains inappropriate content');
      }

      final userData = await _database.ref().child('users/${user.uid}').get();
      final username =
          userData.child('username').value as String? ?? 'Unknown User';

      final commentRef = _database.ref().child('posts/$postId/comments').push();
      await commentRef.set({
        'userId': user.uid,
        'username': username,
        'text': text,
        'timestamp': ServerValue.timestamp,
      });

      // Get post owner to send notification
      final postSnapshot = await _database.ref().child('posts/$postId').get();
      if (postSnapshot.exists) {
        final postData = postSnapshot.value as Map<dynamic, dynamic>;
        final postOwnerId = postData['userId'] as String;

        // Don't notify yourself
        if (postOwnerId != user.uid) {
          await addNotification(
            recipientId: postOwnerId,
            senderId: user.uid,
            type: 'comment',
            message: 'commented on your post',
            postId: postId,
          );
        }
      }
    } catch (e) {
      print('Error adding comment: $e');
      rethrow;
    }
  }

  // Get comments for a post
  Stream<DatabaseEvent> getComments(String postId) {
    return _database
        .ref()
        .child('posts/$postId/comments')
        .orderByChild('timestamp')
        .onValue;
  }

  // Delete a comment
  Future<void> deleteComment(String postId, String commentId) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user logged in');

      final commentRef =
          _database.ref().child('posts/$postId/comments/$commentId');
      final snapshot = await commentRef.get();

      if (snapshot.exists) {
        final commentData = snapshot.value as Map<dynamic, dynamic>;
        if (commentData['userId'] == user.uid) {
          await commentRef.remove();
        } else {
          throw Exception('You can only delete your own comments');
        }
      }
    } catch (e) {
      print('Error deleting comment: $e');
      rethrow;
    }
  }

  // Add a notification
  Future<void> addNotification({
    required String recipientId,
    required String senderId,
    required String type,
    required String message,
    String? postId,
  }) async {
    try {
      // Get sender user details
      final senderSnapshot =
          await _database.ref().child('users/$senderId').get();
      if (!senderSnapshot.exists) return;

      final senderData = senderSnapshot.value as Map<dynamic, dynamic>;
      final senderName = senderData['username'] as String? ?? 'Unknown User';
      final senderImage = senderData['profileImageUrl'] as String? ?? '';

      // Create notification
      final notificationRef =
          _database.ref().child('users/$recipientId/notifications').push();

      final notification = {
        'type': type,
        'senderId': senderId,
        'senderName': senderName,
        'senderImage': senderImage,
        'message': message,
        'timestamp': ServerValue.timestamp,
        'read': false,
      };

      if (postId != null) {
        notification['postId'] = postId;
      }

      await notificationRef.set(notification);
    } catch (e) {
      debugPrint('Error adding notification: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getSuggestedUsers({int limit = 10}) async {
    final currentUid = currentUser?.uid;
    if (currentUid == null) return [];

    try {
      final userSnapshot =
          await database.child('users').limitToFirst(limit + 20).once();
      final List<Map<String, dynamic>> suggestions = [];

      if (userSnapshot.snapshot.exists) {
        for (var child in userSnapshot.snapshot.children) {
          String userId = child.key!;
          if (userId == currentUid) continue;

          bool isUserFollowing = await isFollowing(userId);
          if (isUserFollowing) continue;

          if (child.value is Map) {
            Map<dynamic, dynamic> userData =
                child.value as Map<dynamic, dynamic>;
            suggestions.add({
              'userId': userId,
              'username': userData['username'] ?? 'Unknown',
              'profileImageUrl': userData['profileImageUrl'] ?? '',
            });
          }

          if (suggestions.length >= limit) break;
        }
      }

      return suggestions;
    } catch (e) {
      debugPrint('Error getting suggested users: $e');
      return [];
    }
  }

  // Utility to anonymize username
  String anonymizeUsername(String username, String userId) {
    // If this is the current user, show real username
    if (userId == currentUser?.uid) {
      return username;
    }

    // Otherwise create an anonymous name using a hash of the userId
    final hash = userId.hashCode.abs().toString().substring(0, 6);
    return "User_$hash";
  }

  // Get current monthly theme
  Future<Map<String, dynamic>> getCurrentMonthlyTheme() async {
    try {
      final now = DateTime.now();
      final monthYear = '${now.month}-${now.year}';
      final snapshot =
          await database.child('monthlyThemes').child(monthYear).once();

      if (snapshot.snapshot.exists && snapshot.snapshot.value != null) {
        final themeData = snapshot.snapshot.value as Map<dynamic, dynamic>;
        return {
          'theme': themeData['theme'] as String? ?? 'No theme set',
          'description': themeData['description'] as String? ?? '',
          'startDate': themeData['startDate'] as String? ?? '',
          'endDate': themeData['endDate'] as String? ?? '',
        };
      }

      await _createDefaultMonthlyTheme(monthYear);
      return _getDefaultTheme();
    } catch (e) {
      debugPrint('Error getting monthly theme: $e');
      return _getDefaultTheme();
    }
  }

  // Create a default monthly theme in Firebase
  Future<void> _createDefaultMonthlyTheme(String monthYear) async {
    try {
      final now = DateTime.now();
      final theme = {
        'theme': 'Express Yourself',
        'description': 'Share your creative expression this month!',
        'startDate': DateTime(now.year, now.month, 1).toIso8601String(),
        'endDate': DateTime(now.year, now.month + 1, 0).toIso8601String(),
        'createdAt': ServerValue.timestamp,
      };

      await database.child('monthlyThemes').child(monthYear).set(theme);
    } catch (e) {
      debugPrint('Error creating default theme: $e');
    }
  }

  // Get default theme data
  Map<String, dynamic> _getDefaultTheme() {
    final now = DateTime.now();
    return {
      'theme': 'Express Yourself',
      'description': 'Share your creative expression this month!',
      'startDate': DateTime(now.year, now.month, 1).toIso8601String(),
      'endDate': DateTime(now.year, now.month + 1, 0).toIso8601String(),
    };
  }

  // Get top posts for current month (leaderboard)
  Future<List<Post>> getMonthlyLeaderboard({int limit = 10}) async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      final startTimestamp = startOfMonth.millisecondsSinceEpoch;
      final endTimestamp = endOfMonth.millisecondsSinceEpoch;

      final snapshot = await database
          .child('posts')
          .orderByChild('timestamp')
          .startAt(startTimestamp)
          .endAt(endTimestamp)
          .once();

      if (!snapshot.snapshot.exists) return [];

      final posts = <Post>[];
      for (final child in snapshot.snapshot.children) {
        if (child.value is Map<dynamic, dynamic>) {
          try {
            final post =
                Post.fromMap(child.key!, child.value as Map<dynamic, dynamic>);
            // Double check the timestamp is within the current month
            if (post.timestamp.isAfter(startOfMonth) &&
                post.timestamp.isBefore(endOfMonth)) {
              posts.add(post);
            }
          } catch (e) {
            debugPrint('Error processing leaderboard post: $e');
          }
        }
      }

      posts.sort((a, b) => b.likes.compareTo(a.likes));
      return posts.take(limit).toList();
    } catch (e) {
      debugPrint('Error getting monthly leaderboard: $e');
      return [];
    }
  }

  // Filter out posts older than 30 days
  Future<void> cleanupOldPosts() async {
    try {
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      final cutoffTimestamp = thirtyDaysAgo.millisecondsSinceEpoch;

      final snapshot = await database
          .child('posts')
          .orderByChild('timestamp')
          .endAt(cutoffTimestamp)
          .once();

      if (!snapshot.snapshot.exists) return;

      for (final child in snapshot.snapshot.children) {
        await database.child('posts/${child.key}').remove();
        debugPrint('Deleted old post: ${child.key}');
      }
    } catch (e) {
      debugPrint('Error cleaning up old posts: $e');
    }
  }

  // Set a custom monthly theme (admin function)
  Future<bool> setMonthlyTheme({
    required String theme,
    required String description,
    String? monthYear,
  }) async {
    try {
      final now = DateTime.now();
      final targetMonthYear = monthYear ?? '${now.month}-${now.year}';
      final themeData = {
        'theme': theme,
        'description': description,
        'startDate': DateTime(now.year, now.month, 1).toIso8601String(),
        'endDate': DateTime(now.year, now.month + 1, 0).toIso8601String(),
        'updatedAt': ServerValue.timestamp,
      };

      await database
          .child('monthlyThemes')
          .child(targetMonthYear)
          .update(themeData);
      return true;
    } catch (e) {
      debugPrint('Error setting monthly theme: $e');
      return false;
    }
  }

  // Send a message
  Future<void> sendMessage({
    required String conversationId,
    required String text,
  }) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user logged in');

      // Check for offensive content
      if (!_moderationService.moderateMessage(
        text: text,
        userId: user.uid,
        messageId: 'pending', // Will be replaced with actual message ID
      )) {
        throw Exception('Message contains inappropriate content');
      }

      // ... rest of the existing sendMessage code ...
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      debugPrint('FirebaseService: Starting sign-out process');

      // Cancel all active listeners first
      await cleanup();

      // Then sign out
      await _auth.signOut();

      // Reset initialization flag
      _initialized = false;

      debugPrint('FirebaseService: Sign-out completed successfully');
    } catch (e) {
      debugPrint('FirebaseService: Error during sign-out: $e');
      rethrow;
    }
  }

  // GDPR Data Export - Get all user data for export
  Future<Map<String, dynamic>> getUserDataExport() async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user logged in');

      debugPrint('FirebaseService: Starting data export for user: ${user.uid}');

      final userData = <String, dynamic>{};

      // 1. Get user profile
      final userSnapshot =
          await _database.ref().child('users/${user.uid}').get();
      if (userSnapshot.exists) {
        userData['profile'] = userSnapshot.value;
      }

      // 2. Get user posts
      final postsSnapshot = await _database
          .ref()
          .child('posts')
          .orderByChild('userId')
          .equalTo(user.uid)
          .get();

      if (postsSnapshot.exists) {
        final posts = <String, dynamic>{};
        for (final child in postsSnapshot.children) {
          posts[child.key!] = child.value;
        }
        userData['posts'] = posts;
      }

      // 3. Get user comments
      userData['comments'] = await _getUserComments(user.uid);

      // 4. Get following/followers
      final followingSnapshot =
          await _database.ref().child('users/${user.uid}/following').get();
      if (followingSnapshot.exists) {
        userData['following'] = followingSnapshot.value;
      }

      final followersSnapshot =
          await _database.ref().child('users/${user.uid}/followers').get();
      if (followersSnapshot.exists) {
        userData['followers'] = followersSnapshot.value;
      }

      // 5. Get messages
      userData['messages'] = await _getUserMessages(user.uid);

      // 6. Metadata about the export
      userData['exportMetadata'] = {
        'exportDate': DateTime.now().toIso8601String(),
        'userId': user.uid,
        'email': user.email,
      };

      debugPrint(
          'FirebaseService: Data export completed for user: ${user.uid}');
      return userData;
    } catch (e) {
      debugPrint('FirebaseService: Error exporting user data: $e');
      rethrow;
    }
  }

  // Helper to get user comments across all posts
  Future<Map<String, dynamic>> _getUserComments(String userId) async {
    try {
      final comments = <String, dynamic>{};

      // Get all posts
      final postsSnapshot = await _database.ref().child('posts').get();
      if (!postsSnapshot.exists) return comments;

      // Go through each post's comments to find user's comments
      for (final postSnapshot in postsSnapshot.children) {
        final postId = postSnapshot.key!;
        final commentsSnapshot =
            await _database.ref().child('posts/$postId/comments').get();

        if (!commentsSnapshot.exists) continue;

        for (final commentSnapshot in commentsSnapshot.children) {
          final commentData = commentSnapshot.value as Map<dynamic, dynamic>;
          if (commentData['userId'] == userId) {
            final commentId = commentSnapshot.key!;
            comments['$postId/$commentId'] = commentData;
          }
        }
      }

      return comments;
    } catch (e) {
      debugPrint('FirebaseService: Error getting user comments: $e');
      return {};
    }
  }

  // Helper to get user messages
  Future<Map<String, dynamic>> _getUserMessages(String userId) async {
    try {
      final messages = <String, dynamic>{};

      // Get conversations involving the user
      final conversationsSnapshot =
          await _database.ref().child('messages').get();
      if (!conversationsSnapshot.exists) return messages;

      // Find conversations where the user is a participant
      for (final conversationSnapshot in conversationsSnapshot.children) {
        final conversationId = conversationSnapshot.key!;
        final conversationData =
            conversationSnapshot.value as Map<dynamic, dynamic>;

        if (conversationData.containsKey('participants')) {
          final participants =
              conversationData['participants'] as Map<dynamic, dynamic>;

          // Check if user is a participant
          if (participants.containsValue(userId)) {
            messages[conversationId] = conversationData;
          }
        }
      }

      return messages;
    } catch (e) {
      debugPrint('FirebaseService: Error getting user messages: $e');
      return {};
    }
  }

  // GDPR Account Deletion - Delete user account and all associated data
  Future<void> deleteUserAccount() async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user logged in');

      debugPrint(
          'FirebaseService: Starting account deletion for user: ${user.uid}');

      // 1. Delete user's posts and their comments
      await _deleteUserPosts(user.uid);

      // 2. Delete user's comments on other posts
      await _deleteUserComments(user.uid);

      // 3. Delete following/followers relationships
      await _deleteUserRelationships(user.uid);

      // 4. Delete user's messages
      await _deleteUserMessages(user.uid);

      // 5. Delete user's profile
      await _database.ref().child('users/${user.uid}').remove();

      // 6. Delete Firebase Auth account
      await user.delete();

      debugPrint(
          'FirebaseService: Account deletion completed for user: ${user.uid}');
    } catch (e) {
      debugPrint('FirebaseService: Error deleting account: $e');
      rethrow;
    }
  }

  // Helper to delete user's posts
  Future<void> _deleteUserPosts(String userId) async {
    try {
      // Get all posts by user
      final postsSnapshot = await _database
          .ref()
          .child('posts')
          .orderByChild('userId')
          .equalTo(userId)
          .get();

      if (!postsSnapshot.exists) return;

      // Delete each post
      for (final postSnapshot in postsSnapshot.children) {
        await _database.ref().child('posts/${postSnapshot.key}').remove();
      }
    } catch (e) {
      debugPrint('FirebaseService: Error deleting user posts: $e');
    }
  }

  // Helper to delete user's comments on other posts
  Future<void> _deleteUserComments(String userId) async {
    try {
      // Get all posts
      final postsSnapshot = await _database.ref().child('posts').get();
      if (!postsSnapshot.exists) return;

      // Go through each post's comments to find and delete user's comments
      for (final postSnapshot in postsSnapshot.children) {
        final postId = postSnapshot.key!;
        final commentsSnapshot =
            await _database.ref().child('posts/$postId/comments').get();

        if (!commentsSnapshot.exists) continue;

        for (final commentSnapshot in commentsSnapshot.children) {
          final commentData = commentSnapshot.value as Map<dynamic, dynamic>;
          if (commentData['userId'] == userId) {
            await _database
                .ref()
                .child('posts/$postId/comments/${commentSnapshot.key}')
                .remove();
          }
        }
      }
    } catch (e) {
      debugPrint('FirebaseService: Error deleting user comments: $e');
    }
  }

  // Helper to delete following/followers relationships
  Future<void> _deleteUserRelationships(String userId) async {
    try {
      // Remove user from others' following lists
      final usersSnapshot = await _database.ref().child('users').get();
      if (usersSnapshot.exists) {
        for (final userSnapshot in usersSnapshot.children) {
          final otherUserId = userSnapshot.key!;

          // Skip self
          if (otherUserId == userId) continue;

          // Remove from following
          await _database
              .ref()
              .child('users/$otherUserId/following/$userId')
              .remove();

          // Remove from followers
          await _database
              .ref()
              .child('users/$otherUserId/followers/$userId')
              .remove();
        }
      }
    } catch (e) {
      debugPrint('FirebaseService: Error deleting user relationships: $e');
    }
  }

  // Helper to delete user's messages
  Future<void> _deleteUserMessages(String userId) async {
    try {
      // Get all conversations
      final conversationsSnapshot =
          await _database.ref().child('messages').get();
      if (!conversationsSnapshot.exists) return;

      // Find and delete conversations where the user is a participant
      for (final conversationSnapshot in conversationsSnapshot.children) {
        final conversationId = conversationSnapshot.key!;
        final conversationData =
            conversationSnapshot.value as Map<dynamic, dynamic>;

        if (conversationData.containsKey('participants')) {
          final participants =
              conversationData['participants'] as Map<dynamic, dynamic>;

          // Check if user is a participant
          if (participants.containsValue(userId)) {
            await _database.ref().child('messages/$conversationId').remove();
          }
        }
      }
    } catch (e) {
      debugPrint('FirebaseService: Error deleting user messages: $e');
    }
  }
}

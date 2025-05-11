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
      if (Firebase.apps.isEmpty) {
        debugPrint(
            'FirebaseService: Firebase is not initialized, cannot proceed');
        return;
      }

      debugPrint('FirebaseService: Initializing database settings');
      try {
        FirebaseDatabase.instance.setPersistenceEnabled(true);
      } catch (e) {
        debugPrint(
            'FirebaseService: Error setting persistence, continuing anyway: $e');
      }

      try {
        _database.ref().child('users').keepSynced(true);
      } catch (e) {
        debugPrint(
            'FirebaseService: Error setting keepSynced, continuing anyway: $e');
      }

      _initialized = true;
      debugPrint('FirebaseService: Database settings initialized');
    } catch (e) {
      debugPrint('Error initializing FirebaseService: $e');
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

      for (final listener in _listeners) {
        await listener.cancel();
      }
      _listeners.clear();
      debugPrint(
          'FirebaseService: Cancelled ${_listeners.length} active listeners');

      try {
        _database.ref().child('users').keepSynced(false);
        _database.ref().child('posts').keepSynced(false);
        debugPrint('FirebaseService: Disabled keepSynced for common paths');
      } catch (e) {
        debugPrint('FirebaseService: Error disabling keepSynced: $e');
      }

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

  void _trackListener(StreamSubscription listener) {
    _listeners.add(listener);
    debugPrint(
        'FirebaseService: Tracking new listener (total: ${_listeners.length})');
  }

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

      if (!_moderationService.moderatePost(
        caption: caption,
        userId: user.uid,
        postId: 'pending', // Post ID
      )) {
        throw Exception('Post contains inappropriate content');
      }

      print('Current user ID: ${user.uid}');
      print('Current user displayName: ${user.displayName}');

      final imageUrl = await uploadImage(imageFile);
      print('Image uploaded: $imageUrl');

      final userRef = _database.ref().child('users').child(user.uid);
      print('Checking user profile at path: users/${user.uid}');

      final userSnapshot = await userRef.get();
      print('User snapshot exists: ${userSnapshot.exists}');

      if (!userSnapshot.exists) {
        print('Error: User profile not found in database');
        print('Creating new user profile...');

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

  Future<List<DataSnapshot>> getInitialPosts({int limit = 10}) async {
    try {
      debugPrint('FirebaseService: Fetching initial posts');
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        debugPrint('FirebaseService: No current user found');
        return [];
      }

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

      followingUsers.add(currentUser.uid);

      debugPrint(
          'FirebaseService: Following users: ${followingUsers.toList()}');

      final posts = <DataSnapshot>[];

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

  Stream<DatabaseEvent> getPostsStream({int limit = 10}) {
    debugPrint('FirebaseService: Setting up posts stream');
    try {
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

      final postSnapshot = await _database.ref().child('posts/$postId').get();
      if (!postSnapshot.exists) {
        throw Exception('Post not found');
      }

      final postData = postSnapshot.value as Map<dynamic, dynamic>;
      final postOwnerId = postData['userId'] as String;

      if (postOwnerId == user.uid) {
        throw Exception('You cannot like your own post');
      }

      final likeRef = _database.ref().child('posts/$postId/likes/${user.uid}');
      final snapshot = await likeRef.get();

      if (snapshot.exists) {
        throw Exception('You already liked this post');
      }

      await likeRef.set(true);

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

  Stream<DatabaseEvent> getUserProfile(String userId) {
    return _database.ref().child('users/$userId').onValue;
  }

  Future<void> updateUserProfile({
    required String username,
    String? bio,
  }) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user logged in');

      final updates = <String, dynamic>{
        'username': username,
      };
      if (bio != null) updates['bio'] = bio;

      await _database.ref().child('users/${user.uid}').update(updates);

      await user.updateDisplayName(username);
    } catch (e) {
      print('Error updating user profile: $e');
      rethrow;
    }
  }

  Future<void> updateProfilePicture(XFile imageFile) async {
    try {
      final user = currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      final imageUrl = await uploadImage(imageFile);
      print('Profile picture uploaded successfully: $imageUrl');

      await _database
          .ref()
          .child('users/${user.uid}/profileImageUrl')
          .set(imageUrl);

      await user.updatePhotoURL(imageUrl);

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

  Stream<DatabaseEvent> getFollowersCount(String userId) {
    return _database.ref().child('users/$userId/followers').onValue;
  }

  Stream<DatabaseEvent> getFollowingCount(String userId) {
    return _database.ref().child('users/$userId/following').onValue;
  }

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

  Future<void> addComment(String postId, String text) async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user logged in');

      if (!_moderationService.moderateComment(
        text: text,
        userId: user.uid,
        commentId: 'pending',
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

      final postSnapshot = await _database.ref().child('posts/$postId').get();
      if (postSnapshot.exists) {
        final postData = postSnapshot.value as Map<dynamic, dynamic>;
        final postOwnerId = postData['userId'] as String;

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

  Stream<DatabaseEvent> getComments(String postId) {
    return _database
        .ref()
        .child('posts/$postId/comments')
        .orderByChild('timestamp')
        .onValue;
  }

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

  Future<void> addNotification({
    required String recipientId,
    required String senderId,
    required String type,
    required String message,
    String? postId,
  }) async {
    try {
      final senderSnapshot =
          await _database.ref().child('users/$senderId').get();
      if (!senderSnapshot.exists) return;

      final senderData = senderSnapshot.value as Map<dynamic, dynamic>;
      final senderName = senderData['username'] as String? ?? 'Unknown User';
      final senderImage = senderData['profileImageUrl'] as String? ?? '';

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

  String anonymizeUsername(String username, String userId) {
    if (userId == currentUser?.uid) {
      return username;
    }

    final hash = userId.hashCode.abs().toString().substring(0, 6);
    return "User_$hash";
  }

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

  Map<String, dynamic> _getDefaultTheme() {
    final now = DateTime.now();
    return {
      'theme': 'Express Yourself',
      'description': 'Share your creative expression this month!',
      'startDate': DateTime(now.year, now.month, 1).toIso8601String(),
      'endDate': DateTime(now.year, now.month + 1, 0).toIso8601String(),
    };
  }

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

      if (!_moderationService.moderateMessage(
        text: text,
        userId: user.uid,
        messageId: 'pending', // Message ID
      )) {
        throw Exception('Message contains inappropriate content');
      }
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      debugPrint('FirebaseService: Starting sign-out process');
      await cleanup();
      await _auth.signOut();
      _initialized = false;

      debugPrint('FirebaseService: Sign-out completed successfully');
    } catch (e) {
      debugPrint('FirebaseService: Error during sign-out: $e');
      rethrow;
    }
  }
  Future<Map<String, dynamic>> getUserDataExport() async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user logged in');

      debugPrint('FirebaseService: Starting data export for user: ${user.uid}');

      final userData = <String, dynamic>{};
      final userSnapshot =
          await _database.ref().child('users/${user.uid}').get();
      if (userSnapshot.exists) {
        userData['profile'] = userSnapshot.value;
      }
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
      userData['comments'] = await _getUserComments(user.uid);
      
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

      userData['messages'] = await _getUserMessages(user.uid);

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

  Future<Map<String, dynamic>> _getUserComments(String userId) async {
    try {
      final comments = <String, dynamic>{};

      final postsSnapshot = await _database.ref().child('posts').get();
      if (!postsSnapshot.exists) return comments;

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

  Future<Map<String, dynamic>> _getUserMessages(String userId) async {
    try {
      final messages = <String, dynamic>{};

      final conversationsSnapshot =
          await _database.ref().child('messages').get();
      if (!conversationsSnapshot.exists) return messages;

      for (final conversationSnapshot in conversationsSnapshot.children) {
        final conversationId = conversationSnapshot.key!;
        final conversationData =
            conversationSnapshot.value as Map<dynamic, dynamic>;

        if (conversationData.containsKey('participants')) {
          final participants =
              conversationData['participants'] as Map<dynamic, dynamic>;

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

  Future<void> deleteUserAccount() async {
    try {
      final user = currentUser;
      if (user == null) throw Exception('No user logged in');

      debugPrint(
          'FirebaseService: Starting account deletion for user: ${user.uid}');

      await _deleteUserPosts(user.uid);
      await _deleteUserComments(user.uid);
      await _deleteUserRelationships(user.uid);
      await _deleteUserMessages(user.uid);
      await _database.ref().child('users/${user.uid}').remove();
      await user.delete();

      debugPrint(
          'FirebaseService: Account deletion completed for user: ${user.uid}');
    } catch (e) {
      debugPrint('FirebaseService: Error deleting account: $e');
      rethrow;
    }
  }

  Future<void> _deleteUserPosts(String userId) async {
    try {
      final postsSnapshot = await _database
          .ref()
          .child('posts')
          .orderByChild('userId')
          .equalTo(userId)
          .get();

      if (!postsSnapshot.exists) return;

      for (final postSnapshot in postsSnapshot.children) {
        await _database.ref().child('posts/${postSnapshot.key}').remove();
      }
    } catch (e) {
      debugPrint('FirebaseService: Error deleting user posts: $e');
    }
  }

  Future<void> _deleteUserComments(String userId) async {
    try {
      final postsSnapshot = await _database.ref().child('posts').get();
      if (!postsSnapshot.exists) return;

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

  Future<void> _deleteUserRelationships(String userId) async {
    try {
      // Remove user from others' following lists
      final usersSnapshot = await _database.ref().child('users').get();
      if (usersSnapshot.exists) {
        for (final userSnapshot in usersSnapshot.children) {
          final otherUserId = userSnapshot.key!;

          // Skip self
          if (otherUserId == userId) continue;

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

  Future<void> _deleteUserMessages(String userId) async {
    try {
      final conversationsSnapshot =
          await _database.ref().child('messages').get();
      if (!conversationsSnapshot.exists) return;

      for (final conversationSnapshot in conversationsSnapshot.children) {
        final conversationId = conversationSnapshot.key!;
        final conversationData =
            conversationSnapshot.value as Map<dynamic, dynamic>;

        if (conversationData.containsKey('participants')) {
          final participants =
              conversationData['participants'] as Map<dynamic, dynamic>;

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

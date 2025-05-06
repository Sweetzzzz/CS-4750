import 'package:firebase_database/firebase_database.dart';

class Post {
  final String id;
  final String userId;
  final String username;
  final String? userProfileImage;
  final String imageUrl;
  final String caption;
  final int likes;
  final DateTime timestamp;

  Post({
    required this.id,
    required this.userId,
    required this.username,
    this.userProfileImage,
    required this.imageUrl,
    required this.caption,
    required this.likes,
    required this.timestamp,
  });

  factory Post.fromSnapshot(DataSnapshot snapshot) {
    final data = snapshot.value as Map<dynamic, dynamic>;
    return Post(
      id: snapshot.key!,
      userId: data['userId'] as String,
      username: data['username'] as String,
      userProfileImage: data['userProfileImage'] as String?,
      imageUrl: data['imageUrl'] as String,
      caption: data['caption'] as String,
      likes: data['likes'] != null
          ? (data['likes'] as Map<dynamic, dynamic>).length
          : 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (data['timestamp'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  factory Post.fromMap(String id, Map<dynamic, dynamic> data) {
    int likesCount = 0;
    if (data['likes'] != null) {
      if (data['likes'] is Map<dynamic, dynamic>) {
        likesCount = (data['likes'] as Map<dynamic, dynamic>).length;
      } else if (data['likes'] is int) {
        likesCount = data['likes'] as int;
      }
    }

    return Post(
      id: id,
      userId: data['userId'] as String,
      username: data['username'] as String,
      userProfileImage: data['userProfileImage'] as String?,
      imageUrl: data['imageUrl'] as String,
      caption: data['caption'] as String,
      likes: likesCount,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (data['timestamp'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'userProfileImage': userProfileImage,
      'imageUrl': imageUrl,
      'caption': caption,
      'likes': likes,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }
}

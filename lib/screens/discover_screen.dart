import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/firebase_service.dart';
import 'dart:math';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  List<Map<String, dynamic>> _suggestedUsers = [];
  bool _isLoading = true;
  final Set<String> _followingUsers = {};

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    if (_firebaseService.currentUser == null) return;

    setState(() => _isLoading = true);

    try {
      final userId = _firebaseService.currentUser!.uid;

      // First, get users the current user is already following
      final followingSnapshot = await _firebaseService.database
          .child('users/$userId/following')
          .get();

      if (followingSnapshot.exists) {
        _followingUsers.clear();
        final followingData = followingSnapshot.value as Map<dynamic, dynamic>;
        _followingUsers.addAll(followingData.keys.cast<String>());
      }

      // Then, get all users
      final usersSnapshot =
          await _firebaseService.database.child('users').get();

      if (usersSnapshot.exists) {
        final suggestions = <Map<String, dynamic>>[];
        final allUsers = usersSnapshot.value as Map<dynamic, dynamic>;

        // Filter out current user and users already followed
        for (final entry in allUsers.entries) {
          final otherUserId = entry.key as String;
          final userData = entry.value as Map<dynamic, dynamic>;

          if (otherUserId != userId && !_followingUsers.contains(otherUserId)) {
            // Get follower count for popularity
            int followerCount = 0;
            final followersSnapshot = await _firebaseService.database
                .child('users/$otherUserId/followers')
                .get();

            if (followersSnapshot.exists) {
              followerCount =
                  (followersSnapshot.value as Map<dynamic, dynamic>).length;
            }

            // Get post count for activity
            int postCount = 0;
            final postsSnapshot = await _firebaseService.database
                .child('posts')
                .orderByChild('userId')
                .equalTo(otherUserId)
                .get();

            if (postsSnapshot.exists) {
              postCount = (postsSnapshot.value as Map<dynamic, dynamic>).length;
            }

            suggestions.add({
              'userId': otherUserId,
              'username': userData['username'] as String? ?? 'Unknown User',
              'profileImage': userData['profileImageUrl'] as String? ?? '',
              'bio': userData['bio'] as String? ?? '',
              'followerCount': followerCount,
              'postCount': postCount,
              'score': followerCount * 2 +
                  postCount, // Simple scoring for recommendations
            });
          }
        }

        // Sort by score (popularity and activity)
        suggestions
            .sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

        setState(() {
          _suggestedUsers = suggestions;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading suggestions: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow(String userId, bool currentlyFollowing) async {
    try {
      if (currentlyFollowing) {
        await _firebaseService.unfollowUser(userId);
        setState(() {
          _followingUsers.remove(userId);
        });
      } else {
        await _firebaseService.followUser(userId);
        setState(() {
          _followingUsers.add(userId);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _suggestedUsers.isEmpty
              ? const Center(
                  child: Text('No suggestions available right now'),
                )
              : RefreshIndicator(
                  onRefresh: _loadSuggestions,
                  child: ListView(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Suggested for You',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ...buildCategorySection(
                          'Popular Accounts',
                          _suggestedUsers
                              .where((user) => user['followerCount'] > 0)
                              .toList()),
                      ...buildCategorySection(
                          'Active Users',
                          _suggestedUsers
                              .where((user) => user['postCount'] > 0)
                              .toList()),
                      ...buildCategorySection('New Users',
                          _suggestedUsers.reversed.take(3).toList()),
                    ],
                  ),
                ),
    );
  }

  List<Widget> buildCategorySection(
      String title, List<Map<String, dynamic>> users) {
    if (users.isEmpty) return [];

    // Limit to 5 users per section
    final displayUsers = users.take(5).toList();

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      SizedBox(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: displayUsers.length,
          itemBuilder: (context, index) {
            final user = displayUsers[index];
            final bool isFollowing = _followingUsers.contains(user['userId']);

            return Container(
              width: 150,
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),
                  CircleAvatar(
                    radius: 35,
                    backgroundImage: user['profileImage'] != null &&
                            user['profileImage'].toString().isNotEmpty
                        ? NetworkImage(user['profileImage'])
                        : null,
                    child: user['profileImage'] == null ||
                            user['profileImage'].toString().isEmpty
                        ? Text(
                            (user['username'] as String).isNotEmpty
                                ? (user['username'] as String)[0].toUpperCase()
                                : '?',
                            style: const TextStyle(fontSize: 24))
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      user['username'] as String,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${user['followerCount']} followers',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _toggleFollow(
                          user['userId'] as String,
                          isFollowing,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isFollowing ? Colors.grey : Colors.blue,
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                        ),
                        child: Text(
                          isFollowing ? 'Unfollow' : 'Follow',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ];
  }
}

// A separate discover tab for trends and hashtags
class TrendsSection extends StatelessWidget {
  const TrendsSection({super.key});

  @override
  Widget build(BuildContext context) {
    // Simulate trending hashtags
    final trending = [
      {'tag': '#photography', 'count': '2.5M posts'},
      {'tag': '#nature', 'count': '1.8M posts'},
      {'tag': '#travel', 'count': '3.2M posts'},
      {'tag': '#food', 'count': '4.1M posts'},
      {'tag': '#fitness', 'count': '2.9M posts'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Trending Hashtags',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: trending.length,
          itemBuilder: (context, index) {
            return ListTile(
              title: Text(
                trending[index]['tag']!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(trending[index]['count']!),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                // Navigate to hashtag results
              },
            );
          },
        ),
      ],
    );
  }
}

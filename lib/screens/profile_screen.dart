import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/post.dart';
import '../services/firebase_service.dart';
import 'dart:async';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final FirebaseService _firebaseService = FirebaseService();

  ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isFollowing = false;
  bool _isLoading = true;
  List<Post> _posts = [];
  StreamSubscription? _profileSubscription;
  StreamSubscription? _postsSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('Initializing profile screen for userId: ${widget.userId}');
    if (widget.userId.isEmpty) {
      debugPrint('Warning: Empty userId provided to ProfileScreen');
    }
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      debugPrint('Starting profile data initialization');
      setState(() => _isLoading = true);

      // Check follow status
      if (widget.userId != widget._firebaseService.currentUser?.uid) {
        debugPrint('Checking follow status for user: ${widget.userId}');
        try {
          final isFollowing =
              await widget._firebaseService.isFollowing(widget.userId);
          if (mounted) {
            setState(() => _isFollowing = isFollowing);
          }
        } catch (e) {
          debugPrint('Error checking follow status: $e');
        }
      }

      // Load initial posts
      debugPrint('Attempting to load initial posts');
      try {
        final initialPosts = await widget._firebaseService
            .getInitialUserPosts(widget.userId, limit: 20);
        debugPrint('Received ${initialPosts.length} initial posts');

        if (mounted) {
          setState(() {
            _posts = [];
            for (var snapshot in initialPosts) {
              try {
                debugPrint('Processing post with key: ${snapshot.key}');
                debugPrint('Post value type: ${snapshot.value.runtimeType}');
                debugPrint('Post value: ${snapshot.value}');

                if (snapshot.value is Map<dynamic, dynamic>) {
                  final post = Post.fromMap(
                      snapshot.key!, snapshot.value as Map<dynamic, dynamic>);
                  _posts.add(post);
                  debugPrint('Successfully added post: ${post.id}');
                } else {
                  debugPrint('Skipping non-map post data: ${snapshot.value}');
                }
              } catch (e) {
                debugPrint('Error processing post ${snapshot.key}: $e');
              }
            }
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint('Error loading initial posts: $e');
        if (mounted) {
          setState(() {
            _posts = [];
            _isLoading = false;
          });
        }
      }

      // Set up real-time listeners
      _setupListeners();
    } catch (e, stackTrace) {
      debugPrint('Error initializing profile data: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupListeners() {
    // Profile data listener
    _profileSubscription?.cancel();
    _profileSubscription =
        widget._firebaseService.getUserProfile(widget.userId).listen((event) {
      if (mounted) {
        setState(() {});
      }
    });

    // Posts listener
    _postsSubscription?.cancel();
    _postsSubscription = widget._firebaseService
        .getUserPostsStream(widget.userId, limit: 20)
        .listen((event) {
      debugPrint('Posts stream event received');
      if (mounted && event.snapshot.exists) {
        try {
          setState(() {
            _posts = [];
            for (var child in event.snapshot.children) {
              try {
                if (child.value is Map<dynamic, dynamic>) {
                  final post = Post.fromMap(
                      child.key!, child.value as Map<dynamic, dynamic>);
                  _posts.add(post);
                } else {
                  debugPrint(
                      'Skipping non-map post data in stream: ${child.value}');
                }
              } catch (e) {
                debugPrint(
                    'Error processing post ${child.key} from stream: $e');
              }
            }
          });
        } catch (e) {
          debugPrint('Error processing posts stream: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    _postsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _toggleFollow() async {
    try {
      setState(() => _isLoading = true);

      if (_isFollowing) {
        await widget._firebaseService.unfollowUser(widget.userId);
        // Immediately update UI to reflect changes
        if (mounted) {
          setState(() {
            _isFollowing = false;
            _isLoading = false;
          });
        }
      } else {
        await widget._firebaseService.followUser(widget.userId);
        // Immediately update UI to reflect changes
        if (mounted) {
          setState(() {
            _isFollowing = true;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (widget.userId == widget._firebaseService.currentUser?.uid)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.pushNamed(context, '/settings');
              },
            ),
        ],
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: widget._firebaseService.getUserProfile(widget.userId),
        builder: (context, profileSnapshot) {
          if (profileSnapshot.hasError) {
            return Center(child: Text('Error: ${profileSnapshot.error}'));
          }

          if (profileSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData =
              profileSnapshot.data?.snapshot.value as Map<dynamic, dynamic>?;
          if (userData == null) {
            return const Center(child: Text('User not found'));
          }

          final bool isCurrentUser =
              widget.userId == widget._firebaseService.currentUser?.uid;
          final bool canViewPosts = isCurrentUser || _isFollowing;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundImage:
                              userData['profileImageUrl'] != null &&
                                      userData['profileImageUrl']
                                          .toString()
                                          .isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      userData['profileImageUrl'].toString())
                                  : null,
                          child: userData['profileImageUrl'] == null ||
                                  userData['profileImageUrl'].toString().isEmpty
                              ? Text(
                                  (userData['username']?.toString() ?? '?')[0]
                                      .toUpperCase(),
                                  style: const TextStyle(fontSize: 24),
                                )
                              : null,
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              StreamBuilder<DatabaseEvent>(
                                stream: widget._firebaseService
                                    .getUserPostsStream(widget.userId),
                                builder: (context, postsSnapshot) {
                                  final postCount = postsSnapshot.hasData
                                      ? postsSnapshot
                                          .data!.snapshot.children.length
                                      : 0;
                                  return _buildStatColumn('Posts', postCount);
                                },
                              ),
                              StreamBuilder<DatabaseEvent>(
                                stream: widget._firebaseService
                                    .getFollowersCount(widget.userId),
                                builder: (context, followersSnapshot) {
                                  final followersCount =
                                      followersSnapshot.hasData
                                          ? followersSnapshot
                                              .data!.snapshot.children.length
                                          : 0;
                                  return _buildStatColumn(
                                      'Followers', followersCount);
                                },
                              ),
                              StreamBuilder<DatabaseEvent>(
                                stream: widget._firebaseService
                                    .getFollowingCount(widget.userId),
                                builder: (context, followingSnapshot) {
                                  final followingCount =
                                      followingSnapshot.hasData
                                          ? followingSnapshot
                                              .data!.snapshot.children.length
                                          : 0;
                                  return _buildStatColumn(
                                      'Following', followingCount);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      userData['username']?.toString() ?? 'Unknown User',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (userData['bio']?.toString().isNotEmpty ?? false) ...[
                      const SizedBox(height: 8),
                      Text(userData['bio'].toString()),
                    ],
                    const SizedBox(height: 16),
                    if (isCurrentUser)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/edit_profile');
                          },
                          child: const Text('Edit Profile'),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _toggleFollow,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _isFollowing ? Colors.grey : Colors.blue,
                          ),
                          child: Text(_isFollowing ? 'Unfollow' : 'Follow'),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: !canViewPosts
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.lock,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'This account\'s posts are private',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Follow this account to see their posts',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _toggleFollow,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text(
                                'Follow',
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      )
                    : StreamBuilder<DatabaseEvent>(
                        stream: widget._firebaseService
                            .getUserPostsStream(widget.userId),
                        builder: (context, postsSnapshot) {
                          if (postsSnapshot.hasError) {
                            return Center(
                                child: Text('Error: ${postsSnapshot.error}'));
                          }

                          if (postsSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          final posts = <Post>[];
                          if (postsSnapshot.hasData) {
                            for (final child
                                in postsSnapshot.data!.snapshot.children) {
                              if (child.value is Map<dynamic, dynamic>) {
                                final post = Post.fromMap(child.key!,
                                    child.value as Map<dynamic, dynamic>);
                                posts.add(post);
                              }
                            }
                          }

                          if (posts.isEmpty) {
                            return const Center(
                              child: Text(
                                'No posts yet',
                                style: TextStyle(fontSize: 16),
                              ),
                            );
                          }

                          return GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 1,
                              mainAxisSpacing: 1,
                            ),
                            itemCount: posts.length,
                            itemBuilder: (context, index) {
                              final post = posts[index];
                              return GestureDetector(
                                onTap: () {
                                  // TODO: Navigate to post detail screen
                                },
                                child: Container(
                                  color: Colors.grey[200],
                                  child: post.imageUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: post.imageUrl,
                                          fit: BoxFit.cover,
                                          errorWidget: (context, url, error) =>
                                              const Icon(Icons.error),
                                        )
                                      : const Center(
                                          child: Icon(Icons.image,
                                              size: 30, color: Colors.grey),
                                        ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatColumn(String label, int count) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count.toString(),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}

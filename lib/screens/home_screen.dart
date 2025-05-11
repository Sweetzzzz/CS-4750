import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import '../models/post.dart';
import '../services/firebase_service.dart';
import 'create_post_screen.dart';
import 'profile_screen.dart';
import '../widgets/comment_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  Set<String> _followingUsers = {};
  List<Post> _posts = [];
  List<Post> _allPosts = [];
  bool _isLoading = true;
  bool _debugShowAllPosts = false; 
  StreamSubscription? _followingSubscription;
  StreamSubscription? _postsSubscription;

  @override
  void initState() {
    super.initState();
    debugPrint('HomeScreen: initializing');
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      debugPrint('HomeScreen: starting data initialization');
      final currentUser = _firebaseService.currentUser;
      if (currentUser == null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }


      await Future.delayed(const Duration(milliseconds: 500));

      List<DataSnapshot> posts = [];
      try {
        posts = await _firebaseService.getInitialPosts(limit: 20);
        debugPrint('HomeScreen: loaded ${posts.length} initial posts');
        debugPrint(
            'HomeScreen: post keys: ${posts.map((p) => p.key).toList()}');
      } catch (e) {
        debugPrint('HomeScreen: Error loading initial posts: $e');
        // Try again with a delay
        await Future.delayed(const Duration(seconds: 1));
        try {
          posts = await _firebaseService.getInitialPosts(limit: 20);
          debugPrint(
              'HomeScreen: loaded ${posts.length} initial posts on retry');
        } catch (e) {
          debugPrint('HomeScreen: Error loading initial posts on retry: $e');
        }
      }

      if (posts.isNotEmpty && mounted) {
        setState(() {
          _allPosts = posts
              .map((snapshot) {
                try {
                  debugPrint(
                      'HomeScreen: Processing post with key: ${snapshot.key}');
                  debugPrint('HomeScreen: Post value: ${snapshot.value}');
                  final post = Post.fromMap(
                      snapshot.key!, snapshot.value as Map<dynamic, dynamic>);
                  debugPrint(
                      'HomeScreen: Created post with userId: ${post.userId}, timestamp: ${post.timestamp}');
                  return post;
                } catch (e) {
                  debugPrint(
                      'HomeScreen: Error processing post ${snapshot.key}: $e');
                  return null;
                }
              })
              .where((post) => post != null)
              .cast<Post>()
              .toList();
          debugPrint('HomeScreen: processed ${_allPosts.length} posts');
          debugPrint(
              'HomeScreen: post user IDs: ${_allPosts.map((p) => p.userId).toList()}');
        });
      }

      Map<dynamic, dynamic>? followingData;
      try {
        final followingSnapshot = await _firebaseService.database
            .child('users/${currentUser.uid}/following')
            .get();

        if (followingSnapshot.exists) {
          followingData = followingSnapshot.value as Map<dynamic, dynamic>;
        }
      } catch (e) {
        debugPrint('HomeScreen: Error loading following data: $e');
        await Future.delayed(const Duration(seconds: 1));
        try {
          final followingSnapshot = await _firebaseService.database
              .child('users/${currentUser.uid}/following')
              .get();

          if (followingSnapshot.exists) {
            followingData = followingSnapshot.value as Map<dynamic, dynamic>;
          }
        } catch (e) {
          debugPrint('HomeScreen: Error loading following data on retry: $e');
        }
      }

      if (followingData != null && mounted) {
        setState(() {
          _followingUsers = followingData!.keys.cast<String>().toSet();
          debugPrint(
              'HomeScreen: loaded ${_followingUsers.length} following users');
          debugPrint(
              'HomeScreen: following user IDs: ${_followingUsers.toList()}');
          _filterPosts();
        });
      } else if (mounted) {
        debugPrint('HomeScreen: no following data found');
        _filterPosts();
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }

      await Future.delayed(const Duration(milliseconds: 500));

      _setupListeners(currentUser.uid);
    } catch (e, stack) {
      debugPrint('HomeScreen: Error during initialization: $e');
      debugPrint('Stack trace: $stack');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupListeners(String userId) {
    try {
      _followingSubscription?.cancel();
      _postsSubscription?.cancel();

      _followingSubscription = _firebaseService.database
          .child('users/$userId/following')
          .onValue
          .listen((event) {
        if (!mounted) return;

        debugPrint('HomeScreen: Following data changed');
        Set<String> newFollowingUsers = {};
        if (event.snapshot.exists) {
          newFollowingUsers = (event.snapshot.value as Map<dynamic, dynamic>)
              .keys
              .cast<String>()
              .toSet();
        }

        bool followingChanged =
            newFollowingUsers.length != _followingUsers.length ||
                !newFollowingUsers
                    .every((element) => _followingUsers.contains(element));

        if (followingChanged) {
          debugPrint('HomeScreen: Follow relationships changed');
          debugPrint(
              'HomeScreen: Previous following count: ${_followingUsers.length}');
          debugPrint(
              'HomeScreen: New following count: ${newFollowingUsers.length}');
          
          Set<String> unfollowedUsers =
              _followingUsers.difference(newFollowingUsers);
          Set<String> newlyFollowedUsers =
              newFollowingUsers.difference(_followingUsers);

          if (unfollowedUsers.isNotEmpty) {
            debugPrint(
                'HomeScreen: Unfollowed users: ${unfollowedUsers.toList()}');
          }

          if (newlyFollowedUsers.isNotEmpty) {
            debugPrint(
                'HomeScreen: Newly followed users: ${newlyFollowedUsers.toList()}');
          }

          setState(() {
            _followingUsers = newFollowingUsers;

            if (unfollowedUsers.isNotEmpty) {
              _posts = _posts
                  .where((post) =>
                          post.userId == userId || 
                          !unfollowedUsers.contains(
                              post.userId) // Remove unfollowed users' posts
                      )
                  .toList();
            }

            _filterPosts();
          });
        }
      }, onError: (error) {
        debugPrint('HomeScreen: Error in following listener: $error');
      });

      try {
        _postsSubscription =
            _firebaseService.getPostsStream(limit: 20).listen((event) {
          if (!mounted) return;

          debugPrint('HomeScreen: received posts stream update');
          if (event.snapshot.exists) {
            try {
              final posts = event.snapshot.children
                  .map((child) {
                    try {
                      debugPrint('Processing stream post: ${child.key}');
                      debugPrint('Stream post value: ${child.value}');
                      final post = Post.fromMap(
                          child.key!, child.value as Map<dynamic, dynamic>);
                      debugPrint(
                          'Created stream post with userId: ${post.userId}, timestamp: ${post.timestamp}');
                      return post;
                    } catch (e) {
                      debugPrint(
                          'Error processing stream post ${child.key}: $e');
                      return null;
                    }
                  })
                  .where((post) => post != null)
                  .cast<Post>()
                  .toList();

              if (mounted) {
                setState(() {
                  _allPosts = posts;
                  debugPrint(
                      'HomeScreen: updated posts to ${_allPosts.length}');
                  debugPrint(
                      'HomeScreen: post user IDs: ${_allPosts.map((p) => p.userId).toList()}');
                  _filterPosts();
                });
              }
            } catch (e) {
              debugPrint('HomeScreen: Error processing posts stream: $e');
            }
          }
        }, onError: (error) {
          debugPrint('HomeScreen: Error in posts listener: $error');
        });
      } catch (e) {
        debugPrint('HomeScreen: Error setting up posts stream: $e');
      }
    } catch (e) {
      debugPrint('HomeScreen: Error setting up listeners: $e');
    }
  }

  void _filterPosts() {
    final currentUser = _firebaseService.currentUser;
    if (currentUser == null) return;

    debugPrint('HomeScreen: filtering posts');
    debugPrint('Total posts before filtering: ${_allPosts.length}');
    debugPrint('Following users: ${_followingUsers.length}');
    debugPrint('Current user ID: ${currentUser.uid}');
    debugPrint(
        'All posts user IDs: ${_allPosts.map((p) => '${p.userId} (${p.timestamp})').toList()}');

    setState(() {
      if (_debugShowAllPosts) {
        _posts = List.from(_allPosts)
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        debugPrint(
            'DEBUG MODE: Showing all ${_posts.length} posts without filtering');
      } else {
        _posts = _allPosts.where((post) {
          final isOwnPost = post.userId == currentUser.uid;
          final isFollowingPost = _followingUsers.contains(post.userId);
          debugPrint(
              'Post ${post.id} - userId: ${post.userId}, isOwnPost: $isOwnPost, isFollowingPost: $isFollowingPost');
          return isOwnPost || isFollowingPost;
        }).toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        debugPrint(
            'Following posts count: ${_posts.where((p) => p.userId != currentUser.uid).length}');
        debugPrint(
            'Current user posts count: ${_posts.where((p) => p.userId == currentUser.uid).length}');
      }

      debugPrint('Total filtered posts: ${_posts.length}');

    });
  }

  @override
  void dispose() {
    debugPrint('HomeScreen: disposing');
    _followingSubscription?.cancel();
    _postsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _firebaseService.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: Center(
          child: Text('Please log in to view posts'),
        ),
      );
    }

    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('KnewLife'),
        actions: [
          IconButton(
            icon: const Icon(Icons.stars),
            onPressed: () {
              Navigator.pushNamed(context, '/monthly_theme');
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {
              Navigator.pushNamed(context, '/notifications');
            },
          ),
        ],
      ),
      body: _posts.isEmpty
          ? const Center(
              child: Text(
                'No posts yet. Follow some users to see their posts!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            )
          : ListView.builder(
              itemCount: _posts.length,
              itemBuilder: (context, index) {
                return PostCard(post: _posts[index]);
              },
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore),
            label: 'Discover',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_a_photo),
            label: 'Post',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.message),
            label: 'Messages',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        onTap: (index) {
          switch (index) {
            case 0:
              // Already on home
              break;
            case 1:
              Navigator.pushNamed(context, '/discover');
              break;
            case 2:
              Navigator.pushNamed(context, '/create_post');
              break;
            case 3:
              Navigator.pushNamed(context, '/messaging');
              break;
            case 4:
              Navigator.pushNamed(
                context,
                '/profile',
                arguments: currentUser.uid,
              );
              break;
          }
        },
      ),
    );
  }
}

class PostCard extends StatefulWidget {
  final Post post;

  const PostCard({super.key, required this.post});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  final _commentController = TextEditingController();
  final _firebaseService = FirebaseService();
  bool _showComments = false;
  bool _isLiked = false;
  int _likeCount = 0;
  List<Map<dynamic, dynamic>> _comments = [];
  StreamSubscription? _likeSubscription;
  StreamSubscription? _commentsSubscription;
  late String _displayUsername;

  @override
  void initState() {
    super.initState();
    debugPrint('PostCard: Initializing for post ID: ${widget.post.id}');
    debugPrint('PostCard: Post UserID: ${widget.post.userId}');
    debugPrint('PostCard: Post Username: ${widget.post.username}');
    debugPrint('PostCard: Post Caption: ${widget.post.caption}');
    debugPrint('PostCard: Post ImageURL: ${widget.post.imageUrl}');
    debugPrint('PostCard: Post Timestamp: ${widget.post.timestamp}');

    _displayUsername = _firebaseService.anonymizeUsername(
        widget.post.username, widget.post.userId);

    _initializeData();
  }

  Future<void> _initializeData() async {
    _isLiked = await _firebaseService.hasLikedPost(widget.post.id);

    _likeSubscription = _firebaseService.database
        .child('posts/${widget.post.id}/likes')
        .onValue
        .listen((event) {
      if (mounted) {
        setState(() {
          _likeCount =
              event.snapshot.exists ? event.snapshot.children.length : 0;
        });
      }
    });

    _commentsSubscription =
        _firebaseService.getComments(widget.post.id).listen((event) {
      if (mounted) {
        setState(() {
          _comments = event.snapshot.children
              .map((child) => child.value as Map<dynamic, dynamic>)
              .toList();
        });
      }
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _likeSubscription?.cancel();
    _commentsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty) return;

    try {
      await _firebaseService.addComment(
        widget.post.id,
        _commentController.text.trim(),
      );
      _commentController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding comment: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: GestureDetector(
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/profile',
                  arguments: widget.post.userId,
                );
              },
              child: CircleAvatar(
                backgroundImage: widget.post.userProfileImage != null &&
                        widget.post.userProfileImage!.isNotEmpty
                    ? CachedNetworkImageProvider(widget.post.userProfileImage!)
                    : null,
                child: widget.post.userProfileImage == null ||
                        widget.post.userProfileImage!.isEmpty
                    ? Text(_displayUsername[0].toUpperCase())
                    : null,
              ),
            ),
            title: GestureDetector(
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/profile',
                  arguments: widget.post.userId,
                );
              },
              child: Text(
                _displayUsername,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            subtitle: Text(
              '${widget.post.timestamp.day}/${widget.post.timestamp.month}/${widget.post.timestamp.year}',
            ),
            trailing: widget.post.userId == _firebaseService.currentUser?.uid
                ? PopupMenuButton(
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete Post'),
                      ),
                    ],
                    onSelected: (value) async {
                      if (value != 'delete') return;

                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Post'),
                          content: const Text(
                              'Are you sure you want to delete this post?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        try {
                          await _firebaseService.deletePost(widget.post.id);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Post deleted successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error deleting post: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    },
                  )
                : null,
          ),
          GestureDetector(
            onTap: () {
              setState(() => _showComments = !_showComments);
            },
            child: CachedNetworkImage(
              imageUrl: widget.post.imageUrl,
              placeholder: (context, url) => const Center(
                child: CircularProgressIndicator(),
              ),
              errorWidget: (context, url, error) => const Icon(Icons.error),
              fit: BoxFit.cover,
              width: double.infinity,
              height: 300,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.post.caption,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isLiked ? Icons.favorite : Icons.favorite_border,
                        color: _isLiked
                            ? Colors.red
                            : widget.post.userId ==
                                    _firebaseService.currentUser?.uid
                                ? Colors.grey
                                : null,
                      ),
                      onPressed: widget.post.userId ==
                              _firebaseService.currentUser?.uid
                          ? () {
                              // Show message when user tries to like their own post
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('You cannot like your own post'),
                                ),
                              );
                            }
                          : () async {
                              try {
                                if (_isLiked) {
                                  await _firebaseService
                                      .unlikePost(widget.post.id);
                                } else {
                                  await _firebaseService
                                      .likePost(widget.post.id);
                                }
                                setState(() => _isLiked = !_isLiked);
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              }
                            },
                    ),
                    Text(
                      '$_likeCount likes',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.comment),
                      onPressed: () {
                        setState(() => _showComments = !_showComments);
                      },
                    ),
                    Text(
                      '${_comments.length}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                if (_showComments) ...[
                  const Divider(),
                  ..._comments.map((comment) => ListTile(
                        leading: CircleAvatar(
                          child: Text(comment['username'][0].toUpperCase()),
                        ),
                        title: Text(comment['username']),
                        subtitle: Text(comment['text']),
                      )),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            decoration: const InputDecoration(
                              hintText: 'Add a comment...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: _addComment,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/post.dart';
import '../services/firebase_service.dart';

class MonthlyThemeScreen extends StatefulWidget {
  const MonthlyThemeScreen({Key? key}) : super(key: key);

  @override
  State<MonthlyThemeScreen> createState() => _MonthlyThemeScreenState();
}

class _MonthlyThemeScreenState extends State<MonthlyThemeScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  Map<String, dynamic> _currentTheme = {};
  List<Post> _topPosts = [];
  bool _isLoading = true;
  DateTime _nextReset = DateTime.now().add(const Duration(days: 30));

  @override
  void initState() {
    super.initState();
    _loadData();
    _calculateNextReset();
  }

  void _calculateNextReset() {
    // Calculate when the next 30-day cleanup will occur
    final now = DateTime.now();
    final oldestAllowedPostDate = now.subtract(const Duration(days: 30));

    // Calculate days remaining until oldest posts get deleted
    final daysRemaining = 30 - (now.difference(oldestAllowedPostDate).inDays);

    setState(() {
      _nextReset = now.add(Duration(days: daysRemaining));
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load monthly theme
      final theme = await _firebaseService.getCurrentMonthlyTheme();

      // Load leaderboard
      final leaderboard =
          await _firebaseService.getMonthlyLeaderboard(limit: 10);

      if (mounted) {
        setState(() {
          _currentTheme = theme;
          _topPosts = leaderboard;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading monthly theme data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly Theme'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Theme card
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CURRENT THEME',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _currentTheme['theme'] ?? 'No theme set',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _currentTheme['description'] ?? '',
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  const Icon(Icons.timer_outlined, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Reset in ${_nextReset.difference(DateTime.now()).inDays} days',
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Leaderboard
                      const Text(
                        'MONTHLY LEADERBOARD',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      _topPosts.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.0),
                                child: Text(
                                  'No posts yet this month. Be the first to post!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _topPosts.length,
                              itemBuilder: (context, index) {
                                final post = _topPosts[index];
                                final displayUsername =
                                    _firebaseService.anonymizeUsername(
                                  post.username,
                                  post.userId,
                                );

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.primaries[
                                              index % Colors.primaries.length],
                                          child: Text(
                                            '#${index + 1}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        title: Text(displayUsername),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.favorite,
                                                color: Colors.red),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${post.likes}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16.0),
                                        child: Text(post.caption),
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        height: 200,
                                        width: double.infinity,
                                        child: CachedNetworkImage(
                                          imageUrl: post.imageUrl,
                                          fit: BoxFit.cover,
                                          placeholder: (context, url) =>
                                              const Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              const Icon(Icons.error),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import '../services/firebase_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _firebaseService = FirebaseService();
  List<Map<dynamic, dynamic>> _searchResults = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final snapshot = await _firebaseService.database.child('users').get();
      if (snapshot.exists) {
        final users = snapshot.value as Map<dynamic, dynamic>;
        final results = users.entries.where((entry) {
          final user = entry.value as Map<dynamic, dynamic>;
          final username = user['username']?.toString().toLowerCase() ?? '';
          return username.contains(query.toLowerCase()) &&
              entry.key != _firebaseService.currentUser?.uid;
        }).map((entry) {
          final user = entry.value as Map<dynamic, dynamic>;
          return {
            'userId': entry.key,
            'username': user['username'],
            'profileImageUrl': user['profileImageUrl'],
          };
        }).toList();

        setState(() {
          _searchResults = results;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching users: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Users'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by username...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: _searchUsers,
            ),
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_searchResults.isEmpty && _searchController.text.isNotEmpty)
            const Center(
              child: Text('No users found'),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final user = _searchResults[index];
                  return FutureBuilder<bool>(
                    future: _firebaseService.isFollowing(user['userId']),
                    builder: (context, snapshot) {
                      final isFollowing = snapshot.data ?? false;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: user['profileImageUrl'] != null &&
                                  user['profileImageUrl'].toString().isNotEmpty
                              ? NetworkImage(user['profileImageUrl'])
                              : null,
                          child: user['profileImageUrl'] == null ||
                                  user['profileImageUrl'].toString().isEmpty
                              ? Text(user['username'][0].toUpperCase())
                              : null,
                        ),
                        title: Text(user['username']),
                        subtitle: Text(
                          isFollowing
                              ? 'You can view their posts'
                              : 'Follow to see their posts',
                          style: TextStyle(
                            fontSize: 12,
                            color: isFollowing ? Colors.green : Colors.grey,
                          ),
                        ),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            try {
                              if (isFollowing) {
                                await _firebaseService
                                    .unfollowUser(user['userId']);
                              } else {
                                await _firebaseService
                                    .followUser(user['userId']);
                              }
                              setState(() {}); // Refresh the list
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                isFollowing ? Colors.grey : Colors.blue,
                          ),
                          child: Text(isFollowing ? 'Unfollow' : 'Follow'),
                        ),
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/profile',
                            arguments: user['userId'],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

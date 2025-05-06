import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import '../services/firebase_service.dart';

class MessagingScreen extends StatefulWidget {
  const MessagingScreen({super.key});

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  StreamSubscription? _conversationsSubscription;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    if (_firebaseService.currentUser == null) return;

    setState(() => _isLoading = true);

    try {
      final userId = _firebaseService.currentUser!.uid;
      _conversationsSubscription = _firebaseService.database
          .child('users/$userId/conversations')
          .onValue
          .listen((event) async {
        if (!mounted) return;

        final conversations = <Map<String, dynamic>>[];

        if (event.snapshot.exists) {
          final conversationData =
              event.snapshot.value as Map<dynamic, dynamic>;

          // Convert to a list
          for (final entry in conversationData.entries) {
            final otherUserId = entry.key as String;

            // Get user details
            try {
              final userSnapshot = await _firebaseService.database
                  .child('users/$otherUserId')
                  .get();

              if (userSnapshot.exists) {
                final userData = userSnapshot.value as Map<dynamic, dynamic>;

                // Get the username and anonymize it
                final username =
                    userData['username'] as String? ?? 'Unknown User';
                final anonymizedUsername =
                    _firebaseService.anonymizeUsername(username, otherUserId);

                // Get last message
                final conversationId = [userId, otherUserId]..sort();
                final lastMessageSnapshot = await _firebaseService.database
                    .child('messages/${conversationId.join("_")}')
                    .orderByChild('timestamp')
                    .limitToLast(1)
                    .get();

                String lastMessage = '';
                int lastMessageTime = 0;
                bool unread = false;

                if (lastMessageSnapshot.exists) {
                  final messagesMap =
                      lastMessageSnapshot.value as Map<dynamic, dynamic>;
                  final message =
                      messagesMap.values.first as Map<dynamic, dynamic>;
                  lastMessage = message['text'] as String;
                  lastMessageTime = message['timestamp'] as int;
                  unread = message['senderId'] != userId &&
                      !(message['read'] as bool? ?? false);
                }

                conversations.add({
                  'userId': otherUserId,
                  'username': anonymizedUsername,
                  'profileImage': userData['profileImageUrl'] as String? ?? '',
                  'lastMessage': lastMessage,
                  'lastMessageTime': lastMessageTime,
                  'unread': unread,
                });
              }
            } catch (e) {
              debugPrint('Error loading conversation details: $e');
            }
          }
        }

        // Sort by most recent message
        conversations.sort((a, b) => (b['lastMessageTime'] as int)
            .compareTo(a['lastMessageTime'] as int));

        setState(() {
          _conversations = conversations;
          _isLoading = false;
        });
      });
    } catch (e) {
      debugPrint('Error loading conversations: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _conversationsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              // Navigate to a screen to select a user to message
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NewMessageScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'No messages yet',
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const NewMessageScreen(),
                            ),
                          );
                        },
                        child: const Text('Start a new conversation'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = _conversations[index];

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: conversation['profileImage'] != null &&
                                conversation['profileImage']
                                    .toString()
                                    .isNotEmpty
                            ? NetworkImage(conversation['profileImage'])
                            : null,
                        child: conversation['profileImage'] == null ||
                                conversation['profileImage'].toString().isEmpty
                            ? Text(
                                (conversation['username'] as String).isNotEmpty
                                    ? (conversation['username'] as String)[0]
                                        .toUpperCase()
                                    : '?')
                            : null,
                      ),
                      title: Text(
                        conversation['username'] as String,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        conversation['lastMessage'] as String? ??
                            'No messages yet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _getTimeAgo(conversation['lastMessageTime'] as int),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          if (conversation['unread'] as bool)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              userId: conversation['userId'] as String,
                              username: conversation['username'] as String,
                              profileImage:
                                  conversation['profileImage'] as String,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }

  String _getTimeAgo(int timestamp) {
    if (timestamp == 0) return '';

    final now = DateTime.now();
    final difference = now.millisecondsSinceEpoch - timestamp;
    final seconds = difference ~/ 1000;

    if (seconds < 60) {
      return 'just now';
    } else if (seconds < 60 * 60) {
      final minutes = seconds ~/ 60;
      return '$minutes m';
    } else if (seconds < 60 * 60 * 24) {
      final hours = seconds ~/ (60 * 60);
      return '$hours h';
    } else if (seconds < 60 * 60 * 24 * 7) {
      final days = seconds ~/ (60 * 60 * 24);
      return '$days d';
    } else {
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return '${date.month}/${date.day}';
    }
  }
}

class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key});

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
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
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching users: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Message'),
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

                  // Anonymize username
                  final anonymizedUsername = _firebaseService.anonymizeUsername(
                      user['username'] as String, user['userId'] as String);

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: user['profileImageUrl'] != null &&
                              user['profileImageUrl'].toString().isNotEmpty
                          ? NetworkImage(user['profileImageUrl'])
                          : null,
                      child: user['profileImageUrl'] == null ||
                              user['profileImageUrl'].toString().isEmpty
                          ? Text(anonymizedUsername[0].toUpperCase())
                          : null,
                    ),
                    title: Text(anonymizedUsername),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            userId: user['userId'] as String,
                            username: user['username']
                                as String, // Keep original for internal use
                            profileImage:
                                user['profileImageUrl'] as String? ?? '',
                          ),
                        ),
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

class ChatScreen extends StatefulWidget {
  final String userId;
  final String username;
  final String profileImage;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.username,
    required this.profileImage,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _firebaseService = FirebaseService();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  late StreamSubscription _messagesSubscription;
  String _conversationId = '';

  @override
  void initState() {
    super.initState();
    _setupConversation();
  }

  Future<void> _setupConversation() async {
    final currentUser = _firebaseService.currentUser;
    if (currentUser == null) return;

    setState(() => _isLoading = true);

    // Create or get conversation ID
    final userId1 = currentUser.uid;
    final userId2 = widget.userId;

    // Create a consistent conversation ID by sorting user IDs
    final userIds = [userId1, userId2];
    userIds.sort(); // Sort the user IDs alphabetically
    _conversationId = userIds.join('_'); // Join with underscore

    // Add conversation to both users' lists if it doesn't exist
    await _firebaseService.database
        .child('users/$userId1/conversations/$userId2')
        .set({'createdAt': ServerValue.timestamp});

    await _firebaseService.database
        .child('users/$userId2/conversations/$userId1')
        .set({'createdAt': ServerValue.timestamp});

    // Listen for messages
    _messagesSubscription = _firebaseService.database
        .child('messages/$_conversationId')
        .orderByChild('timestamp')
        .onValue
        .listen((event) {
      if (!mounted) return;

      final messages = <Map<String, dynamic>>[];

      if (event.snapshot.exists) {
        final messagesData = event.snapshot.value as Map<dynamic, dynamic>;

        messagesData.forEach((key, value) {
          if (value is Map<dynamic, dynamic>) {
            messages.add({
              'id': key,
              'senderId': value['senderId'],
              'text': value['text'],
              'timestamp': value['timestamp'],
              'read': value['read'] ?? false,
            });
          }
        });

        // Mark messages as read
        for (final message in messages) {
          if (message['senderId'] != currentUser.uid && !message['read']) {
            _firebaseService.database
                .child('messages/$_conversationId/${message['id']}/read')
                .set(true);
          }
        }

        // Sort by timestamp (oldest first)
        messages.sort(
            (a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));
      }

      setState(() {
        _messages = messages;
        _isLoading = false;
      });

      // Scroll to bottom when new messages arrive
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;

    final currentUser = _firebaseService.currentUser;
    if (currentUser == null) return;

    try {
      // Add message to database
      final messageRef =
          _firebaseService.database.child('messages/$_conversationId').push();

      await messageRef.set({
        'senderId': currentUser.uid,
        'text': message,
        'timestamp': ServerValue.timestamp,
        'read': false,
      });

      _messageController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending message: $e')),
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messagesSubscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _firebaseService.currentUser;

    // Get anonymized username for the chat partner
    final anonymizedUsername =
        _firebaseService.anonymizeUsername(widget.username, widget.userId);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: widget.profileImage.isNotEmpty
                  ? NetworkImage(widget.profileImage)
                  : null,
              child: widget.profileImage.isEmpty
                  ? Text(anonymizedUsername.isNotEmpty
                      ? anonymizedUsername[0].toUpperCase()
                      : '?')
                  : null,
            ),
            const SizedBox(width: 8),
            Text(anonymizedUsername),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(
                          child: Text('No messages yet. Say hello!'),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isSentByMe =
                                message['senderId'] == currentUser?.uid;

                            return Align(
                              alignment: isSentByMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 8,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isSentByMe
                                      ? Colors.blue
                                      : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: isSentByMe
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _getSenderName(message['senderId']),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isSentByMe
                                            ? Colors.white.withOpacity(0.8)
                                            : Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      message['text'] as String,
                                      style: TextStyle(
                                        color: isSentByMe
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: const Offset(0, -1),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        color: Colors.blue,
                        onPressed: _sendMessage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  String _formatTime(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    if (dateTime.day == now.day &&
        dateTime.month == now.month &&
        dateTime.year == now.year) {
      // Today
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (dateTime.day == now.day - 1 &&
        dateTime.month == now.month &&
        dateTime.year == now.year) {
      // Yesterday
      return 'Yesterday ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      // Other day
      return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  // Get anonymized name for message sender
  String _getSenderName(String senderId) {
    if (senderId == _firebaseService.currentUser?.uid) {
      return "You";
    } else {
      return _firebaseService.anonymizeUsername(widget.username, widget.userId);
    }
  }
}

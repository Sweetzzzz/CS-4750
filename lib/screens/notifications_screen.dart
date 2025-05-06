import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import '../services/firebase_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  StreamSubscription? _notificationsSubscription;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (_firebaseService.currentUser == null) return;

    setState(() => _isLoading = true);

    try {
      final userId = _firebaseService.currentUser!.uid;
      _notificationsSubscription = _firebaseService.database
          .child('users/$userId/notifications')
          .orderByChild('timestamp')
          .onValue
          .listen((event) {
        if (!mounted) return;

        final notifications = <Map<String, dynamic>>[];

        if (event.snapshot.exists) {
          final notificationData =
              event.snapshot.value as Map<dynamic, dynamic>;

          // Convert to a list and sort by timestamp (newest first)
          notificationData.forEach((key, value) {
            if (value is Map<dynamic, dynamic>) {
              notifications.add({
                'id': key,
                'type': value['type'],
                'senderId': value['senderId'],
                'senderName': value['senderName'],
                'senderImage': value['senderImage'],
                'message': value['message'],
                'postId': value['postId'],
                'read': value['read'] ?? false,
                'timestamp': value['timestamp'],
              });
            }
          });
        }

        // Sort newest first
        notifications.sort(
            (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
      });
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      setState(() => _isLoading = false);
    }
  }

  // Mark notification as read
  void _markAsRead(String notificationId) {
    if (_firebaseService.currentUser == null) return;

    final userId = _firebaseService.currentUser!.uid;
    _firebaseService.database
        .child('users/$userId/notifications/$notificationId/read')
        .set(true);
  }

  @override
  void dispose() {
    _notificationsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const Center(child: Text('No notifications yet'))
              : ListView.builder(
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final notification = _notifications[index];
                    final bool isRead = notification['read'] as bool;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: notification['senderImage'] != null &&
                                notification['senderImage']
                                    .toString()
                                    .isNotEmpty
                            ? NetworkImage(notification['senderImage'])
                            : null,
                        child: notification['senderImage'] == null ||
                                notification['senderImage'].toString().isEmpty
                            ? Text((notification['senderName'] as String)
                                    .isNotEmpty
                                ? (notification['senderName'] as String)[0]
                                    .toUpperCase()
                                : '?')
                            : null,
                      ),
                      title: RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            TextSpan(
                              text: notification['senderName'] as String,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            TextSpan(
                              text: ' ${notification['message']}',
                            ),
                          ],
                        ),
                      ),
                      subtitle: Text(
                        _getTimeAgo(notification['timestamp'] as int),
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      tileColor: isRead ? null : Colors.blue.withOpacity(0.1),
                      onTap: () {
                        // Mark as read
                        if (!isRead) {
                          _markAsRead(notification['id'] as String);
                        }

                        // Navigate based on notification type
                        final type = notification['type'] as String;
                        if (type == 'follow') {
                          Navigator.pushNamed(
                            context,
                            '/profile',
                            arguments: notification['senderId'] as String,
                          );
                        } else if (type == 'like' &&
                            notification['postId'] != null) {
                          // TODO: Navigate to post detail when implemented
                          Navigator.pushNamed(
                            context,
                            '/profile',
                            arguments: notification['senderId'] as String,
                          );
                        }
                      },
                    );
                  },
                ),
    );
  }

  String _getTimeAgo(int timestamp) {
    final now = DateTime.now();
    final difference = now.millisecondsSinceEpoch - timestamp;
    final seconds = difference ~/ 1000;

    if (seconds < 60) {
      return 'just now';
    } else if (seconds < 60 * 60) {
      final minutes = seconds ~/ 60;
      return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
    } else if (seconds < 60 * 60 * 24) {
      final hours = seconds ~/ (60 * 60);
      return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
    } else if (seconds < 60 * 60 * 24 * 7) {
      final days = seconds ~/ (60 * 60 * 24);
      return '$days ${days == 1 ? 'day' : 'days'} ago';
    } else {
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return '${date.month}/${date.day}/${date.year}';
    }
  }
}

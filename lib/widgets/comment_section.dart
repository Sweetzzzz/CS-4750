import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/firebase_service.dart';

class CommentSection extends StatefulWidget {
  final String postId;
  final FirebaseService firebaseService;

  const CommentSection({
    super.key,
    required this.postId,
    required this.firebaseService,
  });

  @override
  State<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends State<CommentSection> {
  final _commentController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty) return;

    setState(() => _isLoading = true);

    try {
      await widget.firebaseService.addComment(
        widget.postId,
        _commentController.text.trim(),
      );
      _commentController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding comment: $e')),
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
    return Column(
      children: [
        StreamBuilder<DatabaseEvent>(
          stream: widget.firebaseService.getComments(widget.postId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }

            if (!snapshot.hasData || !snapshot.data!.snapshot.exists) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No comments yet'),
              );
            }

            final comments = snapshot.data!.snapshot.children.toList()
              ..sort((a, b) {
                final aTime = a.child('timestamp').value as int? ?? 0;
                final bTime = b.child('timestamp').value as int? ?? 0;
                return bTime.compareTo(aTime);
              });

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: comments.length,
              itemBuilder: (context, index) {
                final comment = comments[index];
                final username = comment.child('username').value as String? ??
                    'Unknown User';
                final text = comment.child('text').value as String? ?? '';
                final userId = comment.child('userId').value as String? ?? '';

                return ListTile(
                  title: Text(username),
                  subtitle: Text(text),
                  trailing: userId == widget.firebaseService.currentUser?.uid
                      ? IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () async {
                            try {
                              await widget.firebaseService.deleteComment(
                                widget.postId,
                                comment.key!,
                              );
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('Error deleting comment: $e')),
                                );
                              }
                            }
                          },
                        )
                      : null,
                );
              },
            );
          },
        ),
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
                  onSubmitted: (_) => _addComment(),
                ),
              ),
              IconButton(
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                onPressed: _isLoading ? null : _addComment,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

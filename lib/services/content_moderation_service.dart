import 'package:flutter/foundation.dart';
import 'offensive_words.dart';

class ContentModerationService {
  // Initialize with the lists from offensive_words.dart
  final List<String> _offensiveWords = List.from(offensiveWords);
  final List<String> _offensivePatterns = List.from(offensivePatterns);

  // Check if content contains offensive language
  bool containsOffensiveLanguage(String text) {
    if (text.isEmpty) return false;

    // Convert to lowercase for case-insensitive matching
    final lowerText = text.toLowerCase();

    // Check against offensive words
    for (final word in _offensiveWords) {
      if (lowerText.contains(word.toLowerCase())) {
        debugPrint('Offensive word detected: $word');
        return true;
      }
    }

    // Check against offensive patterns
    for (final pattern in _offensivePatterns) {
      if (RegExp(pattern).hasMatch(lowerText)) {
        debugPrint('Offensive pattern detected: $pattern');
        return true;
      }
    }

    return false;
  }

  // Moderate post content
  bool moderatePost({
    required String caption,
    required String userId,
    required String postId,
  }) {
    final isClean = !containsOffensiveLanguage(caption);
    if (!isClean) {
      debugPrint('Post $postId by user $userId contains offensive content');
    }
    return isClean;
  }

  // Moderate comment
  bool moderateComment({
    required String text,
    required String userId,
    required String commentId,
  }) {
    final isClean = !containsOffensiveLanguage(text);
    if (!isClean) {
      debugPrint(
          'Comment $commentId by user $userId contains offensive content');
    }
    return isClean;
  }

  // Moderate message
  bool moderateMessage({
    required String text,
    required String userId,
    required String messageId,
  }) {
    final isClean = !containsOffensiveLanguage(text);
    if (!isClean) {
      debugPrint(
          'Message $messageId by user $userId contains offensive content');
    }
    return isClean;
  }

  // Report content
  Future<bool> reportContent({
    required String contentId,
    required String contentType,
    required String reason,
    required String reporterId,
  }) async {
    // In a real implementation, this would store the report in a database
    debugPrint('Content reported: $contentType with ID: $contentId');
    debugPrint('Reason: $reason');
    debugPrint('Reported by: $reporterId');
    return true;
  }

  // Add a word to the offensive words list
  void addOffensiveWord(String word) {
    if (!_offensiveWords.contains(word.toLowerCase())) {
      _offensiveWords.add(word.toLowerCase());
      debugPrint('Added new offensive word: $word');
    }
  }

  // Add a pattern to the offensive patterns list
  void addOffensivePattern(String pattern) {
    if (!_offensivePatterns.contains(pattern)) {
      _offensivePatterns.add(pattern);
      debugPrint('Added new offensive pattern: $pattern');
    }
  }
}

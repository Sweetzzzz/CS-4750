import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/create_post_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/search_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/messaging_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/monthly_theme_screen.dart';
import 'screens/admin_screen.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'services/firebase_service.dart';
import 'services/config_service.dart';
import 'models/post.dart';
import 'dart:async';

bool isProduction = true; // Set to true for production builds

// Schedule post cleanup every 24 hours
void schedulePostCleanup() {
  if (!isProduction) {
    debugPrint('Running scheduled post cleanup');
  }
  Timer.periodic(const Duration(hours: 24), (timer) async {
    try {
      // Check if Firebase is initialized before proceeding
      if (Firebase.apps.isNotEmpty) {
        final firebaseService = FirebaseService();
        await firebaseService.initialize();
        await firebaseService.cleanupOldPosts();
        if (!isProduction) {
          debugPrint('Scheduled post cleanup completed successfully');
        }
      } else {
        if (!isProduction) {
          debugPrint(
              'Skipping scheduled post cleanup - Firebase not initialized');
        }
      }
    } catch (e) {
      if (!isProduction) {
        debugPrint('Error during scheduled post cleanup: $e');
      }
    }
  });
}

Future<void> initializeApp() async {
  try {
    if (!isProduction) {
      debugPrint('Starting app initialization...');
    }

    // Initialize FirebaseService
    final firebaseService = FirebaseService();
    await firebaseService.initialize();

    // Initialize configuration service
    final configService = ConfigService();
    await configService.initialize();

    if (!isProduction) {
      debugPrint('Initializing Firebase App Check...');
    }
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.deviceCheck,
    );
    if (!isProduction) {
      debugPrint('Firebase App Check initialized successfully');
    }

    // Start post cleanup schedule
    schedulePostCleanup();
  } catch (e, stackTrace) {
    if (!isProduction) {
      debugPrint('Error initializing app: $e');
    }
    debugPrint('Stack trace: $stackTrace');
    rethrow;
  }
}

void main() async {
  try {
    if (!isProduction) {
      debugPrint('Starting app initialization...');
    }
    WidgetsFlutterBinding.ensureInitialized();
    if (!isProduction) {
      debugPrint('Flutter binding initialized');
    }

    // Load environment variables first
    await dotenv.load(fileName: ".env");
    if (!isProduction) {
      debugPrint('Environment variables loaded');
    }

    // Initialize Firebase, handling the case where it might already be initialized
    FirebaseApp app;
    try {
      app = await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: dotenv.env['FIREBASE_API_KEY'] ?? '',
          authDomain: dotenv.env['FIREBASE_AUTH_DOMAIN'] ?? '',
          projectId: dotenv.env['FIREBASE_PROJECT_ID'] ?? '',
          storageBucket: dotenv.env['FIREBASE_STORAGE_BUCKET'] ?? '',
          messagingSenderId: dotenv.env['FIREBASE_MESSAGING_SENDER_ID'] ?? '',
          appId: dotenv.env['FIREBASE_APP_ID'] ?? '',
        ),
      );
      if (!isProduction) {
        debugPrint('Firebase newly initialized successfully');
      }
    } catch (e) {
      if (e.toString().contains('duplicate-app')) {
        // Firebase is already initialized, get the existing instance
        app = Firebase.app();
        if (!isProduction) {
          debugPrint('Using existing Firebase app: ${app.name}');
        }
      } else {
        // Some other initialization error occurred
        rethrow;
      }
    }

    // Initialize the rest of the app
    await initializeApp();
    if (!isProduction) {
      debugPrint('App initialization completed');
    }

    if (!isProduction) {
      debugPrint('Starting app...');
    }
    runApp(const MyApp());
  } catch (e, stackTrace) {
    if (!isProduction) {
      debugPrint('Error in main: $e');
    }
    debugPrint('Stack trace: $stackTrace');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error initializing app: $e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (!isProduction) {
      debugPrint('Building MyApp widget');
    }
    return MaterialApp(
      title: 'Instagram Clone',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/home': (context) => HomeScreen(),
        '/create_post': (context) => const CreatePostScreen(),
        '/profile': (context) => ProfileScreen(
              userId: ModalRoute.of(context)!.settings.arguments as String,
            ),
        '/edit_profile': (context) => const EditProfileScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/search': (context) => const SearchScreen(),
        '/notifications': (context) => const NotificationsScreen(),
        '/messaging': (context) => const MessagingScreen(),
        '/discover': (context) => const DiscoverScreen(),
        '/monthly_theme': (context) => const MonthlyThemeScreen(),
        '/admin': (context) => const AdminScreen(),
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    if (!isProduction) {
      debugPrint('Building AuthWrapper widget');
    }
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!isProduction) {
          debugPrint(
              'AuthState changed. Connection state: ${snapshot.connectionState}');
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          if (!isProduction) {
            debugPrint('Waiting for auth state...');
          }
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading...', style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          if (!isProduction) {
            debugPrint('Auth error: ${snapshot.error}');
          }
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasData) {
          if (!isProduction) {
            debugPrint('User is logged in, navigating to HomeScreen');
          }
          return const HomeScreen();
        }

        if (!isProduction) {
          debugPrint('No user logged in, navigating to LoginScreen');
        }
        return const LoginScreen();
      },
    );
  }
}

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({Key? key}) : super(key: key);

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  List<Map<String, dynamic>> _suggestedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSuggestedUsers();
  }

  Future<void> _loadSuggestedUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final suggestions = await _firebaseService.getSuggestedUsers(limit: 20);

      // Anonymize usernames for all suggested users
      final anonymizedSuggestions = suggestions.map((user) {
        final anonymizedUsername = _firebaseService.anonymizeUsername(
            user['username'] as String, user['userId'] as String);

        return {
          ...user,
          'displayName': anonymizedUsername,
        };
      }).toList();

      if (mounted) {
        setState(() {
          _suggestedUsers = anonymizedSuggestions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!isProduction) {
        debugPrint('Error loading suggested users: $e');
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
              ? const Center(child: Text('No suggestions available'))
              : ListView.builder(
                  itemCount: _suggestedUsers.length,
                  itemBuilder: (context, index) {
                    final user = _suggestedUsers[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: user['profileImageUrl'] != null &&
                                user['profileImageUrl'].isNotEmpty
                            ? CachedNetworkImageProvider(
                                user['profileImageUrl'])
                            : null,
                        child: user['profileImageUrl'] == null ||
                                user['profileImageUrl'].isEmpty
                            ? Text(user['displayName'][0].toUpperCase())
                            : null,
                      ),
                      title: Text(user['displayName']),
                      trailing: ElevatedButton(
                        onPressed: () async {
                          await _firebaseService.followUser(user['userId']);
                          // Refresh the list
                          _loadSuggestedUsers();
                        },
                        child: const Text('Follow'),
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
                ),
    );
  }
}

class MonthlyThemeScreen extends StatefulWidget {
  const MonthlyThemeScreen({Key? key}) : super(key: key);

  @override
  State<MonthlyThemeScreen> createState() => _MonthlyThemeScreenState();
}

class _MonthlyThemeScreenState extends State<MonthlyThemeScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  List<Post> _topPosts = [];
  Map<String, dynamic> _currentTheme = {};
  bool _isLoading = true;
  DateTime _nextReset = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadData();
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
          _calculateNextReset();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!isProduction) {
        debugPrint('Error loading monthly theme data: $e');
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _calculateNextReset() {
    final now = DateTime.now();

    // Calculate the last day of the current month
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);

    // Days remaining until end of month
    final daysRemaining = lastDayOfMonth.difference(now).inDays;

    setState(() {
      _nextReset = lastDayOfMonth;
    });
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
          : Column(
              children: [
                // Theme card
                Card(
                  margin: const EdgeInsets.all(16.0),
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
                          _currentTheme['theme'] ?? 'Express Yourself',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_currentTheme['description'] != null &&
                            _currentTheme['description'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Text(
                              _currentTheme['description'],
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        Row(
                          children: [
                            const Icon(Icons.timer_outlined,
                                size: 16, color: Colors.red),
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

                // Leaderboard header
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      const Text(
                        'MONTHLY LEADERBOARD',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_topPosts.length} posts',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                // Leaderboard list
                Expanded(
                  child: _topPosts.isEmpty
                      ? const Center(child: Text('No posts yet this month'))
                      : ListView.builder(
                          itemCount: _topPosts.length,
                          itemBuilder: (context, index) {
                            final post = _topPosts[index];
                            final displayUsername =
                                _firebaseService.anonymizeUsername(
                              post.username,
                              post.userId,
                            );

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16.0, vertical: 4.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.blue,
                                      child: Text(
                                        '#${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(displayUsername),
                                    subtitle: Text(post.caption),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.favorite,
                                            color: Colors.red),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${post.likes}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    height: 200,
                                    width: double.infinity,
                                    child: post.imageUrl.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: post.imageUrl,
                                            fit: BoxFit.cover,
                                            placeholder: (context, url) =>
                                                const Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                            errorWidget:
                                                (context, url, error) =>
                                                    const Icon(Icons.error),
                                          )
                                        : const Center(
                                            child: Icon(Icons.image,
                                                size: 48, color: Colors.grey),
                                          ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

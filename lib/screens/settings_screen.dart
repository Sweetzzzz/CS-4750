import 'package:flutter/material.dart';
import '../services/firebase_service.dart';
import '../services/admin_service.dart';
import 'dart:convert';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final AdminService _adminService = AdminService();
  bool _isAdmin = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    final currentUser = _firebaseService.currentUser;
    debugPrint('Checking admin status for user: ${currentUser?.uid}');
    if (currentUser != null) {
      final isAdmin = await _adminService.isAdmin(currentUser.uid);
      debugPrint('User admin status: $isAdmin');
      setState(() => _isAdmin = isAdmin);
    } else {
      debugPrint('No current user found');
    }
    debugPrint('Building settings screen with admin status: $_isAdmin');
  }

  Future<void> _exportUserData() async {
    setState(() => _isProcessing = true);

    try {
      final userData = await _firebaseService.getUserDataExport();

      // Create a formatted data string
      final formattedData =
          const JsonEncoder.withIndent('  ').convert(userData);

      // Show data in a dialog
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Your Data Export'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: SelectableText(formattedData),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () {
                  // Implement download or share functionality here
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Data saved to downloads folder')),
                  );
                },
                child: const Text('Download'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting data: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Account'),
            content: const Text(
              'Are you sure you want to delete your account? This action cannot be undone, and all your data will be permanently removed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child:
                    const Text('Delete', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    // Double confirmation for account deletion
    final doubleConfirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Final Confirmation'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Please confirm once more that you want to permanently delete your account and all associated data. Type "DELETE" to confirm.',
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Type DELETE to confirm',
                  ),
                  onChanged: (value) {
                    if (value == 'DELETE') {
                      Navigator.pop(context, true);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ) ??
        false;

    if (!doubleConfirmed) return;

    setState(() => _isProcessing = true);

    try {
      await _firebaseService.deleteUserAccount();

      if (mounted) {
        // Navigate to login screen after successful deletion
        Navigator.pushReplacementNamed(context, '/login');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your account has been successfully deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Stack(
        children: [
          ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Edit Profile'),
                onTap: () {
                  Navigator.pushNamed(context, '/edit_profile');
                },
              ),
              ListTile(
                leading: const Icon(Icons.notifications),
                title: const Text('Notifications'),
                onTap: () {
                  Navigator.pushNamed(context, '/notifications');
                },
              ),

              // GDPR Compliance Section
              const Divider(),
              const Padding(
                padding: EdgeInsets.only(left: 16, top: 8),
                child: Text(
                  'Privacy & Data',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.security),
                title: const Text('Privacy Settings'),
                onTap: () {
                  // TODO: Implement privacy settings
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Privacy settings coming soon')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.policy),
                title: const Text('Privacy Policy'),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Privacy Policy'),
                      content: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'Our Privacy Policy',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Last updated: January, 2024\n\n'
                              '1. Data We Collect\n'
                              'We collect information you provide when using our app, including profile information, posts, and messages.\n\n'
                              '2. How We Use Your Data\n'
                              'We use your data to provide and improve our services, personalize your experience, and communicate with you.\n\n'
                              '3. Data Sharing\n'
                              'We do not sell your personal data. We share data with third parties only as necessary to provide our services.\n\n'
                              '4. Your Rights\n'
                              'You have the right to access, correct, delete, and export your personal data.\n\n'
                              '5. Data Security\n'
                              'We implement appropriate security measures to protect your data.\n\n'
                              '6. Contact Us\n'
                              'If you have any questions about our privacy practices, please contact us.',
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Export Your Data'),
                subtitle: const Text('Download a copy of your data (GDPR)'),
                onTap: _isProcessing ? null : _exportUserData,
              ),

              // Help & Info Section
              const Divider(),
              const Padding(
                padding: EdgeInsets.only(left: 16, top: 8),
                child: Text(
                  'Help & Info',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.help),
                title: const Text('Help'),
                onTap: () {
                  // TODO: Implement help section
                },
              ),
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('About'),
                onTap: () {
                  // TODO: Implement about section
                },
              ),

              // Admin Section
              if (_isAdmin) ...[
                const Divider(),
                const Padding(
                  padding: EdgeInsets.only(left: 16, top: 8),
                  child: Text(
                    'Admin',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings),
                  title: const Text('Admin Panel'),
                  onTap: () {
                    Navigator.pushNamed(context, '/admin');
                  },
                ),
              ],

              // Account Section
              const Divider(),
              const Padding(
                padding: EdgeInsets.only(left: 16, top: 8),
                child: Text(
                  'Account',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.orange),
                title: const Text('Logout',
                    style: TextStyle(color: Colors.orange)),
                onTap: _isProcessing
                    ? null
                    : () async {
                        try {
                          await _firebaseService.signOut();
                          if (mounted) {
                            Navigator.pushReplacementNamed(context, '/login');
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error signing out: $e')),
                            );
                          }
                        }
                      },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Delete Account',
                    style: TextStyle(color: Colors.red)),
                subtitle:
                    const Text('Permanently delete your account and all data'),
                onTap: _isProcessing ? null : _deleteAccount,
              ),
              const SizedBox(height: 40), // Bottom padding
            ],
          ),
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}

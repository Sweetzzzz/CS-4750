import 'package:flutter/material.dart';
import '../services/admin_service.dart';
import '../services/firebase_service.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final AdminService _adminService = AdminService();
  final FirebaseService _firebaseService = FirebaseService();
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    _loadUsers();
  }

  Future<void> _checkAdminStatus() async {
    final currentUser = _firebaseService.currentUser;
    if (currentUser != null) {
      final isAdmin = await _adminService.isAdmin(currentUser.uid);
      setState(() => _isAdmin = isAdmin);
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);

    try {
      final snapshot = await _firebaseService.database.child('users').get();
      if (snapshot.exists) {
        final users = <Map<String, dynamic>>[];
        for (final child in snapshot.children) {
          final userData = child.value as Map<dynamic, dynamic>;
          users.add({
            'userId': child.key,
            'username': userData['username'] ?? 'Unknown',
            'email': userData['email'] ?? '',
            'isAdmin': userData['isAdmin'] ?? false,
            'isBanned': userData['isBanned'] ?? false,
          });
        }
        setState(() => _users = users);
      }
    } catch (e) {
      debugPrint('Error loading users: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showUserActions(Map<String, dynamic> user) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('User: ${user['username']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!user['isAdmin'])
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Make Admin'),
                onTap: () => Navigator.pop(context, 'make_admin'),
              ),
            if (user['isAdmin'])
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Remove Admin'),
                onTap: () => Navigator.pop(context, 'remove_admin'),
              ),
            if (!user['isBanned'])
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Ban User'),
                onTap: () => Navigator.pop(context, 'ban'),
              ),
            if (user['isBanned'])
              ListTile(
                leading: const Icon(Icons.check_circle),
                title: const Text('Unban User'),
                onTap: () => Navigator.pop(context, 'unban'),
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete User',
                  style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      switch (result) {
        case 'make_admin':
          await _adminService.makeAdmin(user['userId']);
          break;
        case 'remove_admin':
          await _adminService.removeAdmin(user['userId']);
          break;
        case 'ban':
          await _adminService.banUser(user['userId']);
          break;
        case 'unban':
          await _adminService.unbanUser(user['userId']);
          break;
        case 'delete':
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete User'),
              content: Text(
                  'Are you sure you want to delete ${user['username']}? This action cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child:
                      const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await _adminService.deleteUser(user['userId']);
          }
          break;
      }
      _loadUsers();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const Scaffold(
        body: Center(
          child: Text('Access Denied: Admin privileges required'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(user['username'][0].toUpperCase()),
                  ),
                  title: Text(user['username']),
                  subtitle: Text(user['email']),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (user['isAdmin'])
                        const Icon(Icons.admin_panel_settings,
                            color: Colors.blue),
                      if (user['isBanned'])
                        const Icon(Icons.block, color: Colors.red),
                    ],
                  ),
                  onTap: () => _showUserActions(user),
                );
              },
            ),
    );
  }
}

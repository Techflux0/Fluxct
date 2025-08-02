// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_services.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _usernameController;
  late TextEditingController _displayNameController;
  late TextEditingController _bioController;
  late String _photoUrl;

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = FirebaseAuth.instance.currentUser;

    _usernameController = TextEditingController(
      text: authService.getCurrentUsername(),
    );
    _displayNameController = TextEditingController(
      text: currentUser?.displayName,
    );
    _bioController = TextEditingController();
    _photoUrl = currentUser?.photoURL ?? '';

    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final userId = Provider.of<AuthService>(
      context,
      listen: false,
    ).getCurrentUserId();
    if (userId == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    if (doc.exists) {
      setState(() {
        _usernameController.text = doc.data()?['username'] ?? '';
        _displayNameController.text = doc.data()?['displayName'] ?? '';
        _bioController.text = doc.data()?['bio'] ?? '';
        _photoUrl = doc.data()?['photoUrl'] ?? '';
      });
    }
  }

  Future<void> _saveProfile() async {
    final userId = Provider.of<AuthService>(
      context,
      listen: false,
    ).getCurrentUserId();
    if (userId == null) return;

    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'username': _usernameController.text,
      'displayName': _displayNameController.text,
      'bio': _bioController.text,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    // Update Firebase Auth profile if display name changed
    await FirebaseAuth.instance.currentUser?.updateDisplayName(
      _displayNameController.text,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated successfully')),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saveProfile),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage: _photoUrl.isNotEmpty
                      ? NetworkImage(_photoUrl)
                      : null,
                  child: _photoUrl.isEmpty
                      ? const Icon(Icons.person, size: 50)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.white),
                    onPressed: () {
                      // Implement photo upload
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixText: '@',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _displayNameController,
            decoration: const InputDecoration(
              labelText: 'Display Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _bioController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Bio',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Account Settings',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          ListTile(
            leading: const Icon(Icons.email),
            title: const Text('Email'),
            subtitle: Text(FirebaseAuth.instance.currentUser?.email ?? ''),
            onTap: () {
              // Implement email change
            },
          ),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Privacy'),
            onTap: () {
              // Navigate to privacy settings
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications),
            title: const Text('Notifications'),
            onTap: () {
              // Navigate to notification settings
            },
          ),
        ],
      ),
    );
  }
}

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
  bool _isSaving = false;

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
    setState(() => _isSaving = true);
    try {
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

      await FirebaseAuth.instance.currentUser?.updateDisplayName(
        _displayNameController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile updated successfully'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
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
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _isSaving
                ? const CircularProgressIndicator()
                : IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: _saveProfile,
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Picture Section
            Center(
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.primary.withOpacity(0.2),
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: _photoUrl.isNotEmpty
                              ? Image.network(
                                  _photoUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    Icons.person,
                                    size: 60,
                                    color: theme.colorScheme.onSurface
                                        .withOpacity(0.3),
                                  ),
                                )
                              : Icon(
                                  Icons.person,
                                  size: 60,
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.3),
                                ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDarkMode
                                ? Colors.grey[800]!
                                : Colors.white,
                            width: 2,
                          ),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.camera_alt, size: 20),
                          color: Colors.white,
                          onPressed: () {
                            // Implement photo upload
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tap to change photo',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Profile Information Section
            Text(
              'PROFILE INFORMATION',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _buildTextField(
              context,
              controller: _usernameController,
              label: 'Username',
              prefixText: '@',
              icon: Icons.alternate_email,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              context,
              controller: _displayNameController,
              label: 'Display Name',
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              context,
              controller: _bioController,
              label: 'Bio',
              icon: Icons.info_outline,
              maxLines: 3,
            ),

            const SizedBox(height: 32),

            // Account Settings Section
            Text(
              'ACCOUNT SETTINGS',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _buildSettingTile(
              context,
              icon: Icons.email_outlined,
              title: 'Email',
              subtitle: FirebaseAuth.instance.currentUser?.email ?? 'Not set',
              onTap: () {
                // Implement email change
              },
            ),
            _buildSettingTile(
              context,
              icon: Icons.lock_outline,
              title: 'Privacy',
              subtitle: 'Manage your privacy settings',
              onTap: () {
                // Navigate to privacy settings
              },
            ),
            _buildSettingTile(
              context,
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Configure notifications',
              onTap: () {
                // Navigate to notification settings
              },
            ),
            _buildSettingTile(
              context,
              icon: Icons.security_outlined,
              title: 'Security',
              subtitle: 'Password and security options',
              onTap: () {
                // Navigate to security settings
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    String? prefixText,
    required IconData icon,
    int maxLines = 1,
  }) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefixText,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.3),
          ),
        ),
        filled: true,
        fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.4),
      ),
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: theme.colorScheme.primary),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurface.withOpacity(0.3),
      ),
      onTap: onTap,
    );
  }
}

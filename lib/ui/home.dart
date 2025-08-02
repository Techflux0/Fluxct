import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_services.dart';
import 'settings.dart';
import 'chats.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.chat_bubble_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('Chatmoji'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showUserSearch(context, authService),
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
              const PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
            onSelected: (value) async {
              if (value == 'logout') {
                await authService.signOut();
                if (mounted) Navigator.pushReplacementNamed(context, '/');
              } else if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where(
              'participants',
              arrayContains: authService.getCurrentUserId(),
            )
            .orderBy('lastMessageTime', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading chats'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data?.docs ?? [];

          if (chats.isEmpty) {
            return const Center(
              child: Text(
                'Search for a username to start a conversation',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index].data() as Map<String, dynamic>;
              final participants = chat['participants'] as List<dynamic>;

              // Safely find the other participant
              final otherUserId = participants.firstWhere(
                (id) => id != authService.getCurrentUserId(),
                orElse: () => '', // Return empty string if not found
              );

              if (otherUserId.isEmpty) {
                return const ListTile(
                  leading: CircleAvatar(child: Icon(Icons.error)),
                  title: Text('Invalid chat'),
                );
              }

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(otherUserId)
                    .get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return const ListTile(
                      leading: CircleAvatar(child: Icon(Icons.person)),
                      title: Text('Loading...'),
                    );
                  }

                  if (!userSnapshot.data!.exists) {
                    return const ListTile(
                      leading: CircleAvatar(child: Icon(Icons.error)),
                      title: Text('User not found'),
                    );
                  }

                  final user =
                      userSnapshot.data!.data() as Map<String, dynamic>;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: user['photoUrl'] != null
                          ? NetworkImage(user['photoUrl'])
                          : null,
                      child: user['photoUrl'] == null
                          ? Text(user['username'][0].toUpperCase())
                          : null,
                    ),
                    title: Text(user['displayName'] ?? '@${user['username']}'),
                    subtitle: Text(chat['lastMessage'] ?? ''),
                    trailing: Text(
                      _formatDate(chat['lastMessageTime']?.toDate()),
                      style: const TextStyle(color: Colors.grey),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            chatId: chats[index].id,
                            otherUser: user,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUserSearch(context, authService),
        backgroundColor: Colors.blue,
        child: const Icon(Icons.messenger, color: Colors.white),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    if (date.day == now.day &&
        date.month == now.month &&
        date.year == now.year) {
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day}/${date.month}';
  }

  void _showUserSearch(BuildContext context, AuthService authService) {
    showSearch(
      context: context,
      delegate: UserSearchDelegate(
        authService: authService,
        parentContext: context,
      ),
    );
  }
}

class UserSearchDelegate extends SearchDelegate {
  final AuthService authService;
  final BuildContext parentContext;

  UserSearchDelegate({required this.authService, required this.parentContext});

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _searchUsers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Error searching'));
        }
        final users = snapshot.data ?? [];
        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: user['photoUrl'] != null
                    ? NetworkImage(user['photoUrl'])
                    : null,
                child: user['photoUrl'] == null
                    ? Text(user['username'][0].toUpperCase())
                    : null,
              ),
              title: Text('@${user['username']}'),
              subtitle: Text(user['displayName'] ?? ''),
              trailing: IconButton(
                icon: const Icon(Icons.chat),
                onPressed: () => _startNewChat(context, user),
              ),
              onTap: () => _startNewChat(context, user),
            );
          },
        );
      },
    );
  }

  Future<void> _startNewChat(
    BuildContext context,
    Map<String, dynamic> user,
  ) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final chatId = await authService.createNewChat(user['id']);

      if ((parentContext as Element).mounted) {
        Navigator.of(parentContext).pop(); // Close loading dialog
        Navigator.of(parentContext).push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(chatId: chatId, otherUser: user),
          ),
        );
        close(context, null); // Close search
      }
    } catch (e) {
      if ((parentContext as Element).mounted) {
        Navigator.of(parentContext).pop(); // Close loading dialog
        ScaffoldMessenger.of(parentContext).showSnackBar(
          SnackBar(content: Text('Failed to start chat: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return query.isEmpty
        ? const Center(child: Text('Start typing to search users'))
        : buildResults(context);
  }

  Future<List<Map<String, dynamic>>> _searchUsers() async {
    if (query.isEmpty) return [];
    final searchTerm = query.startsWith('@') ? query.substring(1) : query;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isGreaterThanOrEqualTo: searchTerm)
        .where('username', isLessThan: '${searchTerm}z')
        .limit(10)
        .get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }
}

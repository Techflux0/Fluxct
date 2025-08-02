import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_services.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final Map<String, dynamic> otherUser;

  const ChatScreen({super.key, required this.chatId, required this.otherUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<String> _emojiNames = [];
  final Map<String, Uint8List> _emojiCache = {};
  bool _showEmojis = false;

  static const platform = MethodChannel("com.io.fluxct/emojis");

  @override
  void initState() {
    super.initState();
    _loadEmojis();
  }

  Future<List<String>> _loadEmojis() async {
    try {
      final result = await platform.invokeMethod('listEmojis');
      return List<String>.from(result);
    } on PlatformException catch (e) {
      debugPrint("Failed to load emojis: ${e.message}");
      return [];
    }
  }

  Future<Uint8List> _getEmojiBytes(String emojiName) async {
    if (_emojiCache.containsKey(emojiName)) {
      return _emojiCache[emojiName]!;
    }
    try {
      final bytes = await platform.invokeMethod("getEmojiBytes", {
        "name": emojiName,
      });
      _emojiCache[emojiName] = bytes;
      return bytes;
    } catch (e) {
      debugPrint("Failed to load emoji bytes: $e");
      throw Exception("Emoji not found");
    }
  }

  void _insertEmoji(String emojiName) {
    final index = _messageController.selection.baseOffset;
    final text = _messageController.text;
    final emojiTag = "<img=$emojiName>";

    _messageController.text = text.replaceRange(index, index, emojiTag);
    _messageController.selection = TextSelection.fromPosition(
      TextPosition(offset: index + emojiTag.length),
    );
  }

  Widget _buildMessageContent(String text) {
    // Simple implementation - you can expand this to parse <img> tags
    return Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: widget.otherUser['photoUrl'] != null
                  ? NetworkImage(widget.otherUser['photoUrl'])
                  : null,
              child: widget.otherUser['photoUrl'] == null
                  ? Text(widget.otherUser['username'][0].toUpperCase())
                  : null,
            ),
            const SizedBox(width: 10),
            Text(
              widget.otherUser['displayName'] ??
                  '@${widget.otherUser['username']}',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data?.docs ?? [];

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message =
                        messages[index].data() as Map<String, dynamic>;
                    final isMe =
                        message['senderId'] == authService.getCurrentUserId();

                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 8,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue : Colors.grey[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _buildMessageContent(message['text']),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_showEmojis)
            SizedBox(
              height: 200,
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _emojiNames.length,
                itemBuilder: (context, index) {
                  final emojiName = _emojiNames[index];
                  return FutureBuilder<Uint8List>(
                    future: _getEmojiBytes(emojiName),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return GestureDetector(
                          onTap: () {
                            _insertEmoji(emojiName);
                            _focusNode.requestFocus();
                          },
                          child: Image.memory(
                            snapshot.data!,
                            width: 32,
                            height: 32,
                          ),
                        );
                      } else if (snapshot.hasError) {
                        return const Icon(Icons.error);
                      } else {
                        return const CircularProgressIndicator();
                      }
                    },
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _showEmojis ? Icons.keyboard : Icons.emoji_emotions,
                  ),
                  onPressed: () {
                    setState(() {
                      _showEmojis = !_showEmojis;
                    });
                    if (!_showEmojis) _focusNode.requestFocus();
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    focusNode: _focusNode,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () async {
                    if (_messageController.text.trim().isEmpty) return;

                    try {
                      await authService.sendMessage(
                        chatId: widget.chatId,
                        text: _messageController.text.trim(),
                      );
                      _messageController.clear();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to send: ${e.toString()}'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/services.dart';

class EmojiLoader {
  static const _channel = MethodChannel('com.chatmoji/emojis');

  static Future<List<String>> loadEmojiList() async {
    final List<dynamic> result = await _channel.invokeMethod('listEmojis');
    return result.cast<String>();
  }
}

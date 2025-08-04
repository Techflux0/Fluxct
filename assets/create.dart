import 'dart:convert';
import 'dart:io';

void main() async {
  const emojiFolder = 'emoji';
  const outputFile = 'emoji/emoji.json';

  final directory = Directory(emojiFolder);

  if (!directory.existsSync()) {
    print('❌ Folder "$emojiFolder" does not exist.');
    return;
  }

  final pngFiles =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.png'))
          .map((file) => file.uri.pathSegments.last)
          .toList()
        ..sort();

  final jsonContent = jsonEncode(pngFiles);

  final outFile = File(outputFile);
  await outFile.writeAsString(jsonContent);

  print('✅ emoji.json created with ${pngFiles.length} emojis.');
}

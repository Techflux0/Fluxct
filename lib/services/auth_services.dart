import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class AuthService {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  final FirebaseFirestore _firestore;
  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _prefs;
  final Uuid _uuid;

  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
    FirebaseFirestore? firestore,
    FlutterSecureStorage? secureStorage,
    required SharedPreferences prefs,
    Uuid? uuid,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn.standard(),
       _firestore = firestore ?? FirebaseFirestore.instance,
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _prefs = prefs,
       _uuid = uuid ?? const Uuid();

  Future<bool> isLoggedIn() async {
    try {
      return _auth.currentUser != null ||
          await _secureStorage.read(key: 'auth_token') != null;
    } catch (e) {
      print('Error checking login status: $e');
      return false;
    }
  }

  Future<User?> signInWithGoogle() async {
    try {
      // Step 1: Trigger Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      // Step 2: Obtain auth details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Step 3: Create credential
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Step 4: Sign in with credential
      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );
      final User? user = userCredential.user;
      if (user == null) return null;

      // Step 5: Persist auth data locally
      await _persistAuthData(user, googleAuth.accessToken);

      // Step 6: Handle user profile in Firestore
      if (userCredential.additionalUserInfo?.isNewUser ?? false) {
        await _createNewUserProfile(user);
      } else {
        await _updateExistingUserProfile(user);
      }

      return user;
    } catch (e) {
      print('Google Sign-In Error: $e');
      await _cleanUpAuth();
      rethrow;
    }
  }

  Future<void> _persistAuthData(User user, String? token) async {
    try {
      await Future.wait([
        _secureStorage.write(key: 'auth_token', value: token),
        _prefs.setString('user_id', user.uid),
        _prefs.setString('user_email', user.email ?? ''),
        _prefs.setString('user_name', user.displayName ?? 'User'),
      ]);
    } catch (e) {
      print('Error persisting auth data: $e');
      await _cleanUpAuth();
      rethrow;
    }
  }

  Future<void> _createNewUserProfile(User user) async {
    try {
      final userRef = _firestore.collection('users').doc(user.uid);
      final username = _generateUsername(user.email ?? user.uid);

      await userRef.set({
        'id': user.uid,
        'email': user.email,
        'username': username,
        'displayName': user.displayName ?? username,
        'photoUrl': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
        'status': 'online',
        'chats': [],
        'groupChats': [],
        'settings': {'notifications': true, 'darkMode': false},
      });

      // Update display name if not set
      if (user.displayName == null) {
        await user.updateDisplayName(username);
      }
    } catch (e) {
      print('Error creating user profile: $e');
      await _cleanUpAuth();
      rethrow;
    }
  }

  Future<void> _updateExistingUserProfile(User user) async {
    try {
      final userRef = _firestore.collection('users').doc(user.uid);
      final doc = await userRef.get();

      if (!doc.exists) {
        await _createNewUserProfile(user);
        return;
      }

      await userRef.update({
        'lastSeen': FieldValue.serverTimestamp(),
        'status': 'online',
        'email': user.email,
        'photoUrl': user.photoURL,
      });
    } catch (e) {
      print('Error updating user profile: $e');
      rethrow;
    }
  }

  Future<void> _cleanUpAuth() async {
    try {
      await Future.wait([
        _googleSignIn.signOut(),
        _auth.signOut(),
        _secureStorage.delete(key: 'auth_token'),
      ]);
    } catch (e) {
      print('Error during auth cleanup: $e');
    }
  }

  Future<void> signOut() async {
    try {
      await _cleanUpAuth();
      await _prefs.clear();
    } catch (e) {
      print('Error during sign out: $e');
      rethrow;
    }
  }

  String? getCurrentUserId() => _prefs.getString('user_id');
  String? getCurrentUserEmail() => _prefs.getString('user_email');
  String? getCurrentUsername() => _prefs.getString('user_name');

  User? getCurrentFirebaseUser() => _auth.currentUser;

  Future<void> updateLastSeen() async {
    try {
      final userId = getCurrentUserId();
      if (userId != null) {
        await _firestore.collection('users').doc(userId).update({
          'lastSeen': FieldValue.serverTimestamp(),
          'status': 'offline',
        });
      }
    } catch (e) {
      print('Error updating last seen: $e');
    }
  }

  // Add these methods to your AuthService class

  Future<String> createNewChat(String otherUserId) async {
    await cleanInvalidChats();
    try {
      final currentUserId = getCurrentUserId();
      if (currentUserId == null) throw Exception('Not authenticated');

      // Create a sorted chat ID to prevent duplicate chats
      final chatId = _generateChatId(currentUserId, otherUserId);

      // Create chat document in 'chats' collection
      await _firestore.collection('chats').doc(chatId).set({
        'participants': [currentUserId, otherUserId],
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });

      // Add chat reference to both users' chat lists
      final batch = _firestore.batch();

      final currentUserRef = _firestore.collection('users').doc(currentUserId);
      batch.update(currentUserRef, {
        'chats': FieldValue.arrayUnion([chatId]),
      });

      final otherUserRef = _firestore.collection('users').doc(otherUserId);
      batch.update(otherUserRef, {
        'chats': FieldValue.arrayUnion([chatId]),
      });

      await batch.commit();

      return chatId;
    } catch (e) {
      print('Error creating chat: $e');
      rethrow;
    }
  }

  String _generateChatId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  Future<void> sendMessage({
    required String chatId,
    required String text,
  }) async {
    try {
      final currentUserId = getCurrentUserId();
      if (currentUserId == null) throw Exception('Not authenticated');

      final messageId = _uuid.v4();
      final messageRef = _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId);

      await _firestore.runTransaction((transaction) async {
        // Create new message
        transaction.set(messageRef, {
          'id': messageId,
          'senderId': currentUserId,
          'text': text,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'sent',
        });

        // Update chat last message
        final chatRef = _firestore.collection('chats').doc(chatId);
        transaction.update(chatRef, {
          'lastMessage': text,
          'lastMessageTime': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  Future<void> cleanInvalidChats() async {
    try {
      final currentUserId = getCurrentUserId();
      if (currentUserId == null) return;

      // Get all chats where current user is a participant
      final querySnapshot = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUserId)
          .get();

      final batch = FirebaseFirestore.instance.batch();

      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final participants = List<String>.from(data['participants'] ?? []);

        // Check if chat is invalid (not exactly 2 participants)
        if (participants.length != 2) {
          // First delete all messages in subcollection
          final messages = await doc.reference.collection('messages').get();
          for (final message in messages.docs) {
            batch.delete(message.reference);
          }

          // Then delete the chat document
          batch.delete(doc.reference);

          // Remove chat reference from users' chat lists
          for (final userId in participants) {
            final userRef = FirebaseFirestore.instance
                .collection('users')
                .doc(userId);
            batch.update(userRef, {
              'chats': FieldValue.arrayRemove([doc.id]),
            });
          }
        }
      }

      await batch.commit();
    } catch (e) {
      print('Error cleaning invalid chats: $e');
    }
  }

  String _generateUsername(String input) {
    final namePart = input
        .split('@')
        .first
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final randomString = _uuid.v4().substring(0, 6);
    return '${namePart.isNotEmpty ? namePart : 'user'}_$randomString'
        .toLowerCase();
  }
}

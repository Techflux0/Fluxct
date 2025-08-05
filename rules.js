rules_version = '2';
service cloud.firestore {
    match /databases/{database}/documents {

        match /users/{userId} {
            allow read: if request.auth != null;
            allow create, update: if request.auth != null && request.auth.uid == userId;
        }

        match /chats/{chatId} {
            allow create: if request.auth != null &&
                request.resource.data.keys().hasAll([
                    'participants',
                    'participantData',
                    'createdAt',
                    'updatedAt',
                    'lastMessage',
                    'lastMessageTime',
                    'unreadCount',
                    'isGroup',
                    'pinnedMessageId'
                ]) &&
                request.resource.data.participants.size() == 2 &&
                request.resource.data.participants.hasAll([
                    request.resource.data.participantData.keys().toList()[0],
                    request.resource.data.participantData.keys().toList()[1]
                ]) &&
                request.resource.data.participants.hasAny([request.auth.uid]) &&
                request.resource.data.isGroup == false;

            allow read, update: if request.auth != null &&
                resource.data.participants.hasAny([request.auth.uid]);

            match /messages/{messageId} {
                allow read: if request.auth != null &&
                    get(/databases/$(database)/documents/chats/$(chatId)).data.participants.hasAny([request.auth.uid]);

                allow create: if request.auth != null &&
                    request.resource.data.senderId == request.auth.uid &&
                    get(/databases/$(database)/documents/chats/$(chatId)).data.participants.hasAny([request.auth.uid]);
            }
        }
    }
}

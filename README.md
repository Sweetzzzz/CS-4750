# Instagram Clone

This is a Flutter-based Instagram clone with features for social media sharing, user interactions, and admin functionality.

## GDPR Compliance and Data Protection Features

### Account Data Export (GDPR Compliance)
The app allows users to export all their personal data, as required by GDPR:
- User profile information
- Posts and media content
- Comments on posts
- Following/follower relationships
- Messages and conversations
- Export data is provided in a structured JSON format

### Account Deletion (Right to be Forgotten)
Users can completely delete their account and all associated data:
- Double confirmation process to prevent accidental deletion
- Complete removal of profile information
- Deletion of all user's posts and their comments
- Removal of comments made on other users' posts
- Deletion of following/follower relationships
- Removal of messaging history
- Termination of Firebase Auth account

### Privacy Controls
- Privacy Policy accessible in the app
- User data handling transparency
- Future: Data processing consent management

## Firebase Security Rules

To support these features, Firebase security rules have been updated to:
- Allow users to delete their own data
- Provide appropriate public access to non-sensitive information
- Restrict sensitive operations to authenticated users
- Allow admin users to manage content

## Usage

### Data Export
1. Navigate to Settings
2. Select "Export Your Data" under Privacy & Data
3. View or download your data

### Account Deletion
1. Navigate to Settings
2. Select "Delete Account" under Account
3. Confirm deletion in first dialog
4. Type "DELETE" in second confirmation dialog

Note: Account deletion is permanent and cannot be undone.

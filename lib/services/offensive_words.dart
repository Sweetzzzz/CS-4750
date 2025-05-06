// List of offensive words to filter
const List<String> offensiveWords = [
  // Common offensive words
  'asshole',
  'bitch',
  'bastard',
  'cunt',
  'dick',
  'fuck',
  'shit',
  'pussy',
  'whore',
  'slut',
  'nigger',
  'nigga',
  'chink',
  'spic',
  'kike',

  // Racial slurs
  'nigger',
  'nigga',
  'chink',
  'spic',
  'kike',

  // Homophobic slurs
  'fag',
  'faggot',
  'queer',

  // Add more words as needed
];

// List of offensive patterns (regex)
const List<String> offensivePatterns = [
  // Pattern for detecting potential offensive usernames
  r'\b[a-z]{1,2}[0-9]{1,2}\b',

  // Pattern for detecting repeated characters (spam-like)
  r'(\w)\1{3,}',

  // Pattern for detecting potential email addresses
  r'[\w\.-]+@[\w\.-]+\.\w+',

  // Pattern for detecting potential phone numbers
  r'\b\d{3}[-.]?\d{3}[-.]?\d{4}\b',

  // Add more patterns as needed
];

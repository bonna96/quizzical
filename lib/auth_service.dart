import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ==========================================
// USER MODEL
// ==========================================
class UserModel {
  final String id;
  final String name;
  final String email;
  final String passwordHash;
  final int avatarColorValue;
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.passwordHash,
    required this.avatarColorValue,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'passwordHash': passwordHash,
    'avatarColorValue': avatarColorValue,
    'createdAt': createdAt.toIso8601String(),
  };

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'],
    name: json['name'],
    email: json['email'],
    passwordHash: json['passwordHash'],
    avatarColorValue: json['avatarColorValue'],
    createdAt: DateTime.parse(json['createdAt']),
  );
}

// ==========================================
// QUIZ RESULT MODEL
// ==========================================
class QuizResult {
  final String id;
  final String userId;
  final String categoryName;
  final int score;
  final int total;
  final int durationSeconds;
  final String difficulty;
  final DateTime playedAt;

  QuizResult({
    required this.id,
    required this.userId,
    required this.categoryName,
    required this.score,
    required this.total,
    required this.durationSeconds,
    required this.difficulty,
    required this.playedAt,
  });

  double get accuracy => total > 0 ? score / total : 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'categoryName': categoryName,
    'score': score,
    'total': total,
    'durationSeconds': durationSeconds,
    'difficulty': difficulty,
    'playedAt': playedAt.toIso8601String(),
  };

  factory QuizResult.fromJson(Map<String, dynamic> json) => QuizResult(
    id: json['id'],
    userId: json['userId'],
    categoryName: json['categoryName'],
    score: json['score'],
    total: json['total'],
    durationSeconds: json['durationSeconds'],
    difficulty: json['difficulty'] ?? 'any',
    playedAt: DateTime.parse(json['playedAt']),
  );
}

// ==========================================
// AUTH SERVICE
// ==========================================
class AuthService {
  static const _usersKey = 'app_users';
  static const _currentUserKey = 'current_user_id';
  static const _resultsKey = 'quiz_results';

  // Simple hash (not cryptographically secure — for demo only)
  static String _hashPassword(String password) {
    int hash = 0;
    for (var c in password.codeUnits) {
      hash = ((hash << 5) - hash + c) & 0xFFFFFFFF;
    }
    return hash.toString();
  }

  static Future<Map<String, UserModel>> _getAllUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_usersKey) ?? '{}';
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, UserModel.fromJson(v as Map<String, dynamic>)));
  }

  static Future<void> _saveAllUsers(Map<String, UserModel> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usersKey, jsonEncode(users.map((k, v) => MapEntry(k, v.toJson()))));
  }

  /// Returns null on success, error string on failure
  static Future<String?> signUp(String name, String email, String password) async {
    if (name.trim().isEmpty) return 'Name cannot be empty';
    if (!email.contains('@') || !email.contains('.')) return 'Invalid email address';
    if (password.length < 6) return 'Password must be at least 6 characters';

    final users = await _getAllUsers();
    if (users.values.any((u) => u.email.toLowerCase() == email.toLowerCase())) {
      return 'An account with this email already exists';
    }

    final colors = [0xFF7C4DFF, 0xFF00BCD4, 0xFFFF5722, 0xFF4CAF50, 0xFFE91E63, 0xFF2196F3];
    final newUser = UserModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim(),
      email: email.trim().toLowerCase(),
      passwordHash: _hashPassword(password),
      avatarColorValue: colors[users.length % colors.length],
      createdAt: DateTime.now(),
    );

    users[newUser.id] = newUser;
    await _saveAllUsers(users);
    await _setCurrentUser(newUser.id);
    return null;
  }

  /// Returns null on success, error string on failure
  static Future<String?> login(String email, String password) async {
    final users = await _getAllUsers();
    final match = users.values.where(
      (u) => u.email == email.trim().toLowerCase() && u.passwordHash == _hashPassword(password),
    );
    if (match.isEmpty) return 'Incorrect email or password';
    await _setCurrentUser(match.first.id);
    return null;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentUserKey);
  }

  static Future<UserModel?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_currentUserKey);
    if (id == null) return null;
    final users = await _getAllUsers();
    return users[id];
  }

  static Future<void> _setCurrentUser(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserKey, id);
  }

  static Future<void> updateProfile(String userId, String newName) async {
    final users = await _getAllUsers();
    if (users.containsKey(userId)) {
      final u = users[userId]!;
      users[userId] = UserModel(
        id: u.id, name: newName.trim(), email: u.email,
        passwordHash: u.passwordHash, avatarColorValue: u.avatarColorValue,
        createdAt: u.createdAt,
      );
      await _saveAllUsers(users);
    }
  }

  // ---- Quiz Results ----
  static Future<void> saveQuizResult(QuizResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_resultsKey) ?? '[]';
    final list = (jsonDecode(raw) as List).map((e) => QuizResult.fromJson(e)).toList();
    list.insert(0, result);
    await prefs.setString(_resultsKey, jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static Future<List<QuizResult>> getResultsForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_resultsKey) ?? '[]';
    final list = (jsonDecode(raw) as List).map((e) => QuizResult.fromJson(e)).toList();
    return list.where((r) => r.userId == userId).toList();
  }
}

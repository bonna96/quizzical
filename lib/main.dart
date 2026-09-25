import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:html_unescape/html_unescape.dart';
import 'auth_service.dart';
import 'auth_screens.dart';
import 'widgets.dart';
import 'profile_tab.dart';

// ==========================================
// ENTRY POINT
// ==========================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final user = await AuthService.getCurrentUser();
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => QuizProvider())],
      child: QuizzicalApp(initialUser: user),
    ),
  );
}

class QuizzicalApp extends StatelessWidget {
  final UserModel? initialUser;
  const QuizzicalApp({super.key, required this.initialUser});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quizzical',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(primary: Color(0xFF0CD6E7), surface: Colors.transparent),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      initialRoute: initialUser != null ? '/home' : '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignUpScreen(),
        '/home': (_) => const MainShell(),
      },
    );
  }
}

// ==========================================
// MODELS
// ==========================================
class Category {
  final int id;
  final String name;
  final IconData icon;
  final Color color;
  Category({required this.id, required this.name, required this.icon, required this.color});

  factory Category.fromJson(Map<String, dynamic> json, IconData icon, Color color) =>
      Category(id: json['id'], name: json['name'], icon: icon, color: color);
}

class Question {
  final String category;
  final String type;
  final String difficulty;
  final String question;
  final String correctAnswer;
  final List<String> allAnswers;

  Question({required this.category, required this.type, required this.difficulty,
    required this.question, required this.correctAnswer, required this.allAnswers});

  factory Question.fromJson(Map<String, dynamic> json) {
    final u = HtmlUnescape();
    final correct = u.convert(json['correct_answer'] ?? '');
    final incorrects = (json['incorrect_answers'] as List).map((e) => u.convert(e.toString())).toList();
    final answers = [...incorrects, correct]..shuffle();
    return Question(
      category: json['category'] ?? '', type: json['type'] ?? '',
      difficulty: json['difficulty'] ?? '', question: u.convert(json['question'] ?? ''),
      correctAnswer: correct, allAnswers: answers,
    );
  }
}

// ==========================================
// QUIZ PROVIDER
// ==========================================
class QuizProvider extends ChangeNotifier {
  List<Category> _categories = [];
  bool _isLoadingCategories = false;
  String? _categoryError;
  List<Category> get categories => _categories;
  bool get isLoadingCategories => _isLoadingCategories;
  String? get categoryError => _categoryError;

  int selectedCategoryId = 9;
  String selectedCategoryName = "General Knowledge";
  int questionAmount = 10;
  String selectedDifficulty = "easy";
  String selectedType = "multiple";

  List<Question> _questions = [];
  bool _isLoadingQuiz = false;
  String? _quizError;
  int _currentIndex = 0;
  int _score = 0;
  String? _selectedAnswer;
  bool _isAnswered = false;
  int _totalSeconds = 0;
  Timer? _timer;
  int _remainingTime = 20;

  List<Question> get questions => _questions;
  bool get isLoadingQuiz => _isLoadingQuiz;
  String? get quizError => _quizError;
  int get currentIndex => _currentIndex;
  int get score => _score;
  String? get selectedAnswer => _selectedAnswer;
  bool get isAnswered => _isAnswered;
  int get remainingTime => _remainingTime;
  int get totalSeconds => _totalSeconds;

  final List<Map<String, dynamic>> _palette = [
    {'icon': Icons.calculate, 'color': const Color(0xFFFF9800)},
    {'icon': Icons.science, 'color': const Color(0xFF69F0AE)},
    {'icon': Icons.theater_comedy, 'color': const Color(0xFFE040FB)},
    {'icon': Icons.brush, 'color': const Color(0xFFFF5252)},
    {'icon': Icons.menu_book, 'color': const Color(0xFF448AFF)},
    {'icon': Icons.language, 'color': const Color(0xFF64FFDA)},
    {'icon': Icons.sports_basketball, 'color': const Color(0xFFFF6D00)},
    {'icon': Icons.music_note, 'color': const Color(0xFFF48FB1)},
    {'icon': Icons.history_edu, 'color': const Color(0xFFFFD740)},
    {'icon': Icons.terrain, 'color': const Color(0xFF69F0AE)},
  ];

  Future<void> fetchCategories() async {
    if (_categories.isNotEmpty) return;
    _isLoadingCategories = true; _categoryError = null; notifyListeners();
    try {
      final res = await http.get(Uri.parse('https://opentdb.com/api_category.php'));
      if (res.statusCode == 200) {
        final list = (jsonDecode(res.body)['trivia_categories'] as List);
        _categories = list.asMap().entries.map((e) {
          final s = _palette[e.key % _palette.length];
          return Category.fromJson(e.value, s['icon'], s['color']);
        }).toList();
      } else { _categoryError = 'Server error: ${res.statusCode}'; }
    } catch (_) { _categoryError = 'Network error. Check connection.'; }
    finally { _isLoadingCategories = false; notifyListeners(); }
  }

  Future<void> loadSavedConfig() async {
    final p = await SharedPreferences.getInstance();
    questionAmount = p.getInt('pref_amount') ?? 10;
    selectedDifficulty = p.getString('pref_difficulty') ?? 'easy';
    selectedType = p.getString('pref_type') ?? 'multiple';
    notifyListeners();
  }

  Future<bool> startQuiz() async {
    _isLoadingQuiz = true; _quizError = null; _score = 0; _currentIndex = 0;
    _isAnswered = false; _selectedAnswer = null; _totalSeconds = 0; notifyListeners();

    final p = await SharedPreferences.getInstance();
    await p.setInt('pref_amount', questionAmount);
    await p.setString('pref_difficulty', selectedDifficulty);
    await p.setString('pref_type', selectedType);

    String url = 'https://opentdb.com/api.php?amount=$questionAmount&category=$selectedCategoryId';
    if (selectedDifficulty != 'any') url += '&difficulty=$selectedDifficulty';
    if (selectedType != 'any') url += '&type=$selectedType';

    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['response_code'] == 0) {
          _questions = (data['results'] as List).map((e) => Question.fromJson(e)).toList();
          _isLoadingQuiz = false; _startTimer(); notifyListeners(); return true;
        } else { _quizError = 'No questions for this configuration. Try different settings.'; }
      } else { _quizError = 'Server error (${res.statusCode})'; }
    } catch (_) { _quizError = 'Network error. Check your connection.'; }
    _isLoadingQuiz = false; notifyListeners(); return false;
  }

  void _startTimer() {
    _timer?.cancel(); _remainingTime = 20;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      _totalSeconds++;
      if (_remainingTime > 0) { _remainingTime--; notifyListeners(); }
      else { t.cancel(); handleTimeout(); }
    });
  }

  void handleTimeout() { if (!_isAnswered) { _isAnswered = true; _selectedAnswer = null; notifyListeners(); } }

  void selectAnswer(String ans) {
    if (_isAnswered) return;
    _isAnswered = true; _selectedAnswer = ans; _timer?.cancel();
    if (ans == _questions[_currentIndex].correctAnswer) _score++;
    notifyListeners();
  }

  bool nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      _currentIndex++; _isAnswered = false; _selectedAnswer = null; _startTimer(); notifyListeners(); return true;
    } else { _timer?.cancel(); return false; }
  }

  void cancelTimer() => _timer?.cancel();
}

// ==========================================
// MAIN SHELL WITH CURVED NAVBAR
// ==========================================
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  UserModel? _user;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final u = await AuthService.getCurrentUser();
    if (mounted) setState(() => _user = u);
    if (u == null && mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: AppBackground(child: const Center(child: CircularProgressIndicator(color: Color(0xFF0CD6E7)))),
      );
    }

    final tabs = [
      HomeTab(user: _user!),
      CategoryTab(user: _user!),
      HistoryTab(userId: _user!.id),
      ProfileTab(user: _user!),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: AppBackground(child: tabs[_selectedIndex]),
      bottomNavigationBar: CurvedNavBar(
        selectedIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
      ),
    );
  }
}

// ==========================================
// TAB 0 — HOME (WELCOME + START)
// ==========================================
class HomeTab extends StatelessWidget {
  final UserModel user;
  const HomeTab({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                UserAvatar(user: user, radius: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hello, ${user.name.split(' ').first}! 👋',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Ready to quiz today?', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                    ],
                  ),
                ),
                GlassContainer(
                  width: 40, height: 40, borderRadius: 12, padding: EdgeInsets.zero,
                  child: const Icon(Icons.notifications_none, color: Colors.white70, size: 22),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Hero Banner
            GlassContainer(
              padding: const EdgeInsets.all(28),
              borderRadius: 28,
              color: const Color(0xFF7C4DFF).withOpacity(0.2),
              border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.4), width: 1.5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Play &\nWin!', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold, height: 1.2)),
                        const SizedBox(height: 8),
                        Text('Test your knowledge\nacross 24+ categories', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, height: 1.4)),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0CD6E7),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                          onPressed: () {
                            // Switch to categories tab (index 1)
                            final shell = context.findAncestorStateOfType<_MainShellState>();
                            shell?.setState(() => shell._selectedIndex = 1);
                          },
                          child: const Text('Start Quiz', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 80),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Quick Stats
            const Text('Your Stats', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _QuickStats(userId: user.id),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}

class _QuickStats extends StatefulWidget {
  final String userId;
  const _QuickStats({required this.userId});

  @override
  State<_QuickStats> createState() => _QuickStatsState();
}

class _QuickStatsState extends State<_QuickStats> {
  List<QuizResult> _results = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AuthService.getResultsForUser(widget.userId);
    if (mounted) setState(() => _results = r);
  }

  @override
  Widget build(BuildContext context) {
    final total = _results.length;
    final bestScore = total > 0 ? _results.map((r) => r.score).reduce((a, b) => a > b ? a : b) : 0;
    final avgAcc = total > 0 ? (_results.map((r) => r.accuracy).reduce((a, b) => a + b) / total * 100).toStringAsFixed(0) : '0';

    return Row(
      children: [
        Expanded(child: _miniStat('Games\nPlayed', '$total', Icons.sports_esports, const Color(0xFF0CD6E7))),
        const SizedBox(width: 12),
        Expanded(child: _miniStat('Best\nScore', '$bestScore', Icons.emoji_events, Colors.amber)),
        const SizedBox(width: 12),
        Expanded(child: _miniStat('Avg\nAccuracy', '$avgAcc%', Icons.analytics, const Color(0xFF7C4DFF))),
      ],
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 10), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ==========================================
// TAB 1 — CATEGORIES
// ==========================================
class CategoryTab extends StatefulWidget {
  final UserModel user;
  const CategoryTab({super.key, required this.user});

  @override
  State<CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends State<CategoryTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<QuizProvider>().fetchCategories());
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<QuizProvider>();
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: const Text('Choose Category', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: prov.isLoadingCategories
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0CD6E7)))
                : prov.categoryError != null
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: GlassContainer(
                          padding: const EdgeInsets.all(24),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.wifi_off_rounded, color: Colors.redAccent, size: 48),
                            const SizedBox(height: 12),
                            Text(prov.categoryError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0CD6E7), foregroundColor: Colors.black),
                              onPressed: () {
                                context.read<QuizProvider>()._categories = [];
                                context.read<QuizProvider>().fetchCategories();
                              },
                              icon: const Icon(Icons.refresh), label: const Text('Retry'),
                            ),
                          ]),
                        ),
                      ))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, childAspectRatio: 1.05, crossAxisSpacing: 14, mainAxisSpacing: 14,
                        ),
                        itemCount: prov.categories.length,
                        itemBuilder: (ctx, i) {
                          final cat = prov.categories[i];
                          return GestureDetector(
                            onTap: () {
                              prov.selectedCategoryId = cat.id;
                              prov.selectedCategoryName = cat.name;
                              Navigator.push(ctx, MaterialPageRoute(builder: (_) => QuizConfigScreen(userId: widget.user.id)));
                            },
                            child: GlassContainer(
                              borderRadius: 20,
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: cat.color.withOpacity(0.15),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: cat.color.withOpacity(0.4)),
                                    ),
                                    child: Icon(cat.icon, size: 30, color: cat.color),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(cat.name, textAlign: TextAlign.center, maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// TAB 2 — HISTORY
// ==========================================
class HistoryTab extends StatefulWidget {
  final String userId;
  const HistoryTab({super.key, required this.userId});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<QuizResult> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await AuthService.getResultsForUser(widget.userId);
    if (mounted) setState(() { _results = r; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Quiz History', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                Text('${_results.length} games', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF0CD6E7)))
                : _results.isEmpty
                    ? Center(
                        child: GlassContainer(
                          margin: const EdgeInsets.all(32),
                          padding: const EdgeInsets.all(32),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.history_toggle_off, color: Colors.white.withOpacity(0.3), size: 56),
                            const SizedBox(height: 16),
                            Text('No quiz history yet.\nPlay a quiz to see results here!',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15, height: 1.5)),
                          ]),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                        itemCount: _results.length,
                        itemBuilder: (ctx, i) => _historyCard(_results[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _historyCard(QuizResult r) {
    final acc = (r.accuracy * 100).toStringAsFixed(0);
    final date = '${r.playedAt.day}/${r.playedAt.month}/${r.playedAt.year} · ${r.playedAt.hour}:${r.playedAt.minute.toString().padLeft(2, '0')}';
    final mins = r.durationSeconds ~/ 60;
    final secs = r.durationSeconds % 60;
    final timeStr = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
    final color = r.accuracy >= 0.8 ? const Color(0xFF0CD6E7) : r.accuracy >= 0.5 ? Colors.amber : Colors.redAccent;

    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.15), border: Border.all(color: color.withOpacity(0.4))),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('$acc%', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.categoryName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: color, size: 14),
                    const SizedBox(width: 4),
                    Text('${r.score}/${r.total} correct', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                    const SizedBox(width: 10),
                    Icon(Icons.timer_outlined, color: Colors.white38, size: 14),
                    const SizedBox(width: 4),
                    Text(timeStr, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(date, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(r.difficulty.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 9, letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// QUIZ CONFIG SCREEN
// ==========================================
class QuizConfigScreen extends StatefulWidget {
  final String userId;
  const QuizConfigScreen({super.key, required this.userId});

  @override
  State<QuizConfigScreen> createState() => _QuizConfigScreenState();
}

class _QuizConfigScreenState extends State<QuizConfigScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<QuizProvider>().loadSavedConfig());
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<QuizProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Configure Quiz', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassContainer(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(Icons.category_rounded, color: Color(0xFF0CD6E7)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Category', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                        Text(prov.selectedCategoryName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ])),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                GlassContainer(
                  padding: const EdgeInsets.all(20),
                  borderRadius: 24,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text('Questions', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0CD6E7).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${prov.questionAmount}', style: const TextStyle(color: Color(0xFF0CD6E7), fontWeight: FontWeight.bold)),
                      ),
                    ]),
                    Slider(
                      activeColor: const Color(0xFF0CD6E7), inactiveColor: Colors.white24,
                      value: prov.questionAmount.toDouble(), min: 1, max: 50, divisions: 49,
                      onChanged: (v) => setState(() => prov.questionAmount = v.toInt()),
                    ),
                    const SizedBox(height: 16),
                    const Text('Difficulty', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    _dropdown(
                      value: prov.selectedDifficulty,
                      items: const [
                        DropdownMenuItem(value: 'any', child: Text('Any Difficulty')),
                        DropdownMenuItem(value: 'easy', child: Text('Easy')),
                        DropdownMenuItem(value: 'medium', child: Text('Medium')),
                        DropdownMenuItem(value: 'hard', child: Text('Hard')),
                      ],
                      onChanged: (v) { if (v != null) setState(() => prov.selectedDifficulty = v); },
                    ),
                    const SizedBox(height: 16),
                    const Text('Question Type', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    _dropdown(
                      value: prov.selectedType,
                      items: const [
                        DropdownMenuItem(value: 'any', child: Text('Any Type')),
                        DropdownMenuItem(value: 'multiple', child: Text('Multiple Choice')),
                        DropdownMenuItem(value: 'boolean', child: Text('True / False')),
                      ],
                      onChanged: (v) { if (v != null) setState(() => prov.selectedType = v); },
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                if (prov.quizError != null)
                  Padding(padding: const EdgeInsets.only(bottom: 16), child: GlassContainer(
                    padding: const EdgeInsets.all(14),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(prov.quizError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
                    ]),
                  )),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0CD6E7), foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: prov.isLoadingQuiz ? null : () async {
                      final success = await prov.startQuiz();
                      if (success && context.mounted) {
                        Navigator.pushReplacement(context, MaterialPageRoute(
                          builder: (_) => QuizPlayScreen(userId: widget.userId)));
                      }
                    },
                    child: prov.isLoadingQuiz
                        ? const CircularProgressIndicator(color: Colors.black, strokeWidth: 3)
                        : const Text('Start Quiz', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropdown({required String value, required List<DropdownMenuItem<String>> items, required Function(String?) onChanged}) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16), borderRadius: 14, blur: 8,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value, isExpanded: true, dropdownColor: const Color(0xFF1a1040),
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white70),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          items: items, onChanged: onChanged,
        ),
      ),
    );
  }
}

// ==========================================
// QUIZ PLAY SCREEN
// ==========================================
class QuizPlayScreen extends StatelessWidget {
  final String userId;
  const QuizPlayScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<QuizProvider>();
    final q = prov.questions[prov.currentIndex];
    final progress = (prov.currentIndex + 1) / prov.questions.length;
    final timerPct = prov.remainingTime / 20.0;

    return WillPopScope(
      onWillPop: () async { prov.cancelTimer(); return true; },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent, elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () { prov.cancelTimer(); Navigator.pop(context); },
          ),
          title: Text('${prov.selectedCategoryName}',
            style: const TextStyle(color: Colors.white70, fontSize: 14), overflow: TextOverflow.ellipsis),
          centerTitle: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress, backgroundColor: Colors.white12, minHeight: 6,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF0CD6E7)),
                ),
              ),
            ),
          ),
        ),
        body: AppBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Q ${prov.currentIndex + 1}/${prov.questions.length}',
                      style: const TextStyle(color: Color(0xFF0CD6E7), fontWeight: FontWeight.bold, fontSize: 16)),
                    SizedBox(
                      width: 50, height: 50,
                      child: Stack(alignment: Alignment.center, children: [
                        CircularProgressIndicator(
                          value: timerPct, strokeWidth: 4, backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation(prov.remainingTime > 10 ? const Color(0xFF0CD6E7) : Colors.redAccent),
                        ),
                        Text('${prov.remainingTime}', style: TextStyle(
                          color: prov.remainingTime > 10 ? Colors.white : Colors.redAccent,
                          fontSize: 13, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  GlassContainer(
                    padding: const EdgeInsets.all(20),
                    child: Text(q.question, style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.5, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(height: 20),

                  Expanded(
                    child: ListView.separated(
                      itemCount: q.allAnswers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (ctx, i) {
                        final ans = q.allAnswers[i];
                        Color border = Colors.white.withOpacity(0.2);
                        IconData icon = Icons.radio_button_unchecked;
                        Color iconColor = Colors.white38;
                        Color bg = Colors.white.withOpacity(0.05);
                        if (prov.isAnswered) {
                          if (ans == q.correctAnswer) { border = const Color(0xFF0CD6E7); icon = Icons.check_circle; iconColor = const Color(0xFF0CD6E7); bg = const Color(0xFF0CD6E7).withOpacity(0.1); }
                          else if (ans == prov.selectedAnswer) { border = Colors.redAccent; icon = Icons.cancel; iconColor = Colors.redAccent; bg = Colors.redAccent.withOpacity(0.1); }
                        }
                        return GestureDetector(
                          onTap: () => prov.selectAnswer(ans),
                          child: GlassContainer(
                            color: bg, border: Border.all(color: border, width: 2),
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                            borderRadius: 16,
                            child: Row(
                              children: [
                                Expanded(child: Text(ans, style: const TextStyle(color: Colors.white, fontSize: 15))),
                                Icon(icon, color: iconColor, size: 22),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  if (prov.isAnswered)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0CD6E7), foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () async {
                            final hasNext = prov.nextQuestion();
                            if (!hasNext && context.mounted) {
                              // Save result
                              final result = QuizResult(
                                id: DateTime.now().millisecondsSinceEpoch.toString(),
                                userId: userId,
                                categoryName: prov.selectedCategoryName,
                                score: prov.score,
                                total: prov.questions.length,
                                durationSeconds: prov.totalSeconds,
                                difficulty: prov.selectedDifficulty,
                                playedAt: DateTime.now(),
                              );
                              await AuthService.saveQuizResult(result);
                              if (context.mounted) {
                                Navigator.pushReplacement(context, MaterialPageRoute(
                                  builder: (_) => ResultsScreen(result: result, userId: userId)));
                              }
                            }
                          },
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(prov.currentIndex < prov.questions.length - 1 ? 'Next Question' : 'See Results',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded),
                          ]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// RESULTS SCREEN
// ==========================================
class ResultsScreen extends StatelessWidget {
  final QuizResult result;
  final String userId;
  const ResultsScreen({super.key, required this.result, required this.userId});

  String _fmt(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final acc = (result.accuracy * 100).toStringAsFixed(0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Quiz Result', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),

                Center(child: GlassContainer(
                  width: 130, height: 130, borderRadius: 65, padding: const EdgeInsets.all(16),
                  color: const Color(0xFF7C4DFF).withOpacity(0.2),
                  border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.4), width: 2),
                  child: Image.network('https://cdn-icons-png.flaticon.com/512/3112/3112946.png', fit: BoxFit.contain),
                )),
                const SizedBox(height: 20),

                const Text('Congratulations!', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('You scored ${result.score} out of ${result.total}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 15)),
                const SizedBox(height: 24),

                GlassContainer(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  borderRadius: 24,
                  child: Column(children: [
                    const Text('YOUR SCORE', style: TextStyle(color: Color(0xFFE91E63), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${result.score}', style: const TextStyle(color: Color(0xFF0CD6E7), fontSize: 52, fontWeight: FontWeight.bold)),
                        Text('/${result.total}', style: const TextStyle(color: Colors.white54, fontSize: 24, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 24),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      _chip(Icons.percent, '$acc%', 'Accuracy'),
                      Container(width: 1, height: 36, color: Colors.white12),
                      _chip(Icons.timer_outlined, _fmt(result.durationSeconds), 'Time'),
                      Container(width: 1, height: 36, color: Colors.white12),
                      _chip(Icons.monetization_on, '${result.score * 25}', 'Coins'),
                    ]),
                  ]),
                ),
                const SizedBox(height: 24),

                SizedBox(height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0CD6E7), foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.pushAndRemoveUntil(
                      context, MaterialPageRoute(builder: (_) => const MainShell()), (_) => false),
                    icon: const Icon(Icons.home_rounded),
                    label: const Text('Back to Home', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(height: 52,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () => Navigator.pushAndRemoveUntil(
                      context, MaterialPageRoute(builder: (_) => const MainShell()), (_) => false),
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Play Again', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String val, String label) => Column(children: [
    Icon(icon, color: const Color(0xFF0CD6E7), size: 20),
    const SizedBox(height: 4),
    Text(val, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
    Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
  ]);
}
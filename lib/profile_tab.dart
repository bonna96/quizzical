import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'widgets.dart';

// ==========================================
// PROFILE TAB
// ==========================================
class ProfileTab extends StatefulWidget {
  final UserModel user;
  const ProfileTab({super.key, required this.user});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  List<QuizResult> _results = [];
  bool _loading = true;
  final _nameCtrl = TextEditingController();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.user.name;
    _loadResults();
  }

  Future<void> _loadResults() async {
    final r = await AuthService.getResultsForUser(widget.user.id);
    if (mounted) setState(() { _results = r; _loading = false; });
  }

  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    await AuthService.updateProfile(widget.user.id, _nameCtrl.text);
    if (mounted) {
      setState(() => _editing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated!'), backgroundColor: Color(0xFF7C4DFF)),
      );
    }
  }

  // Computed stats
  int get _totalGames => _results.length;
  double get _avgAccuracy => _results.isEmpty ? 0 : _results.map((r) => r.accuracy).reduce((a, b) => a + b) / _results.length;
  int get _bestScore => _results.isEmpty ? 0 : _results.map((r) => r.score).reduce((a, b) => a > b ? a : b);
  String get _favoriteCategory {
    if (_results.isEmpty) return '—';
    final freq = <String, int>{};
    for (var r in _results) freq[r.categoryName] = (freq[r.categoryName] ?? 0) + 1;
    return freq.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          // Profile Card
          GlassContainer(
            padding: const EdgeInsets.all(24),
            borderRadius: 24,
            child: Column(
              children: [
                UserAvatar(user: widget.user, radius: 40),
                const SizedBox(height: 16),
                _editing
                    ? TextField(
                        controller: _nameCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          border: UnderlineInputBorder(borderSide: BorderSide(color: const Color(0xFF0CD6E7).withOpacity(0.5))),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.3))),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF0CD6E7))),
                        ),
                      )
                    : Text(widget.user.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(widget.user.email, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_editing) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0CD6E7), foregroundColor: Colors.black),
                        onPressed: _saveProfile,
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Save'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30)),
                        onPressed: () { setState(() { _editing = false; _nameCtrl.text = widget.user.name; }); },
                        child: const Text('Cancel'),
                      ),
                    ] else
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30)),
                        onPressed: () => setState(() => _editing = true),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit Name'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Performance Stats
          GlassContainer(
            padding: const EdgeInsets.all(20),
            borderRadius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Performance Overview',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _statCard('Total Games', '$_totalGames', Icons.sports_esports_outlined, const Color(0xFF0CD6E7))),
                    const SizedBox(width: 12),
                    Expanded(child: _statCard('Best Score', '$_bestScore', Icons.emoji_events_outlined, Colors.amber)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _statCard('Avg Accuracy', '${(_avgAccuracy * 100).toStringAsFixed(0)}%', Icons.percent, const Color(0xFF7C4DFF))),
                    const SizedBox(width: 12),
                    Expanded(child: _statCard('Fav Category', _favoriteCategory, Icons.category_outlined, Colors.pinkAccent, small: true)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Recent Games
          GlassContainer(
            padding: const EdgeInsets.all(20),
            borderRadius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recent Games', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                if (_loading)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFF0CD6E7))))
                else if (_results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      children: [
                        Icon(Icons.hourglass_empty, color: Colors.white.withOpacity(0.3), size: 40),
                        const SizedBox(height: 12),
                        Text('No games yet. Start playing!', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                      ],
                    ),
                  )
                else
                  ...(_results.take(10).map((r) => _resultTile(r))),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Logout button
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                await AuthService.logout();
                if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color, {bool small = false}) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 16,
      color: color.withOpacity(0.08),
      border: Border.all(color: color.withOpacity(0.25)),
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: small ? 13 : 18),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _resultTile(QuizResult r) {
    final acc = (r.accuracy * 100).toStringAsFixed(0);
    final date = '${r.playedAt.day}/${r.playedAt.month}/${r.playedAt.year}';
    final mins = r.durationSeconds ~/ 60;
    final secs = r.durationSeconds % 60;
    final timeStr = '${mins}m ${secs}s';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _accuracyColor(r.accuracy).withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: _accuracyColor(r.accuracy).withOpacity(0.4)),
              ),
              child: Center(child: Text('$acc%', style: TextStyle(color: _accuracyColor(r.accuracy), fontSize: 11, fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.categoryName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${r.score}/${r.total} correct · $timeStr · $date', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
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
      ),
    );
  }

  Color _accuracyColor(double acc) {
    if (acc >= 0.8) return const Color(0xFF0CD6E7);
    if (acc >= 0.5) return Colors.amber;
    return Colors.redAccent;
  }
}

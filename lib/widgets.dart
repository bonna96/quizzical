import 'dart:ui';
import 'package:flutter/material.dart';
import 'auth_service.dart';

// ==========================================
// APP BACKGROUND
// ==========================================
class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/bg.jpg', fit: BoxFit.cover),
        Container(color: Colors.black.withOpacity(0.3)),
        child,
      ],
    );
  }
}

// ==========================================
// GLASS CONTAINER
// ==========================================
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final Color? color;
  final Border? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 20.0,
    this.blur = 12.0,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return margin != null
        ? Padding(padding: margin!, child: _buildGlass())
        : _buildGlass();
  }

  Widget _buildGlass() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: color ?? Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(borderRadius),
            border: border ?? Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ==========================================
// GLASS TEXT FIELD
// ==========================================
class GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;

  const GlassTextField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      borderRadius: 16,
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        validator: validator,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
          border: InputBorder.none,
          prefixIcon: Icon(icon, color: const Color(0xFF0CD6E7), size: 22),
        ),
      ),
    );
  }
}

// ==========================================
// CURVED SCOOP NAVBAR (matches provided image style)
// ==========================================
class CurvedNavBar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onTap;

  const CurvedNavBar({super.key, required this.selectedIndex, required this.onTap});

  @override
  State<CurvedNavBar> createState() => _CurvedNavBarState();
}

class _CurvedNavBarState extends State<CurvedNavBar> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  static const _items = [
    _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
    _NavItem(Icons.category_outlined, Icons.category_rounded, 'Categories'),
    _NavItem(Icons.bar_chart_outlined, Icons.bar_chart_rounded, 'History'),
    _NavItem(Icons.person_outline, Icons.person_rounded, 'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _anim = Tween<double>(begin: widget.selectedIndex.toDouble(), end: widget.selectedIndex.toDouble())
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(CurvedNavBar old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      _anim = Tween<double>(begin: old.selectedIndex.toDouble(), end: widget.selectedIndex.toDouble())
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 104,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // Glass bar with animated scoop
          AnimatedBuilder(
            animation: _anim,
            builder: (ctx, _) {
              return ClipPath(
                clipper: _ScoopClipper(pos: _anim.value, count: _items.length),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: CustomPaint(
                    painter: _ScoopPainter(pos: _anim.value, count: _items.length),
                    child: SizedBox(
                      height: 72,
                      child: Row(
                        children: List.generate(_items.length, (i) {
                          final sel = widget.selectedIndex == i;
                          return Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => widget.onTap(i),
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (!sel)
                                      Icon(_items[i].icon, color: Colors.white60, size: 26)
                                    else
                                      const SizedBox(height: 26),
                                    const SizedBox(height: 4),
                                    Text(
                                      _items[i].label,
                                      style: TextStyle(
                                        color: sel ? Colors.white : Colors.white54,
                                        fontSize: 10,
                                        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Floating active icon bubble
          AnimatedBuilder(
            animation: _anim,
            builder: (ctx, _) {
              final w = MediaQuery.of(ctx).size.width;
              final iw = w / _items.length;
              final x = _anim.value * iw + iw / 2;
              return Positioned(
                left: x - 30,
                bottom: 46,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: const Color(0xFF7C4DFF).withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  padding: const EdgeInsets.all(4),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF7C4DFF),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_items[widget.selectedIndex].activeIcon, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}

// Shared path builder for scoop shape
Path _buildScoopPath(Size size, double pos, int count) {
  final path = Path();
  final iw = size.width / count;
  final cx = pos * iw + iw / 2;
  const r = 24.0;
  const sw = 72.0; // scoop width
  const sd = 36.0; // scoop depth

  path.moveTo(0, r);
  path.quadraticBezierTo(0, 0, r, 0);
  path.lineTo(cx - sw / 2 - 12, 0);
  path.cubicTo(cx - sw / 2, 0, cx - sw / 2 + 8, sd, cx, sd);
  path.cubicTo(cx + sw / 2 - 8, sd, cx + sw / 2, 0, cx + sw / 2 + 12, 0);
  path.lineTo(size.width - r, 0);
  path.quadraticBezierTo(size.width, 0, size.width, r);
  path.lineTo(size.width, size.height);
  path.lineTo(0, size.height);
  path.close();
  return path;
}

class _ScoopClipper extends CustomClipper<Path> {
  final double pos;
  final int count;
  _ScoopClipper({required this.pos, required this.count});

  @override
  Path getClip(Size size) => _buildScoopPath(size, pos, count);

  @override
  bool shouldReclip(_ScoopClipper old) => old.pos != pos;
}

class _ScoopPainter extends CustomPainter {
  final double pos;
  final int count;
  _ScoopPainter({required this.pos, required this.count});

  @override
  void paint(Canvas canvas, Size size) {
    final path = _buildScoopPath(size, pos, count);
    canvas.drawPath(path, Paint()..color = Colors.white.withOpacity(0.12)..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_ScoopPainter old) => old.pos != pos;
}

// ==========================================
// USER AVATAR
// ==========================================
class UserAvatar extends StatelessWidget {
  final UserModel user;
  final double radius;

  const UserAvatar({super.key, required this.user, this.radius = 24});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Color(user.avatarColorValue),
      child: Text(
        user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
        style: TextStyle(color: Colors.white, fontSize: radius * 0.8, fontWeight: FontWeight.bold),
      ),
    );
  }
}

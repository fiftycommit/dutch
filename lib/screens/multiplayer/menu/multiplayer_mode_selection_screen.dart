import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../utils/ui_constants.dart';

class MultiplayerModeSelectionScreen extends StatelessWidget {
  const MultiplayerModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0d2818),
              Color(0xFF1a472a),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => context.go('/multiplayer'),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'MULTIJOUEUR',
                      style: TextStyle(
                        color: Colors.amber,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;
                    
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 16.0 : 20.0,
                              vertical: isMobile ? 10.0 : 20.0,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Section CRÉER UN SALON
                                _SectionHeader(
                                  icon: Icons.add_circle_outline,
                                  title: 'CRÉER UN SALON',
                                  isMobile: isMobile,
                                ),
                                SizedBox(height: isMobile ? 12 : 16),
                                _ModeCard(
                                  icon: Icons.lock_outline,
                                  title: 'Salon Privé',
                                  description: 'Crée un salon et partage le code à tes amis',
                                  color: Colors.blue.shade700,
                                  onTap: () => context.go('/multiplayer/create-private'),
                                  badge: 'CODE',
                                ),
                                SizedBox(height: isMobile ? 10 : 12),
                                _ModeCard(
                                  icon: Icons.public,
                                  title: 'Salon Public',
                                  description: 'Crée un salon visible par tous les joueurs',
                                  color: Colors.green.shade700,
                                  onTap: () => context.go('/multiplayer/create-public'),
                                  badge: 'OUVERT',
                                ),
                                
                                SizedBox(height: isMobile ? 28 : 40),
                                
                                // Section REJOINDRE UN SALON
                                _SectionHeader(
                                  icon: Icons.login,
                                  title: 'REJOINDRE UN SALON',
                                  isMobile: isMobile,
                                ),
                                SizedBox(height: isMobile ? 12 : 16),
                                _ModeCard(
                                  icon: Icons.vpn_key,
                                  title: 'Salon Privé',
                                  description: 'Entre le code à 6 caractères pour rejoindre',
                                  color: Colors.orange.shade700,
                                  onTap: () => context.go('/multiplayer/join-private'),
                                  badge: 'CODE',
                                ),
                                SizedBox(height: isMobile ? 10 : 12),
                                _ModeCard(
                                  icon: Icons.list_alt,
                                  title: 'Salon Public',
                                  description: 'Parcours la liste des salons ouverts',
                                  color: Colors.purple.shade700,
                                  onTap: () => context.go('/multiplayer/matchmaking'),
                                  badge: 'LISTE',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isMobile;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          color: Colors.amber,
          size: isMobile ? 22 : 26,
        ),
        SizedBox(width: isMobile ? 8 : 10),
        Text(
          title,
          style: TextStyle(
            color: Colors.amber,
            fontSize: isMobile ? 16 : 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;
  final String badge;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
    required this.onTap,
    required this.badge,
  });

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        
        return ScaleTransition(
          scale: _scaleAnimation,
          child: GestureDetector(
            onTapDown: (_) {
              setState(() => _isPressed = true);
              _controller.forward();
            },
            onTapUp: (_) {
              setState(() => _isPressed = false);
              _controller.reverse();
              widget.onTap();
            },
            onTapCancel: () {
              setState(() => _isPressed = false);
              _controller.reverse();
            },
            child: Container(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.color.withValues(alpha: 0.2),
                widget.color.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isPressed
                  ? widget.color
                  : widget.color.withValues(alpha: 0.5),
              width: 2,
            ),
            boxShadow: _isPressed
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ]
                : [],
          ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(isMobile ? 12 : 16),
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.icon,
                      size: isMobile ? 32 : 40,
                      color: widget.color,
                    ),
                  ),
                  SizedBox(width: isMobile ? 12 : 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isMobile ? 14 : 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isMobile ? 6 : 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: widget.color,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                widget.badge,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isMobile ? 9 : 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: isMobile ? 6 : 8),
                        Text(
                          widget.description,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: isMobile ? 12 : 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: widget.color,
                    size: isMobile ? 16 : 20,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

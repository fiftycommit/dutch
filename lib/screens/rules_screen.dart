import 'package:flutter/material.dart';
import '../utils/screen_utils.dart';

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0d2818),
      appBar: AppBar(
        title: const Text('Règles du jeu'),
        backgroundColor: const Color(0xFF1a3a28),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(ScreenUtils.spacing(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              context,
              '🎯 Objectif du jeu',
              'Le but du Dutch est de terminer la manche avec le moins de points possible.\n\n'
                  'À chaque tour, les joueurs essaient d\'échanger leurs cartes les plus pénalisantes '
                  'et de mémoriser leurs cartes pour prendre l\'avantage.',
            ),
            _buildSection(
              context,
              '🔄 Déroulement d\'un tour',
              'À votre tour, vous n\'avez que DEUX choix :\n\n'
                  '1️⃣ Piocher une carte\n'
                  '• Vous pouvez soit échanger la carte piochée avec une carte de votre main.\n'
                  '  → La carte de votre main est alors défaussée et la carte piochée remplace la carte défaussée.\n'
                  '• Soit défausser directement la carte piochée.\n'
                  '  → Si elle a un pouvoir, vous pouvez l\'activer.\n'
                  '• Puis la défausse collective s\'active.\n\n'
                  '⚠️ Si vous piochez, vous ne pourrez PLUS annoncer Dutch durant ce tour.\n\n'
                  '2️⃣ Annoncer « DUTCH »\n'
                  '• Uniquement si vous n\'avez pas pioché.\n'
                  '• Possible à tout moment, mais recommandé si vous pensez avoir le score le plus bas.\n',
            ),
            _buildSection(
              context,
              '♻️ Défausse collective',
              'À chaque carte défaussée :\n\n'
                  '• Tous les joueurs peuvent défausser une carte STRICTEMENT identique '
                  '(même valeur et même couleur).\n'
                  '• Il faut se souvenir de la position de sa carte.\n\n'
                  '⚠️ Attention :\n'
                  '• Mauvaise carte → vous la reprenez et piochez une carte de pénalité.\n'
                  '• Regarder une carte sans autorisation → carte de pénalité.\n\n'
                  'ℹ️ Les Rois rouges (♥ ♦) valent 0 point.',
            ),
            _buildSection(
              context,
              '🏁 Fin de la manche',
              'Quand un joueur annonce « DUTCH » :\n\n'
                  '• Tous les joueurs révèlent leurs cartes.\n'
                  '• Les points sont comptés.\n\n'
                  '✅ Si le joueur a le plus petit score, il gagne la manche.\n'
                  '❌ S\'il n\'a PAS le plus petit score, il est dernier.\n'
                  '🤝 En cas d\'égalité, le joueur ayant dit Dutch l\'emporte.',
            ),
            _buildCardValuesTable(context),
            _buildSection(
              context,
              '✨ Cartes spéciales (Pouvoirs)',
              'Les pouvoirs s\'activent UNIQUEMENT quand la carte est défaussée.\n\n'
                  '🃏 Joker (0 point)\n'
                  '• Mélange le jeu d\'un joueur de ton choix.\n\n'
                  '7️⃣ Le Sept\n'
                  '• Regarde une de vos cartes que vous ne connaissez pas.\n\n'
                  '🔟 Le Dix\n'
                  '• Regarde une carte du jeu d\'un adversaire.\n\n'
                  '🤵 Le Valet (11 points)\n'
                  '• Échange une carte :\n'
                  '  → soit avec un adversaire\n'
                  '  → soit entre deux adversaires.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, String content) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 16)),
      padding: EdgeInsets.all(ScreenUtils.spacing(context, 16)),
      decoration: BoxDecoration(
        color: const Color(0xFF1a472a),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2d5f3e)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: const Color(0xFF81c784),
              fontSize: ScreenUtils.scaleFont(context, 18),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ScreenUtils.spacing(context, 12)),
          Text(
            content,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: ScreenUtils.scaleFont(context, 15),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardValuesTable(BuildContext context) {
    final rows = [
      ['🃏 Joker', '0 point'],
      ['👑 Roi rouge (♥ ♦)', '0 point'],
      ['As', '1 point'],
      ['2 à 10', 'Valeur de la carte (Exemple : 4 vaut 4 points)'],
      ['🤵 Valet', '11 points'],
      ['👸 Dame', '12 points'],
      ['👑 Roi noir (♠ ♣)', '13 points'],
    ];

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 16)),
      padding: EdgeInsets.all(ScreenUtils.spacing(context, 16)),
      decoration: BoxDecoration(
        color: const Color(0xFF1a472a),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2d5f3e)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🃏 Valeur des cartes',
            style: TextStyle(
              color: const Color(0xFF81c784),
              fontSize: ScreenUtils.scaleFont(context, 18),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ScreenUtils.spacing(context, 12)),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
            },
            border: TableBorder.all(color: Colors.white24),
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Colors.white12),
                children: [
                  _tableCell(context, 'Carte', true),
                  _tableCell(context, 'Valeur', true),
                ],
              ),
              ...rows.map(
                (row) => TableRow(
                  children: [
                    _tableCell(context, row[0]),
                    _tableCell(context, row[1]),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableCell(BuildContext context, String text, [bool header = false]) {
    return Padding(
      padding: EdgeInsets.all(ScreenUtils.spacing(context, 8)),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: header ? 1 : 0.9),
          fontWeight: header ? FontWeight.bold : FontWeight.normal,
          fontSize: ScreenUtils.scaleFont(context, 14),
        ),
      ),
    );
  }
}

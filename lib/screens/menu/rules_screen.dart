import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../utils/screen_utils.dart';

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
          onPressed: () => context.go('/'),
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
            _buildRankSection(context),
            _buildRPSection(context),
            _buildBotsSection(context),
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

  Widget _buildRankSection(BuildContext context) {
    final ranks = [
      ['🥉 Bronze', '0 - 299 RP'],
      ['🥈 Argent', '300 - 599 RP'],
      ['🥇 Or', '600 - 899 RP'],
      ['💎 Platine', '900+ RP'],
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
            '🏆 Système de Rang',
            style: TextStyle(
              color: const Color(0xFF81c784),
              fontSize: ScreenUtils.scaleFont(context, 18),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ScreenUtils.spacing(context, 12)),
          Text(
            'Gagnez des RP (Points de Rang) en jouant pour monter dans les rangs.\n'
            'Plus votre rang est élevé, plus les bots sont difficiles !',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: ScreenUtils.scaleFont(context, 15),
              height: 1.4,
            ),
          ),
          SizedBox(height: ScreenUtils.spacing(context, 12)),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1),
              1: FlexColumnWidth(1),
            },
            border: TableBorder.all(color: Colors.white24),
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Colors.white12),
                children: [
                  _tableCell(context, 'Rang', true),
                  _tableCell(context, 'Points requis', true),
                ],
              ),
              ...ranks.map(
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

  Widget _buildRPSection(BuildContext context) {
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
            '📊 Points de Rang (RP)',
            style: TextStyle(
              color: const Color(0xFF81c784),
              fontSize: ScreenUtils.scaleFont(context, 18),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ScreenUtils.spacing(context, 12)),
          Text(
            'Les RP gagnés/perdus dépendent de votre rang actuel.\n'
            'En Bronze, les défaites coûtent cher mais les victoires rapportent peu.\n'
            'En Platine, c\'est l\'inverse : les bots sont si forts que perdre est moins punitif.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: ScreenUtils.scaleFont(context, 15),
              height: 1.4,
            ),
          ),
          SizedBox(height: ScreenUtils.spacing(context, 16)),
          _buildRPTable(context),
          SizedBox(height: ScreenUtils.spacing(context, 16)),
          Text(
            '🎁 Bonus Dutch (tous rangs)',
            style: TextStyle(
              color: const Color(0xFFFFD700),
              fontSize: ScreenUtils.scaleFont(context, 16),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ScreenUtils.spacing(context, 8)),
          Text(
            '• Dutch + 1er : +20 RP\n'
            '• Dutch + 1er + main vide : +30 RP supplémentaires\n'
            '  → Total possible : +50 RP de bonus !\n\n'
            '⚠️ Malus Dutch\n'
            '• Dutch raté (pas 1er) : -30 RP',
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

  Widget _buildRPTable(BuildContext context) {
    final rpData = [
      ['Position', 'Bronze', 'Argent', 'Or', 'Platine'],
      ['🏆 1er', '+30', '+45', '+55', '+70'],
      ['2ème', '+15', '+20', '+25', '+30'],
      ['3ème', '-25', '-20', '-18', '-15'],
      ['4ème', '-50', '-40', '-30', '-20'],
    ];

    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1),
        4: FlexColumnWidth(1),
      },
      border: TableBorder.all(color: Colors.white24),
      children: rpData.asMap().entries.map((entry) {
        final isHeader = entry.key == 0;
        return TableRow(
          decoration:
              isHeader ? const BoxDecoration(color: Colors.white12) : null,
          children: entry.value
              .map((cell) => _tableCell(context, cell, isHeader))
              .toList(),
        );
      }).toList(),
    );
  }

  Widget _buildBotsSection(BuildContext context) {
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
            '🤖 Niveaux des Bots',
            style: TextStyle(
              color: const Color(0xFF81c784),
              fontSize: ScreenUtils.scaleFont(context, 18),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ScreenUtils.spacing(context, 12)),
          Text(
            'Les bots s\'adaptent à votre rang. Plus vous montez, plus ils sont redoutables !',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: ScreenUtils.scaleFont(context, 15),
              height: 1.4,
            ),
          ),
          SizedBox(height: ScreenUtils.spacing(context, 16)),
          _buildBotCard(
            context,
            '🥉 Bots Bronze',
            'Débutants et distraits',
            [
              'Oublient souvent vos cartes (25%/tour)',
              'Se trompent lors des échanges (45%)',
              'Dutch à 12 points ou moins',
              'Réaction lente à la défausse',
            ],
            const Color(0xFFCD7F32),
          ),
          _buildBotCard(
            context,
            '🥈 Bots Argent',
            'Compétents',
            [
              'Bonne mémoire (oubli 10%/tour)',
              'Rarement confus (15%)',
              'Dutch à 6 points ou moins',
              'Réaction correcte à la défausse',
            ],
            const Color(0xFFC0C0C0),
          ),
          _buildBotCard(
            context,
            '🥇 Bots Or',
            'Experts',
            [
              'Excellente mémoire (oubli 2%/tour)',
              'Très précis (confusion 5%)',
              'Dutch agressif à 4 points',
              'Réaction rapide à la défausse',
            ],
            const Color(0xFFFFD700),
          ),
          _buildBotCard(
            context,
            '💎 Bots Platine',
            'ULTIMES - Quasi imbattables !',
            [
              'Mémoire PARFAITE (n\'oublient jamais)',
              'AUCUNE erreur sur les échanges',
              'Dutch ultra-agressif à 2 points',
              'Réaction instantanée (95%)',
            ],
            const Color(0xFF00CED1),
          ),
        ],
      ),
    );
  }

  Widget _buildBotCard(
    BuildContext context,
    String title,
    String subtitle,
    List<String> features,
    Color accentColor,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 12)),
      padding: EdgeInsets.all(ScreenUtils.spacing(context, 12)),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accentColor,
              fontSize: ScreenUtils.scaleFont(context, 16),
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: ScreenUtils.scaleFont(context, 13),
              fontStyle: FontStyle.italic,
            ),
          ),
          SizedBox(height: ScreenUtils.spacing(context, 8)),
          ...features.map((f) => Padding(
                padding:
                    EdgeInsets.only(bottom: ScreenUtils.spacing(context, 4)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ',
                        style: TextStyle(
                            color: accentColor,
                            fontSize: ScreenUtils.scaleFont(context, 14))),
                    Expanded(
                      child: Text(
                        f,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: ScreenUtils.scaleFont(context, 14),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

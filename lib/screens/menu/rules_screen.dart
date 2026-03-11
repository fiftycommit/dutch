import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import '../../utils/screen_utils.dart';
import '../../utils/ui_constants.dart';

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  static const _carte7      = 'assets/images/cards/07-trefle.svg';
  static const _carte10     = 'assets/images/cards/10-carreau.svg';
  static const _carteValet  = 'assets/images/cards/V-carreau.svg';
  static const _carteJoker  = 'assets/images/cards/joker-rouge.svg';
  static const _carteRoiRed = 'assets/images/cards/R-coeur.svg';
  static const _carteRoiBla = 'assets/images/cards/R-pique.svg';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.gradientTop,
      appBar: AppBar(
        title: const Text('Règles du jeu'),
        backgroundColor: AppColors.backgroundMedium,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () async {
            final didPop = await Navigator.of(context).maybePop();
            if (!didPop && context.mounted) context.go('/');
          },
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
            // §1 Introduction
            _buildRuleSection(
              context,
              icon: Icons.info_outline,
              title: "Le Dutch, c'est quoi ?",
              child: Text(
                "Un jeu de cartes basé sur la mémoire pour 2 à 6 joueurs. "
                "Vous avez 4 cartes face cachée, et vous pouvez en mémoriser 2 au début de la partie. "
                "Ensuite, impossible de les revoir !",
                style: _body(context),
              ),
            ),

            // §2 Objectif
            _buildRuleSection(
              context,
              icon: Icons.emoji_events_outlined,
              title: 'Le but du jeu',
              child: RichText(
                text: TextSpan(style: _body(context), children: const [
                  TextSpan(text: 'Terminer la manche avec '),
                  TextSpan(
                    text: 'le moins de points possible',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF81c784)),
                  ),
                  TextSpan(text: '. Les points sont calculés en additionnant la valeur de vos 4 cartes.'),
                ]),
              ),
            ),

            // §3 Valeur des cartes
            _buildRuleSection(
              context,
              icon: Icons.style_outlined,
              title: 'Valeur des cartes',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chaque carte a une valeur qui compte dans votre score final :', style: _body(context)),
                  SizedBox(height: ScreenUtils.spacing(context, 12)),
                  _valueRow(context, 'As', '1 pt'),
                  _valueRow(context, '2 à 10', 'Valeur de la carte'),
                  _valueRow(context, 'Valet', '11 pts'),
                  _valueRow(context, 'Dame', '12 pts'),
                  SizedBox(height: ScreenUtils.spacing(context, 16)),
                  Text(
                    'Quelques exceptions à la règle :',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: ScreenUtils.scaleFont(context, 14),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ScreenUtils.spacing(context, 12)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _specialCard(context, _carteJoker, 'Joker', '0 pt', false),
                      _specialCard(context, _carteRoiRed, 'Roi rouge\n(♥ ♦)', '0 pt', false),
                      _specialCard(context, _carteRoiBla, 'Roi noir\n(♠ ♣)', '13 pts', true),
                    ],
                  ),
                ],
              ),
            ),

            // §4 Défausse collective
            _buildRuleSection(
              context,
              icon: Icons.group_outlined,
              title: 'Défausse collective',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(style: _body(context), children: const [
                      TextSpan(text: 'Quand un joueur défausse, les autres peuvent défausser une carte du '),
                      TextSpan(
                        text: 'même rang',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF81c784)),
                      ),
                      TextSpan(text: ' — peu importe la couleur ou l\'enseigne.'),
                    ]),
                  ),
                  SizedBox(height: ScreenUtils.spacing(context, 12)),
                  _warningBlock(
                    context,
                    title: 'Attention !',
                    text: 'Mauvaise carte → vous la reprenez et piochez une pénalité.\nRegarder une carte sans autorisation → pénalité.',
                    bg: const Color(0xFFB71C1C),
                    accent: const Color(0xFFFF5252),
                  ),
                ],
              ),
            ),

            // §5 Pouvoirs spéciaux
            _buildRuleSection(
              context,
              icon: Icons.bolt_outlined,
              title: 'Pouvoirs spéciaux',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Activés uniquement quand la carte est défaussée en premier :', style: _body(context)),
                  SizedBox(height: ScreenUtils.spacing(context, 12)),
                  _powerCard(context, _carte10,    'Tous les 10',    'Espionner : voir une carte d\'un adversaire'),
                  _powerCard(context, _carteValet, 'Valet (♥ ♦)',    'Échanger : échanger 2 cartes entre adversaires'),
                  _powerCard(context, _carteJoker, 'Joker',          'Mélanger : mélanger la main d\'un joueur'),
                  _powerCard(context, _carte7,     '7',              'Révéler : voir une de vos propres cartes'),
                ],
              ),
            ),

            // §6 Déroulement
            _buildRuleSection(
              context,
              icon: Icons.play_circle_outline,
              title: 'Déroulement d\'une partie',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _stepCard(context, '1', 'Phase de mémorisation',
                      'Appuyez sur deux cartes pour les révéler. Elles restent visibles 3 secondes puis se retournent.'),
                  _stepCard(context, '2', 'Votre tour',
                      'Deux actions possibles : Piocher une carte ou appeler Dutch.'),
                  _stepCard(context, '3', 'Piocher',
                      'Tirez une carte. Échangez-la avec une carte de votre main, ou défaussez-la directement (bouton JETER).'),
                  _reactionBlock(context),
                  _stepCard(context, '5', 'Appeler Dutch',
                      'Quand vous pensez avoir le plus petit score, appuyez sur Dutch. La manche s\'arrête immédiatement.'),
                  SizedBox(height: ScreenUtils.spacing(context, 12)),
                  _warningBlock(
                    context,
                    title: 'Règle du Dutch',
                    text: 'Si vous appelez Dutch sans avoir le plus petit score, vous êtes classé dernier ! '
                        'En cas d\'égalité, le joueur qui a appelé Dutch est classé premier.',
                    bg: const Color(0xFFE65100),
                    accent: const Color(0xFFFF9800),
                  ),
                ],
              ),
            ),

            // §7 Modes de jeu
            _buildRuleSection(
              context,
              icon: Icons.gamepad_outlined,
              title: 'Modes de jeu',
              child: Column(
                children: [
                  _modeCard(context, 'Partie Rapide',
                      'Lancez une partie composée d\'une seule manche.',
                      [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]),
                  _modeCard(context, 'Tournoi',
                      'Enchaînez plusieurs manches successives jusqu\'à atteindre la finale.',
                      [const Color(0xFF2E7D32), const Color(0xFF388E3C)]),
                  _modeCard(context, 'Multijoueur',
                      'Jouez avec d\'autres joueurs en ligne.',
                      [const Color(0xFF1A237E), const Color(0xFF283593)]),
                ],
              ),
            ),

            // §8 Réglages & SBMM
            _buildRuleSection(
              context,
              icon: Icons.tune_outlined,
              title: 'Réglages et SBMM',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dans les réglages, vous pouvez personnaliser le temps de réaction, '
                    'le niveau des bots, et activer le SBMM (Skill-Based Matchmaking).',
                    style: _body(context),
                  ),
                  SizedBox(height: ScreenUtils.spacing(context, 12)),
                  _sbmmCard(context, 'SBMM désactivé',
                      'Choisissez manuellement le niveau des bots et le nombre de joueurs.'),
                  SizedBox(height: ScreenUtils.spacing(context, 8)),
                  _sbmmCard(context, 'SBMM activé',
                      'Seul le nombre de joueurs est configurable. Le niveau des bots s\'ajuste automatiquement à votre niveau.'),
                ],
              ),
            ),

            // §9 Rang
            _buildRankSection(context),

            // §10 RP
            _buildRPSection(context),

            // §11 Bots
            _buildBotsSection(context),

            // Footer
            Padding(
              padding: EdgeInsets.symmetric(vertical: ScreenUtils.spacing(context, 24)),
              child: Center(
                child: Text(
                  'Bonne partie ! 🎮',
                  style: TextStyle(
                    color: const Color(0xFF81c784),
                    fontSize: ScreenUtils.scaleFont(context, 18),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Styles ────────────────────────────────────────────────────────────────

  TextStyle _body(BuildContext context) => TextStyle(
        color: Colors.white.withValues(alpha: 0.9),
        fontSize: ScreenUtils.scaleFont(context, 15),
        height: 1.4,
      );

  // ── Section avec icône ────────────────────────────────────────────────────

  Widget _buildRuleSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 16)),
      padding: EdgeInsets.all(ScreenUtils.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.gradientBottom,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.buttonSecondary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ScreenUtils.spacing(context, 8)),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: ScreenUtils.scaleFont(context, 18)),
              ),
              SizedBox(width: ScreenUtils.spacing(context, 12)),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: const Color(0xFF81c784),
                    fontSize: ScreenUtils.scaleFont(context, 18),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: ScreenUtils.spacing(context, 16)),
          child,
        ],
      ),
    );
  }

  // ── Ligne valeur carte ────────────────────────────────────────────────────

  Widget _valueRow(BuildContext context, String label, String value) {
    return Container(
      margin: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 6)),
      padding: EdgeInsets.symmetric(
        horizontal: ScreenUtils.spacing(context, 12),
        vertical: ScreenUtils.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: ScreenUtils.scaleFont(context, 14))),
          Text(value, style: TextStyle(color: const Color(0xFF81c784), fontSize: ScreenUtils.scaleFont(context, 14), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── Carte spéciale avec image ─────────────────────────────────────────────

  Widget _specialCard(BuildContext context, String asset, String label, String value, bool isNegative) {
    return Container(
      padding: EdgeInsets.all(ScreenUtils.spacing(context, 10)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.buttonSecondary),
      ),
      child: Column(
        children: [
          SvgPicture.asset(asset, width: 52, height: 76),
          SizedBox(height: ScreenUtils.spacing(context, 6)),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: ScreenUtils.scaleFont(context, 12)),
          ),
          SizedBox(height: ScreenUtils.spacing(context, 2)),
          Text(
            value,
            style: TextStyle(
              color: isNegative ? const Color(0xFFEF5350) : const Color(0xFF81c784),
              fontSize: ScreenUtils.scaleFont(context, 14),
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ── Carte pouvoir ─────────────────────────────────────────────────────────

  Widget _powerCard(BuildContext context, String asset, String label, String description) {
    return Container(
      margin: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 10)),
      padding: EdgeInsets.all(ScreenUtils.spacing(context, 12)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.buttonSecondary),
      ),
      child: Row(
        children: [
          SvgPicture.asset(asset, width: 44, height: 64),
          SizedBox(width: ScreenUtils.spacing(context, 14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: const Color(0xFF81c784), fontSize: ScreenUtils.scaleFont(context, 15), fontWeight: FontWeight.bold)),
                SizedBox(height: ScreenUtils.spacing(context, 4)),
                Text(description, style: _body(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Étape numérotée ───────────────────────────────────────────────────────

  Widget _stepCard(BuildContext context, String step, String title, String description) {
    return Padding(
      padding: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
              ),
            ),
            alignment: Alignment.center,
            child: Text(step, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          SizedBox(width: ScreenUtils.spacing(context, 12)),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(ScreenUtils.spacing(context, 10)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: Colors.white, fontSize: ScreenUtils.scaleFont(context, 14), fontWeight: FontWeight.bold)),
                  SizedBox(height: ScreenUtils.spacing(context, 4)),
                  Text(description, style: _body(context)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bloc phase de réaction (step 4, mis en valeur) ────────────────────────

  Widget _reactionBlock(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
              ),
            ),
            alignment: Alignment.center,
            child: const Text('4', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          SizedBox(width: ScreenUtils.spacing(context, 12)),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(ScreenUtils.spacing(context, 12)),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)]),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF4CAF50)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('⚡ Phase de réaction',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: ScreenUtils.scaleFont(context, 14))),
                  SizedBox(height: ScreenUtils.spacing(context, 8)),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(color: Colors.white, fontSize: ScreenUtils.scaleFont(context, 13), height: 1.4),
                      children: const [
                        TextSpan(text: 'Quand une carte est défaussée, '),
                        TextSpan(
                          text: 'tous les joueurs peuvent défausser une carte du même rang',
                          style: TextStyle(color: Color(0xFF81c784), fontWeight: FontWeight.bold),
                        ),
                        TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  SizedBox(height: ScreenUtils.spacing(context, 8)),
                  Container(
                    padding: EdgeInsets.all(ScreenUtils.spacing(context, 10)),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🎯 Important :',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: ScreenUtils.scaleFont(context, 13))),
                        SizedBox(height: ScreenUtils.spacing(context, 6)),
                        ...[
                          'Seule la valeur compte (ex : 7♥ défaussé → n\'importe quel 7 peut suivre)',
                          'L\'enseigne (♠ ♥ ♦ ♣) n\'a aucune importance',
                          'La couleur (rouge/noir) n\'a aucune importance',
                          'Basez-vous sur votre mémoire !',
                        ].map((t) => Padding(
                              padding: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 4)),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('• ', style: TextStyle(color: const Color(0xFF81c784), fontSize: ScreenUtils.scaleFont(context, 13))),
                                  Expanded(
                                    child: Text(t,
                                        style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.9),
                                            fontSize: ScreenUtils.scaleFont(context, 13),
                                            height: 1.3)),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bloc warning ──────────────────────────────────────────────────────────

  Widget _warningBlock(
    BuildContext context, {
    required String title,
    required String text,
    required Color bg,
    required Color accent,
  }) {
    return Container(
      padding: EdgeInsets.all(ScreenUtils.spacing(context, 12)),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: accent, size: 18),
          SizedBox(width: ScreenUtils.spacing(context, 8)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: ScreenUtils.scaleFont(context, 13))),
                SizedBox(height: ScreenUtils.spacing(context, 4)),
                Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: ScreenUtils.scaleFont(context, 13), height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Carte mode de jeu ─────────────────────────────────────────────────────

  Widget _modeCard(BuildContext context, String title, String description, List<Color> colors) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 10)),
      padding: EdgeInsets.all(ScreenUtils.spacing(context, 14)),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.white, fontSize: ScreenUtils.scaleFont(context, 15), fontWeight: FontWeight.bold)),
          SizedBox(height: ScreenUtils.spacing(context, 4)),
          Text(description, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: ScreenUtils.scaleFont(context, 13))),
        ],
      ),
    );
  }

  // ── Carte SBMM ───────────────────────────────────────────────────────────

  Widget _sbmmCard(BuildContext context, String title, String description) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ScreenUtils.spacing(context, 12)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Colors.white, fontSize: ScreenUtils.scaleFont(context, 14), fontWeight: FontWeight.bold)),
          SizedBox(height: ScreenUtils.spacing(context, 4)),
          Text(description, style: _body(context)),
        ],
      ),
    );
  }

  // ── Cellule de tableau ────────────────────────────────────────────────────

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

  // ── §9 Rang ───────────────────────────────────────────────────────────────

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
        color: AppColors.gradientBottom,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.buttonSecondary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ScreenUtils.spacing(context, 8)),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.military_tech_outlined, color: Colors.white, size: ScreenUtils.scaleFont(context, 18)),
              ),
              SizedBox(width: ScreenUtils.spacing(context, 12)),
              Expanded(
                child: Text(
                  '🏆 Système de Rang',
                  style: TextStyle(
                    color: const Color(0xFF81c784),
                    fontSize: ScreenUtils.scaleFont(context, 18),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: ScreenUtils.spacing(context, 16)),
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
            columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1)},
            border: TableBorder.all(color: Colors.white24),
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Colors.white12),
                children: [_tableCell(context, 'Rang', true), _tableCell(context, 'Points requis', true)],
              ),
              ...ranks.map((row) => TableRow(children: [_tableCell(context, row[0]), _tableCell(context, row[1])])),
            ],
          ),
        ],
      ),
    );
  }

  // ── §10 RP ────────────────────────────────────────────────────────────────

  Widget _buildRPSection(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 16)),
      padding: EdgeInsets.all(ScreenUtils.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.gradientBottom,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.buttonSecondary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ScreenUtils.spacing(context, 8)),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.bar_chart, color: Colors.white, size: ScreenUtils.scaleFont(context, 18)),
              ),
              SizedBox(width: ScreenUtils.spacing(context, 12)),
              Expanded(
                child: Text(
                  '📊 Points de Rang (RP)',
                  style: TextStyle(
                    color: const Color(0xFF81c784),
                    fontSize: ScreenUtils.scaleFont(context, 18),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: ScreenUtils.spacing(context, 16)),
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
          decoration: isHeader ? const BoxDecoration(color: Colors.white12) : null,
          children: entry.value.map((cell) => _tableCell(context, cell, isHeader)).toList(),
        );
      }).toList(),
    );
  }

  // ── §11 Bots ──────────────────────────────────────────────────────────────

  Widget _buildBotsSection(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 16)),
      padding: EdgeInsets.all(ScreenUtils.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.gradientBottom,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.buttonSecondary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ScreenUtils.spacing(context, 8)),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.smart_toy_outlined, color: Colors.white, size: ScreenUtils.scaleFont(context, 18)),
              ),
              SizedBox(width: ScreenUtils.spacing(context, 12)),
              Expanded(
                child: Text(
                  '🤖 Niveaux des Bots',
                  style: TextStyle(
                    color: const Color(0xFF81c784),
                    fontSize: ScreenUtils.scaleFont(context, 18),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: ScreenUtils.spacing(context, 16)),
          Text(
            'Les bots s\'adaptent à votre rang. Plus vous montez, plus ils sont redoutables !',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: ScreenUtils.scaleFont(context, 15),
              height: 1.4,
            ),
          ),
          SizedBox(height: ScreenUtils.spacing(context, 16)),
          _buildBotCard(context, '🥉 Bots Bronze', 'Débutants et distraits', [
            'Oublient souvent vos cartes (25%/tour)',
            'Se trompent lors des échanges (45%)',
            'Dutch à 12 points ou moins',
            'Réaction lente à la défausse',
          ], const Color(0xFFCD7F32)),
          _buildBotCard(context, '🥈 Bots Argent', 'Compétents', [
            'Bonne mémoire (oubli 10%/tour)',
            'Rarement confus (15%)',
            'Dutch à 6 points ou moins',
            'Réaction correcte à la défausse',
          ], const Color(0xFFC0C0C0)),
          _buildBotCard(context, '🥇 Bots Or', 'Experts', [
            'Excellente mémoire (oubli 2%/tour)',
            'Très précis (confusion 5%)',
            'Dutch agressif à 4 points',
            'Réaction rapide à la défausse',
          ], const Color(0xFFFFD700)),
          _buildBotCard(context, '💎 Bots Platine', 'ULTIMES - Quasi imbattables !', [
            'Mémoire PARFAITE (n\'oublient jamais)',
            'AUCUNE erreur sur les échanges',
            'Dutch ultra-agressif à 2 points',
            'Réaction instantanée (95%)',
          ], const Color(0xFF00CED1)),
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
          Text(title, style: TextStyle(color: accentColor, fontSize: ScreenUtils.scaleFont(context, 16), fontWeight: FontWeight.bold)),
          Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: ScreenUtils.scaleFont(context, 13), fontStyle: FontStyle.italic)),
          SizedBox(height: ScreenUtils.spacing(context, 8)),
          ...features.map((f) => Padding(
                padding: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 4)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: accentColor, fontSize: ScreenUtils.scaleFont(context, 14))),
                    Expanded(
                      child: Text(f, style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: ScreenUtils.scaleFont(context, 14))),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

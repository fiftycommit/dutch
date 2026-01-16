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
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(ScreenUtils.spacing(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSection(
              context,
              '🎯 But du jeu',
              'Avoir le MOINS de points possible à la fin de la partie.',
            ),

            _buildSection(
              context,
              '🎴 Début de partie',
              '• Chaque joueur reçoit 4 cartes face cachée\n'
              '• Tu peux regarder 2 de tes cartes au début\n'
              '• Les cartes se cachent après quelques secondes',
            ),

            _buildSection(
              context,
              '🔄 Ton tour',
              '1️⃣ Pioche une carte\n'
              '2️⃣ Choisis :\n'
              '   • GARDER la carte : elle remplace une de tes 4 cartes\n'
              '   • DÉFAUSSER : la carte va à la poubelle\n'
              '   • Si tu défausses une carte spéciale, son pouvoir s\'active !',
            ),

            _buildSection(
              context,
              '⚡ Pouvoirs Spéciaux',
              '• 7, 8, 9 : Tu peux regarder une de tes cartes\n'
              '• 10, 11, 12 : Tu peux regarder une carte adverse\n'
              '• Valet (V) : Échange une de tes cartes avec un adversaire (à l\'aveugle)\n'
              '• Dame (D) : Regarde une carte de chaque joueur\n'
              '• Roi Noir (♠️♣️) : Vaut 13 points (Aïe !)\n'
              '• Roi Rouge (♥️♦️) : Vaut 0 point (Génial !)\n'
              '• Joker : Mélange tout le jeu !',
            ),

            _buildSection(
              context,
              '🔥 Le DUTCH',
              '• Quand tu penses avoir le score le plus bas, crie "DUTCH" !\n'
              '• Le tour se termine immédiatement.\n'
              '• Si tu as bien le score le plus bas : TU GAGNES ! (0 pts)\n'
              '• Si tu t\'es trompé : TU PERDS ! (Pénalité + Carte de punition)',
            ),

            // --- NOUVELLE SECTION CLASSEMENT ---
            _buildSection(
              context,
              '📈 Classement & Niveaux',
              'Gagne des points (RP) pour monter en grade et affronter des Bots plus forts !\n\n'
              '• Victoire : +50 RP\n'
              '• Victoire par Dutch : +80 RP\n'
              '• Défaite : -20 RP\n'
              '• Dutch Raté : -50 RP (Attention !)\n\n'
              '🏅 Bronze (<150) : Bots Faciles\n'
              '🥈 Argent (150-450) : Bots Moyens\n'
              '🥇 Or (450+) : Bots Difficiles',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, String content) {
    return Container(
      margin: EdgeInsets.only(bottom: ScreenUtils.spacing(context, 16)),
      padding: EdgeInsets.all(ScreenUtils.spacing(context, 12)),
      decoration: BoxDecoration(
        color: const Color(0xFF1a472a),
        borderRadius: BorderRadius.circular(ScreenUtils.borderRadius(context, 8)),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.amber.shade300,
              fontSize: ScreenUtils.scaleFont(context, 14),
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ScreenUtils.spacing(context, 8)),
          Text(
            content,
            style: TextStyle(
              color: Colors.white,
              fontSize: ScreenUtils.scaleFont(context, 11),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../models/game_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('RÉGLAGES', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1a3a28),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1a3a28), Color(0xFF0d1f15)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader("MÉCANIQUE DE JEU"),
            
            // --- CURSEUR : TEMPS DE RÉACTION ---
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Vitesse Défausse", style: TextStyle(color: Colors.white, fontSize: 16)),
                      Text(
                        "${(settings.reactionTimeMs / 1000).toStringAsFixed(1)} s", 
                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)
                      ),
                    ],
                  ),
                  Slider(
                    value: settings.reactionTimeMs.toDouble(),
                    min: 2000, 
                    max: 6000, 
                    divisions: 8,
                    activeColor: Colors.amber,
                    inactiveColor: Colors.white24,
                    onChanged: (value) {
                      settings.setReactionTime(value.toInt());
                    },
                  ),
                  const Text(
                    "Temps disponible pour jouer une carte sur la défausse.",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            
            // --- MÉTHODE DE MÉLANGE (DIFFICULTÉ DU JEU) ---
            _buildSectionHeader("MÉTHODE DE MÉLANGE (CHANCE)"),
            
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildShuffleOption(
                    settings, 
                    Difficulty.easy, 
                    "DÉTENDU", 
                    "Mélange 100% aléatoire. Chance pure.\nIdéal pour les parties rapides.",
                    Colors.green
                  ),
                  const Divider(height: 1, color: Colors.white24),
                  _buildShuffleOption(
                    settings, 
                    Difficulty.medium, 
                    "TACTIQUE", 
                    "Mélange pondéré et équilibré.\nMoins de chaos, plus de stratégie.",
                    Colors.amber
                  ),
                  const Divider(height: 1, color: Colors.white24),
                  _buildShuffleOption(
                    settings, 
                    Difficulty.hard, 
                    "CHALLENGER", 
                    "Pioche exigeante.\nLes bonnes cartes se méritent.",
                    Colors.red
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            _buildSectionHeader("AUDIO & IMMERSION"),
            _buildSwitchTile(
              "Effets Sonores",
              "Bruits de cartes et alertes",
              settings.soundEnabled,
              (val) => settings.toggleSound(val),
            ),
            _buildSwitchTile(
              "Vibrations",
              "Retour haptique",
              settings.hapticEnabled,
              (val) => settings.toggleHaptic(val),
            ),
            
            const SizedBox(height: 10),
            _buildSwitchTile(
              "SBMM (Adaptatif)",
              "Ajuste l'IA des bots selon vos résultats",
              settings.useSBMM,
              (val) => settings.toggleSBMM(val),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        title, 
        style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, Function(bool) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.amber,
      ),
    );
  }

  Widget _buildShuffleOption(SettingsProvider settings, Difficulty level, String label, String desc, Color color) {
    // On utilise luckDifficulty pour stocker le mode de mélange
    bool isSelected = settings.luckDifficulty == level;
    return InkWell(
      onTap: () => settings.setLuckDifficulty(level),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: isSelected ? color : Colors.white24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: isSelected ? color : Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(desc, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
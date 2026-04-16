import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/settings_provider.dart';
import '../../services/matchmaking/sbmm_local_service.dart';
import '../../utils/ui_constants.dart';

class SettingsScreen extends StatefulWidget {
  final int initialSlot;

  const SettingsScreen({super.key, this.initialSlot = 1});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<int, String> _slotNames = {
    1: 'Joueur 1',
    2: 'Joueur 2',
    3: 'Joueur 3',
  };

  @override
  void initState() {
    super.initState();
    _loadSlotNames();
  }

  Future<void> _loadSlotNames() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _slotNames = {
        1: _readSlotName(prefs, 1),
        2: _readSlotName(prefs, 2),
        3: _readSlotName(prefs, 3),
      };
    });
  }

  String _slotNameKey(int slotId) => 'slot_name_$slotId';

  String _defaultSlotName(int slotId) => 'Joueur $slotId';

  String _readSlotName(SharedPreferences prefs, int slotId) {
    final raw = prefs.getString(_slotNameKey(slotId));
    if (raw == null) return _defaultSlotName(slotId);
    final trimmed = raw.trim();
    return trimmed.isEmpty ? _defaultSlotName(slotId) : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return DefaultTabController(
      initialIndex: (widget.initialSlot - 1).clamp(0, 2),
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('RÉGLAGES',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.backgroundMedium,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () async {
              final didPop = await Navigator.of(context).maybePop();
              if (!didPop && context.mounted) context.go('/');
            },
          ),
          bottom: TabBar(
            indicatorColor: Colors.amber,
            labelColor: Colors.amber,
            unselectedLabelColor: AppColors.textDisabled,
            tabs: [
              Tab(
                child: Text(
                  _slotNames[1] ?? _defaultSlotName(1),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Tab(
                child: Text(
                  _slotNames[2] ?? _defaultSlotName(2),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Tab(
                child: Text(
                  _slotNames[3] ?? _defaultSlotName(3),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.backgroundMedium, AppColors.backgroundDark],
            ),
          ),
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            children: List.generate(3, (index) => _buildSettingsPage(settings)),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsPage(SettingsProvider settings) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader("MÉCANIQUE DE JEU"),
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
                  const Text("Vitesse Défausse",
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  Text(
                      "${(settings.reactionTimeMs / 1000).toStringAsFixed(1)} s",
                      style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
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
                style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Affichage action bot",
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  Text(
                      settings.actionTextDisplayMs == 0
                          ? "Désactivé"
                          : "${(settings.actionTextDisplayMs / 1000).toStringAsFixed(1)} s",
                      style: const TextStyle(
                          color: Colors.amber,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
              Slider(
                value: settings.actionTextDisplayMs.toDouble(),
                min: 0,
                max: 10000,
                divisions: 20,
                activeColor: Colors.amber,
                inactiveColor: Colors.white24,
                onChanged: (value) {
                  settings.setActionTextDisplayTime(value.toInt());
                },
              ),
              const Text(
                "Durée d'affichage de l'action des bots avant la réaction. 0 = désactivé.",
                style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
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
        _buildSwitchTile(
          "Animations",
          "Vol des cartes et transitions",
          settings.animationsEnabled,
          (val) => settings.toggleAnimations(val),
        ),
        _buildSwitchTile(
          "Pluie de cartes",
          "Animation de fond sur le menu principal",
          settings.cardRainEnabled,
          (val) => settings.toggleCardRain(val),
        ),
        const SizedBox(height: 10),
        _buildSwitchTile(
          "SBMM (Adaptatif)",
          "Ajuste l'IA des bots selon vos résultats",
          settings.useSBMM,
          (val) => settings.toggleSBMM(val),
        ),
        _buildActionTile(
          title: "Réinitialiser la progression SBMM",
          subtitle: "Remet le niveau des bots au démarrage",
          icon: Icons.restart_alt,
          onTap: _confirmResetSBMM,
        ),
      ],
    );
  }

  Future<void> _confirmResetSBMM() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundMedium,
        title: const Text(
          'Réinitialiser le SBMM ?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Ton cursor et ton historique récent seront effacés. Les prochaines parties repartiront au niveau initial.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Réinitialiser',
              style: TextStyle(color: Colors.amber),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await SBMMLocalService.reset();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Progression SBMM réinitialisée'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(title,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSwitchTile(
      String title, String subtitle, bool value, Function(bool) onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12)),
      child: SwitchListTile(
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle,
            style:
                const TextStyle(color: AppColors.textDisabled, fontSize: 12)),
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.amber,
      ),
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: Colors.amber),
        title: Text(
          title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppColors.textDisabled, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
        onTap: onTap,
      ),
    );
  }
}

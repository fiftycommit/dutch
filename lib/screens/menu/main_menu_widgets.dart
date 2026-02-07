import 'package:flutter/material.dart';
import '../../utils/ui_constants.dart';

Color getRankColor(String rank) {
  switch (rank) {
    case 'Platine':
      return const Color(0xFF00BFFF); // Bleu diamant brillant
    case 'Or':
      return Colors.amber;
    case 'Argent':
      return const Color(0xFFC0C0C0);
    default:
      return const Color(0xFFCD7F32); // Bronze
  }
}

/// Slot compact pour le mode paysage
class CompactSlotCard extends StatelessWidget {
  final int id;
  final String name;
  final String rank;
  final String rp;
  final bool isSelected;
  final Color rankColor;
  final VoidCallback onTap;

  const CompactSlotCard({
    super.key,
    required this.id,
    required this.name,
    required this.rank,
    required this.rp,
    required this.isSelected,
    required this.rankColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          color: isSelected ? rankColor : Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: Colors.white, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: rankColor.withValues(alpha: 0.5), blurRadius: 8)
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person,
                color: isSelected ? Colors.black : AppColors.textSecondary, size: 20),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(name,
                  style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(rank,
                  style: TextStyle(
                      color: isSelected ? Colors.black87 : rankColor,
                      fontWeight: FontWeight.bold,
                      fontSize: AppFontSizes.small)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(rp,
                  style: TextStyle(
                      color: isSelected ? Colors.black54 : AppColors.textDisabled,
                      fontSize: AppFontSizes.small)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slot portrait classique
class SaveSlotCard extends StatelessWidget {
  final int id;
  final String name;
  final String rank;
  final String rp;
  final bool isSelected;
  final Color rankColor;
  final VoidCallback onTap;

  const SaveSlotCard({
    super.key,
    required this.id,
    required this.name,
    required this.rank,
    required this.rp,
    required this.isSelected,
    required this.rankColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 100,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? rankColor : Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: Colors.white, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: rankColor.withValues(alpha: 0.5), blurRadius: 10)
                ]
              : [],
        ),
        child: Column(
          children: [
            Icon(Icons.person,
                color: isSelected ? Colors.black : AppColors.textSecondary, size: 30),
            const SizedBox(height: 4),
            Text(name,
                style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12)),
            Text(rank,
                style: TextStyle(
                    color: isSelected ? Colors.black87 : rankColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11)),
            Text(rp,
                style: TextStyle(
                    color: isSelected ? Colors.black54 : Colors.grey,
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

/// Bouton de menu compact pour paysage
class CompactMenuButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onPressed;

  const CompactMenuButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 40,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon,
            color: isPrimary ? Colors.black : Colors.white, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? Colors.amber : AppColors.buttonSecondary,
          foregroundColor: isPrimary ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: isPrimary ? 6 : 3,
        ),
      ),
    );
  }
}

/// Bouton de menu portrait
class MenuButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onPressed;

  const MenuButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: isPrimary ? Colors.black : Colors.white),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? Colors.amber : AppColors.buttonSecondary,
          foregroundColor: isPrimary ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: isPrimary ? 8 : 4,
        ),
      ),
    );
  }
}

/// Petit bouton icône pour paysage
class SmallIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const SmallIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      color: AppColors.textSecondary,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.backgroundMedium,
        padding: const EdgeInsets.all(8),
      ),
    );
  }
}

/// Bouton icône avec label pour portrait
class LabeledIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const LabeledIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 28),
          color: AppColors.textSecondary,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.backgroundMedium,
            padding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}

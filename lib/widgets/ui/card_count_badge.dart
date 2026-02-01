import 'package:flutter/material.dart';

/// Badge affichant le nombre de cartes d'un joueur
/// Widget neutre utilisable en solo et en multi
class CardCountBadge extends StatelessWidget {
  final int count;
  final bool isCompact;

  const CardCountBadge({
    super.key,
    required this.count,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 3 : 6),
      decoration: BoxDecoration(
        color: Colors.amber,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Text(
        "$count",
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: isCompact ? 9 : 14,
          color: Colors.black,
        ),
      ),
    );
  }
}

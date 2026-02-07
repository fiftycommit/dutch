import 'package:flutter/material.dart';

class WinrateBucket {
  int played = 0;
  int won = 0;

  double get winRate => played > 0 ? won / played : 0;
}

class HistoryGroup {
  final bool isTournament;
  final String? tournamentId;
  final List<Map<String, dynamic>> matches;
  final DateTime date;

  const HistoryGroup({
    required this.isTournament,
    required this.tournamentId,
    required this.matches,
    required this.date,
  });
}

class OutcomeStyle {
  final IconData icon;
  final Color color;
  final String label;

  const OutcomeStyle({
    required this.icon,
    required this.color,
    required this.label,
  });
}

class RpDisplay {
  final String text;
  final Color color;

  const RpDisplay({
    required this.text,
    required this.color,
  });
}

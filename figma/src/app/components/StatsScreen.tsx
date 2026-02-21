import { motion } from "motion/react";
import { ArrowLeft, Trophy, Target, TrendingUp, Clock } from "lucide-react";

interface StatsScreenProps {
  onBack: () => void;
}

// Données mock pour les stats
const playerStats = [
  { name: "Max", wins: 12, games: 25, winRate: 48 },
  { name: "El Roy", wins: 15, games: 28, winRate: 54 },
  { name: "Irfat", wins: 10, games: 22, winRate: 45 },
];

export function StatsScreen({ onBack }: StatsScreenProps) {
  return (
    <div className="size-full flex flex-col p-6 md:p-8 overflow-y-auto">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex items-center gap-4 mb-8"
      >
        <motion.button
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          onClick={onBack}
          className="p-3 rounded-2xl bg-white/60 backdrop-blur-xl shadow-sm hover:shadow-md transition-shadow"
        >
          <ArrowLeft className="size-5 text-slate-700" />
        </motion.button>
        <h2 className="text-3xl font-bold text-slate-800">Statistiques</h2>
      </motion.div>

      {/* Contenu */}
      <div className="flex-1 max-w-4xl mx-auto w-full space-y-6 pb-8">
        {/* Stats globales */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <StatCard
            icon={<Trophy className="size-5" />}
            label="Parties jouées"
            value="75"
            delay={0.1}
          />
          <StatCard
            icon={<Target className="size-5" />}
            label="Victoires"
            value="37"
            delay={0.15}
          />
          <StatCard
            icon={<TrendingUp className="size-5" />}
            label="Taux de victoire"
            value="49%"
            delay={0.2}
          />
          <StatCard
            icon={<Clock className="size-5" />}
            label="Temps de jeu"
            value="24h"
            delay={0.25}
          />
        </div>

        {/* Classement des joueurs */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3 }}
          className="p-6 bg-white/80 backdrop-blur-xl rounded-3xl shadow-sm"
        >
          <h3 className="text-xl font-bold text-slate-800 mb-4">
            Classement des joueurs
          </h3>
          <div className="space-y-3">
            {playerStats
              .sort((a, b) => b.winRate - a.winRate)
              .map((player, index) => (
                <PlayerStatRow
                  key={player.name}
                  rank={index + 1}
                  name={player.name}
                  wins={player.wins}
                  games={player.games}
                  winRate={player.winRate}
                  delay={0.35 + index * 0.05}
                />
              ))}
          </div>
        </motion.div>
      </div>
    </div>
  );
}

interface StatCardProps {
  icon: React.ReactNode;
  label: string;
  value: string;
  delay: number;
}

function StatCard({ icon, label, value, delay }: StatCardProps) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ delay }}
      className="p-4 bg-white/80 backdrop-blur-xl rounded-3xl shadow-sm hover:shadow-md transition-shadow"
    >
      <div className="flex items-center gap-2 mb-2">
        <div className="p-2 rounded-xl bg-gradient-to-br from-indigo-500 to-purple-600">
          <div className="text-white">{icon}</div>
        </div>
      </div>
      <p className="text-2xl font-bold text-slate-800">{value}</p>
      <p className="text-sm text-slate-500">{label}</p>
    </motion.div>
  );
}

interface PlayerStatRowProps {
  rank: number;
  name: string;
  wins: number;
  games: number;
  winRate: number;
  delay: number;
}

function PlayerStatRow({
  rank,
  name,
  wins,
  games,
  winRate,
  delay,
}: PlayerStatRowProps) {
  const getRankColor = (rank: number) => {
    if (rank === 1) return "from-yellow-400 to-amber-500";
    if (rank === 2) return "from-slate-300 to-slate-400";
    if (rank === 3) return "from-orange-400 to-orange-500";
    return "from-slate-200 to-slate-300";
  };

  return (
    <motion.div
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ delay }}
      className="flex items-center gap-4 p-4 bg-gradient-to-r from-white/50 to-white/30 rounded-2xl"
    >
      <div
        className={`w-10 h-10 rounded-full bg-gradient-to-br ${getRankColor(
          rank
        )} flex items-center justify-center text-white font-bold shadow-md`}
      >
        {rank}
      </div>
      <div className="flex-1">
        <h4 className="font-semibold text-slate-800">{name}</h4>
        <p className="text-sm text-slate-500">
          {wins} victoires / {games} parties
        </p>
      </div>
      <div className="text-right">
        <p className="text-xl font-bold text-indigo-600">{winRate}%</p>
        <p className="text-xs text-slate-500">Taux de victoire</p>
      </div>
    </motion.div>
  );
}

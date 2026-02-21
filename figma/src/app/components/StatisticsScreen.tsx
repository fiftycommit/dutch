import { motion, AnimatePresence } from "motion/react";
import { ArrowLeft, Gamepad2, Trophy, Target, Star, Flame, Zap, TrendingUp, Users, Trash2, ChevronRight, X } from "lucide-react";
import { useState } from "react";

interface StatisticsScreenProps {
  onBack: () => void;
}

interface GameHistory {
  id: string;
  type: "victory" | "defeat" | "3rd-place";
  rank: string;
  date: string;
  time: string;
  points: number;
  rpChange: number;
  players: number;
  detailedLogs?: string[];
}

// Données mockées
const mockHistory: GameHistory[] = [
  {
    id: "1",
    type: "defeat",
    rank: "#6",
    date: "3/2",
    time: "15h37",
    points: 999,
    rpChange: -50,
    players: 6,
    detailedLogs: [
      "[15:37] 🃏 Distribution terminée (2 Jokers dans le deck)",
      "[15:37] 🎴 Mélange Tactique",
      "[15:37] Tirage au sort : Bramsou commence !",
      "[15:38] Bramsou pioche.",
      "[15:38] Bramsou remplace son 10 par la carte piochée",
      "[15:38] Bramsou regarde une carte de Vous.",
      "[15:38] Bramsou a utilisé son pouvoir.",
      "[15:38] MATCH ! - Vous avez posé un 10 !",
      "[15:39] Vous piochez.",
      "[15:39] Vous remplacez votre 9 par la carte piochée",
      "[15:40] Bot3 pioche et défausse.",
      "[15:41] Bot4 annonce DUTCH !",
      "[15:42] Fin de manche - Bot4 gagne avec 8 points."
    ]
  },
  {
    id: "2",
    type: "defeat",
    rank: "#4",
    date: "24/1",
    time: "11h24",
    points: 999,
    rpChange: -50,
    players: 6,
  },
  {
    id: "3",
    type: "defeat",
    rank: "#4",
    date: "24/1",
    time: "10h57",
    points: 999,
    rpChange: -50,
    players: 6,
  },
  {
    id: "4",
    type: "3rd-place",
    rank: "#3",
    date: "19/1",
    time: "14h15",
    points: 12,
    rpChange: 0,
    players: 6,
  },
  {
    id: "5",
    type: "defeat",
    rank: "#4",
    date: "24/1",
    time: "10h49",
    points: 999,
    rpChange: -50,
    players: 6,
  },
];

export function StatisticsScreen({ onBack }: StatisticsScreenProps) {
  const [selectedProfile, setSelectedProfile] = useState(1);
  const [selectedGame, setSelectedGame] = useState<GameHistory | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);

  const handleGameClick = (game: GameHistory) => {
    setSelectedGame(game);
    setShowDetailModal(true);
  };

  // Calculs des stats
  const totalGames = 5;
  const totalWins = 0;
  const winRate = 0.0;
  const bestScore = 999;
  const currentStreak = 0;
  const bestStreak = 0;
  const dutchSuccess = 0;
  const dutchAttempts = 0;
  const dutchRate = 0.0;

  return (
    <div className="size-full flex flex-col bg-gradient-to-br from-indigo-50 via-purple-50 to-blue-50">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex items-center gap-4 p-4 md:p-6 lg:p-8 landscape:p-3"
      >
        <motion.button
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          onClick={onBack}
          className="p-3 landscape:p-2 rounded-2xl landscape:rounded-xl bg-white/60 backdrop-blur-xl shadow-sm hover:shadow-md transition-shadow"
        >
          <ArrowLeft className="size-5 landscape:size-4 text-slate-700" />
        </motion.button>
        <h1 className="text-2xl md:text-3xl landscape:text-xl font-bold bg-gradient-to-r from-indigo-600 via-purple-600 to-blue-600 bg-clip-text text-transparent">
          Statistiques
        </h1>
      </motion.div>

      {/* Contenu scrollable */}
      <div className="flex-1 overflow-y-auto px-4 md:px-6 lg:px-8 landscape:px-3 pb-6">
        <div className="max-w-7xl mx-auto space-y-4 md:space-y-6 landscape:space-y-3">
          
          {/* Sélection du profil */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.1 }}
            className="flex gap-3 md:gap-4 landscape:gap-2"
          >
            {[1, 2, 3].map((profile) => (
              <motion.button
                key={profile}
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.98 }}
                onClick={() => setSelectedProfile(profile)}
                className={`flex-1 py-3 md:py-4 landscape:py-2 px-4 rounded-xl md:rounded-2xl landscape:rounded-lg font-bold transition-all ${
                  selectedProfile === profile
                    ? "bg-white/80 backdrop-blur-xl text-slate-800 shadow-lg"
                    : "bg-white/40 backdrop-blur-xl text-slate-500 hover:bg-white/50"
                }`}
              >
                Profil {profile}
              </motion.button>
            ))}
          </motion.div>

          {/* Section principale - Stats overview */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 md:gap-6 landscape:gap-3">
            
            {/* Carte principale - Vue d'ensemble */}
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 0.15 }}
              className="lg:col-span-2 bg-white/70 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl shadow-lg p-6 md:p-8 landscape:p-4"
            >
              <div className="flex items-center gap-3 mb-6">
                <div className="p-3 rounded-xl bg-gradient-to-br from-indigo-500 to-purple-600 text-white">
                  <Trophy className="size-6 md:size-7 landscape:size-5" />
                </div>
                <div>
                  <h2 className="text-xl md:text-2xl landscape:text-lg font-bold text-slate-800">
                    Vue d'ensemble
                  </h2>
                  <p className="text-sm text-slate-500">Performance globale</p>
                </div>
              </div>

              <div className="grid grid-cols-2 md:grid-cols-3 gap-4 md:gap-6 landscape:gap-3">
                <MiniStatCard
                  icon={<Gamepad2 className="size-5 landscape:size-4" />}
                  label="Parties"
                  value={totalGames.toString()}
                  color="from-blue-500 to-cyan-500"
                />
                <MiniStatCard
                  icon={<Trophy className="size-5 landscape:size-4" />}
                  label="Victoires"
                  value={totalWins.toString()}
                  color="from-purple-500 to-pink-500"
                />
                <MiniStatCard
                  icon={<Target className="size-5 landscape:size-4" />}
                  label="Win Rate"
                  value={`${winRate}%`}
                  color="from-emerald-500 to-teal-500"
                />
                <MiniStatCard
                  icon={<Star className="size-5 landscape:size-4" />}
                  label="Score le plus bas"
                  value={bestScore.toString()}
                  color="from-amber-500 to-orange-500"
                />
                <MiniStatCard
                  icon={<Flame className="size-5 landscape:size-4" />}
                  label="Série actuelle"
                  value={currentStreak.toString()}
                  color="from-rose-500 to-red-500"
                />
                <MiniStatCard
                  icon={<Zap className="size-5 landscape:size-4" />}
                  label="Record série"
                  value={bestStreak.toString()}
                  color="from-yellow-500 to-orange-500"
                />
              </div>
            </motion.div>

            {/* Efficacité DUTCH - Grande carte */}
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 0.2 }}
              className="bg-gradient-to-br from-indigo-500 via-purple-600 to-pink-500 rounded-2xl md:rounded-3xl landscape:rounded-xl shadow-lg p-6 md:p-8 landscape:p-4 text-white flex flex-col justify-center"
            >
              <div className="text-center">
                <div className="flex items-center justify-center gap-2 mb-3">
                  <TrendingUp className="size-5 md:size-6 landscape:size-4" />
                  <h3 className="text-sm md:text-base landscape:text-xs font-medium uppercase tracking-wider opacity-90">
                    Efficacité DUTCH
                  </h3>
                </div>
                <div className="text-6xl md:text-7xl landscape:text-5xl font-bold mb-3">
                  {dutchRate}%
                </div>
                <p className="text-sm md:text-base landscape:text-xs opacity-80">
                  {dutchSuccess} réussis sur {dutchAttempts} tentés
                </p>
              </div>
            </motion.div>
          </div>

          {/* Winrate par nombre de joueurs */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.25 }}
            className="bg-white/70 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl shadow-lg p-6 md:p-8 landscape:p-4"
          >
            <div className="flex items-center gap-3 mb-6 landscape:mb-4">
              <div className="p-3 landscape:p-2 rounded-xl bg-gradient-to-br from-violet-500 to-purple-600 text-white">
                <Users className="size-5 md:size-6 landscape:size-4" />
              </div>
              <div>
                <h3 className="text-lg md:text-xl landscape:text-base font-bold text-slate-800">
                  Performance par nombre de joueurs
                </h3>
                <p className="text-sm text-slate-500">Taux de victoire selon la configuration</p>
              </div>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 landscape:gap-3">
              <PlayerCountCard
                players={4}
                winrate="0.0%"
                wins={0}
                total={3}
              />
              <PlayerCountCard
                players={6}
                winrate="0.0%"
                wins={0}
                total={1}
              />
            </div>
          </motion.div>

          {/* Historique des parties */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.3 }}
            className="bg-white/70 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl shadow-lg p-6 md:p-8 landscape:p-4"
          >
            <div className="flex items-center justify-between mb-6 landscape:mb-4">
              <div className="flex items-center gap-3">
                <div className="p-3 landscape:p-2 rounded-xl bg-gradient-to-br from-slate-500 to-slate-600 text-white">
                  <Gamepad2 className="size-5 md:size-6 landscape:size-4" />
                </div>
                <div>
                  <h3 className="text-lg md:text-xl landscape:text-base font-bold text-slate-800">
                    Historique des parties
                  </h3>
                  <p className="text-sm text-slate-500">Vos dernières {mockHistory.length} parties</p>
                </div>
              </div>
              <motion.button
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                className="p-2 md:p-3 landscape:p-2 rounded-xl bg-red-50 hover:bg-red-100 transition-colors"
                title="Effacer l'historique"
              >
                <Trash2 className="size-4 md:size-5 landscape:size-3 text-red-600" />
              </motion.button>
            </div>
            
            <div className="space-y-3 landscape:space-y-2">
              {mockHistory.map((game, index) => (
                <HistoryCard
                  key={game.id}
                  game={game}
                  onClick={() => handleGameClick(game)}
                  delay={0.35 + index * 0.05}
                />
              ))}
            </div>
          </motion.div>
        </div>
      </div>

      {/* Modal de détails */}
      <AnimatePresence>
        {showDetailModal && selectedGame && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-black/50 backdrop-blur-sm z-50 flex items-center justify-center p-4"
            onClick={() => setShowDetailModal(false)}
          >
            <motion.div
              initial={{ scale: 0.9, y: 20 }}
              animate={{ scale: 1, y: 0 }}
              exit={{ scale: 0.9, y: 20 }}
              onClick={(e) => e.stopPropagation()}
              className="bg-gradient-to-br from-slate-800 to-slate-900 rounded-2xl md:rounded-3xl shadow-2xl p-6 md:p-8 max-w-2xl w-full max-h-[80vh] overflow-y-auto"
            >
              {/* Header du modal */}
              <div className="flex items-center justify-between mb-6">
                <div>
                  <h2 className="text-xl md:text-2xl font-bold text-white mb-1">
                    {selectedGame.type === "victory" ? "🏆 Victoire" : selectedGame.type === "3rd-place" ? "🥉 3ème place" : "👎 Défaite"} {selectedGame.rank}
                  </h2>
                  <p className="text-slate-400 text-sm">{selectedGame.players} joueurs</p>
                </div>
                <motion.button
                  whileHover={{ scale: 1.1 }}
                  whileTap={{ scale: 0.9 }}
                  onClick={() => setShowDetailModal(false)}
                  className="p-2 rounded-xl bg-white/10 hover:bg-white/20 transition-colors"
                >
                  <X className="size-5 text-white" />
                </motion.button>
              </div>

              {/* Détails de la partie */}
              <div className={`${
                selectedGame.type === "victory" ? "bg-green-900/30 border-green-800/50" :
                selectedGame.type === "3rd-place" ? "bg-orange-900/30 border-orange-800/50" :
                "bg-red-900/30 border-red-800/50"
              } border rounded-xl p-5 mb-6`}>
                <div className="flex items-start justify-between">
                  <div>
                    <h3 className="text-white font-bold text-lg mb-1">
                      {selectedGame.date} à {selectedGame.time}
                    </h3>
                    <p className="text-slate-300 text-sm">Partie classée • {selectedGame.players} joueurs</p>
                  </div>
                  <div className="text-right">
                    <div className="text-white font-bold text-2xl">{selectedGame.points}</div>
                    <p className="text-slate-400 text-xs mb-2">points</p>
                    <div className={`text-sm font-bold px-3 py-1 rounded-full ${
                      selectedGame.rpChange > 0 
                        ? "bg-green-500/20 text-green-400" 
                        : "bg-red-500/20 text-red-400"
                    }`}>
                      {selectedGame.rpChange > 0 ? "+" : ""}{selectedGame.rpChange} RP
                    </div>
                  </div>
                </div>
              </div>

              {/* Historique détaillé de la partie */}
              {selectedGame.detailedLogs && (
                <div>
                  <h3 className="text-white font-bold text-lg mb-4 flex items-center gap-2">
                    📋 Historique de la partie
                  </h3>
                  <div className="bg-slate-900/50 rounded-xl p-4 space-y-2 max-h-96 overflow-y-auto border border-slate-700/50">
                    {selectedGame.detailedLogs.map((log, idx) => (
                      <motion.div
                        key={idx}
                        initial={{ opacity: 0, x: -10 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ delay: idx * 0.03 }}
                        className="text-sm text-slate-300 leading-relaxed py-1"
                      >
                        {log}
                      </motion.div>
                    ))}
                  </div>
                </div>
              )}

              {/* Bouton fermer */}
              <motion.button
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.98 }}
                onClick={() => setShowDetailModal(false)}
                className="w-full mt-6 py-3 rounded-xl bg-white/10 hover:bg-white/20 text-white font-medium transition-colors"
              >
                Fermer
              </motion.button>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// Composants utilitaires

interface MiniStatCardProps {
  icon: React.ReactNode;
  label: string;
  value: string;
  color: string;
}

function MiniStatCard({ icon, label, value, color }: MiniStatCardProps) {
  return (
    <div className="text-center">
      <div className={`inline-flex p-3 landscape:p-2 rounded-xl bg-gradient-to-br ${color} text-white mb-2`}>
        {icon}
      </div>
      <div className="text-2xl md:text-3xl landscape:text-xl font-bold text-slate-800 mb-1">
        {value}
      </div>
      <div className="text-xs md:text-sm landscape:text-xs text-slate-600">
        {label}
      </div>
    </div>
  );
}

interface PlayerCountCardProps {
  players: number;
  winrate: string;
  wins: number;
  total: number;
}

function PlayerCountCard({ players, winrate, wins, total }: PlayerCountCardProps) {
  const percentage = total > 0 ? (wins / total) * 100 : 0;
  
  return (
    <motion.div
      whileHover={{ scale: 1.02 }}
      className="bg-gradient-to-br from-slate-50 to-white p-5 md:p-6 landscape:p-4 rounded-xl md:rounded-2xl landscape:rounded-lg border border-slate-200"
    >
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <Users className="size-5 text-indigo-600" />
          <span className="font-bold text-lg text-slate-800">{players} joueurs</span>
        </div>
        <div className="text-2xl md:text-3xl landscape:text-2xl font-bold bg-gradient-to-r from-indigo-600 to-purple-600 bg-clip-text text-transparent">
          {winrate}
        </div>
      </div>
      <div className="space-y-2">
        <div className="flex justify-between text-sm text-slate-600">
          <span>{wins} victoires sur {total} parties</span>
        </div>
        <div className="h-2 bg-slate-200 rounded-full overflow-hidden">
          <motion.div
            initial={{ width: 0 }}
            animate={{ width: `${percentage}%` }}
            transition={{ duration: 1, ease: "easeOut" }}
            className="h-full bg-gradient-to-r from-indigo-500 to-purple-600"
          />
        </div>
      </div>
    </motion.div>
  );
}

interface HistoryCardProps {
  game: GameHistory;
  onClick: () => void;
  delay: number;
}

function HistoryCard({ game, onClick, delay }: HistoryCardProps) {
  const getTypeConfig = () => {
    switch (game.type) {
      case "victory":
        return {
          bg: "from-green-50 to-emerald-50",
          border: "border-green-300",
          icon: "🏆",
          label: "Victoire",
          badgeBg: "bg-green-100",
          badgeText: "text-green-700"
        };
      case "defeat":
        return {
          bg: "from-red-50 to-rose-50",
          border: "border-red-300",
          icon: "👎",
          label: "Défaite",
          badgeBg: "bg-red-100",
          badgeText: "text-red-700"
        };
      case "3rd-place":
        return {
          bg: "from-orange-50 to-amber-50",
          border: "border-orange-300",
          icon: "🥉",
          label: "3ème place",
          badgeBg: "bg-orange-100",
          badgeText: "text-orange-700"
        };
    }
  };

  const config = getTypeConfig();

  return (
    <motion.button
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ delay }}
      whileHover={{ scale: 1.01, x: 4 }}
      whileTap={{ scale: 0.99 }}
      onClick={onClick}
      className={`w-full bg-gradient-to-r ${config.bg} border ${config.border} rounded-xl md:rounded-2xl landscape:rounded-lg p-4 md:p-5 landscape:p-3 flex items-center justify-between transition-all group`}
    >
      <div className="flex items-center gap-4 md:gap-5 landscape:gap-3">
        <div className="text-3xl md:text-4xl landscape:text-2xl">
          {config.icon}
        </div>
        <div className="text-left">
          <div className="flex items-center gap-2 mb-1">
            <span className={`${config.badgeBg} ${config.badgeText} px-3 py-1 rounded-full text-xs md:text-sm landscape:text-xs font-bold`}>
              {config.label}
            </span>
            <span className="text-slate-500 text-xs md:text-sm landscape:text-xs font-medium">
              {game.rank}
            </span>
          </div>
          <div className="flex items-center gap-3 text-xs md:text-sm landscape:text-xs text-slate-600">
            <span>{game.date} • {game.time}</span>
            <span className="flex items-center gap-1">
              <Users className="size-3" />
              {game.players}
            </span>
          </div>
        </div>
      </div>
      <div className="flex items-center gap-4 landscape:gap-3">
        <div className="text-right">
          <div className="text-slate-800 font-bold text-base md:text-lg landscape:text-sm">
            {game.points} pts
          </div>
          <div className={`text-xs md:text-sm landscape:text-xs font-bold ${
            game.rpChange > 0 ? "text-green-600" : "text-red-600"
          }`}>
            {game.rpChange > 0 ? "+" : ""}{game.rpChange} RP
          </div>
        </div>
        <ChevronRight className="size-5 md:size-6 landscape:size-4 text-slate-400 group-hover:text-slate-600 transition-colors" />
      </div>
    </motion.button>
  );
}
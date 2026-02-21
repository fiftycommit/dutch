import { motion } from "motion/react";
import { ArrowLeft, Trophy, Users, Bot, Sparkles } from "lucide-react";
import { useState } from "react";

interface TournamentScreenProps {
  onBack: () => void;
  sbmmEnabled?: boolean;
}

type BotLevel = "easy" | "medium" | "hard" | "platinum" | "mix";

export function TournamentScreen({ onBack, sbmmEnabled = false }: TournamentScreenProps) {
  const [botLevel, setBotLevel] = useState<BotLevel>("medium");
  const [playerCount, setPlayerCount] = useState<number>(4);

  const botLevels: { id: BotLevel; label: string; icon: string }[] = [
    { id: "easy", label: "Facile", icon: "😊" },
    { id: "medium", label: "Moyen", icon: "🎯" },
    { id: "hard", label: "Difficile", icon: "🔥" },
    { id: "platinum", label: "Platine", icon: "💎" },
    { id: "mix", label: "Mix", icon: "🎲" },
  ];

  const handleStart = () => {
    console.log("Starting tournament:", { botLevel, playerCount, sbmmEnabled });
    // TODO: Démarrer le tournoi
  };

  return (
    <div className="size-full flex flex-col relative overflow-hidden">
      {/* Background decorative elements */}
      <div className="absolute inset-0 opacity-10">
        <div className="absolute top-20 left-10 size-64 bg-emerald-400 rounded-full blur-3xl" />
        <div className="absolute bottom-20 right-10 size-96 bg-green-400 rounded-full blur-3xl" />
      </div>

      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="relative z-10 flex items-center gap-4 p-4 md:p-6 lg:p-8 landscape:p-3"
      >
        <motion.button
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          onClick={onBack}
          className="p-3 landscape:p-2 rounded-2xl landscape:rounded-xl bg-white/60 backdrop-blur-xl shadow-lg hover:bg-white/80 transition-colors"
        >
          <ArrowLeft className="size-5 landscape:size-4 text-emerald-800" />
        </motion.button>
        <div className="flex items-center gap-3">
          <div className="p-3 landscape:p-2 rounded-2xl bg-yellow-500 backdrop-blur-xl">
            <Trophy className="size-6 landscape:size-5 text-white" />
          </div>
          <h1 className="text-2xl md:text-3xl landscape:text-xl font-bold text-emerald-900">
            Configuration Tournoi
          </h1>
        </div>
      </motion.div>

      {/* Content */}
      <div className="relative z-10 flex-1 flex items-center justify-center px-4 md:px-6 lg:px-8 landscape:px-3 py-6 md:py-8 landscape:py-2 landscape:overflow-y-auto">
        <div className="w-full max-w-2xl space-y-8 md:space-y-12 landscape:space-y-3">
          
          {/* SBMM Notice */}
          {sbmmEnabled && (
            <motion.div
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              className="bg-gradient-to-br from-yellow-400 to-amber-500 rounded-2xl md:rounded-3xl landscape:rounded-xl p-6 md:p-8 landscape:p-4 text-center shadow-2xl border-2 border-yellow-300"
            >
              <div className="flex items-center justify-center gap-2 mb-2">
                <Sparkles className="size-6 md:size-7 landscape:size-5 text-yellow-900" />
                <h3 className="text-xl md:text-2xl landscape:text-lg font-bold text-yellow-900">
                  Mode Adaptatif Actif
                </h3>
                <Sparkles className="size-6 md:size-7 landscape:size-5 text-yellow-900" />
              </div>
              <p className="text-sm md:text-base landscape:text-sm text-yellow-900/80">
                Le niveau s'ajuste automatiquement à vos résultats.
              </p>
            </motion.div>
          )}

          {/* Info - Mode adaptatif disponible dans les réglages */}
          {!sbmmEnabled && (
            <motion.div
              initial={{ opacity: 0, y: -10 }}
              animate={{ opacity: 1, y: 0 }}
              className="bg-blue-500/20 backdrop-blur-sm rounded-xl md:rounded-2xl landscape:rounded-lg p-4 md:p-5 landscape:p-3 text-center border border-blue-600/30"
            >
              <p className="text-sm md:text-base landscape:text-sm text-blue-900 leading-relaxed">
                💡 <span className="font-semibold">Astuce :</span> Activez le mode adaptatif dans les réglages pour jouer avec des bots qui s'ajustent à votre niveau !
              </p>
            </motion.div>
          )}

          {/* Bot Level Selection - masqué si SBMM actif */}
          {!sbmmEnabled && (
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.1 }}
              className="space-y-4"
            >
              <div className="flex items-center gap-3 justify-center">
                <Bot className="size-6 text-emerald-800" />
                <h2 className="text-xl md:text-2xl landscape:text-lg font-bold text-emerald-900 text-center">
                  Niveau des Bots
                </h2>
              </div>
              <div className="flex flex-wrap justify-center gap-2 md:gap-3 landscape:gap-2">
                {botLevels.map((level) => (
                  <motion.button
                    key={level.id}
                    whileHover={{ scale: 1.05 }}
                    whileTap={{ scale: 0.95 }}
                    onClick={() => setBotLevel(level.id)}
                    className={`px-4 md:px-6 landscape:px-4 py-3 md:py-4 landscape:py-2 rounded-xl md:rounded-2xl landscape:rounded-lg font-bold text-sm md:text-base landscape:text-sm transition-all ${
                      botLevel === level.id
                        ? "bg-yellow-500 text-yellow-900 shadow-lg scale-105"
                        : "bg-white/60 backdrop-blur-xl text-emerald-800 hover:bg-white/80"
                    }`}
                  >
                    <span className="mr-2">{level.icon}</span>
                    {level.label}
                  </motion.button>
                ))}
              </div>
            </motion.div>
          )}

          {/* Player Count Selection - Tournoi = 4 ou 6 joueurs uniquement */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: sbmmEnabled ? 0.1 : 0.2 }}
            className="space-y-4"
          >
            <div className="space-y-1 text-center">
              <div className="flex items-center gap-3 justify-center">
                <Users className="size-6 text-emerald-800" />
                <h2 className="text-xl md:text-2xl landscape:text-lg font-bold text-emerald-900">
                  Nombre de joueurs
                </h2>
              </div>
              <p className="text-sm md:text-base landscape:text-sm text-emerald-700">
                (en plus de vous)
              </p>
            </div>
            <div className="flex justify-center gap-3 md:gap-4 landscape:gap-2">
              {[4, 6].map((count) => (
                <motion.button
                  key={count}
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  onClick={() => setPlayerCount(count)}
                  className={`size-16 md:size-20 landscape:size-12 rounded-xl md:rounded-2xl landscape:rounded-lg font-bold text-xl md:text-2xl landscape:text-lg transition-all ${
                    playerCount === count
                      ? "bg-yellow-500 text-yellow-900 shadow-lg scale-105"
                      : "bg-white/60 backdrop-blur-xl text-emerald-800 hover:bg-white/80"
                  }`}
                >
                  {count}
                </motion.button>
              ))}
            </div>
          </motion.div>

          {/* Start Button */}
          <motion.button
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: sbmmEnabled ? 0.2 : 0.3 }}
            whileHover={{ scale: 1.02 }}
            whileTap={{ scale: 0.98 }}
            onClick={handleStart}
            className="w-full max-w-xs mx-auto block py-4 md:py-5 landscape:py-3 px-8 rounded-2xl md:rounded-3xl landscape:rounded-xl bg-yellow-500 hover:bg-yellow-600 text-yellow-900 font-bold text-lg md:text-xl landscape:text-base shadow-2xl transition-colors"
          >
            COMMENCER
          </motion.button>
        </div>
      </div>
    </div>
  );
}
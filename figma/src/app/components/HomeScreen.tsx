import { useState, useRef, useEffect } from "react";
import { motion, AnimatePresence } from "motion/react";
import { Settings, BookOpen, BarChart3, Play, Trophy, Users, ChevronDown, Zap, Crown, Globe } from "lucide-react";
import { Screen } from "../App";

interface HomeScreenProps {
  selectedPlayer: string | null;
  onSelectPlayer: (player: string) => void;
  onNavigate: (screen: Screen) => void;
  darkMode?: boolean;
}

const players = ["Max", "El Roy", "Irfat", "Invité"];

interface IconButtonProps {
  icon: React.ReactNode;
  onClick: () => void;
  tooltip: string;
  position?: "left" | "right";
  className?: string;
}

function IconButton({ icon, onClick, tooltip, position = "right", className = "" }: IconButtonProps) {
  const [showTooltip, setShowTooltip] = useState(false);
  const [longPressTimer, setLongPressTimer] = useState<NodeJS.Timeout | null>(null);

  const handleMouseEnter = () => {
    setShowTooltip(true);
  };

  const handleMouseLeave = () => {
    setShowTooltip(false);
  };

  const handleTouchStart = () => {
    const timer = setTimeout(() => {
      setShowTooltip(true);
    }, 500); // 500ms pour le long press
    setLongPressTimer(timer);
  };

  const handleTouchEnd = () => {
    if (longPressTimer) {
      clearTimeout(longPressTimer);
      setLongPressTimer(null);
    }
    setShowTooltip(false);
  };

  return (
    <div className="relative">
      <motion.button
        whileHover={{ scale: 1.05 }}
        whileTap={{ scale: 0.95 }}
        onClick={onClick}
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
        onTouchStart={handleTouchStart}
        onTouchEnd={handleTouchEnd}
        className={className}
      >
        {icon}
      </motion.button>
      
      <AnimatePresence>
        {showTooltip && (
          <motion.div
            initial={{ opacity: 0, scale: 0.8, x: position === "right" ? -10 : 10 }}
            animate={{ opacity: 1, scale: 1, x: 0 }}
            exit={{ opacity: 0, scale: 0.8 }}
            className={`absolute top-1/2 -translate-y-1/2 ${
              position === "right" ? "left-full ml-2" : "right-full mr-2"
            } bg-slate-800 text-white text-xs px-3 py-1.5 rounded-lg whitespace-nowrap pointer-events-none z-50 shadow-lg`}
          >
            {tooltip}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

export function HomeScreen({
  selectedPlayer,
  onSelectPlayer,
  onNavigate,
  darkMode = false,
}: HomeScreenProps) {
  const [showPlayerDropdown, setShowPlayerDropdown] = useState(false);
  const [showNewPlayerDialog, setShowNewPlayerDialog] = useState(false);
  const [newPlayerName, setNewPlayerName] = useState("");
  const [errorMessage, setErrorMessage] = useState("");
  const dropdownRef = useRef<HTMLDivElement>(null);
  const dialogRef = useRef<HTMLDivElement>(null);

  // Classes conditionnelles selon le mode
  const cardBg = darkMode ? "bg-slate-800/60" : "bg-white/60";
  const cardBgHover = darkMode ? "hover:bg-slate-700/60" : "hover:bg-white/70";
  const textPrimary = darkMode ? "text-white" : "text-slate-700";
  const textSecondary = darkMode ? "text-slate-300" : "text-slate-500";
  const iconColor = darkMode ? "text-white" : "text-slate-700";

  // Fermer le dropdown en cliquant en dehors
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setShowPlayerDropdown(false);
      }
    }

    if (showPlayerDropdown) {
      document.addEventListener("mousedown", handleClickOutside);
      return () => document.removeEventListener("mousedown", handleClickOutside);
    }
  }, [showPlayerDropdown]);

  // Fermer le dialog en cliquant en dehors
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (dialogRef.current && event.target === dialogRef.current) {
        setShowNewPlayerDialog(false);
        setNewPlayerName("");
        setErrorMessage("");
      }
    }

    if (showNewPlayerDialog) {
      document.addEventListener("mousedown", handleClickOutside);
      return () => document.removeEventListener("mousedown", handleClickOutside);
    }
  }, [showNewPlayerDialog]);

  // Gestion du clavier
  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        if (showNewPlayerDialog) {
          setShowNewPlayerDialog(false);
          setNewPlayerName("");
          setErrorMessage("");
        } else if (showPlayerDropdown) {
          setShowPlayerDropdown(false);
        }
      }
    }

    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, [showPlayerDropdown, showNewPlayerDialog]);

  // Validation et ajout d'un nouveau joueur
  const handleAddPlayer = () => {
    const trimmedName = newPlayerName.trim();
    
    if (!trimmedName) {
      setErrorMessage("Le nom ne peut pas être vide");
      return;
    }

    if (players.includes(trimmedName)) {
      setErrorMessage("Ce joueur existe déjà");
      return;
    }

    onSelectPlayer(trimmedName);
    setShowNewPlayerDialog(false);
    setShowPlayerDropdown(false);
    setNewPlayerName("");
    setErrorMessage("");
  };

  // Gérer Enter dans l'input
  const handleKeyDownInput = (event: React.KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "Enter") {
      handleAddPlayer();
    }
  };

  return (
    <div className="size-full flex flex-col p-4 md:p-6 lg:p-12 landscape:max-h-screen landscape:p-3 overflow-y-auto">
      {/* Header avec icônes */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="w-full flex justify-between items-center mb-4 landscape:mb-2 lg:mb-12"
      >
        <div className="flex gap-3 landscape:gap-2">
          <IconButton
            icon={<BarChart3 className="size-5 landscape:size-4 text-slate-700" />}
            onClick={() => onNavigate("stats")}
            tooltip="Statistiques"
            className="p-3 landscape:p-2 rounded-2xl landscape:rounded-xl bg-white/60 backdrop-blur-xl shadow-sm hover:shadow-md transition-shadow"
          />

          <IconButton
            icon={<BookOpen className="size-5 landscape:size-4 text-slate-700" />}
            onClick={() => onNavigate("rules")}
            tooltip="Règles"
            className="p-3 landscape:p-2 rounded-2xl landscape:rounded-xl bg-white/60 backdrop-blur-xl shadow-sm hover:shadow-md transition-shadow hidden landscape:flex lg:flex"
          />
          
          {/* Bouton test game - temporaire */}
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            onClick={() => onNavigate("game")}
            className="p-3 landscape:p-2 px-4 rounded-2xl landscape:rounded-xl bg-gradient-to-r from-emerald-500 to-green-600 hover:from-emerald-600 hover:to-green-700 shadow-sm hover:shadow-md transition-all text-white font-bold text-xs"
          >
            🎮 TEST
          </motion.button>
        </div>

        <IconButton
          icon={<Settings className="size-5 landscape:size-4 text-slate-700" />}
          onClick={() => onNavigate("settings")}
          tooltip="Paramètres"
          position="left"
          className="p-3 landscape:p-2 rounded-2xl landscape:rounded-xl bg-white/60 backdrop-blur-xl shadow-sm hover:shadow-md transition-shadow"
        />
      </motion.div>

      {/* Contenu principal - Layout responsive */}
      <div className="flex-1 flex flex-col lg:flex-row landscape:flex-row items-center justify-center gap-4 md:gap-6 lg:gap-16 landscape:gap-6 max-w-6xl mx-auto w-full">
        {/* Section gauche - Titre et sélecteur */}
        <div className="flex flex-col items-center lg:items-start landscape:items-start space-y-3 md:space-y-4 lg:space-y-8 landscape:space-y-2 w-full lg:w-auto landscape:w-auto lg:flex-1 landscape:flex-1">
          {/* Titre du jeu */}
          <motion.div
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 0.1 }}
            className="text-center lg:text-left landscape:text-left space-y-1 landscape:space-y-0"
          >
            <h1 className="text-5xl md:text-6xl lg:text-8xl landscape:text-4xl font-bold bg-gradient-to-r from-indigo-600 via-purple-600 to-blue-600 bg-clip-text text-transparent">
              Dutch
            </h1>
            <p className="text-xs md:text-sm lg:text-base landscape:text-xs text-slate-500">
              Par Max, El Roy & Irfat
            </p>
          </motion.div>

          {/* Sélecteur de joueur */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 }}
            className="w-full max-w-md landscape:max-w-xs relative"
          >
            <motion.button
              onClick={() => setShowPlayerDropdown(!showPlayerDropdown)}
              className="w-full px-4 md:px-6 landscape:px-3 py-3 md:py-4 landscape:py-2 bg-white/80 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl shadow-lg hover:shadow-xl transition-all flex items-center justify-between group"
              animate={!selectedPlayer ? { boxShadow: ["0 10px 15px -3px rgba(99, 102, 241, 0.1)", "0 10px 15px -3px rgba(99, 102, 241, 0.3)", "0 10px 15px -3px rgba(99, 102, 241, 0.1)"] } : {}}
              transition={{ duration: 2, repeat: !selectedPlayer ? Infinity : 0, ease: "easeInOut" }}
            >
              <span className="text-slate-700 font-medium text-sm landscape:text-xs">
                {selectedPlayer || "Sélectionner un joueur"}
              </span>
              <ChevronDown
                className={`size-5 landscape:size-4 text-slate-400 transition-transform ${
                  showPlayerDropdown ? "rotate-180" : ""
                }`}
              />
            </motion.button>

            {showPlayerDropdown && (
              <motion.div
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                className="absolute w-full bottom-full mb-2 bg-white/95 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl shadow-xl overflow-hidden z-10"
                ref={dropdownRef}
              >
                {/* Titre principal */}
                <div className="px-4 md:px-6 landscape:px-3 py-3 landscape:py-2 border-b border-slate-200/50">
                  <h3 className="text-xs md:text-sm landscape:text-xs font-bold text-slate-500 uppercase tracking-wide">
                    Choisir un joueur
                  </h3>
                </div>
                
                {/* Sous-titre pour la liste */}
                <div className="px-4 md:px-6 landscape:px-3 pt-3 landscape:pt-2 pb-1">
                  <p className="text-[10px] md:text-xs landscape:text-[10px] font-semibold text-slate-400 uppercase tracking-wide">
                    Joueurs disponibles
                  </p>
                </div>
                
                {/* Liste des joueurs */}
                {players.map((player, index) => (
                  <motion.button
                    key={player}
                    initial={{ opacity: 0, x: -20 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: index * 0.05 }}
                    onClick={() => {
                      onSelectPlayer(player);
                      setShowPlayerDropdown(false);
                    }}
                    className="w-full px-4 md:px-6 landscape:px-3 py-3 md:py-4 landscape:py-2 text-left hover:bg-indigo-50 transition-colors text-slate-700 font-medium text-sm landscape:text-xs"
                  >
                    {player}
                  </motion.button>
                ))}
                
                {/* Bouton Ajouter */}
                <motion.button
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: players.length * 0.05 }}
                  onClick={() => setShowNewPlayerDialog(true)}
                  className="w-full px-4 md:px-6 landscape:px-3 py-3 md:py-4 landscape:py-2 text-left hover:bg-indigo-50 transition-colors text-indigo-600 font-semibold text-sm landscape:text-xs border-t border-slate-200/50"
                >
                  + Ajouter un nouveau joueur
                </motion.button>
              </motion.div>
            )}
          </motion.div>

          {/* Stats rapides - Visible sur desktop et landscape */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.25 }}
            className="hidden lg:flex landscape:flex flex-col gap-3 landscape:gap-2 w-full max-w-md landscape:max-w-xs"
          >
            <div className="flex gap-3 landscape:gap-2">
              <div className="flex-1 p-4 landscape:p-2 bg-white/60 backdrop-blur-xl rounded-2xl landscape:rounded-xl shadow-sm">
                <div className="flex items-center gap-2 landscape:gap-1 mb-1">
                  <Trophy className="size-4 landscape:size-3 text-indigo-600" />
                  <span className="text-xs landscape:text-[10px] text-slate-500">Victoires</span>
                </div>
                <p className="text-2xl landscape:text-lg font-bold text-slate-800">37</p>
              </div>
              <div className="flex-1 p-4 landscape:p-2 bg-white/60 backdrop-blur-xl rounded-2xl landscape:rounded-xl shadow-sm">
                <div className="flex items-center gap-2 landscape:gap-1 mb-1">
                  <Zap className="size-4 landscape:size-3 text-purple-600" />
                  <span className="text-xs landscape:text-[10px] text-slate-500">Parties</span>
                </div>
                <p className="text-2xl landscape:text-lg font-bold text-slate-800">75</p>
              </div>
            </div>
          </motion.div>
        </div>

        {/* Section droite - Modes de jeu en grille */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.3 }}
          className="w-full lg:flex-1 max-w-2xl landscape:flex-1"
        >
          {/* Mobile Portrait: liste verticale */}
          <div className="lg:hidden landscape:hidden space-y-3">
            <GameModeButton
              icon={<Play className="size-6" />}
              title="Partie Rapide"
              subtitle="Commencer une partie immédiatement"
              disabled={!selectedPlayer}
              delay={0.35}
              mode="quick"
              onClick={() => onNavigate("quickGame")}
            />
            <GameModeButton
              icon={<Trophy className="size-6" />}
              title="Tournoi"
              subtitle="Participer à un tournoi"
              disabled={!selectedPlayer}
              delay={0.4}
              mode="tournament"
              onClick={() => onNavigate("tournament")}
            />
            <GameModeButton
              icon={<Users className="size-6" />}
              title="Multijoueur"
              subtitle="Jouer avec d'autres joueurs"
              disabled={!selectedPlayer}
              delay={0.45}
              mode="multiplayer"
              onClick={() => onNavigate("multiplayer")}
            />
          </div>

          {/* Mobile Landscape: grille 2 colonnes avec Multijoueur en bas sur 2 colonnes */}
          <div className="hidden landscape:grid lg:hidden grid-cols-2 gap-2">
            <GameModeLandscapeCard
              icon={<Play className="size-5" />}
              title="Partie Rapide"
              stats="5-10 min"
              disabled={!selectedPlayer}
              delay={0.35}
              mode="quick"
              onClick={() => onNavigate("quickGame")}
            />
            <GameModeLandscapeCard
              icon={<Trophy className="size-5" />}
              title="Tournoi"
              stats="30-45 min"
              disabled={!selectedPlayer}
              delay={0.4}
              mode="tournament"
              onClick={() => onNavigate("tournament")}
            />
            <GameModeLandscapeCard
              icon={<Users className="size-5" />}
              title="Multijoueur"
              stats="10-20 min"
              disabled={!selectedPlayer}
              delay={0.45}
              mode="multiplayer"
              onClick={() => onNavigate("multiplayer")}
              large
            />
          </div>

          {/* Desktop: grille 2 colonnes */}
          <div className="hidden lg:grid grid-cols-2 gap-4">
            <GameModeCard
              icon={<Play className="size-8" />}
              title="Partie Rapide"
              subtitle="Commencer une partie immédiatement"
              stats="5-10 min"
              disabled={!selectedPlayer}
              delay={0.35}
              mode="quick"
              onClick={() => onNavigate("quickGame")}
            />
            <GameModeCard
              icon={<Trophy className="size-8" />}
              title="Tournoi"
              subtitle="Participer à un tournoi"
              stats="30-45 min"
              disabled={!selectedPlayer}
              delay={0.4}
              mode="tournament"
              onClick={() => onNavigate("tournament")}
            />
            <GameModeCard
              icon={<Users className="size-8" />}
              title="Multijoueur"
              subtitle="Jouer avec d'autres joueurs"
              stats="10-20 min"
              disabled={!selectedPlayer}
              delay={0.45}
              mode="multiplayer"
              onClick={() => onNavigate("multiplayer")}
              large
            />
          </div>
        </motion.div>
      </div>

      {/* Footer - Bouton règles (mobile portrait uniquement) */}
      <motion.button
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.5 }}
        whileHover={{ scale: 1.02 }}
        whileTap={{ scale: 0.98 }}
        onClick={() => onNavigate("rules")}
        className="lg:hidden landscape:hidden w-full max-w-md mx-auto px-4 md:px-6 py-3 md:py-4 bg-white/60 backdrop-blur-xl rounded-xl md:rounded-2xl shadow-sm hover:shadow-md transition-all flex items-center justify-center gap-2 text-slate-700 mt-4 md:mt-6"
      >
        <BookOpen className="size-5" />
        <span className="font-medium">Consulter les règles</span>
      </motion.button>

      {/* Dialog pour ajouter un nouveau joueur */}
      {showNewPlayerDialog && (
        <motion.div
          ref={dialogRef}
          initial={{ opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.1 }}
          className="fixed top-0 left-0 w-full h-full bg-black/50 flex items-center justify-center z-50 p-4"
        >
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 }}
            className="bg-white/95 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl shadow-xl p-6 md:p-8 max-w-md w-full"
          >
            <h2 className="text-xl font-bold text-slate-700 mb-4">Ajouter un nouveau joueur</h2>
            <input
              type="text"
              value={newPlayerName}
              onChange={(e) => setNewPlayerName(e.target.value)}
              placeholder="Nom du joueur"
              className="w-full px-4 py-3 md:py-4 bg-white/80 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl shadow-sm hover:shadow-md transition-shadow focus:outline-none focus:ring-2 focus:ring-indigo-500"
              onKeyDown={handleKeyDownInput}
            />
            {errorMessage && (
              <p className="text-sm text-red-500 mt-2">{errorMessage}</p>
            )}
            <div className="flex justify-end mt-4">
              <button
                onClick={() => setShowNewPlayerDialog(false)}
                className="px-4 py-2 md:py-3 bg-white/60 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl shadow-sm hover:shadow-md transition-shadow text-slate-700 font-medium"
              >
                Annuler
              </button>
              <button
                onClick={handleAddPlayer}
                className="px-4 py-2 md:py-3 bg-gradient-to-r from-indigo-500 to-purple-600 hover:from-indigo-600 hover:to-purple-700 rounded-2xl md:rounded-3xl landscape:rounded-xl shadow-lg hover:shadow-xl transition-all text-white font-medium ml-2"
              >
                Ajouter
              </button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </div>
  );
}

interface GameModeButtonProps {
  icon: React.ReactNode;
  title: string;
  subtitle: string;
  disabled?: boolean;
  delay: number;
  mode: string;
  onClick?: () => void;
}

function GameModeButton({
  icon,
  title,
  subtitle,
  disabled = false,
  delay,
  onClick,
}: GameModeButtonProps) {
  return (
    <motion.button
      initial={{ opacity: 0, x: -20 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ delay }}
      whileHover={{ scale: disabled ? 1 : 1.02 }}
      whileTap={{ scale: disabled ? 1 : 0.98 }}
      disabled={disabled}
      onClick={onClick}
      className={`w-full p-4 md:p-5 rounded-2xl md:rounded-3xl shadow-lg hover:shadow-xl transition-all flex items-center gap-3 md:gap-4 ${
        disabled
          ? "bg-white/40 backdrop-blur-xl cursor-not-allowed opacity-50"
          : "bg-gradient-to-r from-indigo-500 to-purple-600 hover:from-indigo-600 hover:to-purple-700"
      }`}
    >
      <div
        className={`p-2 md:p-3 rounded-xl md:rounded-2xl ${
          disabled ? "bg-white/50" : "bg-white/20"
        }`}
      >
        <div className={disabled ? "text-slate-400" : "text-white"}>{icon}</div>
      </div>
      <div className="flex-1 text-left">
        <h3
          className={`font-semibold text-base md:text-lg ${
            disabled ? "text-slate-400" : "text-white"
          }`}
        >
          {title}
        </h3>
        <p
          className={`text-xs md:text-sm ${
            disabled ? "text-slate-400" : "text-indigo-100"
          }`}
        >
          {subtitle}
        </p>
      </div>
    </motion.button>
  );
}

interface GameModeCardProps {
  icon: React.ReactNode;
  title: string;
  subtitle: string;
  stats: string;
  disabled?: boolean;
  delay: number;
  mode: string;
  large?: boolean;
  onClick?: () => void;
}

function GameModeCard({
  icon,
  title,
  subtitle,
  stats,
  disabled = false,
  delay,
  large = false,
  onClick,
}: GameModeCardProps) {
  return (
    <motion.button
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ delay }}
      whileHover={{ scale: disabled ? 1 : 1.02 }}
      whileTap={{ scale: disabled ? 1 : 0.98 }}
      disabled={disabled}
      onClick={onClick}
      className={`p-6 rounded-3xl shadow-lg hover:shadow-xl transition-all flex flex-col ${
        large ? "lg:col-span-2" : ""
      } ${
        disabled
          ? "bg-white/40 backdrop-blur-xl cursor-not-allowed opacity-50"
          : "bg-gradient-to-br from-indigo-500 to-purple-600 hover:from-indigo-600 hover:to-purple-700"
      }`}
    >
      <div
        className={`p-4 rounded-2xl w-fit mb-4 ${
          disabled ? "bg-white/50" : "bg-white/20"
        }`}
      >
        <div className={disabled ? "text-slate-400" : "text-white"}>{icon}</div>
      </div>
      <div className="flex-1 text-left">
        <h3
          className={`font-bold text-xl mb-2 ${
            disabled ? "text-slate-400" : "text-white"
          }`}
        >
          {title}
        </h3>
        <p
          className={`text-sm mb-3 ${
            disabled ? "text-slate-400" : "text-indigo-100"
          }`}
        >
          {subtitle}
        </p>
        <div
          className={`text-xs font-medium ${
            disabled ? "text-slate-400" : "text-white/70"
          }`}
        >
          ⏱️ {stats}
        </div>
      </div>
    </motion.button>
  );
}

interface GameModeLandscapeCardProps {
  icon: React.ReactNode;
  title: string;
  stats: string;
  disabled?: boolean;
  delay: number;
  mode: string;
  large?: boolean;
  onClick?: () => void;
}

function GameModeLandscapeCard({
  icon,
  title,
  stats,
  disabled = false,
  delay,
  large = false,
  onClick,
}: GameModeLandscapeCardProps) {
  return (
    <motion.button
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      transition={{ delay }}
      whileHover={{ scale: disabled ? 1 : 1.02 }}
      whileTap={{ scale: disabled ? 1 : 0.98 }}
      disabled={disabled}
      onClick={onClick}
      className={`p-2 rounded-2xl shadow-lg hover:shadow-xl transition-all flex flex-col ${
        large ? "col-span-2" : ""
      } ${
        disabled
          ? "bg-white/40 backdrop-blur-xl cursor-not-allowed opacity-50"
          : "bg-gradient-to-br from-indigo-500 to-purple-600 hover:from-indigo-600 hover:to-purple-700"
      }`}
    >
      <div
        className={`p-2 rounded-2xl w-fit mb-2 ${
          disabled ? "bg-white/50" : "bg-white/20"
        }`}
      >
        <div className={disabled ? "text-slate-400" : "text-white"}>{icon}</div>
      </div>
      <div className="flex-1 text-left">
        <h3
          className={`font-bold text-sm ${
            disabled ? "text-slate-400" : "text-white"
          }`}
        >
          {title}
        </h3>
        <div
          className={`text-xs font-medium ${
            disabled ? "text-slate-400" : "text-white/70"
          }`}
        >
          ⏱️ {stats}
        </div>
      </div>
    </motion.button>
  );
}
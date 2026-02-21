import { motion, AnimatePresence } from "motion/react";
import { ArrowLeft, Users, Volume2, Menu } from "lucide-react";
import { useState } from "react";

interface GameScreenProps {
  onBack: () => void;
}

interface Player {
  id: number;
  name: string;
  cards: number;
  isActive: boolean;
  position: "top" | "left" | "right" | "bottom";
}

const mockPlayers: Player[] = [
  { id: 1, name: "Max", cards: 4, isActive: false, position: "top" },
  { id: 2, name: "El Roy", cards: 3, isActive: true, position: "left" },
  { id: 3, name: "Vous", cards: 4, isActive: false, position: "bottom" },
  { id: 4, name: "Irfat", cards: 4, isActive: false, position: "right" },
];

// Représentation simple des cartes
const cardSuits = ["♠", "♥", "♦", "♣"];
const cardValues = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];

export function GameScreen({ onBack }: GameScreenProps) {
  const [showMenu, setShowMenu] = useState(false);
  const [selectedCard, setSelectedCard] = useState<number | null>(null);
  const [playerCards] = useState([
    { id: 1, suit: "♠", value: "K", revealed: false },
    { id: 2, suit: "♥", value: "7", revealed: false },
    { id: 3, suit: "♦", value: "A", revealed: false },
    { id: 4, suit: "♣", value: "5", revealed: false },
  ]);

  const discardPile = { suit: "♥", value: "9" };
  const currentPlayer = mockPlayers.find(p => p.isActive);

  return (
    <div className="size-full relative overflow-hidden bg-gradient-to-br from-emerald-700 via-green-700 to-teal-800">
      {/* Texture subtile du tapis */}
      <div className="absolute inset-0 opacity-10 bg-[radial-gradient(circle_at_50%_50%,rgba(255,255,255,0.1),transparent_50%)]" />
      
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="absolute top-0 left-0 right-0 z-20 flex items-center justify-between p-3 md:p-4 landscape:p-2"
      >
        {/* Bouton retour */}
        <motion.button
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          onClick={onBack}
          className="p-2.5 md:p-3 landscape:p-2 rounded-xl md:rounded-2xl landscape:rounded-lg bg-white/10 backdrop-blur-xl border border-white/20 hover:bg-white/20 transition-all shadow-lg"
        >
          <ArrowLeft className="size-5 md:size-6 landscape:size-4 text-white" />
        </motion.button>

        {/* Info partie */}
        <div className="flex items-center gap-2 md:gap-3 landscape:gap-2 px-3 md:px-4 landscape:px-3 py-2 md:py-2.5 landscape:py-1.5 rounded-xl md:rounded-2xl landscape:rounded-lg bg-white/10 backdrop-blur-xl border border-white/20 shadow-lg">
          <Users className="size-4 md:size-5 landscape:size-3 text-white/80" />
          <span className="text-white font-semibold text-xs md:text-sm landscape:text-xs">
            Manche 1/3
          </span>
        </div>

        {/* Boutons actions */}
        <div className="flex gap-2">
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            className="p-2.5 md:p-3 landscape:p-2 rounded-xl md:rounded-2xl landscape:rounded-lg bg-white/10 backdrop-blur-xl border border-white/20 hover:bg-white/20 transition-all shadow-lg"
          >
            <Volume2 className="size-5 md:size-6 landscape:size-4 text-white" />
          </motion.button>
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            onClick={() => setShowMenu(!showMenu)}
            className="p-2.5 md:p-3 landscape:p-2 rounded-xl md:rounded-2xl landscape:rounded-lg bg-white/10 backdrop-blur-xl border border-white/20 hover:bg-white/20 transition-all shadow-lg"
          >
            <Menu className="size-5 md:size-6 landscape:size-4 text-white" />
          </motion.button>
        </div>
      </motion.div>

      {/* Zone de jeu principale */}
      <div className="size-full flex items-center justify-center p-4 md:p-8 landscape:p-4 pt-20 md:pt-24 landscape:pt-16 pb-20">
        <div className="relative w-full h-full max-w-6xl max-h-[800px]">
          {/* Joueur du haut */}
          <OpponentArea player={mockPlayers[0]} />

          {/* Joueur gauche */}
          <OpponentAreaSide player={mockPlayers[1]} side="left" />

          {/* Joueur droite */}
          <OpponentAreaSide player={mockPlayers[3]} side="right" />

          {/* Zone centrale - Pioche et Défausse */}
          <motion.div
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 0.3 }}
            className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 flex items-center gap-4 md:gap-8 landscape:gap-4"
          >
            {/* Pioche */}
            <motion.button
              whileHover={{ scale: 1.05, y: -5 }}
              whileTap={{ scale: 0.95 }}
              className="relative group"
            >
              <div className="w-16 h-24 md:w-20 md:h-32 landscape:w-16 landscape:h-24 rounded-lg md:rounded-xl landscape:rounded-lg bg-gradient-to-br from-indigo-600 to-purple-700 shadow-2xl border-2 border-white/30 flex items-center justify-center transition-all group-hover:shadow-indigo-500/50">
                <div className="text-white text-xs md:text-sm landscape:text-xs font-bold">PIOCHE</div>
              </div>
              {/* Effet de pile */}
              <div className="absolute -top-1 -right-1 w-16 h-24 md:w-20 md:h-32 landscape:w-16 landscape:h-24 rounded-lg md:rounded-xl landscape:rounded-lg bg-gradient-to-br from-indigo-500 to-purple-600 -z-10 opacity-50" />
              <div className="absolute -top-2 -right-2 w-16 h-24 md:w-20 md:h-32 landscape:w-16 landscape:h-24 rounded-lg md:rounded-xl landscape:rounded-lg bg-gradient-to-br from-indigo-400 to-purple-500 -z-20 opacity-30" />
            </motion.button>

            {/* Défausse */}
            <motion.div
              initial={{ scale: 0, rotate: -180 }}
              animate={{ scale: 1, rotate: 0 }}
              transition={{ delay: 0.5, type: "spring" }}
              className="relative"
            >
              <PlayingCard 
                suit={discardPile.suit} 
                value={discardPile.value} 
                revealed 
                size="large"
                isDiscard
              />
              <motion.div
                animate={{ scale: [1, 1.1, 1] }}
                transition={{ duration: 2, repeat: Infinity }}
                className="absolute -inset-2 rounded-xl md:rounded-2xl landscape:rounded-xl bg-gradient-to-r from-amber-400 to-orange-500 opacity-20 blur-xl -z-10"
              />
            </motion.div>
          </motion.div>

          {/* Zone du joueur (en bas) */}
          <motion.div
            initial={{ opacity: 0, y: 50 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.4 }}
            className="absolute bottom-0 left-1/2 -translate-x-1/2 w-full max-w-xl"
          >
            {/* Nom et indicateur */}
            <div className="flex justify-center mb-3 md:mb-4 landscape:mb-2">
              <motion.div
                animate={mockPlayers[2].isActive ? {
                  boxShadow: [
                    "0 0 20px rgba(251, 191, 36, 0.5)",
                    "0 0 40px rgba(251, 191, 36, 0.8)",
                    "0 0 20px rgba(251, 191, 36, 0.5)",
                  ]
                } : {}}
                transition={{ duration: 2, repeat: Infinity }}
                className={`px-4 md:px-6 landscape:px-4 py-2 md:py-2.5 landscape:py-1.5 rounded-xl md:rounded-2xl landscape:rounded-lg backdrop-blur-xl border-2 shadow-lg ${
                  mockPlayers[2].isActive
                    ? "bg-amber-500/20 border-amber-400"
                    : "bg-white/10 border-white/20"
                }`}
              >
                <div className="flex items-center gap-2">
                  {mockPlayers[2].isActive && (
                    <motion.div
                      animate={{ scale: [1, 1.2, 1] }}
                      transition={{ duration: 1, repeat: Infinity }}
                      className="w-2 h-2 rounded-full bg-amber-400"
                    />
                  )}
                  <span className="text-white font-bold text-sm md:text-base landscape:text-sm">
                    {mockPlayers[2].name}
                  </span>
                </div>
              </motion.div>
            </div>

            {/* Cartes du joueur */}
            <div className="flex justify-center gap-2 md:gap-3 landscape:gap-2 mb-4 md:mb-6 landscape:mb-3">
              {playerCards.map((card, index) => (
                <motion.button
                  key={card.id}
                  initial={{ opacity: 0, y: 20, rotate: -10 }}
                  animate={{ 
                    opacity: 1, 
                    y: selectedCard === card.id ? -10 : 0,
                    rotate: 0 
                  }}
                  transition={{ delay: 0.5 + index * 0.1 }}
                  whileHover={{ y: -15, scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  onClick={() => setSelectedCard(selectedCard === card.id ? null : card.id)}
                  className="relative"
                >
                  <PlayingCard 
                    suit={card.suit}
                    value={card.value}
                    revealed={card.revealed}
                    selected={selectedCard === card.id}
                  />
                </motion.button>
              ))}
            </div>

            {/* Actions du joueur */}
            <div className="flex justify-center gap-3 md:gap-4 landscape:gap-3">
              <motion.button
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                className="px-6 md:px-8 landscape:px-6 py-3 md:py-4 landscape:py-2.5 rounded-xl md:rounded-2xl landscape:rounded-xl bg-gradient-to-r from-indigo-500 to-purple-600 hover:from-indigo-600 hover:to-purple-700 text-white font-bold text-sm md:text-base landscape:text-sm shadow-lg backdrop-blur-xl border border-white/20 transition-all"
              >
                PIOCHER
              </motion.button>
              <motion.button
                whileHover={{ scale: 1.05 }}
                whileTap={{ scale: 0.95 }}
                animate={{
                  boxShadow: [
                    "0 4px 20px rgba(251, 146, 60, 0.3)",
                    "0 4px 30px rgba(251, 146, 60, 0.6)",
                    "0 4px 20px rgba(251, 146, 60, 0.3)",
                  ]
                }}
                transition={{ duration: 2, repeat: Infinity }}
                className="px-6 md:px-8 landscape:px-6 py-3 md:py-4 landscape:py-2.5 rounded-xl md:rounded-2xl landscape:rounded-xl bg-gradient-to-r from-amber-500 to-orange-600 hover:from-amber-600 hover:to-orange-700 text-white font-bold text-sm md:text-base landscape:text-sm shadow-lg backdrop-blur-xl border border-white/20 transition-all"
              >
                DUTCH
              </motion.button>
            </div>
          </motion.div>
        </div>
      </div>

      {/* Menu latéral */}
      <AnimatePresence>
        {showMenu && (
          <>
            {/* Overlay */}
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setShowMenu(false)}
              className="absolute inset-0 bg-black/50 backdrop-blur-sm z-30"
            />

            {/* Menu */}
            <motion.div
              initial={{ x: "100%" }}
              animate={{ x: 0 }}
              exit={{ x: "100%" }}
              transition={{ type: "spring", damping: 25 }}
              className="absolute top-0 right-0 bottom-0 w-80 md:w-96 landscape:w-80 bg-white/95 backdrop-blur-xl shadow-2xl z-40 p-6 md:p-8 landscape:p-6"
            >
              <h2 className="text-2xl md:text-3xl landscape:text-2xl font-bold text-slate-800 mb-6">Menu</h2>
              <div className="space-y-3">
                <MenuButton onClick={() => {}}>Reprendre</MenuButton>
                <MenuButton onClick={() => {}}>Règles</MenuButton>
                <MenuButton onClick={() => {}}>Statistiques</MenuButton>
                <MenuButton onClick={onBack} variant="danger">Quitter la partie</MenuButton>
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  );
}

// Composant carte à jouer
interface PlayingCardProps {
  suit: string;
  value: string;
  revealed?: boolean;
  selected?: boolean;
  size?: "small" | "medium" | "large";
  isDiscard?: boolean;
}

function PlayingCard({ suit, value, revealed = false, selected = false, size = "medium", isDiscard = false }: PlayingCardProps) {
  const isRed = suit === "♥" || suit === "♦";
  
  const sizeClasses = {
    small: "w-12 h-16 md:w-14 md:h-20 landscape:w-12 landscape:h-16",
    medium: "w-16 h-24 md:w-20 md:h-32 landscape:w-16 landscape:h-24",
    large: "w-20 h-32 md:w-24 md:h-36 landscape:w-20 landscape:h-32",
  };

  const textSizeClasses = {
    small: "text-xs md:text-sm landscape:text-xs",
    medium: "text-sm md:text-base landscape:text-sm",
    large: "text-base md:text-lg landscape:text-base",
  };

  if (!revealed) {
    return (
      <div className={`${sizeClasses[size]} rounded-lg md:rounded-xl landscape:rounded-lg bg-gradient-to-br from-indigo-600 to-purple-700 shadow-xl border-2 ${
        selected ? "border-amber-400 ring-2 ring-amber-400" : "border-white/30"
      } transition-all`}>
        <div className="size-full p-1.5 md:p-2 landscape:p-1.5">
          <div className="size-full rounded-md border-2 border-white/20 bg-white/5" />
        </div>
      </div>
    );
  }

  return (
    <div className={`${sizeClasses[size]} rounded-lg md:rounded-xl landscape:rounded-lg bg-white shadow-2xl border-2 ${
      selected ? "border-amber-400 ring-2 ring-amber-400" : isDiscard ? "border-amber-400/50" : "border-slate-300"
    } p-2 md:p-3 landscape:p-2 flex flex-col transition-all`}>
      {/* Valeur et symbole en haut à gauche */}
      <div className={`${textSizeClasses[size]} font-bold ${isRed ? "text-red-600" : "text-slate-800"}`}>
        <div>{value}</div>
        <div className="leading-none">{suit}</div>
      </div>

      {/* Symbole central */}
      <div className="flex-1 flex items-center justify-center">
        <span className={`${size === "large" ? "text-4xl md:text-5xl landscape:text-4xl" : size === "medium" ? "text-2xl md:text-3xl landscape:text-2xl" : "text-xl md:text-2xl landscape:text-xl"} ${isRed ? "text-red-600" : "text-slate-800"}`}>
          {suit}
        </span>
      </div>

      {/* Valeur et symbole en bas à droite (inversé) */}
      <div className={`${textSizeClasses[size]} font-bold ${isRed ? "text-red-600" : "text-slate-800"} text-right rotate-180`}>
        <div>{value}</div>
        <div className="leading-none">{suit}</div>
      </div>
    </div>
  );
}

// Composant zone adversaire (haut)
interface OpponentAreaProps {
  player: Player;
}

function OpponentArea({ player }: OpponentAreaProps) {
  return (
    <motion.div
      initial={{ opacity: 0, y: -50 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay: 0.2 }}
      className="absolute top-0 left-1/2 -translate-x-1/2"
    >
      {/* Nom et indicateur */}
      <div className="flex justify-center mb-2 md:mb-3 landscape:mb-2">
        <motion.div
          animate={player.isActive ? {
            boxShadow: [
              "0 0 20px rgba(251, 191, 36, 0.5)",
              "0 0 40px rgba(251, 191, 36, 0.8)",
              "0 0 20px rgba(251, 191, 36, 0.5)",
            ]
          } : {}}
          transition={{ duration: 2, repeat: Infinity }}
          className={`px-3 md:px-4 landscape:px-3 py-1.5 md:py-2 landscape:py-1.5 rounded-lg md:rounded-xl landscape:rounded-lg backdrop-blur-xl border-2 shadow-lg ${
            player.isActive
              ? "bg-amber-500/20 border-amber-400"
              : "bg-white/10 border-white/20"
          }`}
        >
          <div className="flex items-center gap-2">
            {player.isActive && (
              <motion.div
                animate={{ scale: [1, 1.2, 1] }}
                transition={{ duration: 1, repeat: Infinity }}
                className="w-2 h-2 rounded-full bg-amber-400"
              />
            )}
            <span className="text-white font-bold text-xs md:text-sm landscape:text-xs">
              {player.name}
            </span>
          </div>
        </motion.div>
      </div>

      {/* Cartes */}
      <div className="flex gap-1 md:gap-2 landscape:gap-1">
        {Array.from({ length: player.cards }).map((_, i) => (
          <motion.div
            key={i}
            initial={{ opacity: 0, y: -20, rotate: 10 }}
            animate={{ opacity: 1, y: 0, rotate: 0 }}
            transition={{ delay: 0.3 + i * 0.1 }}
          >
            <PlayingCard suit="♠" value="K" size="small" />
          </motion.div>
        ))}
      </div>
    </motion.div>
  );
}

// Composant zone adversaire (côtés)
interface OpponentAreaSideProps {
  player: Player;
  side: "left" | "right";
}

function OpponentAreaSide({ player, side }: OpponentAreaSideProps) {
  return (
    <motion.div
      initial={{ opacity: 0, x: side === "left" ? -50 : 50 }}
      animate={{ opacity: 1, x: 0 }}
      transition={{ delay: 0.2 }}
      className={`absolute top-1/2 -translate-y-1/2 ${side === "left" ? "left-0" : "right-0"}`}
    >
      <div className="flex flex-col items-center gap-2 md:gap-3 landscape:gap-2">
        {/* Nom et indicateur */}
        <motion.div
          animate={player.isActive ? {
            boxShadow: [
              "0 0 20px rgba(251, 191, 36, 0.5)",
              "0 0 40px rgba(251, 191, 36, 0.8)",
              "0 0 20px rgba(251, 191, 36, 0.5)",
            ]
          } : {}}
          transition={{ duration: 2, repeat: Infinity }}
          className={`px-3 md:px-4 landscape:px-3 py-1.5 md:py-2 landscape:py-1.5 rounded-lg md:rounded-xl landscape:rounded-lg backdrop-blur-xl border-2 shadow-lg ${
            player.isActive
              ? "bg-amber-500/20 border-amber-400"
              : "bg-white/10 border-white/20"
          }`}
        >
          <div className="flex items-center gap-2">
            {player.isActive && (
              <motion.div
                animate={{ scale: [1, 1.2, 1] }}
                transition={{ duration: 1, repeat: Infinity }}
                className="w-2 h-2 rounded-full bg-amber-400"
              />
            )}
            <span className="text-white font-bold text-xs md:text-sm landscape:text-xs">
              {player.name}
            </span>
          </div>
        </motion.div>

        {/* Cartes (verticalement) */}
        <div className="flex flex-col gap-1 md:gap-2 landscape:gap-1">
          {Array.from({ length: player.cards }).map((_, i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, x: side === "left" ? -20 : 20, rotate: side === "left" ? -10 : 10 }}
              animate={{ opacity: 1, x: 0, rotate: 0 }}
              transition={{ delay: 0.3 + i * 0.1 }}
            >
              <PlayingCard suit="♠" value="K" size="small" />
            </motion.div>
          ))}
        </div>
      </div>
    </motion.div>
  );
}

// Composant bouton menu
interface MenuButtonProps {
  children: React.ReactNode;
  onClick: () => void;
  variant?: "default" | "danger";
}

function MenuButton({ children, onClick, variant = "default" }: MenuButtonProps) {
  return (
    <motion.button
      whileHover={{ scale: 1.02, x: 5 }}
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className={`w-full px-6 py-4 rounded-xl md:rounded-2xl landscape:rounded-xl font-semibold text-left shadow-md transition-all ${
        variant === "danger"
          ? "bg-red-500 hover:bg-red-600 text-white"
          : "bg-white/60 hover:bg-white/80 text-slate-800"
      }`}
    >
      {children}
    </motion.button>
  );
}

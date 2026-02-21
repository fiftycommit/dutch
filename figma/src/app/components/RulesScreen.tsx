import { motion } from "motion/react";
import { ArrowLeft, Trophy, Eye, Zap, Users, Play, Crown, AlertTriangle, Info } from "lucide-react";
import { Screen } from "../App";
import { ImageWithFallback } from "./figma/ImageWithFallback";

interface RulesScreenProps {
  onNavigate: (screen: Screen) => void;
}

export function RulesScreen({ onNavigate }: RulesScreenProps) {
  // Chemins des images de cartes (depuis /public)
  const carte7Trefle = "/cards/07-trefle.svg";
  const carte10Carreau = "/cards/10-carreau.svg";
  const carteValetCarreau = "/cards/V-carreau.svg";
  const carteJokerRouge = "/cards/joker-rouge.svg";
  const carteRoiCoeur = "/cards/R-coeur.svg";
  const carteRoiPique = "/cards/R-pique.svg";

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
          onClick={() => onNavigate("home")}
          className="p-3 landscape:p-2 rounded-2xl landscape:rounded-xl bg-white/60 backdrop-blur-xl shadow-sm hover:shadow-md transition-shadow"
        >
          <ArrowLeft className="size-5 landscape:size-4 text-slate-700" />
        </motion.button>
        <h1 className="text-2xl md:text-3xl landscape:text-xl font-bold bg-gradient-to-r from-indigo-600 via-purple-600 to-blue-600 bg-clip-text text-transparent">
          Règles du jeu
        </h1>
      </motion.div>

      {/* Contenu scrollable */}
      <div className="flex-1 overflow-y-auto px-4 md:px-6 lg:px-8 landscape:px-3 pb-6">
        <div className="max-w-4xl mx-auto space-y-4 md:space-y-6 landscape:space-y-3">
          
          {/* Introduction */}
          <RuleSection
            icon={<Info className="size-5 landscape:size-4" />}
            title="Le Dutch, c'est quoi ?"
            delay={0.1}
          >
            <p className="text-slate-700 leading-relaxed text-sm md:text-base landscape:text-xs">
              Un jeu de cartes basé sur la mémoire pour 2 à 6 joueurs. Vous avez 4 cartes face cachée, 
              et vous pouvez en mémoriser 2 au début de la partie. Ensuite, impossible de les revoir !
            </p>
          </RuleSection>

          {/* Objectif */}
          <RuleSection
            icon={<Trophy className="size-5 landscape:size-4" />}
            title="Le but du jeu"
            delay={0.15}
          >
            <p className="text-slate-700 leading-relaxed text-sm md:text-base landscape:text-xs">
              Terminer la manche avec <strong>le moins de points possible</strong>. 
              Les points sont calculés en additionnant la valeur de vos 4 cartes.
            </p>
          </RuleSection>

          {/* Valeur des cartes */}
          <RuleSection
            icon={<Crown className="size-5 landscape:size-4" />}
            title="Valeur des cartes"
            delay={0.2}
          >
            <p className="text-slate-700 leading-relaxed text-sm md:text-base landscape:text-xs mb-4">
              Chaque carte a une valeur qui compte dans votre score final :
            </p>
            
            {/* Cartes normales */}
            <div className="space-y-2 text-sm md:text-base landscape:text-xs mb-4">
              <ValueCard label="As" value="1 pt" />
              <ValueCard label="2 à 10" value="2 pts, 3 pts... 10 pts" />
              <ValueCard label="Valet" value="11 pts" />
              <ValueCard label="Dame" value="12 pts" />
            </div>

            {/* Cartes qui ne suivent pas la logique */}
            <p className="text-slate-700 font-semibold text-sm md:text-base landscape:text-xs mb-3">
              Quelques exceptions à la règle :
            </p>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4 md:gap-6 landscape:gap-3">
              <SpecialCardVisual
                image={carteJokerRouge}
                label="Joker"
                value="0 pt"
              />
              <SpecialCardVisual
                image={carteRoiCoeur}
                label="Roi rouge (♥ ♦)"
                value="0 pt"
              />
              <SpecialCardVisual
                image={carteRoiPique}
                label="Roi noir (♠ ♣)"
                value="13 pts"
                isNegative
              />
            </div>
          </RuleSection>

          {/* Défausse collective */}
          <RuleSection
            icon={<Users className="size-5 landscape:size-4" />}
            title="Défausse collective"
            delay={0.25}
          >
            <p className="text-slate-700 leading-relaxed text-sm md:text-base landscape:text-xs mb-3">
              Quand un joueur défausse, les autres peuvent défausser une carte du même rang (peu importe la couleur).
            </p>
            <div className="bg-red-50 border-l-4 border-red-400 p-3 md:p-4 landscape:p-2 rounded-lg">
              <div className="flex items-start gap-2">
                <AlertTriangle className="size-4 landscape:size-3 text-red-600 flex-shrink-0 mt-0.5" />
                <div className="text-sm md:text-base landscape:text-xs text-red-800">
                  <p className="font-semibold mb-1">Attention !</p>
                  <p>Erreur = carte de pénalité. 3 clics erronés = 3 pénalités !</p>
                </div>
              </div>
            </div>
          </RuleSection>

          {/* Pouvoirs spéciaux */}
          <RuleSection
            icon={<Zap className="size-5 landscape:size-4" />}
            title="Pouvoirs spéciaux"
            delay={0.3}
          >
            <p className="text-slate-700 leading-relaxed text-sm md:text-base landscape:text-xs mb-3">
              Activés uniquement quand la carte est défaussée en premier :
            </p>
            <div className="space-y-4 md:space-y-6 landscape:space-y-3">
              <PowerCardLarge
                image={carte10Carreau}
                label="Tous les 10"
                description="Espionner : Voir une carte d'un adversaire"
              />
              <PowerCardLarge
                image={carteValetCarreau}
                label="Valet (♥ ♦)"
                description="Échanger : Échanger 2 cartes entre adversaires"
              />
              <PowerCardLarge
                image={carteJokerRouge}
                label="Joker"
                description="Mélanger : Mélanger la main d'un joueur"
              />
              <PowerCardLarge
                image={carte7Trefle}
                label="7"
                description="Révéler : Voir une de vos cartes"
              />
            </div>
          </RuleSection>

          {/* Déroulement */}
          <RuleSection
            icon={<Play className="size-5 landscape:size-4" />}
            title="Déroulement d'une partie"
            delay={0.35}
          >
            <div className="space-y-3 md:space-y-4 landscape:space-y-2">
              <StepCard
                step="1"
                title="Phase de mémorisation"
                description="Cliquez sur deux cartes pour les révéler. Elles restent visibles 3 secondes puis se retournent."
              />
              <StepCard
                step="2"
                title="Votre tour"
                description="Deux actions possibles : Piocher une carte ou appeler Dutch."
              />
              <StepCard
                step="3"
                title="Piocher"
                description="Tirez une carte. Vous pouvez l'échanger avec une carte de votre main ou la défausser (bouton JETER rouge)."
              />
              <div className="bg-gradient-to-r from-purple-500 to-indigo-600 rounded-2xl md:rounded-3xl landscape:rounded-xl p-4 md:p-6 landscape:p-3 shadow-xl border-4 border-purple-300">
                <div className="flex items-start gap-3 landscape:gap-2">
                  <div className="flex-shrink-0 w-7 h-7 md:w-8 md:h-8 landscape:w-6 landscape:h-6 rounded-full bg-white text-purple-600 font-bold flex items-center justify-center text-xs md:text-sm landscape:text-xs">
                    4
                  </div>
                  <div className="flex-1">
                    <p className="font-bold text-white mb-2 text-base md:text-lg landscape:text-sm">⚡ Phase de réaction</p>
                    <p className="text-white/95 text-sm md:text-base landscape:text-xs leading-relaxed mb-3">
                      Quand une carte est défaussée, <strong className="text-yellow-300">tous les joueurs peuvent défausser une carte de la même valeur</strong>.
                    </p>
                    <div className="bg-white/20 backdrop-blur-sm rounded-xl md:rounded-2xl landscape:rounded-lg p-3 md:p-4 landscape:p-2 border-2 border-white/30">
                      <p className="text-white font-semibold text-sm md:text-base landscape:text-xs mb-2">🎯 Important :</p>
                      <ul className="text-white/95 text-xs md:text-sm landscape:text-xs space-y-1.5">
                        <li>• Seule la <strong className="text-yellow-300">valeur</strong> compte (ex: 7 de cœur défaussé → vous pouvez défausser n'importe quel 7)</li>
                        <li>• L'<strong className="text-yellow-300">enseigne</strong> (♠ ♥ ♦ ♣) n'a <strong>aucune importance</strong></li>
                        <li>• La <strong className="text-yellow-300">couleur</strong> (rouge/noir) n'a <strong>aucune importance</strong></li>
                        <li>• Basez-vous sur votre mémoire !</li>
                      </ul>
                    </div>
                  </div>
                </div>
              </div>
              <StepCard
                step="5"
                title="Appeler Dutch"
                description="Quand vous pensez avoir le plus petit score, cliquez sur Dutch. Le jeu s'arrête immédiatement (mort subite)."
              />
            </div>
            
            <div className="bg-amber-50 border-l-4 border-amber-400 p-3 md:p-4 landscape:p-2 rounded-lg mt-4">
              <div className="flex items-start gap-2">
                <AlertTriangle className="size-4 landscape:size-3 text-amber-600 flex-shrink-0 mt-0.5" />
                <div className="text-sm md:text-base landscape:text-xs text-amber-800">
                  <p className="font-semibold mb-1">Règle du Dutch</p>
                  <p>Si vous appelez Dutch sans avoir le plus petit score, vous êtes éliminé d'office ! En cas d'égalité, le joueur qui a appelé Dutch est classé premier.</p>
                </div>
              </div>
            </div>
          </RuleSection>

          {/* Modes de jeu */}
          <RuleSection
            icon={<Trophy className="size-5 landscape:size-4" />}
            title="Modes de jeu"
            delay={0.4}
          >
            <div className="space-y-3 md:space-y-4 landscape:space-y-2">
              <ModeCard
                title="Partie Rapide"
                description="Lancez une partie composée d'une seule manche."
                color="from-indigo-500 to-purple-600"
              />
              <ModeCard
                title="Tournoi"
                description="Enchaînez plusieurs manches successives jusqu'à atteindre la finale."
                color="from-purple-500 to-pink-600"
              />
              <ModeCard
                title="Multijoueur"
                description="Jouez avec d'autres joueurs en ligne."
                color="from-blue-500 to-indigo-600"
              />
            </div>
          </RuleSection>

          {/* Réglages */}
          <RuleSection
            icon={<Eye className="size-5 landscape:size-4" />}
            title="Réglages et SBMM"
            delay={0.45}
          >
            <p className="text-slate-700 leading-relaxed text-sm md:text-base landscape:text-xs mb-3">
              Dans les réglages, vous pouvez personnaliser plusieurs éléments : temps de réaction, niveau des bots, et activation du SBMM (Skill-Based Matchmaking).
            </p>
            <div className="space-y-2 text-sm md:text-base landscape:text-xs">
              <div className="bg-white/60 backdrop-blur-xl rounded-xl md:rounded-2xl landscape:rounded-lg p-3 md:p-4 landscape:p-2">
                <p className="font-semibold text-slate-800 mb-1">SBMM désactivé</p>
                <p className="text-slate-600">Choisissez manuellement le niveau des bots et le nombre de joueurs.</p>
              </div>
              <div className="bg-white/60 backdrop-blur-xl rounded-xl md:rounded-2xl landscape:rounded-lg p-3 md:p-4 landscape:p-2">
                <p className="font-semibold text-slate-800 mb-1">SBMM activé</p>
                <p className="text-slate-600">Seul le nombre de joueurs est configurable. Le niveau des bots s'ajuste automatiquement à votre niveau.</p>
              </div>
            </div>
          </RuleSection>

          {/* Footer */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.5 }}
            className="text-center py-6 md:py-8 landscape:py-4"
          >
            <p className="text-lg md:text-xl landscape:text-base font-semibold bg-gradient-to-r from-indigo-600 via-purple-600 to-blue-600 bg-clip-text text-transparent">
              Bonne partie ! 🎮
            </p>
          </motion.div>
        </div>
      </div>
    </div>
  );
}

// Composants utilitaires
interface RuleSectionProps {
  icon: React.ReactNode;
  title: string;
  delay: number;
  children: React.ReactNode;
}

function RuleSection({ icon, title, delay, children }: RuleSectionProps) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay }}
      className="bg-white/70 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl shadow-lg p-4 md:p-6 landscape:p-3"
    >
      <div className="flex items-center gap-3 landscape:gap-2 mb-3 md:mb-4 landscape:mb-2">
        <div className="p-2 md:p-3 landscape:p-1.5 rounded-xl md:rounded-2xl landscape:rounded-lg bg-gradient-to-br from-indigo-500 to-purple-600 text-white">
          {icon}
        </div>
        <h2 className="text-lg md:text-xl landscape:text-base font-bold text-slate-800">
          {title}
        </h2>
      </div>
      <div className="space-y-2 md:space-y-3 landscape:space-y-2">{children}</div>
    </motion.div>
  );
}

interface ValueCardProps {
  label: string;
  value: string;
  special?: boolean;
}

function ValueCard({ label, value, special = false }: ValueCardProps) {
  return (
    <div className={`flex justify-between items-center p-2 md:p-3 landscape:p-2 rounded-lg md:rounded-xl landscape:rounded-lg ${
      special ? "bg-gradient-to-r from-indigo-50 to-purple-50 border border-indigo-200" : "bg-slate-50"
    }`}>
      <span className="font-medium text-slate-700">{label}</span>
      <span className={`font-bold ${special ? "text-indigo-600" : "text-slate-600"}`}>{value}</span>
    </div>
  );
}

interface PowerCardProps {
  number: string;
  title: string;
  description: string;
}

function PowerCard({ number, title, description }: PowerCardProps) {
  return (
    <div className="bg-gradient-to-r from-purple-50 to-indigo-50 rounded-xl md:rounded-2xl landscape:rounded-lg p-3 md:p-4 landscape:p-2 border border-purple-200">
      <div className="flex items-start gap-3 landscape:gap-2">
        <div className="flex-shrink-0 w-8 h-8 md:w-10 md:h-10 landscape:w-7 landscape:h-7 rounded-lg md:rounded-xl landscape:rounded-lg bg-gradient-to-br from-purple-500 to-indigo-600 text-white font-bold flex items-center justify-center text-sm md:text-base landscape:text-xs">
          {number}
        </div>
        <div className="flex-1">
          <p className="font-semibold text-slate-800 mb-1 text-sm md:text-base landscape:text-xs">{title}</p>
          <p className="text-slate-600 text-xs md:text-sm landscape:text-xs">{description}</p>
        </div>
      </div>
    </div>
  );
}

interface PowerCardWithImageProps {
  image: string;
  title: string;
  description: string;
}

function PowerCardWithImage({ image, title, description }: PowerCardWithImageProps) {
  return (
    <div className="bg-gradient-to-r from-purple-50 to-indigo-50 rounded-xl md:rounded-2xl landscape:rounded-lg p-3 md:p-4 landscape:p-2 border border-purple-200">
      <div className="flex items-start gap-3 landscape:gap-2">
        <div className="flex-shrink-0 w-8 h-8 md:w-10 md:h-10 landscape:w-7 landscape:h-7 rounded-lg md:rounded-xl landscape:rounded-lg bg-gradient-to-br from-purple-500 to-indigo-600 text-white font-bold flex items-center justify-center text-sm md:text-base landscape:text-xs">
          <img src={image} alt={title} className="w-6 h-6 md:w-8 md:h-8 landscape:w-6 landscape:h-6" />
        </div>
        <div className="flex-1">
          <p className="font-semibold text-slate-800 mb-1 text-sm md:text-base landscape:text-xs">{title}</p>
          <p className="text-slate-600 text-xs md:text-sm landscape:text-xs">{description}</p>
        </div>
      </div>
    </div>
  );
}

interface PowerCardVerticalProps {
  image: string;
  title: string;
  description: string;
}

function PowerCardVertical({ image, title, description }: PowerCardVerticalProps) {
  return (
    <div className="bg-gradient-to-r from-purple-50 to-indigo-50 rounded-xl md:rounded-2xl landscape:rounded-lg p-3 md:p-4 landscape:p-2 border border-purple-200">
      <div className="flex flex-col items-center gap-3 landscape:gap-2">
        <div className="flex-shrink-0 w-8 h-8 md:w-10 md:h-10 landscape:w-7 landscape:h-7 rounded-lg md:rounded-xl landscape:rounded-lg bg-gradient-to-br from-purple-500 to-indigo-600 text-white font-bold flex items-center justify-center text-sm md:text-base landscape:text-xs">
          <img src={image} alt={title} className="w-6 h-6 md:w-8 md:h-8 landscape:w-6 landscape:h-6" />
        </div>
        <div className="flex-1">
          <p className="font-semibold text-slate-800 mb-1 text-sm md:text-base landscape:text-xs">{title}</p>
          <p className="text-slate-600 text-xs md:text-sm landscape:text-xs">{description}</p>
        </div>
      </div>
    </div>
  );
}

interface StepCardProps {
  step: string;
  title: string;
  description: string;
}

function StepCard({ step, title, description }: StepCardProps) {
  return (
    <div className="flex items-start gap-3 landscape:gap-2">
      <div className="flex-shrink-0 w-7 h-7 md:w-8 md:h-8 landscape:w-6 landscape:h-6 rounded-full bg-gradient-to-br from-indigo-500 to-purple-600 text-white font-bold flex items-center justify-center text-xs md:text-sm landscape:text-xs">
        {step}
      </div>
      <div className="flex-1 bg-slate-50 rounded-lg md:rounded-xl landscape:rounded-lg p-3 md:p-4 landscape:p-2">
        <p className="font-semibold text-slate-800 mb-1 text-sm md:text-base landscape:text-xs">{title}</p>
        <p className="text-slate-600 text-xs md:text-sm landscape:text-xs">{description}</p>
      </div>
    </div>
  );
}

interface ModeCardProps {
  title: string;
  description: string;
  color: string;
}

function ModeCard({ title, description, color }: ModeCardProps) {
  return (
    <div className={`bg-gradient-to-r ${color} rounded-xl md:rounded-2xl landscape:rounded-lg p-4 md:p-5 landscape:p-3 text-white shadow-lg`}>
      <p className="font-bold text-base md:text-lg landscape:text-sm mb-1">{title}</p>
      <p className="text-white/90 text-xs md:text-sm landscape:text-xs">{description}</p>
    </div>
  );
}

interface SpecialCardVisualProps {
  image: string;
  label: string;
  value: string;
  isNegative?: boolean;
}

function SpecialCardVisual({ image, label, value, isNegative = false }: SpecialCardVisualProps) {
  return (
    <div className="bg-gradient-to-br from-white/80 to-indigo-50/50 backdrop-blur-sm border-2 border-indigo-200 rounded-2xl md:rounded-3xl landscape:rounded-xl p-4 md:p-6 landscape:p-3 shadow-lg hover:shadow-xl transition-shadow">
      <div className="flex flex-col items-center gap-3 md:gap-4 landscape:gap-2">
        <div className="w-24 h-36 md:w-32 md:h-48 landscape:w-20 landscape:h-30 rounded-lg overflow-hidden shadow-md">
          <img 
            src={image} 
            alt={label} 
            className="w-full h-full object-contain"
            style={{ aspectRatio: '1.447' }}
          />
        </div>
        <div className="text-center space-y-1">
          <p className="font-semibold text-slate-800 text-sm md:text-base landscape:text-xs">{label}</p>
          <p className={`font-bold text-lg md:text-xl landscape:text-base ${isNegative ? "text-red-600" : "text-green-600"}`}>
            {value}
          </p>
        </div>
      </div>
    </div>
  );
}

interface PowerCardLargeProps {
  image: string;
  label: string;
  description: string;
  value?: string;
  isNegative?: boolean;
}

function PowerCardLarge({ image, label, description }: PowerCardLargeProps) {
  return (
    <div className="bg-gradient-to-br from-white/80 to-purple-50/50 backdrop-blur-sm border-2 border-purple-200 rounded-2xl md:rounded-3xl landscape:rounded-xl p-4 md:p-6 landscape:p-3 shadow-lg hover:shadow-xl transition-shadow">
      <div className="flex flex-col items-center gap-3 md:gap-4 landscape:gap-2">
        <h3 className="font-bold text-slate-800 text-base md:text-lg landscape:text-sm">{label}</h3>
        <div className="w-24 h-36 md:w-32 md:h-48 landscape:w-20 landscape:h-30 rounded-lg overflow-hidden shadow-md">
          <img 
            src={image} 
            alt={label} 
            className="w-full h-full object-contain"
            style={{ aspectRatio: '1.447' }}
          />
        </div>
        <p className="text-purple-700 font-semibold text-sm md:text-base landscape:text-xs text-center">{description}</p>
      </div>
    </div>
  );
}
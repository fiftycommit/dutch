import { motion } from "motion/react";
import { ArrowLeft, User, Clock, Eye, Shuffle, Volume2, Vibrate, Sparkles, Zap } from "lucide-react";
import { Switch } from "./ui/switch";
import { useState } from "react";

interface SettingsScreenProps {
  onBack: () => void;
  sbmmEnabled: boolean;
  onSbmmChange: (enabled: boolean) => void;
  darkMode: boolean;
  onDarkModeChange: (enabled: boolean) => void;
}

export function SettingsScreen({ onBack, sbmmEnabled, onSbmmChange, darkMode, onDarkModeChange }: SettingsScreenProps) {
  // États pour les réglages
  const [selectedProfile, setSelectedProfile] = useState(1);
  const [reactionTime, setReactionTime] = useState(50);
  const [botActionDisplay, setBotActionDisplay] = useState(75);
  const [shuffleMethod, setShuffleMethod] = useState<"relaxed" | "tactical" | "challenger">("tactical");
  const [vibrationsEnabled, setVibrationsEnabled] = useState(true);
  const [animationsEnabled, setAnimationsEnabled] = useState(true);

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
          Réglages
        </h1>
      </motion.div>

      {/* Contenu scrollable */}
      <div className="flex-1 overflow-y-auto px-4 md:px-6 lg:px-8 landscape:px-3 pb-6">
        <div className="max-w-4xl mx-auto space-y-4 md:space-y-6 landscape:space-y-3">
          
          {/* Profils */}
          <SettingSection
            icon={<User className="size-5 landscape:size-4" />}
            title="Profils"
            delay={0.1}
          >
            <div className="grid grid-cols-3 gap-3 md:gap-4 landscape:gap-2">
              {[1, 2, 3].map((profile) => (
                <ProfileCard
                  key={profile}
                  number={profile}
                  isSelected={selectedProfile === profile}
                  onClick={() => setSelectedProfile(profile)}
                />
              ))}
            </div>
          </SettingSection>

          {/* Mécanique de jeu */}
          <SettingSection
            icon={<Clock className="size-5 landscape:size-4" />}
            title="Mécanique de jeu"
            delay={0.15}
          >
            <div className="space-y-4 md:space-y-5 landscape:space-y-3">
              <SliderControl
                label="Temps de réaction"
                value={reactionTime}
                onChange={setReactionTime}
                min={0}
                max={100}
                unit="%"
              />
              <SliderControl
                label="Affichage des actions des bots"
                value={botActionDisplay}
                onChange={setBotActionDisplay}
                min={0}
                max={100}
                unit="%"
              />
            </div>
          </SettingSection>

          {/* Méthode de mélange */}
          <SettingSection
            icon={<Shuffle className="size-5 landscape:size-4" />}
            title="Méthode de mélange"
            delay={0.2}
          >
            <div className="grid grid-cols-1 md:grid-cols-3 gap-3 md:gap-4 landscape:gap-2">
              <ShuffleMethodCard
                method="relaxed"
                label="Détendu"
                emoji="😌"
                description="Tranquille"
                isSelected={shuffleMethod === "relaxed"}
                onClick={() => setShuffleMethod("relaxed")}
              />
              <ShuffleMethodCard
                method="tactical"
                label="Tactique"
                emoji="🎯"
                description="Équilibré"
                isSelected={shuffleMethod === "tactical"}
                onClick={() => setShuffleMethod("tactical")}
              />
              <ShuffleMethodCard
                method="challenger"
                label="Challenger"
                emoji="🔥"
                description="Intense"
                isSelected={shuffleMethod === "challenger"}
                onClick={() => setShuffleMethod("challenger")}
              />
            </div>
          </SettingSection>

          {/* Immersion */}
          <SettingSection
            icon={<Sparkles className="size-5 landscape:size-4" />}
            title="Immersion"
            delay={0.25}
          >
            <div className="space-y-3 md:space-y-4 landscape:space-y-2">
              <ToggleItem
                icon={<Vibrate className="size-4 landscape:size-3" />}
                label="Vibrations"
                checked={vibrationsEnabled}
                onChange={setVibrationsEnabled}
              />
              <ToggleItem
                icon={<Sparkles className="size-4 landscape:size-3" />}
                label="Animations"
                checked={animationsEnabled}
                onChange={setAnimationsEnabled}
              />
            </div>
          </SettingSection>

          {/* Adaptatif */}
          <SettingSection
            icon={<Zap className="size-5 landscape:size-4" />}
            title="Adaptatif"
            delay={0.3}
          >
            <div className="space-y-3">
              <ToggleItem
                icon={<Zap className="size-4 landscape:size-3" />}
                label="SBMM (Skill-Based Matchmaking)"
                description="Ajuste automatiquement le niveau des bots selon vos performances"
                checked={sbmmEnabled}
                onChange={onSbmmChange}
              />
              {sbmmEnabled && (
                <motion.div
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: "auto" }}
                  exit={{ opacity: 0, height: 0 }}
                  className="bg-indigo-50 border-l-4 border-indigo-400 p-3 md:p-4 landscape:p-2 rounded-lg"
                >
                  <p className="text-sm md:text-base landscape:text-xs text-indigo-800">
                    ℹ️ Le niveau des bots s'adaptera automatiquement à votre niveau de jeu.
                  </p>
                </motion.div>
              )}
            </div>
          </SettingSection>

          {/* Thème */}
          <SettingSection
            icon={<Sparkles className="size-5 landscape:size-4" />}
            title="Thème"
            delay={0.35}
          >
            <div className="space-y-3 md:space-y-4 landscape:space-y-2">
              <ToggleItem
                icon={<Sparkles className="size-4 landscape:size-3" />}
                label="Mode sombre"
                checked={darkMode}
                onChange={onDarkModeChange}
              />
            </div>
          </SettingSection>
        </div>
      </div>
    </div>
  );
}

// Composants utilitaires

interface SettingSectionProps {
  icon: React.ReactNode;
  title: string;
  delay: number;
  children: React.ReactNode;
}

function SettingSection({ icon, title, delay, children }: SettingSectionProps) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ delay }}
      className="bg-white/70 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl shadow-lg p-4 md:p-6 landscape:p-3"
    >
      <div className="flex items-center gap-3 landscape:gap-2 mb-4 landscape:mb-3">
        <div className="p-2 md:p-3 landscape:p-1.5 rounded-xl md:rounded-2xl landscape:rounded-lg bg-gradient-to-br from-indigo-500 to-purple-600 text-white">
          {icon}
        </div>
        <h2 className="text-lg md:text-xl landscape:text-base font-bold text-slate-800">
          {title}
        </h2>
      </div>
      {children}
    </motion.div>
  );
}

interface ProfileCardProps {
  number: number;
  isSelected: boolean;
  onClick: () => void;
}

function ProfileCard({ number, isSelected, onClick }: ProfileCardProps) {
  return (
    <motion.button
      whileHover={{ scale: 1.05 }}
      whileTap={{ scale: 0.95 }}
      onClick={onClick}
      className={`p-4 md:p-6 landscape:p-3 rounded-xl md:rounded-2xl landscape:rounded-lg transition-all ${
        isSelected
          ? "bg-gradient-to-br from-indigo-500 to-purple-600 text-white shadow-lg"
          : "bg-white/50 text-slate-700 hover:bg-white/70"
      }`}
    >
      <div className="flex flex-col items-center gap-2 landscape:gap-1">
        <User className="size-6 md:size-8 landscape:size-5" />
        <span className="font-bold text-sm md:text-base landscape:text-xs">
          Profil {number}
        </span>
      </div>
    </motion.button>
  );
}

interface SliderControlProps {
  label: string;
  value: number;
  onChange: (value: number) => void;
  min: number;
  max: number;
  unit: string;
}

function SliderControl({ label, value, onChange, min, max, unit }: SliderControlProps) {
  // Texte d'explication selon le slider
  const getDescription = () => {
    if (label === "Temps de réaction") {
      return "Durée pendant laquelle vous pouvez défausser une carte de même valeur après qu'un joueur ait défaussé (ou vous même 😉)";
    }
    return null;
  };

  const description = getDescription();

  return (
    <div className="space-y-2 landscape:space-y-1">
      <div className="flex justify-between items-center">
        <label className="text-sm md:text-base landscape:text-xs font-medium text-slate-700">
          {label}
        </label>
        <span className="text-sm md:text-base landscape:text-xs font-bold text-indigo-600">
          {value}{unit}
        </span>
      </div>
      {description && (
        <p className="text-xs md:text-sm landscape:text-xs text-slate-500 leading-relaxed">
          {description}
        </p>
      )}
      <input
        type="range"
        min={min}
        max={max}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="w-full h-2 bg-slate-200 rounded-lg appearance-none cursor-pointer accent-indigo-600"
        style={{
          background: `linear-gradient(to right, rgb(79 70 229) 0%, rgb(79 70 229) ${value}%, rgb(226 232 240) ${value}%, rgb(226 232 240) 100%)`
        }}
      />
    </div>
  );
}

interface ShuffleMethodCardProps {
  method: string;
  label: string;
  emoji: string;
  description: string;
  isSelected: boolean;
  onClick: () => void;
}

function ShuffleMethodCard({ label, emoji, description, isSelected, onClick }: ShuffleMethodCardProps) {
  return (
    <motion.button
      whileHover={{ scale: 1.05 }}
      whileTap={{ scale: 0.95 }}
      onClick={onClick}
      className={`p-4 md:p-5 landscape:p-3 rounded-xl md:rounded-2xl landscape:rounded-lg transition-all ${
        isSelected
          ? "bg-gradient-to-br from-purple-500 to-indigo-600 text-white shadow-lg"
          : "bg-white/50 text-slate-700 hover:bg-white/70"
      }`}
    >
      <div className="flex flex-col items-center gap-2 landscape:gap-1 text-center">
        <span className="text-3xl md:text-4xl landscape:text-2xl">{emoji}</span>
        <span className="font-bold text-sm md:text-base landscape:text-xs">{label}</span>
        <span className={`text-xs md:text-sm landscape:text-xs ${isSelected ? "text-white/80" : "text-slate-500"}`}>
          {description}
        </span>
      </div>
    </motion.button>
  );
}

interface ToggleItemProps {
  icon: React.ReactNode;
  label: string;
  description?: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
}

function ToggleItem({ icon, label, description, checked, onChange }: ToggleItemProps) {
  return (
    <div className="flex items-center justify-between p-3 md:p-4 landscape:p-2 bg-slate-50 rounded-lg md:rounded-xl landscape:rounded-lg">
      <div className="flex items-center gap-3 landscape:gap-2 flex-1">
        <div className="p-2 landscape:p-1.5 rounded-lg bg-gradient-to-br from-indigo-500 to-purple-600 text-white">
          {icon}
        </div>
        <div className="flex-1">
          <p className="font-medium text-slate-800 text-sm md:text-base landscape:text-xs">
            {label}
          </p>
          {description && (
            <p className="text-xs md:text-sm landscape:text-xs text-slate-500 mt-0.5">
              {description}
            </p>
          )}
        </div>
      </div>
      <Switch checked={checked} onCheckedChange={onChange} />
    </div>
  );
}
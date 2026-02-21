import { useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import { HomeScreen } from "./components/HomeScreen";
import { SettingsScreen } from "./components/SettingsScreen";
import { RulesScreen } from "./components/RulesScreen";
import { StatisticsScreen } from "./components/StatisticsScreen";
import { QuickGameScreen } from "./components/QuickGameScreen";
import { TournamentScreen } from "./components/TournamentScreen";
import { MultiplayerScreen } from "./components/MultiplayerScreen";
import { ProfileScreen } from "./components/ProfileScreen";
import { GameScreen } from "./components/GameScreen";

export type Screen = "home" | "settings" | "rules" | "stats" | "quickGame" | "tournament" | "multiplayer" | "profile" | "game";

export default function App() {
  const [currentScreen, setCurrentScreen] = useState<Screen>("home");
  const [selectedPlayer, setSelectedPlayer] = useState<string | null>(null);
  const [sbmmEnabled, setSbmmEnabled] = useState<boolean>(false);
  const [darkMode, setDarkMode] = useState<boolean>(false);
  const [displayName, setDisplayName] = useState<string>("allister");
  const [username, setUsername] = useState<string>("tasty");
  const [profileInitialTab, setProfileInitialTab] = useState<"profile" | "friends" | "blocked">("profile");

  // Déterminer le fond selon l'écran et le mode
  const getBackgroundClass = () => {
    if (currentScreen === "game") {
      // L'écran de jeu a son propre fond vert
      return "";
    }
    
    if (darkMode) {
      // Mode sombre : gradient slate foncé
      if (currentScreen === "quickGame" || currentScreen === "tournament") {
        return "from-slate-900 via-slate-800 to-slate-900";
      }
      return "from-slate-900 via-slate-800 to-slate-900";
    }
    
    // Mode clair : gradients actuels
    if (currentScreen === "quickGame" || currentScreen === "tournament") {
      return "from-emerald-50 via-green-50 to-teal-100";
    }
    return "from-slate-50 via-blue-50 to-indigo-100";
  };

  const handleUpdateProfile = (newDisplayName: string, newUsername: string) => {
    setDisplayName(newDisplayName);
    setUsername(newUsername);
  };

  const renderScreen = () => {
    switch (currentScreen) {
      case "home":
        return (
          <HomeScreen
            selectedPlayer={selectedPlayer}
            onSelectPlayer={setSelectedPlayer}
            onNavigate={setCurrentScreen}
            darkMode={darkMode}
          />
        );
      case "settings":
        return <SettingsScreen onBack={() => setCurrentScreen("home")} sbmmEnabled={sbmmEnabled} onSbmmChange={setSbmmEnabled} darkMode={darkMode} onDarkModeChange={setDarkMode} />;
      case "rules":
        return <RulesScreen onNavigate={setCurrentScreen} darkMode={darkMode} />;
      case "stats":
        return <StatisticsScreen onBack={() => setCurrentScreen("home")} darkMode={darkMode} />;
      case "quickGame":
        return <QuickGameScreen onBack={() => setCurrentScreen("home")} sbmmEnabled={sbmmEnabled} darkMode={darkMode} />;
      case "tournament":
        return <TournamentScreen onBack={() => setCurrentScreen("home")} sbmmEnabled={sbmmEnabled} darkMode={darkMode} />;
      case "multiplayer":
        return (
          <MultiplayerScreen
            onBack={() => setCurrentScreen("home")}
            onNavigateToProfile={(tab = "profile") => {
              setProfileInitialTab(tab);
              setCurrentScreen("profile");
            }}
            displayName={displayName}
            username={username}
            onUpdateProfile={handleUpdateProfile}
            darkMode={darkMode}
          />
        );
      case "profile":
        return (
          <ProfileScreen
            onBack={() => setCurrentScreen("multiplayer")}
            displayName={displayName}
            username={username}
            onUpdateProfile={handleUpdateProfile}
            initialTab={profileInitialTab}
            darkMode={darkMode}
          />
        );
      case "game":
        return <GameScreen onBack={() => setCurrentScreen("home")} darkMode={darkMode} />;
      default:
        return (
          <HomeScreen
            selectedPlayer={selectedPlayer}
            onSelectPlayer={setSelectedPlayer}
            onNavigate={setCurrentScreen}
            darkMode={darkMode}
          />
        );
    }
  };

  return (
    <div className="size-full overflow-hidden relative">
      {/* Fond avec transition douce */}
      <div className={`absolute inset-0 bg-gradient-to-br ${getBackgroundClass()} transition-all duration-700 ease-in-out`} />
      
      {/* Contenu avec animation de slide */}
      <AnimatePresence mode="wait">
        <motion.div
          key={currentScreen}
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: -20 }}
          transition={{ duration: 0.3, ease: "easeOut" }}
          className="relative z-10 size-full"
        >
          {renderScreen()}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
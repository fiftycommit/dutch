import { motion, AnimatePresence } from "motion/react";
import { ArrowLeft, User, Lock, Eye, EyeOff, Users, RefreshCw, Home, ChevronDown, LogOut, UserCircle2 } from "lucide-react";
import { useState } from "react";
import { RegisterScreen } from "./RegisterScreen";
import { ForgotPasswordScreen } from "./ForgotPasswordScreen";

interface MultiplayerScreenProps {
  onBack: () => void;
  onNavigateToProfile: (tab?: "profile" | "friends" | "blocked") => void;
  displayName: string;
  username: string;
  onUpdateProfile: (displayName: string, username: string) => void;
}

type AuthView = "login" | "register" | "forgotPassword";

export function MultiplayerScreen({ onBack, onNavigateToProfile, displayName: initialDisplayName, username: initialUsername, onUpdateProfile }: MultiplayerScreenProps) {
  const [authView, setAuthView] = useState<AuthView>("login");
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [loginUsername, setLoginUsername] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [shakeUsername, setShakeUsername] = useState(false);
  const [shakePassword, setShakePassword] = useState(false);
  
  // After login state
  const [showUserMenu, setShowUserMenu] = useState(false);
  const [displayName, setDisplayName] = useState(initialDisplayName);
  const [username, setUsername] = useState(initialUsername);
  const [isEditingProfile, setIsEditingProfile] = useState(false);

  // Mock data
  const friendsCount = 0;
  const savedRooms: any[] = [];

  const handleLogin = (e: React.FormEvent) => {
    e.preventDefault();
    
    if (loginUsername === "admin" && password === "admin") {
      setError("");
      setIsLoggedIn(true);
    } else {
      setError("Identifiants incorrects");
      setShakeUsername(true);
      setShakePassword(true);
      
      setTimeout(() => {
        setShakeUsername(false);
        setShakePassword(false);
      }, 500);
      
      setTimeout(() => {
        setError("");
      }, 3000);
    }
  };

  const handleLogout = () => {
    setShowUserMenu(false);
    setIsLoggedIn(false);
    setLoginUsername("");
    setPassword("");
  };

  const handleSaveProfile = () => {
    onUpdateProfile(displayName, username);
    setIsEditingProfile(false);
  };

  const handleCancelEdit = () => {
    setDisplayName(initialDisplayName);
    setUsername(initialUsername);
    setIsEditingProfile(false);
  };

  // Show Register Screen
  if (!isLoggedIn && authView === "register") {
    return (
      <RegisterScreen
        onBack={() => setAuthView("login")}
        onRegisterSuccess={() => {
          setAuthView("login");
          setError("");
        }}
      />
    );
  }

  // Show Forgot Password Screen
  if (!isLoggedIn && authView === "forgotPassword") {
    return (
      <ForgotPasswordScreen
        onBack={() => setAuthView("login")}
        onResetSuccess={() => {
          setAuthView("login");
          setError("");
        }}
      />
    );
  }

  if (!isLoggedIn) {
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
            Multijoueur
          </h1>
        </motion.div>

        {/* Login Form */}
        <div className="relative z-10 flex-1 flex items-center justify-center px-4 md:px-6 lg:px-8 landscape:px-3 py-6 md:py-8 landscape:py-2">
          <motion.div
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 0.1 }}
            className="w-full max-w-md"
          >
            {/* Icon */}
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.2 }}
              className="flex justify-center mb-6 md:mb-8 landscape:mb-3"
            >
              <div className="p-6 md:p-8 landscape:p-4 rounded-full bg-gradient-to-br from-indigo-500 to-purple-600 shadow-lg">
                <User className="size-12 md:size-16 landscape:size-8 text-white" />
              </div>
            </motion.div>

            {/* Title */}
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.3 }}
              className="text-center mb-8 md:mb-10 landscape:mb-4"
            >
              <h2 className="text-3xl md:text-4xl landscape:text-2xl font-bold text-slate-700 mb-2 landscape:mb-1">
                Connexion
              </h2>
              <p className="text-sm md:text-base landscape:text-xs text-slate-500">
                Connecte-toi pour jouer en multijoueur
              </p>
            </motion.div>

            {/* Form */}
            <motion.form
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.4 }}
              onSubmit={handleLogin}
              className="space-y-4 md:space-y-5 landscape:space-y-2"
            >
              {/* Username */}
              <motion.div
                animate={{
                  x: shakeUsername ? [0, -10, 10, -10, 10, -5, 5, 0] : 0
                }}
                transition={{ duration: 0.4 }}
              >
                <div className="relative">
                  <div className="absolute left-4 landscape:left-3 top-1/2 -translate-y-1/2 text-slate-400">
                    <User className="size-5 landscape:size-4" />
                  </div>
                  <input
                    type="text"
                    value={loginUsername}
                    onChange={(e) => setLoginUsername(e.target.value)}
                    placeholder="Email ou nom d'utilisateur"
                    className={`w-full pl-12 landscape:pl-10 pr-4 landscape:pr-3 py-4 md:py-5 landscape:py-2.5 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl text-white placeholder-slate-400 focus:outline-none transition-all text-base landscape:text-sm ${
                      error 
                        ? 'bg-slate-800/90 border-2 border-red-500' 
                        : 'bg-slate-800/90 focus:ring-2 focus:ring-indigo-500'
                    }`}
                  />
                </div>
              </motion.div>

              {/* Password */}
              <motion.div
                animate={{
                  x: shakePassword ? [0, -10, 10, -10, 10, -5, 5, 0] : 0
                }}
                transition={{ duration: 0.4 }}
              >
                <div className="relative">
                  <div className="absolute left-4 landscape:left-3 top-1/2 -translate-y-1/2 text-slate-400">
                    <Lock className="size-5 landscape:size-4" />
                  </div>
                  <input
                    type={showPassword ? "text" : "password"}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    placeholder="Mot de passe"
                    className={`w-full pl-12 landscape:pl-10 pr-12 landscape:pr-10 py-4 md:py-5 landscape:py-2.5 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl text-white placeholder-slate-400 focus:outline-none transition-all text-base landscape:text-sm ${
                      error 
                        ? 'bg-slate-800/90 border-2 border-red-500' 
                        : 'bg-slate-800/90 focus:ring-2 focus:ring-indigo-500'
                    }`}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-4 landscape:right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-300 transition-colors"
                  >
                    {showPassword ? (
                      <EyeOff className="size-5 landscape:size-4" />
                    ) : (
                      <Eye className="size-5 landscape:size-4" />
                    )}
                  </button>
                </div>
              </motion.div>

              {/* Error Message */}
              <AnimatePresence>
                {error && (
                  <motion.div
                    initial={{ opacity: 0, height: 0 }}
                    animate={{ opacity: 1, height: "auto" }}
                    exit={{ opacity: 0, height: 0 }}
                    className="bg-red-500/10 border-2 border-red-500 rounded-xl landscape:rounded-lg p-3 md:p-4 landscape:p-2"
                  >
                    <p className="text-red-500 text-sm md:text-base landscape:text-xs text-center font-semibold">
                      {error}
                    </p>
                  </motion.div>
                )}
              </AnimatePresence>

              {/* Submit Button */}
              <motion.button
                type="submit"
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.98 }}
                className="w-full py-4 md:py-5 landscape:py-2.5 bg-gradient-to-r from-indigo-500 to-purple-600 hover:from-indigo-600 hover:to-purple-700 rounded-2xl md:rounded-3xl landscape:rounded-xl text-white font-semibold text-base md:text-lg landscape:text-sm shadow-lg hover:shadow-xl transition-all"
              >
                Se connecter
              </motion.button>

              {/* Links */}
              <div className="space-y-2 landscape:space-y-1 text-center">
                <button
                  type="button"
                  onClick={() => setAuthView("forgotPassword")}
                  className="block w-full text-indigo-600 hover:text-indigo-700 text-sm md:text-base landscape:text-xs font-medium transition-colors"
                >
                  Mot de passe oublié ?
                </button>
                <button
                  type="button"
                  onClick={() => setAuthView("register")}
                  className="block w-full text-slate-600 hover:text-slate-700 text-sm md:text-base landscape:text-xs font-medium transition-colors"
                >
                  Pas encore de compte ? <span className="text-indigo-600 hover:text-indigo-700">S'inscrire</span>
                </button>
              </div>
            </motion.form>
          </motion.div>
        </div>
      </div>
    );
  }

  // Écran principal après connexion
  return (
    <div className="size-full flex flex-col bg-gradient-to-br from-indigo-50 via-purple-50 to-blue-50">
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        className="flex items-center justify-between p-4 md:p-6 lg:p-8 landscape:p-3"
      >
        <div className="flex items-center gap-4">
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            onClick={onBack}
            className="p-3 landscape:p-2 rounded-2xl landscape:rounded-xl bg-white/60 backdrop-blur-xl shadow-sm hover:shadow-md transition-shadow"
          >
            <ArrowLeft className="size-5 landscape:size-4 text-slate-700" />
          </motion.button>
          <h1 className="text-2xl md:text-3xl landscape:text-xl font-bold bg-gradient-to-r from-indigo-600 via-purple-600 to-blue-600 bg-clip-text text-transparent">
            Multijoueur
          </h1>
        </div>

        {/* User Info */}
        <div className="flex items-center gap-3 landscape:gap-2">
          {/* User Button */}
          <div className="relative">
            <motion.button
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={() => setShowUserMenu(!showUserMenu)}
              className="flex items-center gap-2 px-3 md:px-4 py-2 rounded-full bg-white/60 backdrop-blur-xl text-slate-700 shadow-sm"
            >
              <User className="size-4" />
              <span className="text-sm font-medium hidden md:inline">@{username}</span>
              <ChevronDown className={`size-3 transition-transform ${showUserMenu ? "rotate-180" : ""}`} />
            </motion.button>

            {/* Dropdown Menu */}
            <AnimatePresence>
              {showUserMenu && (
                <motion.div
                  initial={{ opacity: 0, y: -10, scale: 0.95 }}
                  animate={{ opacity: 1, y: 0, scale: 1 }}
                  exit={{ opacity: 0, y: -10, scale: 0.95 }}
                  className="absolute top-full right-0 mt-2 w-48 bg-white/95 backdrop-blur-xl rounded-xl shadow-xl overflow-hidden z-50"
                >
                  <div className="p-3 border-b border-slate-200">
                    <p className="font-bold text-slate-700">{displayName}</p>
                    <p className="text-sm text-slate-500">@{username}</p>
                  </div>
                  <button
                    onClick={() => {
                      setShowUserMenu(false);
                      onNavigateToProfile();
                    }}
                    className="w-full flex items-center gap-3 px-4 py-3 text-left text-slate-700 hover:bg-indigo-50 transition-colors"
                  >
                    <UserCircle2 className="size-4" />
                    <span className="text-sm">Mon Profil</span>
                  </button>
                  <button
                    onClick={() => {
                      setShowUserMenu(false);
                      onNavigateToProfile("friends");
                    }}
                    className="w-full flex items-center gap-3 px-4 py-3 text-left text-slate-700 hover:bg-indigo-50 transition-colors"
                  >
                    <Users className="size-4" />
                    <span className="text-sm">Mes Amis</span>
                  </button>
                  <button
                    onClick={handleLogout}
                    className="w-full flex items-center gap-3 px-4 py-3 text-left text-red-600 hover:bg-red-50 transition-colors"
                  >
                    <LogOut className="size-4" />
                    <span className="text-sm">Déconnexion</span>
                  </button>
                </motion.div>
              )}
            </AnimatePresence>
          </div>

          {/* Friends Count */}
          <div 
            onClick={() => onNavigateToProfile("friends")}
            className="hidden md:flex items-center gap-2 px-3 md:px-4 py-2 rounded-full bg-white/60 backdrop-blur-xl text-slate-700 shadow-sm cursor-pointer hover:bg-white/80 transition-all"
          >
            <Users className="size-4" />
            <span className="text-sm font-medium">{friendsCount} amis</span>
          </div>
        </div>
      </motion.div>

      {/* Content */}
      <div className="relative z-10 flex-1 overflow-y-auto px-4 md:px-6 lg:px-8 landscape:px-3 pb-6">
        {/* Mobile Portrait & Desktop: Stack vertical */}
        <div className="lg:hidden portrait:block landscape:hidden space-y-4 md:space-y-6">
          {/* Create Room Card */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.1 }}
            className="bg-white/70 backdrop-blur-xl rounded-2xl md:rounded-3xl shadow-lg p-4 md:p-6"
          >
            <div className="flex items-start gap-4">
              <div className="flex-shrink-0 p-3 md:p-4 rounded-2xl bg-gradient-to-br from-amber-400 to-orange-500">
                <Home className="size-6 md:size-8 text-white" />
              </div>
              <div className="flex-1">
                <h3 className="text-lg md:text-xl font-bold text-slate-700 mb-2">
                  Créer un salon
                </h3>
                <p className="text-sm md:text-base text-slate-600 mb-4">
                  Lance un salon privé ou public et invite ton groupe.
                </p>
                <motion.button
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  className="flex items-center gap-2 text-indigo-600 font-medium hover:text-indigo-700 transition-colors"
                >
                  <span className="text-sm md:text-base">Ouvrir</span>
                  <ArrowLeft className="size-4 rotate-180" />
                </motion.button>
              </div>
            </div>
          </motion.div>

          {/* Join Room Card */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.15 }}
            className="bg-white/70 backdrop-blur-xl rounded-2xl md:rounded-3xl shadow-lg p-4 md:p-6"
          >
            <div className="flex items-start gap-4">
              <div className="flex-shrink-0 p-3 md:p-4 rounded-2xl bg-gradient-to-br from-orange-500 to-amber-600">
                <Lock className="size-6 md:size-8 text-white" />
              </div>
              <div className="flex-1">
                <h3 className="text-lg md:text-xl font-bold text-slate-700 mb-2">
                  Rejoindre un salon
                </h3>
                <p className="text-sm md:text-base text-slate-600 mb-4">
                  Saisis un code privé ou rejoins une partie publique disponible.
                </p>
                <motion.button
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  className="flex items-center gap-2 text-indigo-600 font-medium hover:text-indigo-700 transition-colors"
                >
                  <span className="text-sm md:text-base">Ouvrir</span>
                  <ArrowLeft className="size-4 rotate-180" />
                </motion.button>
              </div>
            </div>
          </motion.div>

          {/* My Rooms Section */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 }}
            className="bg-white/70 backdrop-blur-xl rounded-2xl md:rounded-3xl shadow-lg p-4 md:p-6"
          >
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <Lock className="size-5 text-indigo-600" />
                <h3 className="text-lg md:text-xl font-bold text-slate-700">
                  Mes salons
                </h3>
              </div>
              <motion.button
                whileHover={{ rotate: 180 }}
                transition={{ duration: 0.3 }}
                className="p-2 rounded-lg hover:bg-indigo-100 transition-colors"
              >
                <RefreshCw className="size-5 text-indigo-600" />
              </motion.button>
            </div>
            <p className="text-sm text-slate-600 mb-6">
              Salons en attente / arrière-plan. Tu peux rejoindre sans les supprimer de la liste.
            </p>
            
            {savedRooms.length === 0 ? (
              <div className="py-12 text-center">
                <p className="text-slate-500">Aucun salon enregistré.</p>
              </div>
            ) : (
              <div className="space-y-3">
                {/* Room items would go here */}
              </div>
            )}
          </motion.div>
        </div>

        {/* Mobile Landscape: 2 colonnes */}
        <div className="hidden landscape:grid lg:hidden grid-cols-2 gap-3 h-full">
          {/* Left column: Create & Join */}
          <div className="flex flex-col gap-3">
            {/* Create Room Card */}
            <motion.div
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.1 }}
              className="bg-white/70 backdrop-blur-xl rounded-xl shadow-lg p-4 flex-1 flex flex-col justify-center"
            >
              <div className="flex items-start gap-3">
                <div className="flex-shrink-0 p-3 rounded-lg bg-gradient-to-br from-amber-400 to-orange-500">
                  <Home className="size-6 text-white" />
                </div>
                <div className="flex-1 min-w-0">
                  <h3 className="text-base font-bold text-slate-700 mb-2">
                    Créer un salon
                  </h3>
                  <p className="text-sm text-slate-600 mb-3">
                    Lance un salon privé ou public.
                  </p>
                  <motion.button
                    whileHover={{ scale: 1.05 }}
                    whileTap={{ scale: 0.95 }}
                    className="flex items-center gap-1 text-indigo-600 font-medium hover:text-indigo-700 transition-colors"
                  >
                    <span className="text-sm">Ouvrir</span>
                    <ArrowLeft className="size-3 rotate-180" />
                  </motion.button>
                </div>
              </div>
            </motion.div>

            {/* Join Room Card */}
            <motion.div
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.15 }}
              className="bg-white/70 backdrop-blur-xl rounded-xl shadow-lg p-4 flex-1 flex flex-col justify-center"
            >
              <div className="flex items-start gap-3">
                <div className="flex-shrink-0 p-3 rounded-lg bg-gradient-to-br from-orange-500 to-amber-600">
                  <Lock className="size-6 text-white" />
                </div>
                <div className="flex-1 min-w-0">
                  <h3 className="text-base font-bold text-slate-700 mb-2">
                    Rejoindre un salon
                  </h3>
                  <p className="text-sm text-slate-600 mb-3">
                    Code privé ou partie publique.
                  </p>
                  <motion.button
                    whileHover={{ scale: 1.05 }}
                    whileTap={{ scale: 0.95 }}
                    className="flex items-center gap-1 text-indigo-600 font-medium hover:text-indigo-700 transition-colors"
                  >
                    <span className="text-sm">Ouvrir</span>
                    <ArrowLeft className="size-3 rotate-180" />
                  </motion.button>
                </div>
              </div>
            </motion.div>
          </div>

          {/* Right column: My Rooms */}
          <motion.div
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ delay: 0.2 }}
            className="bg-white/70 backdrop-blur-xl rounded-xl shadow-lg p-3 flex flex-col"
          >
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-2">
                <Lock className="size-4 text-indigo-600" />
                <h3 className="text-sm font-bold text-slate-700">
                  Mes salons
                </h3>
              </div>
              <motion.button
                whileHover={{ rotate: 180 }}
                transition={{ duration: 0.3 }}
                className="p-1 rounded-lg hover:bg-indigo-100 transition-colors"
              >
                <RefreshCw className="size-4 text-indigo-600" />
              </motion.button>
            </div>
            <p className="text-xs text-slate-600 mb-3">
              Salons en attente. Tu peux rejoindre sans les supprimer.
            </p>
            
            <div className="flex-1 overflow-y-auto">
              {savedRooms.length === 0 ? (
                <div className="flex items-center justify-center h-full">
                  <p className="text-xs text-slate-500">Aucun salon</p>
                </div>
              ) : (
                <div className="space-y-2">
                  {/* Room items would go here */}
                </div>
              )}
            </div>
          </motion.div>
        </div>

        {/* Desktop: Stack vertical (same as mobile portrait) */}
        <div className="hidden lg:block space-y-6">
          {/* Create Room Card */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.1 }}
            className="bg-white/70 backdrop-blur-xl rounded-3xl shadow-lg p-6"
          >
            <div className="flex items-start gap-4">
              <div className="flex-shrink-0 p-4 rounded-2xl bg-gradient-to-br from-amber-400 to-orange-500">
                <Home className="size-8 text-white" />
              </div>
              <div className="flex-1">
                <h3 className="text-xl font-bold text-slate-700 mb-2">
                  Créer un salon
                </h3>
                <p className="text-base text-slate-600 mb-4">
                  Lance un salon privé ou public et invite ton groupe.
                </p>
                <motion.button
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  className="flex items-center gap-2 text-indigo-600 font-medium hover:text-indigo-700 transition-colors"
                >
                  <span className="text-base">Ouvrir</span>
                  <ArrowLeft className="size-4 rotate-180" />
                </motion.button>
              </div>
            </div>
          </motion.div>

          {/* Join Room Card */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.15 }}
            className="bg-white/70 backdrop-blur-xl rounded-3xl shadow-lg p-6"
          >
            <div className="flex items-start gap-4">
              <div className="flex-shrink-0 p-4 rounded-2xl bg-gradient-to-br from-orange-500 to-amber-600">
                <Lock className="size-8 text-white" />
              </div>
              <div className="flex-1">
                <h3 className="text-xl font-bold text-slate-700 mb-2">
                  Rejoindre un salon
                </h3>
                <p className="text-base text-slate-600 mb-4">
                  Saisis un code privé ou rejoins une partie publique disponible.
                </p>
                <motion.button
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  className="flex items-center gap-2 text-indigo-600 font-medium hover:text-indigo-700 transition-colors"
                >
                  <span className="text-base">Ouvrir</span>
                  <ArrowLeft className="size-4 rotate-180" />
                </motion.button>
              </div>
            </div>
          </motion.div>

          {/* My Rooms Section */}
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.2 }}
            className="bg-white/70 backdrop-blur-xl rounded-3xl shadow-lg p-6"
          >
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <Lock className="size-5 text-indigo-600" />
                <h3 className="text-xl font-bold text-slate-700">
                  Mes salons
                </h3>
              </div>
              <motion.button
                whileHover={{ rotate: 180 }}
                transition={{ duration: 0.3 }}
                className="p-2 rounded-lg hover:bg-indigo-100 transition-colors"
              >
                <RefreshCw className="size-5 text-indigo-600" />
              </motion.button>
            </div>
            <p className="text-sm text-slate-600 mb-6">
              Salons en attente / arrière-plan. Tu peux rejoindre sans les supprimer de la liste.
            </p>
            
            {savedRooms.length === 0 ? (
              <div className="py-12 text-center">
                <p className="text-slate-500">Aucun salon enregistré.</p>
              </div>
            ) : (
              <div className="space-y-3">
                {/* Room items would go here */}
              </div>
            )}
          </motion.div>
        </div>
      </div>
    </div>
  );
}
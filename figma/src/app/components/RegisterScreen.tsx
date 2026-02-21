import { motion, AnimatePresence } from "motion/react";
import { ArrowLeft, User, Mail, Lock, Eye, EyeOff } from "lucide-react";
import { useState } from "react";

interface RegisterScreenProps {
  onBack: () => void;
  onRegisterSuccess: () => void;
}

export function RegisterScreen({ onBack, onRegisterSuccess }: RegisterScreenProps) {
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [shakeUsername, setShakeUsername] = useState(false);
  const [shakeEmail, setShakeEmail] = useState(false);
  const [shakePassword, setShakePassword] = useState(false);
  const [shakeConfirmPassword, setShakeConfirmPassword] = useState(false);

  const handleRegister = (e: React.FormEvent) => {
    e.preventDefault();
    
    // Validation
    if (!username || !email || !password || !confirmPassword) {
      setError("Tous les champs sont obligatoires");
      setShakeUsername(true);
      setShakeEmail(true);
      setShakePassword(true);
      setShakeConfirmPassword(true);
      setTimeout(() => {
        setShakeUsername(false);
        setShakeEmail(false);
        setShakePassword(false);
        setShakeConfirmPassword(false);
      }, 400);
      setTimeout(() => setError(""), 3000);
      return;
    }

    if (password !== confirmPassword) {
      setError("Les mots de passe ne correspondent pas");
      setShakePassword(true);
      setShakeConfirmPassword(true);
      setTimeout(() => {
        setShakePassword(false);
        setShakeConfirmPassword(false);
      }, 400);
      setTimeout(() => setError(""), 3000);
      return;
    }

    if (password.length < 6) {
      setError("Le mot de passe doit contenir au moins 6 caractères");
      setShakePassword(true);
      setShakeConfirmPassword(true);
      setTimeout(() => {
        setShakePassword(false);
        setShakeConfirmPassword(false);
      }, 400);
      setTimeout(() => setError(""), 3000);
      return;
    }

    // Success
    setError("");
    onRegisterSuccess();
  };

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
          S'inscrire
        </h1>
      </motion.div>

      {/* Register Form */}
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
            <div className="p-6 md:p-8 landscape:p-4 rounded-full bg-gradient-to-br from-amber-400 to-orange-500 shadow-lg">
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
              Créer un compte
            </h2>
            <p className="text-sm md:text-base landscape:text-xs text-slate-500">
              Rejoins la communauté Dutch
            </p>
          </motion.div>

          {/* Form */}
          <motion.form
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.4 }}
            onSubmit={handleRegister}
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
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="Nom d'utilisateur"
                  className={`w-full pl-12 landscape:pl-10 pr-4 landscape:pr-3 py-4 md:py-5 landscape:py-2.5 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl text-white placeholder-slate-400 focus:outline-none transition-all text-base landscape:text-sm ${
                    error 
                      ? 'bg-slate-800/90 border-2 border-red-500' 
                      : 'bg-slate-800/90 focus:ring-2 focus:ring-amber-500'
                  }`}
                />
              </div>
            </motion.div>

            {/* Email */}
            <motion.div
              animate={{
                x: shakeEmail ? [0, -10, 10, -10, 10, -5, 5, 0] : 0
              }}
              transition={{ duration: 0.4 }}
            >
              <div className="relative">
                <div className="absolute left-4 landscape:left-3 top-1/2 -translate-y-1/2 text-slate-400">
                  <Mail className="size-5 landscape:size-4" />
                </div>
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="Email"
                  className={`w-full pl-12 landscape:pl-10 pr-4 landscape:pr-3 py-4 md:py-5 landscape:py-2.5 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl text-white placeholder-slate-400 focus:outline-none transition-all text-base landscape:text-sm ${
                    error 
                      ? 'bg-slate-800/90 border-2 border-red-500' 
                      : 'bg-slate-800/90 focus:ring-2 focus:ring-amber-500'
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
                      : 'bg-slate-800/90 focus:ring-2 focus:ring-amber-500'
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

            {/* Confirm Password */}
            <motion.div
              animate={{
                x: shakeConfirmPassword ? [0, -10, 10, -10, 10, -5, 5, 0] : 0
              }}
              transition={{ duration: 0.4 }}
            >
              <div className="relative">
                <div className="absolute left-4 landscape:left-3 top-1/2 -translate-y-1/2 text-slate-400">
                  <Lock className="size-5 landscape:size-4" />
                </div>
                <input
                  type={showPassword ? "text" : "password"}
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  placeholder="Confirmer le mot de passe"
                  className={`w-full pl-12 landscape:pl-10 pr-12 landscape:pr-10 py-4 md:py-5 landscape:py-2.5 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl text-white placeholder-slate-400 focus:outline-none transition-all text-base landscape:text-sm ${
                    error 
                      ? 'bg-slate-800/90 border-2 border-red-500' 
                      : 'bg-slate-800/90 focus:ring-2 focus:ring-amber-500'
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
              className="w-full py-4 md:py-5 landscape:py-2.5 bg-gradient-to-r from-amber-400 to-orange-500 hover:from-amber-500 hover:to-orange-600 rounded-2xl md:rounded-3xl landscape:rounded-xl text-white font-semibold text-base md:text-lg landscape:text-sm shadow-lg hover:shadow-xl transition-all"
            >
              Créer mon compte
            </motion.button>

            {/* Link to Login */}
            <div className="text-center pt-2">
              <button
                type="button"
                onClick={onBack}
                className="text-slate-600 hover:text-slate-700 text-sm md:text-base landscape:text-xs font-medium transition-colors"
              >
                Déjà un compte ? <span className="text-indigo-600 hover:text-indigo-700">Se connecter</span>
              </button>
            </div>
          </motion.form>
        </motion.div>
      </div>
    </div>
  );
}

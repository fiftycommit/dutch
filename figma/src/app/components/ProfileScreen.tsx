import { motion, AnimatePresence } from "motion/react";
import { ArrowLeft, User, Lock, Edit, X, Save, UserCircle2, UserX, Users, UserPlus } from "lucide-react";
import { useState } from "react";

interface ProfileScreenProps {
  onBack: () => void;
  displayName: string;
  username: string;
  onUpdateProfile: (displayName: string, username: string) => void;
  initialTab?: ProfileTab;
}

type ProfileTab = "profile" | "friends" | "blocked";

export function ProfileScreen({ onBack, displayName: initialDisplayName, username: initialUsername, onUpdateProfile, initialTab = "profile" }: ProfileScreenProps) {
  const [profileTab, setProfileTab] = useState<ProfileTab>(initialTab);
  const [isEditingProfile, setIsEditingProfile] = useState(false);
  const [displayName, setDisplayName] = useState(initialDisplayName);
  const [username, setUsername] = useState(initialUsername);
  const [showPasswordModal, setShowPasswordModal] = useState(false);

  const handleSaveProfile = () => {
    onUpdateProfile(displayName, username);
    setIsEditingProfile(false);
  };

  const handleCancelEdit = () => {
    setDisplayName(initialDisplayName);
    setUsername(initialUsername);
    setIsEditingProfile(false);
  };

  return (
    <div className="size-full flex flex-col bg-gradient-to-br from-indigo-50 via-purple-50 to-blue-50">
      {/* Header */}
      <div className="bg-gradient-to-r from-amber-400 to-orange-500 p-4 md:p-6 landscape:p-3">
        <div className="flex items-center justify-between mb-4 md:mb-6 landscape:mb-3">
          <motion.button
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            onClick={onBack}
            className="text-white"
          >
            <ArrowLeft className="size-6 landscape:size-5" />
          </motion.button>
          <h1 className="text-xl md:text-2xl landscape:text-lg font-bold text-white">Mon Profil</h1>
          <div className="w-6" />
        </div>

        {/* Tabs */}
        <div className="flex items-center justify-around max-w-md mx-auto">
          <button
            onClick={() => setProfileTab("profile")}
            className={`flex flex-col items-center gap-1 py-2 px-4 landscape:py-1 landscape:px-3 transition-all ${
              profileTab === "profile" ? "opacity-100 border-b-2 border-white" : "opacity-60"
            }`}
          >
            <User className="size-5 md:size-6 landscape:size-4 text-white" />
            <span className="text-xs md:text-sm landscape:text-xs text-white font-medium">Profil</span>
          </button>
          <button
            onClick={() => setProfileTab("friends")}
            className={`flex flex-col items-center gap-1 py-2 px-4 landscape:py-1 landscape:px-3 transition-all ${
              profileTab === "friends" ? "opacity-100 border-b-2 border-white" : "opacity-60"
            }`}
          >
            <Users className="size-5 md:size-6 landscape:size-4 text-white" />
            <span className="text-xs md:text-sm landscape:text-xs text-white font-medium">Amis</span>
          </button>
          <button
            onClick={() => setProfileTab("blocked")}
            className={`flex flex-col items-center gap-1 py-2 px-4 landscape:py-1 landscape:px-3 transition-all ${
              profileTab === "blocked" ? "opacity-100 border-b-2 border-white" : "opacity-60"
            }`}
          >
            <UserX className="size-5 md:size-6 landscape:size-4 text-white" />
            <span className="text-xs md:text-sm landscape:text-xs text-white font-medium">Bloqués</span>
          </button>
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4 md:p-6 lg:p-8 landscape:p-3">
        <div className="max-w-2xl mx-auto landscape:max-w-full">
          {profileTab === "profile" && (
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              className="space-y-4 md:space-y-6 landscape:space-y-3"
            >
              {/* Profile Card */}
              <div className="bg-white/70 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl p-6 md:p-8 landscape:p-4 shadow-lg">
                <div className="flex items-center gap-4 landscape:gap-3 mb-6 landscape:mb-3">
                  <div className="flex-shrink-0 size-16 md:size-20 landscape:size-12 rounded-full bg-gradient-to-br from-amber-400 to-orange-500 flex items-center justify-center text-white text-2xl md:text-3xl landscape:text-lg font-bold">
                    {displayName.charAt(0).toUpperCase()}
                  </div>
                  <div className="flex-1">
                    <h2 className="text-xl md:text-2xl landscape:text-base font-bold text-slate-700">{displayName}</h2>
                    <p className="text-base md:text-lg landscape:text-sm text-indigo-600">@{username}</p>
                  </div>
                  {!isEditingProfile ? (
                    <motion.button
                      whileHover={{ scale: 1.05 }}
                      whileTap={{ scale: 0.95 }}
                      onClick={() => setIsEditingProfile(true)}
                      className="p-3 landscape:p-2 rounded-xl bg-indigo-100 text-indigo-600 hover:bg-indigo-200 transition-colors"
                    >
                      <Edit className="size-5 landscape:size-4" />
                    </motion.button>
                  ) : (
                    <motion.button
                      whileHover={{ scale: 1.05 }}
                      whileTap={{ scale: 0.95 }}
                      onClick={handleCancelEdit}
                      className="p-3 landscape:p-2 rounded-xl bg-slate-100 text-slate-600 hover:bg-slate-200 transition-colors"
                    >
                      <X className="size-5 landscape:size-4" />
                    </motion.button>
                  )}
                </div>

                {/* Edit Form */}
                <AnimatePresence>
                  {isEditingProfile && (
                    <motion.div
                      initial={{ opacity: 0, height: 0 }}
                      animate={{ opacity: 1, height: "auto" }}
                      exit={{ opacity: 0, height: 0 }}
                      className="space-y-4 landscape:space-y-2 pt-4 landscape:pt-2 border-t border-slate-200"
                    >
                      <div>
                        <label className="flex items-center gap-2 text-sm landscape:text-xs text-slate-600 mb-2 landscape:mb-1">
                          <User className="size-4 landscape:size-3" />
                          Nom d'affichage
                        </label>
                        <input
                          type="text"
                          value={displayName}
                          onChange={(e) => setDisplayName(e.target.value)}
                          className="w-full px-4 py-3 landscape:px-3 landscape:py-2 bg-white border border-slate-300 rounded-xl text-slate-700 placeholder-slate-400 focus:outline-none focus:border-indigo-500"
                        />
                      </div>
                      <div>
                        <label className="flex items-center gap-2 text-sm landscape:text-xs text-slate-600 mb-2 landscape:mb-1">
                          <span>@</span>
                          Nom d'utilisateur
                        </label>
                        <input
                          type="text"
                          value={username}
                          onChange={(e) => setUsername(e.target.value)}
                          className="w-full px-4 py-3 landscape:px-3 landscape:py-2 bg-white border border-slate-300 rounded-xl text-slate-700 placeholder-slate-400 focus:outline-none focus:border-indigo-500"
                        />
                      </div>
                      <div className="flex gap-3 landscape:gap-2">
                        <button
                          onClick={handleCancelEdit}
                          className="flex-1 py-3 landscape:py-2 rounded-xl border border-slate-300 text-slate-700 text-sm landscape:text-xs font-medium hover:bg-slate-50 transition-colors"
                        >
                          Annuler
                        </button>
                        <button
                          onClick={handleSaveProfile}
                          className="flex-1 py-3 landscape:py-2 rounded-xl bg-gradient-to-r from-amber-400 to-orange-500 text-white text-sm landscape:text-xs font-medium flex items-center justify-center gap-2 hover:from-amber-500 hover:to-orange-600 transition-all"
                        >
                          <Save className="size-4 landscape:size-3" />
                          Enregistrer
                        </button>
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>

              {/* Security Section */}
              <div className="bg-white/70 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl p-6 md:p-8 landscape:p-4 shadow-lg">
                <h3 className="text-lg md:text-xl landscape:text-base font-bold text-slate-700 mb-4 landscape:mb-3">Sécurité</h3>
                <div className="space-y-3 landscape:space-y-2">
                  <button
                    onClick={() => setShowPasswordModal(true)}
                    className="w-full flex items-center justify-between p-4 landscape:p-3 bg-indigo-50 rounded-xl text-slate-700 hover:bg-indigo-100 transition-colors"
                  >
                    <div className="flex items-center gap-3 landscape:gap-2">
                      <Lock className="size-5 landscape:size-4" />
                      <span className="font-medium text-sm landscape:text-xs">Changer le mot de passe</span>
                    </div>
                    <ArrowLeft className="size-4 landscape:size-3 rotate-180" />
                  </button>
                  <button className="w-full flex items-start gap-3 landscape:gap-2 p-4 landscape:p-3 bg-red-50 rounded-xl text-left hover:bg-red-100 transition-colors">
                    <UserX className="size-5 landscape:size-4 text-red-600 flex-shrink-0 mt-0.5" />
                    <div>
                      <p className="text-red-600 font-medium text-sm landscape:text-xs">Supprimer mon compte</p>
                      <p className="text-xs landscape:text-[10px] text-red-500 mt-1">Action irréversible</p>
                    </div>
                  </button>
                </div>
              </div>
            </motion.div>
          )}

          {profileTab === "friends" && (
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              className="bg-white/70 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl p-6 md:p-8 landscape:p-4 shadow-lg"
            >
              <div className="py-12 md:py-16 landscape:py-8 text-center">
                <Users className="size-12 md:size-16 landscape:size-10 text-indigo-500 mx-auto mb-4 landscape:mb-2" />
                <p className="text-slate-600 text-base md:text-lg landscape:text-sm mb-2 landscape:mb-1">Aucun ami pour le moment.</p>
                <p className="text-sm md:text-base landscape:text-xs text-slate-500">Ajoutez-en avec le bouton + !</p>
                <motion.button
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  className="mt-6 md:mt-8 landscape:mt-4 size-12 md:size-14 landscape:size-10 rounded-full bg-gradient-to-br from-amber-400 to-orange-500 flex items-center justify-center text-white mx-auto shadow-lg hover:shadow-xl transition-shadow"
                >
                  <UserPlus className="size-6 md:size-7 landscape:size-5" />
                </motion.button>
              </div>
            </motion.div>
          )}

          {profileTab === "blocked" && (
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              className="bg-white/70 backdrop-blur-xl rounded-2xl md:rounded-3xl landscape:rounded-xl p-6 md:p-8 landscape:p-4 shadow-lg"
            >
              <div className="py-12 md:py-16 landscape:py-8 text-center">
                <UserX className="size-12 md:size-16 landscape:size-10 text-slate-400 mx-auto mb-4 landscape:mb-2" />
                <p className="text-slate-600 text-base md:text-lg landscape:text-sm">Aucun utilisateur bloqué.</p>
              </div>
            </motion.div>
          )}
        </div>
      </div>

      {/* Password Modal */}
      <AnimatePresence>
        {showPasswordModal && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-4 landscape:p-3"
            onClick={() => setShowPasswordModal(false)}
          >
            <motion.div
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.9 }}
              onClick={(e) => e.stopPropagation()}
              className="w-full max-w-md landscape:max-w-sm bg-white/95 backdrop-blur-xl rounded-2xl landscape:rounded-xl p-6 landscape:p-4"
            >
              <h3 className="text-xl landscape:text-base font-bold text-slate-700 mb-6 landscape:mb-4">
                Changer le mot de passe
              </h3>
              <div className="space-y-4 landscape:space-y-2 mb-6 landscape:mb-4">
                <div>
                  <label className="text-sm landscape:text-xs text-slate-600 mb-2 landscape:mb-1 block">
                    Mot de passe actuel
                  </label>
                  <input
                    type="password"
                    className="w-full px-4 py-3 landscape:px-3 landscape:py-2 bg-white border border-slate-300 rounded-xl text-slate-700 focus:outline-none focus:border-indigo-500"
                  />
                </div>
                <div>
                  <label className="text-sm landscape:text-xs text-slate-600 mb-2 landscape:mb-1 block">
                    Nouveau mot de passe
                  </label>
                  <input
                    type="password"
                    className="w-full px-4 py-3 landscape:px-3 landscape:py-2 bg-white border border-slate-300 rounded-xl text-slate-700 focus:outline-none focus:border-indigo-500"
                  />
                </div>
                <div>
                  <label className="text-sm landscape:text-xs text-slate-600 mb-2 landscape:mb-1 block">
                    Confirmer le nouveau mot de passe
                  </label>
                  <input
                    type="password"
                    className="w-full px-4 py-3 landscape:px-3 landscape:py-2 bg-white border border-slate-300 rounded-xl text-slate-700 focus:outline-none focus:border-indigo-500"
                  />
                </div>
              </div>
              <div className="flex gap-3 landscape:gap-2">
                <button
                  onClick={() => setShowPasswordModal(false)}
                  className="flex-1 py-3 landscape:py-2 rounded-xl border border-slate-300 text-slate-700 text-sm landscape:text-xs font-medium hover:bg-slate-50 transition-colors"
                >
                  Annuler
                </button>
                <button
                  onClick={() => setShowPasswordModal(false)}
                  className="flex-1 py-3 landscape:py-2 rounded-xl bg-gradient-to-r from-amber-400 to-orange-500 text-white text-sm landscape:text-xs font-medium hover:from-amber-500 hover:to-orange-600 transition-all"
                >
                  Confirmer
                </button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
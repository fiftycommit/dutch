import os

# Dictionnaire de "Niveau 2" (Double corruption)
# Basé spécifiquement sur tes extraits
REPLACEMENTS = {
    # --- ACCENTS DOUBLES ---
    "ÃƒÂ©": "é",
    "Ãƒâ€°": "É",
    "ÃƒÂ¨": "è",
    "ÃƒÂª": "ê",
    "ÃƒÂ": "à",
    "ÃƒÂ´": "ô",
    "ÃƒÂ§": "ç",
    
    # --- EMOJIS DOUBLES ---
    "Ã°Å¸Â¤â€“": "🤖", # Robot
    "Ã¢ÂÅ’": "❌",     # Croix rouge
    "Ã¢Å“â€¦": "✅",     # Check vert
    "Ã°Å¸â€œÅ ": "📊", # Graphique
    "Ã°Å¸â€œÂ¢": "📣", # Mégaphone
    "Ã¢ÂÂ±ïÂ¸Â": "⏳", # Sablier
    "Ã°Å¸Â¤â€": "🤔", # Pensif
    "Ã°Å¸ÂÂ": "🏁",   # Drapeau fin
    "Ã°Å¸â€Â": "🔍", # Loupe
    "Ã°Å¸Å½Â¯": "🎯",   # Cible
    "Ã°Å¸Å½Â­": "🎭",   # Masques
    "Ã°Å¸Â§Â ": "🧠",   # Cerveau
    "Ã°Å¸Å½Â´": "🎴",   # Cartes
    "Ã¢Â ": "",         # Espace insécable cassé
}

def clean_file(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()

        new_content = content
        changes = 0
        
        # On applique les corrections
        for bad, good in REPLACEMENTS.items():
            if bad in new_content:
                changes += new_content.count(bad)
                new_content = new_content.replace(bad, good)

        if new_content != content:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print(f"✅ Réparé : {filepath} ({changes} corrections)")
            return True
            
    except Exception as e:
        print(f"⚠️ Erreur sur {filepath}: {e}")
    
    return False

def main():
    target_dir = "lib"
    print(f"🧹 Démarrage du Nettoyage Profond (Niveau 2)...")

    if not os.path.exists(target_dir):
        print("❌ Dossier lib introuvable.")
        return

    for root, _, files in os.walk(target_dir):
        for file in files:
            if file.endswith(".dart"):
                clean_file(os.path.join(root, file))

    print("-" * 30)
    print("🚀 Terminé. Pense à recharger les fichiers dans VS Code !")

if __name__ == "__main__":
    main()
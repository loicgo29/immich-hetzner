# immmichhetzner

**Immich sur Hetzner** — Instance de vérification des sauvegardes photos.

Instance éphémère pour valider que les photos sauvegardées sur la Storage Box Hetzner sont réellement restaurables.

## 🎯 Objectif

- ✅ Déployer Immich sur Hetzner CX23
- ✅ Télécharger l'archive photos (2,4 To) depuis Storage Box
- ✅ Extraire et restaurer la base de données
- ✅ Vérifier que les photos s'affichent correctement
- ✅ Générer un rapport de vérification

## 📊 État

**Status :** 🔵 Initialisation (2026-09-03)

| Composant | État |
|-----------|------|
| Infrastructure Hetzner | ⏳ À déployer |
| Docker Compose | ✅ Prêt |
| Restauration scripts | ✅ Prêt |
| Documentation | ✅ Complet |

## 🚀 Démarrage rapide

### Prérequis

- SSH vers bastion Hetzner : `~/.ssh/hetzner-bastion`
- Accès Storage Box : `~/.ssh/id_ed25519_storagebox`
- Docker installé sur Hetzner
- Credentials Bitwarden « hetzner-immich »

### Déploiement

```bash
# 1. Se connecter à Hetzner
ssh -i ~/.ssh/hetzner-bastion root@157.180.42.146

# 2. Sur Hetzner : cloner le projet
mkdir -p /donnees && cd /donnees
git clone <repo> immich-hetzner
cd immich-hetzner

# 3. Configurer
cp .env.hetzner.template .env.hetzner
# → remplir avec credentials Bitwarden

# 4. Lancer Immich
docker-compose up -d

# 5. Restaurer les photos
./restore-photos.sh all
# → attendre 2-8h

# 6. Accéder
# http://157.180.42.146:3000
```

Voir [DEPLOYMENT.md](DEPLOYMENT.md) pour les détails complets.

## 📁 Structure

```
immmichhetzner/
├── docker-compose.yml          # Immich + PostgreSQL + Redis
├── restore-photos.sh           # Script de restauration
├── .env.hetzner                # Config production
├── .env.example                # Template local
├── DEPLOYMENT.md               # Guide complet
└── README.md                   # Ce fichier
```

## 🔑 Variables d'environnement

| Variable | Valeur | Source |
|----------|--------|--------|
| `DB_USER` | `immich` | Fixe |
| `DB_PASSWORD` | - | Bitwarden |
| `DB_NAME` | `immich` | Fixe |
| `STORAGE_BOX_USER` | `u575742` | Fixe |
| `STORAGE_BOX_HOST` | `u575742.your-storagebox.de` | Fixe |
| `STORAGE_BOX_PORT` | `23` | Fixe |
| `IMMICH_UPLOAD_LOCATION` | `/donnees/immich/library` | Fixe (Hetzner) |

## 🔒 Sécurité

- Pas de credentials en git (`.env*` dans `.gitignore`)
- SSH clé pubkey seulement (pas de mot de passe)
- Storage Box sur port 23 (SFTP, pas HTTP)
- Instance temporaire sans risque de production

## 📚 Documentation

- **DEPLOYMENT.md** — Guide complet (préparation → vérification → nettoyage)
- **restore-photos.sh** — Script auto-commenté
- **docker-compose.yml** — Services Immich, PostgreSQL, Redis

## 🛠️ Troubleshooting

Voir la section "🆘 Troubleshooting" dans [DEPLOYMENT.md](DEPLOYMENT.md).

## ⚠️ Points critiques

- **Ne pas toucher au NAS-logo** — ce projet en est complètement indépendant
- **Ne pas supprimer les archives** de Storage Box sans backup externe
- **Éphémère** — arrêter après vérification (coûts ~0,10 €/jour)
- **Pas de production** — cette instance n'est que pour la vérification

## 📖 Références

- TODO.md (section 🔵 Plan de secours) — Contexte du projet
- transfert-archive-photos.sh — Logique du transfert vers Storage Box
- maisonnettev2 docker-compose patterns

## 🤝 Contribution

Changes doivent respecter :
- ✅ Pas de secrets en git
- ✅ SSH pubkey partout
- ✅ Documentation à jour
- ✅ Tests de restauration avant production

---

**Créé** : 2026-09-03  
**Responsable** : Logo  
**Endpoint Hetzner** : `157.180.42.146`  
**Statut**: 🔵 Initialisation

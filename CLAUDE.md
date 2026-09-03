# CLAUDE.md — immmichhetzner

**Immich sur Hetzner** — Instance de vérification des sauvegardes photos.

Projet **complètement indépendant** du NAS-logo existant. Aucune modification du NAS-logo ne doit être apportée.

## 🎯 Objectif du projet

Valider que les 2,4 To de photos sauvegardées sur la Storage Box Hetzner (`u575742.your-storagebox.de`) sont réellement restaurables via une instance Immich complète.

**Pourquoi c'est important :**
- Une sauvegarde jamais restaurée n'est pas une sauvegarde
- `rclone sync` propage les suppressions : une corruption locale se réplique au cloud
- Ce test rejou la procédure complète de restauration (pas juste une lecture de fichiers)

## 🏗️ Architecture

```
Storage Box (2,4 To)              Hetzner CX23 (157.180.42.146)
├─ Photos archive (tar.gz)   →    ├─ PostgreSQL 16
├─ DB dump (sql.gz)          →    ├─ Redis 7
└─ (SFTP, port 23)                ├─ Immich Server (3001)
                                  ├─ Immich Web (3000)
                                  └─ Immich ML
```

## 🚀 Déploiement

### Étapes

1. **Préparer** — Créer `/donnees` sur Hetzner, cloner le projet
2. **Configurer** — Remplir `.env.hetzner` depuis Bitwarden
3. **Lancer** — `docker-compose -f docker-compose.yml -f docker-compose.hetzner.yml up -d`
4. **Restaurer** — `./restore-photos.sh all` (2-8 heures)
5. **Vérifier** — Accéder à http://157.180.42.146:3000, voir les photos
6. **Nettoyer** — `docker-compose down`, supprimer les volumes

Voir [DEPLOYMENT.md](DEPLOYMENT.md) pour le guide complet.

## 📁 Fichiers clés

| Fichier | Rôle |
|---------|------|
| `docker-compose.yml` | Services Immich + PostgreSQL + Redis (local & Hetzner) |
| `docker-compose.hetzner.yml` | Surcharge pour Hetzner (chemins `/donnees`, ports) |
| `restore-photos.sh` | Script de restauration (download → extract → db-restore → verify) |
| `.env.hetzner.template` | Template prod (à remplir depuis Bitwarden) |
| `.env.example` | Template développement local |
| `DEPLOYMENT.md` | Guide détaillé (préparation → déploiement → vérification) |
| `README.md` | Vue d'ensemble + démarrage rapide |

## 🔑 Credentials

### Bitwarden « hetzner-immich »

```
- DB_PASSWORD    — Mot de passe PostgreSQL Immich
- IMMICH_API_KEY — (généré au premier accès web)
```

### SSH

```
- ~/.ssh/hetzner-bastion          — Clé pour bastion Hetzner
- ~/.ssh/id_ed25519_storagebox    — Clé pour Storage Box
```

### Storage Box

```
- User: u575742
- Host: u575742.your-storagebox.de
- Port: 23 (SFTP)
- Path: backup-aout-2026/
```

## 🔒 Sécurité

- ✅ Pas de secrets en git (`.env*` dans `.gitignore`)
- ✅ SSH pubkey seulement (pas de password)
- ✅ Storage Box sur port 23 (SFTP, pas HTTP)
- ✅ Instance temporaire sans production data
- ✅ Aucune modification du NAS-logo existant

## 🛠️ Commandes utiles

```bash
# Déployer
docker-compose -f docker-compose.yml -f docker-compose.hetzner.yml up -d

# Logs
docker logs immich-server
docker logs immich-web

# Restaurer
./restore-photos.sh download    # Télécharger l'archive
./restore-photos.sh extract     # Extraire
./restore-photos.sh db-restore  # Restaurer la DB
./restore-photos.sh verify      # Vérifier
./restore-photos.sh all         # Tout

# Arrêter
docker-compose down

# État
docker ps
docker ps -a
```

## 📊 Timeline attendue

| Étape | Durée | Cumulé |
|-------|-------|--------|
| Préparation + config | 15 min | 15 min |
| Docker up | 5 min | 20 min |
| Download archive | 2-6 heures | 2h20-6h20 |
| Extract | 30 min | 2h50-6h50 |
| DB Restore | 5 min | 2h55-6h55 |
| Verify | 10 min | 3h05-7h05 |
| **Total** | **~3-7 heures** | - |

## ⚠️ Points critiques

### Ne pas faire

- ❌ Modifier le NAS-logo existant
- ❌ Supprimer les archives Storage Box
- ❌ Laisser l'instance en permanence (coûts)
- ❌ Commiter des secrets `.env` réels

### À vérifier après restauration

- ✅ Photos visibles dans Immich Web UI
- ✅ Nombre de photos > 0 dans `/donnees/immich/library`
- ✅ Base de données contient les métadonnées
- ✅ Rapport de vérification généré

## 🔄 Processus de vérification

Le script `restore-photos.sh` suit ce processus :

1. **Prérequis** — Vérifier Storage Box accessible, Docker OK
2. **Download** — Rsync 2,4 To depuis Storage Box (avec reprise automatique)
3. **Extract** — Dézipper dans `/donnees/immich/library`
4. **DB Restore** — `pg_restore` du dump SQL
5. **Verify** — Compter les photos, vérifier API Immich, générer rapport

Chaque étape peut être relancée indépendamment.

## 🆘 Troubleshooting

| Problème | Solution |
|----------|----------|
| Storage Box injoignable | Vérifier clé SSH, port 23, Hetzner status |
| Archive corrupted | Relancer `restore-photos.sh download` |
| Docker not found | Installer Docker : `curl -fsSL https://get.docker.com \| sh` |
| PostgreSQL restore échoue | Vérifier dump valide, base vierge |
| Immich ne voit pas les photos | Vérifier permissions, redémarrer container |

Voir [DEPLOYMENT.md](DEPLOYMENT.md) pour plus de détails.

## 📚 Références

- **TODO.md** (section 🔵) — Contexte complet du projet
- **transfert-archive-photos.sh** — Logique du transfert initial
- **maisonnettev2 patterns** — docker-compose.hetzner.yml inspiré de maisonnettev2
- **Immich docs** : https://immich.app/docs

## 🤝 Workflow

### Ajouter une fonctionnalité

1. Créer une branche (`git checkout -b feature/...`)
2. Modifier `docker-compose.yml`, `restore-photos.sh`, docs
3. Tester localement et sur Hetzner
4. Aucun secret en git
5. Commit et push

### Restaurer une version

```bash
# Avant de relancer une restauration
docker-compose down
docker volume rm immich-postgres immich-redis immich-library
rm -rf /donnees/immich

# Puis relancer
docker-compose -f docker-compose.yml -f docker-compose.hetzner.yml up -d
./restore-photos.sh all
```

---

**Créé** : 2026-09-03  
**Responsable** : Logo  
**Statut** : 🔵 Initialisation  
**Infrastructure** : Hetzner CX23 (157.180.42.146)  
**Éphémère** : Oui (arrêter après vérification)

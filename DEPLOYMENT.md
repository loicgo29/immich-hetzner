# Immich sur Hetzner — Vérification des Sauvegardes

**Objectif :** Monter une instance Immich éphémère sur Hetzner pour vérifier que les photos sauvegardées sur la Storage Box sont restaurables.

**Statut :** 🔵 Initialisation  
**Créé le :** 2026-09-03  
**Instance Hetzner :** Bastion SSH `157.180.42.146`

---

## Vue d'ensemble

```
Storage Box Hetzner (u575742.your-storagebox.de)
  ├─ backup-aout-2026/
  │   ├─ immich-files-20260703-143501.tar.gz (2,4 To — photos)
  │   └─ immich-db-*.sql.gz (base de données)
  │
  └─→ Hetzner CX23 (157.180.42.146)
      ├─ PostgreSQL 16
      ├─ Redis 7
      ├─ Immich Server (API)
      ├─ Immich Web (Frontend port 3000)
      └─ Immich ML (reconnaissance)
```

### Quoi ne PAS faire

- ❌ Toucher au NAS-logo existant (ce projet en est complètement indépendant)
- ❌ Supprimer les archives de Storage Box
- ❌ Modifier la base de données de production
- ❌ Laisser cette instance active en permanence (elle est éphémère, coûte ~0,07 €/jour)

---

## 1️⃣ Préparation locale

### 1.1 Cloner et configurer

```bash
cd /Volumes/logousb/SSD/Projects/immmichhetzner
git clone <repo>  # Si pas déjà fait
cp .env.example .env.local
```

### 1.2 Remplir les credentials depuis Bitwarden

```bash
# Ouvrir Bitwarden et chercher « hetzner-immich »
# Copier les valeurs dans .env.local :

# DB_PASSWORD=<password depuis Bitwarden>
# STORAGE_BOX_USER=u575742
# STORAGE_BOX_HOST=u575742.your-storagebox.de
# STORAGE_BOX_PORT=23
# STORAGE_BOX_SSH_KEY=$HOME/.ssh/id_ed25519_storagebox
```

### 1.3 Vérifier la connectivité Storage Box

```bash
ssh -p 23 -i ~/.ssh/id_ed25519_storagebox u575742@u575742.your-storagebox.de "ls -la backup-aout-2026/"

# Doit montrer :
# immich-files-20260703-143501.tar.gz (2.4 To)
# immich-db-*.sql.gz
```

---

## 2️⃣ Déploiement sur Hetzner

### 2.1 Se connecter au bastion

```bash
ssh -i ~/.ssh/hetzner-bastion root@157.180.42.146
```

### 2.2 Préparer le serveur

```bash
# Sur Hetzner (bastion)

# Créer le dossier /donnees (volume attaché)
mkdir -p /donnees/immich/{library,upload,backups}

# Créer l'utilisateur immich
useradd -m -s /bin/bash immich 2>/dev/null || true
chown -R immich:immich /donnees/immich

# Installer Docker (si pas déjà fait)
curl -fsSL https://get.docker.com | sh
usermod -aG docker root

# Vérifier
docker --version
```

### 2.3 Cloner ce projet sur Hetzner

```bash
# Toujours sur Hetzner
cd /donnees
git clone <repo> immich-hetzner
cd immich-hetzner
```

### 2.4 Configurer .env.hetzner

```bash
# Sur Hetzner, remplir depuis Bitwarden
cp .env.hetzner.template .env.hetzner
# Éditer avec les vrais credentials
```

### 2.5 Lancer Immich

```bash
# Sur Hetzner
docker-compose -f docker-compose.yml up -d --pull always

# Vérifier
docker ps
docker logs immich-server

# Attendre ~2 minutes que tout démarre
sleep 120
docker exec immich-server curl http://localhost:3001/api/server/health
```

---

## 3️⃣ Restauration des photos

### 3.1 Depuis votre machine locale

```bash
cd /Volumes/logousb/SSD/Projects/immmichhetzner

# Copier le script sur Hetzner
scp -i ~/.ssh/hetzner-bastion restore-photos.sh root@157.180.42.146:/donnees/immich-hetzner/

# Se connecter et lancer la restauration
ssh -i ~/.ssh/hetzner-bastion root@157.180.42.146

# Sur Hetzner :
cd /donnees/immich-hetzner
chmod +x restore-photos.sh
source .env.hetzner
./restore-photos.sh all
```

### 3.2 Étapes de restauration

Le script `.sh all` exécute :

1. **Download** — Télécharge l'archive 2,4 To depuis Storage Box (via rsync, ~2-6h selon la connexion)
2. **Extract** — Dézipppe dans `/donnees/immich/library` (~30 min)
3. **DB Restore** — Restaure PostgreSQL (~5 min)
4. **Verify** — Vérifie que les photos sont visibles (~10 min)

```bash
# Ou faire étape par étape
./restore-photos.sh download    # Juste télécharger
./restore-photos.sh extract     # Juste extraire
./restore-photos.sh db-restore  # Juste la DB
./restore-photos.sh verify      # Juste vérifier
```

### 3.3 Accéder à Immich

Une fois restauré, Immich est accessible sur :

- **Web UI** : `http://157.180.42.146:3000`
- **API** : `http://157.180.42.146:3001/api`

**Premier accès :**
1. Aller sur http://157.180.42.146:3000
2. Créer un compte admin
3. Accepter les photos importées (Immich scaniera `/donnees/immich/library`)

---

## 4️⃣ Vérification

### 4.1 Photos visibles ?

```bash
# Sur Hetzner
ls -la /donnees/immich/library/ | head -20
find /donnees/immich/library -type f -name "*.jpg" | wc -l
```

### 4.2 Base de données restaurée ?

```bash
# Sur Hetzner, dans le container PostgreSQL
docker exec immich-postgres psql -U immich -d immich -c "SELECT COUNT(*) FROM assets;"
```

### 4.3 Rapport de vérification

```bash
# Le script génère un rapport JSON
cat /donnees/immich/.tmp/verification-report.json
```

---

## 5️⃣ Nettoyage (après vérification)

### 5.1 Arrêter Immich

```bash
# Sur Hetzner
docker-compose down
# Les données restent sur /donnees
```

### 5.2 Supprimer les volumes

```bash
# Si vérification OK et tout confirmé
docker volume rm immich-postgres immich-redis immich-library
rm -rf /donnees/immich
```

### 5.3 Destroy le serveur Hetzner (si Terraform)

```bash
# Depuis votre Mac, si vous aviez créé via Terraform
cd /Volumes/logousb/SSD/Projects/immmichhetzner/terraform/
terraform destroy
```

---

## 🔗 Références

- **Storage Box** : `u575742@u575742.your-storagebox.de` (port 23, SFTP)
- **Bastion Hetzner** : `157.180.42.146` (clé : `~/.ssh/hetzner-bastion`)
- **Immich Official** : https://immich.app
- **Docker Compose** : https://docs.docker.com/compose
- **PostgreSQL** : https://www.postgresql.org

---

## 📋 Checklist de déploiement

- [ ] Credentials Bitwarden récupérés
- [ ] SSH vers bastion OK (`ssh -i ~/.ssh/hetzner-bastion root@157.180.42.146`)
- [ ] Storage Box accessible (`ssh -p 23 … u575742@… "ls backup-aout-2026"`)
- [ ] `/donnees` créé sur Hetzner
- [ ] Projet cloné sur Hetzner
- [ ] `.env.hetzner` rempli
- [ ] `docker-compose up -d` réussi
- [ ] `./restore-photos.sh all` lancé et terminé
- [ ] Photos visibles dans Immich Web UI
- [ ] Rapport de vérification généré
- [ ] Nettoyage effectué après vérification

---

## 🆘 Troubleshooting

| Problème | Solution |
|----------|----------|
| `Storage Box injoignable` | Vérifier clé SSH, port 23 ouvert, Hetzner status |
| `Docker: command not found` | Installer Docker avec `curl -fsSL https://get.docker.com \| sh` |
| `rsync: connection refused` | Vérifier `-p 23` correct, clé SSH valide |
| `Archive corrupted` | Relancer `restore-photos.sh download` |
| `PostgreSQL restore échoue` | Vérifier dump SQL valide, base vierge |
| `Immich ne voit pas les photos` | Vérifier permissions `/donnees/immich/library`, redémarrer container |

---

## Notes

- Cette instance est **éphémère** : elle n'a pas vocation à rester en production
- Les coûts sont minimes (~0,05-0,10 €/jour sur CX23)
- **Ne jamais** supprimer les archives de Storage Box sans backup vérifié
- Un test de restauration réussit = les sauvegardes sont fiables

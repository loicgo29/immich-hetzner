# Code Progress — immmichhetzner

**Objectif** : Restaurer 2,2 To de photos Immich du NAS DS124 via Storage Box vers Hetzner CX23

---

## ✅ Avancements

### Phase 1 : Diagnostic et corrections (COMPLÉTÉ)

| Problème | Diagnostic | Solution | Commit |
|----------|-----------|----------|--------|
| Double chemin `IMMICH_LIBRARY` | Script ajoute `/donnees/immich/library` deux fois → `/donnees/immich/library/donnees/immich/library` | Corriger `IMMICH_LIBRARY="${IMMICH_UPLOAD_LOCATION:-.}"` | `81a4b49` |
| Taille archive incorrecte | Template: 2,4 To arrondi, réalité: 2,386 TB | Mise à jour `PHOTO_ARCHIVE_SIZE=2199023255552` | `81a4b49` |
| Chemin Storage Box vague | Quelle est la structure réelle sur Storage Box ? | Exploration : trouvé `backup-aout-2026/` (2,2 TB) | - |

### Phase 2 : Stratégie rsync (ÉVOLUÉE)

**v1** (Rejet) : Archive `.tar.gz` depuis `backup-aout-2026/`
- ❌ Complexité inutile (télécharger 2,2 TB, extraire)
- Raison : Les fichiers sont sur le NAS, pas en archive sur Storage Box

**v2** (Rejet) : Rsync direct NAS (192.168.1.40) → Hetzner
- ✅ Logique correcte : fichiers individuels du DS124
- ❌ Impossible : Hetzner ne peut pas atteindre IP privée 192.168.1.40
- Commit : `238c058` (implémenté mais ne marche pas)

**v3** (ACTUEL) : Rsync Storage Box → Hetzner
- ✅ Storage Box accessible depuis Hetzner (port 23 SFTP)
- ✅ Les 2,2 To du DS124 sont déjà sur Storage Box (transférés par rsync antérieur)
- Besoin : Trouver le chemin exact des fichiers sur Storage Box

### Phase 3 : Transfer NAS → Storage Box (🔴 EN COURS)

**Découverte Storage Box** :
```
228 Gi total
├─ 1.1 TB    AOUT2026/              ← Fichiers incomplets du DS124
├─ 2.2 TB    backup-aout-2026/      ← Archive compressée (non extractible)
└─ 2.9 TB    immich-backup/         ← Ancienne sauvegarde Immich
```

**Solution** : Lancer rsync direct NAS → Storage Box via `rclone`
- macmini n'a que 52 GB libres (besoin 2,2 TB)
- Impossible de passer par stockage local
- `rclone sync` = transfer direct sans intermédiaire

**Remotes rclone configurées** :
```bash
nas-ds124:       sftp 192.168.1.40 (NAS DS124)
storage-box:     sftp u575742.your-storagebox.de:23
```

**Sync lancé** :
```bash
rclone sync --progress \
  nas-ds124:/volume1/backup-6tb/NAS-LOGO-VOLUME/personnes/loic-perso/immich \
  storage-box:AOUT2026/
```

**État** : ⏳ EN COURS (2,2 TB, ~2-4 heures)

**Progression** :
```bash
rclone size storage-box:AOUT2026/
rclone ls storage-box:AOUT2026/ -R | wc -l
```

**Si interruption** :
- Relancer la même commande (reprendra où c'était arrêté)
- rclone sync est idempotent

---

## 🔴 Problèmes rencontrés et solutions

### 1. rclone sync NAS → Storage Box échoue ❌
**Erreur** :
```
CRITICAL: Failed to create file system for "nas-ds124:..."
ssh: subsystem request failed
```

**Cause** : NAS DS124 n'a pas de serveur SFTP activé
- rclone nécessite SFTP
- Le NAS ne supporte peut-être que SSH + rsync

**Solution** : 
- ✅ Vérifier si SSH rsync fonctionne sur NAS
- ✅ Ou activer SFTP sur NAS DS124

### 2. macmini n'a pas assez d'espace ❌
- Disponible : 52 GB
- Besoin : 2,2 TB
- Impossible de stocker les fichiers localement

**Solution adoptée** : rclone sync direct (échoue faute de SFTP)

### 3. Hetzner n'a pas accès au NAS ❌
- 192.168.1.40 = IP privée (réseau local)
- Hetzner = cloud public, pas de route vers réseau local
- SSH hang vers Hetzner (authentification ?)

**Clé SSH trouvée** : `~/.ssh/hetzner-bastion`
- À tester : `ssh -i ~/.ssh/hetzner-bastion deploy@157.180.42.146`

**À vérifier** :
- Hetzner a-t-il VPN/tunnel vers réseau local ?
- Peut-on faire rsync NAS → Storage Box depuis Hetzner ?

---

## 📋 Prochaines étapes

### 1. Attendre fin du sync NAS → Storage Box ⏳
```bash
# Vérifier progression en background
rclone size storage-box:AOUT2026/
rclone ls storage-box:AOUT2026/ -R | wc -l

# Ou relancer pour reprendre si interruption
rclone sync --progress \
  nas-ds124:/volume1/backup-6tb/NAS-LOGO-VOLUME/personnes/loic-perso/immich \
  storage-box:AOUT2026/
```

**Estimé** : 2-4 heures pour 2,2 TB

### 2. Vérifier intégrité (checksums)
```bash
# Générer checksums source
rclone hashsum MD5 \
  nas-ds124:/volume1/backup-6tb/NAS-LOGO-VOLUME/personnes/loic-perso/immich \
  > nas-checksums.md5

# Générer checksums destination
rclone hashsum MD5 storage-box:AOUT2026/ > storage-box-checksums.md5

# Comparer
diff nas-checksums.md5 storage-box-checksums.md5
```

### 3. Mettre à jour `.env.hetzner`
```bash
# Sur Hetzner
ssh deploy@157.180.42.146
cd /donnees/immich-hetzner
```

Éditer `.env.hetzner` :
```
STORAGE_BOX_DIR=AOUT2026
```

### 4. Tester rsync Storage Box → Hetzner
```bash
git pull
./restore-photos.sh test
./restore-photos.sh sync
```

### 5. Vérifier et conclure
```bash
./restore-photos.sh verify
# Doit afficher : nombre de fichiers > 0, Immich API responsive
```

---

## 📊 Timeline et État

| Étape | Durée | État | Notes |
|-------|-------|------|-------|
| Diagnostic chemins | ✅ Fait | ✅ COMPLÉTÉ | Trouvé `AOUT2026/` (1.1 TB) + `backup-aout-2026/` (2.2 TB) |
| Config rclone | ✅ Fait | ✅ COMPLÉTÉ | nas-ds124, storage-box remotes créées |
| Rsync NAS → Storage Box | ⏳ | 🔴 ÉCHOUE | Erreur SFTP (NAS n'a pas subsystem SFTP) |
| Vérif accès Hetzner | ⏳ | 🔴 À TESTER | SSH hang, clé hetzner-bastion trouvée |
| Rsync Storage Box → Hetzner | ⏳ | ⏳ EN ATTENTE | À faire une fois NAS → Storage Box ok |
| Vérification finale | ⏳ | ⏳ EN ATTENTE | Immich health check |
| **TOTAL** | **~3-5 h** | **🔴 BLOQUÉ** | Attendu : Transfer NAS → Storage Box |

---

## 🔑 Clés SSH disponibles

| Clé | Host | User | Port | État |
|-----|------|------|------|------|
| `backup-key` | NAS DS124 (192.168.1.40) | backup | 22 | ✅ Existe |
| `hetzner-bastion` | Hetzner (157.180.42.146) | deploy | 22 | ✅ Existe |
| `id_ed25519_storagebox` | Storage Box | u575742 | 23 | ✅ Existe |
| `hetzner-storagebox` | Storage Box (alt) | ? | 23 | ✅ Existe |
| `synology` | Synology NAS ? | ? | 22 | ✅ Existe |

---

## 🛠️ Solution FINALE : Rsync direct macmini → Storage Box

**NAS DS124 accessible** ✅ depuis macmini (192.168.1.40)  
**Chemin correct** : `/volume1/personnes/loic-perso/immich/` (NOT `/volume1/backup-6tb/`)

### Rsync Workflow

```bash
# ÉTAPE 1 : NAS → macmini
rsync -av --progress --partial --append-verify --timeout=600 \
  -e 'ssh -i ~/.ssh/backup-key' \
  backup@192.168.1.40:/volume1/personnes/loic-perso/immich/ \
  /Volumes/logousb/SSD/Projects/immich-temp/

# ÉTAPE 2 : macmini → Storage Box AOUT2026/
rsync -av --progress --partial --append-verify --timeout=600 \
  -e 'ssh -p 23 -i ~/.ssh/id_ed25519_storagebox' \
  /Volumes/logousb/SSD/Projects/immich-temp/ \
  u575742@u575742.your-storagebox.de:AOUT2026/

# ÉTAPE 3 : Storage Box → Hetzner
ssh -i ~/.ssh/hetzner-bastion deploy@157.180.42.146 \
  "rsync -av --progress --partial \
    -e 'ssh -p 23 -i ~/.ssh/id_ed25519_storagebox' \
    u575742@u575742.your-storagebox.de:AOUT2026/ \
    /donnees/immich/library/"
```

**Durée totale** : ~6-12 heures (2-4h par étape)  
**Risques** : Corruption partielle si interruption → relancer le rsync

### Options rejetées
- ❌ Option A : rclone (NAS n'a pas SFTP subsystem)
- ❌ Option B : Synology (192.168.5.2 timeout, hors ligne)
- ❌ Option C : Hetzner direct (pas accès réseau local)

---

## 🔗 Commits importants

- `81a4b49` — Fix path et archive size
- `6e8f82d` — Fix Storage Box path (v1)
- `419cbd6` — Archive download + extract (v2)
- `238c058` — Direct NAS rsync (v2, rejected)
- **À venir** — Storage Box rsync (v3)

---

## 📝 Notes

- Hetzner IP: 157.180.42.146
- NAS DS124 IP: 192.168.1.40 (privé, inaccessible de Hetzner)
- Storage Box: u575742.your-storagebox.de:23
- Target: /donnees/immich/library (sur Hetzner)
- Source: ? (à confirmer sur Storage Box)

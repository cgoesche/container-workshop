# Portes Ouvertes OVHcloud Montréal
## Création de conteneurs à partir de zéro - Ressources de l'atelier

### Description

Ce guide vous aidera à atteindre les différents objectifs présentés lors de l'atelier et vous offrira une démonstration pratique des mécanismes fondamentaux permettant la création des conteneurs d'aujourd'hui. Nous espérons qu'il vous aidera également à répondre à certaines questions complexes sur ce sujet.

### Prérequis

#### Vérifier le support des namespaces du noyau et de cgroupv2

Pour réussir la création d'un environment similaire a un container, certaines fonctionnalités du noyau doivent être activées sur votre système. Vous pouvez les vérifier en exécutant la commande ci-dessous et en confirmant que la sortie est identique.

```
# namespaces
$ grep -E '^CONFIG_(UTS|USER|PID)_NS' /boot/config-$(uname -r)
CONFIG_UTS_NS=y
CONFIG_USER_NS=y
CONFIG_PID_NS=y

# cgroupv2
$ mount -l | grep cgroup
cgroup2 on /sys/fs/cgroup type cgroup2
```

#### Paramètres du user namespace

Certaines distributions n'autorisent pas la création de namespaces utilisateur par des utilisateurs non privilégiés. La valeur de la sortie doit être supérieure à 0.

```
$ cat /proc/sys/user/max_user_namespaces
# ou
$ sysctl -n user.max_user_namespaces
```

Si la valeur n'est pas supérieure à 0, exécutez la commande suivante :

```
$ sudo sysctl -w user.max_user_namespaces=10000
```

#### Paquets

```
# Fedora/RHEL
$ sudo dnf install mkosi
# Debian/Ubuntu
$ sudo apt install mkosi
```

### Construction du container

Après avoir exécuté les commandes ci-dessous, nous parviendrons à la création d'un conteneur de base non privilégié basé sur Debian 13 (Trixie), avec une connectivité internet et des privilèges de niveau root à l'intérieur du conteneur.

#### Création du système de fichiers racine (rootfs)

La configuration pour mkosi se trouve dans le fichier mkosi.conf.

```
$ mkdir mkosi.output
$ mkosi clean
$ mkosi
```

#### Mappage des identifiants utilisateur/groupe (UID/GID)

Nous allons définir quelques variables d'environnement pour le mappage des identifiants d'utilisateur et de groupe qui seront utiles dans une commande ultérieure.

```
$ cat /etc/subuid
username:524288:65536

$ export START_UID_HOST="524288"
$ export UID_MAP_RANGE_SIZE="65536"

$ cat /etc/subgid
username:524288:65536

$ export START_GID_HOST="524288"
$ export GID_MAP_RANGE_SIZE="65536"
```

Ce qui précède signifie que nous pouvons mapper jusqu'à 65536 UID dans le nouveau namespace utilisateur, en commençant par l'UID 524288 sur l'hôte. Il en va de même pour les GID.

#### Création de nouveaux namespaces

Nous allons créer quatre nouveaux namespaces, à savoir PID, UTS, mount et User, et y lancer bash comme premier processus.

```
$ unshare --fork --kill-child --pid --uts --mount --mount-proc --user --map-users=0:${UID}:1 --map-users=1:${START_HOST_UID}:${UID_MAP_RANGE_SIZE} --map-groups=0:${UID}:1 --map-groups=1:${START_HOST_GID}:${GID_MAP_RANGE_SIZE} bash --norc --noprofile
```

Définissez le drapeau de propagation de montage pour le nouveau namespace de montage de manière récursive sur "private". Ceci est important car nous ne voulons pas que les opérations de montage soient visibles dans le namespace de montage parent (hôte). Cela est également nécessaire pour que pivot_root fonctionne, car l'échange des systèmes de fichiers racines affecterait sinon le namespace de montage de l'hôte et provoquerait une erreur.

```
$ mount --make-rprivate /
```

#### Préparer le nouveau système de fichiers racine

L'outil que nous utiliserons pour échanger le point de montage du système de fichiers racine (pivot_root) nécessite un point de montage réel comme argument pour le "nouveau rootfs". Par conséquent, nous allons transformer le répertoire de notre rootfs en un véritable point de montage pour ensuite effectuer l'échange.

Nous créons également un répertoire oldrootfs où nous monterons l'ancien système de fichiers racine, afin de pouvoir le détacher plus tard.

```
$ cd mkosi.output
$ mount --bind container-rootfs/ container-rootfs/
$ cd container-rootfs/
$ mkdir -p oldrootfs
```

#### Pivoter les systèmes de fichiers racines (Pivot root)

Ici, la racine absolue du nouveau namespace de montage sera le point de montage que nous avons créé pour le nouveau système de fichiers racine.

```
$ /sbin/pivot_root . oldrootfs
cd /
```

#### Monter le système de fichiers proc

Le système de fichiers proc est un pseudo-système de fichiers qui fournit une interface vers les structures de données du noyau, affichant essentiellement des informations sur les processus et le système.

```
$ mount -t proc proc /proc
```

#### Préparer /dev

Ceci est nécessaire car nous ne pouvons pas créer de nœuds de périphériques comme le multiplexeur de terminaux sur le répertoire nu qui est lié au namespace de montage de l'hôte. Par conséquent, nous devons créer une ardoise propre dans notre namespace de montage qui soit facilement supprimable après le démarrage, d'où l'utilisation de tmpfs. L'option nosuid est une mesure de défense en profondeur, car nous ne voulons pas créer de binaires capables d'élever les privilèges sur l'hôte, dans ce cas vers notre propre utilisateur.

```
$ mount -t tmpfs -o mode=755,nosuid tmpfs /dev
```

#### Créer une nouvelle instance de multiplexeur de pseudo-terminal

Avoir une instance de multiplexeur de pseudo-terminaux dédiée à ce nouveau namespace de montage élimine le risque de partager la même que celle de l'hôte, afin de prévenir des problèmes de sécurité imprévus.

```
$ mkdir -p /dev/pts
$ mount -t devpts devpts dev/pts/ -o newinstance,ptmxmode=0666,mode=620
# Beaucoup d'applications cherchent encore l'emplacement hérité `/dev/ptmx` pour créer des pseudo-terminaux
$ ln -s /dev/pts/ptmx /dev/ptmx
```

#### Peupler /dev

Nous empruntons les nodes /dev déjà créés dans le système de fichiers racine de l'hôte et créons un point de montage pour eux dans notre conteneur.

```
$ touch /dev/{null,random,zero}
$ mount --bind /oldrootfs/dev/null /dev/null
$ mount --bind /oldrootfs/dev/random /dev/random
$ mount --bind /oldrootfs/dev/zero /dev/zero
```

Les commandes ci-dessous créent des fichiers qui pointent vers les descripteurs de fichiers 0, 1 et 2 de chaque processus, car le noyau résout dynamiquement self vers le PID du processus appelant.
/dev/{stdin,sdtout,stderr} sont nécessaires au bon fonctionnement des entrées/sorties de certaines commandes comme bash, sed ou grep.

```
$ ln -s /proc/self/fd /dev/fd
$ ln -s /proc/self/fd/0 /dev/stdin
$ ln -s /proc/self/fd/1 /dev/stdout
$ ln -s /proc/self/fd/2 /dev/stderr
```

#### Détacher l'ancien système de fichiers racine de l'hôte de la hiérarchie des fichiers

Cela rendra également invisibles tous les points de montage accessibles via l'ancien système de fichiers racine.

```
$ umount -l /oldrootfs
$ rmdir /oldrootfs
```

#### Réinitialiser le shell dans le nouvel environnement

Cette étape permet de s'assurer que nous exécutons le binaire bash à partir du nouveau système de fichiers racine créé précédemment, en détachant le lien que nous avions avec celui exécuté depuis l'ancien système de fichiers racine. Cela nous donne l'environnement de conteneur propre et isolé dont nous avons besoin.

```
$ exec /bin/bash --norc --noprofile
```

### Configuration des limites d'allocation des ressources

#### Créer un cgroup

```
# Exécuter sur l'hôte
$ sudo mkdir /sys/fs/cgroup/container-group
```

Activer le contrôle des PIDs

```
$ echo "+pids" | sudo tee /sys/fs/cgroup/container-group/cgroup.subtree_control
```

Définir le nombre maximum de processus

```
$ echo 10 | sudo tee /sys/fs/cgroup/container-group/pids.max
```

Ajouter notre nouveau processus (isolé par namespace) au cgroup
```
# Obtenir le PID
$ pgrep unshare
428163

$ pstree -p 428163
unshare(428163)───bash(428166)

# Rajouter le PID au cgroup
$ echo 428166 | sudo tee /sys/fs/cgroup/container-group/cgroup.procs
```

Tester la limite de ressources PID
```
$ for i in {1..10}; do (echo "Proc $i"; sleep 1000; ) &  done
```

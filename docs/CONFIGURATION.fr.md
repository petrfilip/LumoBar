# Guide de configuration — Tuya, Hue, LIFX, Govee, Yeelight

> 🇬🇧 [Read this guide in English](CONFIGURATION.md)

LumoBar gère cinq écosystèmes en parallèle. Vous pouvez en activer un seul
ou les cinq — la liste de lampes est fusionnée et triée par nom.

| Marque | Type d'accès | Internet requis ? |
| --- | --- | --- |
| **Tuya / Smart Life** | Cloud (Access ID + Secret + UID) | Oui |
| **Philips Hue** | Bridge local (LAN) | Non (LAN) |
| **LIFX** | Cloud (token personnel) | Oui |
| **Govee** | Cloud (clé API Developer) | Oui |
| **Yeelight** | LAN direct (mode développeur) | Non (LAN) |

Chaque marque a sa propre section de réglages dans **Réglages → Fournisseurs**.
Sautez directement à la section correspondante :

- [Tuya](#tuya--smart-life)
- [Philips Hue](#philips-hue)
- [LIFX](#lifx)
- [Govee](#govee)
- [Yeelight](#yeelight)

---

## Tuya / Smart Life

LumoBar a besoin de quatre informations pour communiquer avec le cloud
Tuya :

1. Un **Access ID**
2. Un **Access Secret**
3. La **région** de votre compte (Europe, US West, US East, Chine, Inde, …)
4. L'**UID** du compte Tuya / Smart Life qui possède vos lampes

Ce guide vous explique comment obtenir les quatre. Comptez environ cinq
minutes la première fois — c'est à faire une seule fois.

> Tuya renomme parfois certaines sections de son portail. Si un libellé a
> changé, cherchez l'équivalent le plus proche — la procédure de fond est
> stable.

---

## 1. Appairer vos lampes dans l'application mobile

Avant que LumoBar puisse parler à vos lampes, elles doivent être
appairées dans l'écosystème Tuya.

- Installez **Smart Life** ([iOS](https://apps.apple.com/app/smart-life-smart-living/id1115101477) /
  [Android](https://play.google.com/store/apps/details?id=com.tuya.smartlife))
  ou n'importe quelle app Tuya livrée avec vos lampes.
- Créez un compte avec une **adresse email** (pas un numéro de téléphone —
  ça rend le lien cloud plus simple plus tard).
- Appairez vos lampes en suivant les instructions du fabricant. Confirmez
  qu'elles répondent depuis l'app mobile.

Notez :

- L'email/téléphone utilisé.
- Le **pays** choisi à l'inscription. C'est votre **région**.

---

## 2. Créer un projet Tuya IoT Cloud

1. Allez sur <https://iot.tuya.com/> et **connectez-vous** (ou créez un
   compte).
2. Dans la barre latérale gauche, choisissez **Cloud → Development**.
3. Cliquez sur **Create Cloud Project**.
4. Remplissez :
   - **Project name** : ce que vous voulez (ex. `LumoBar`).
   - **Industry** : *Smart Home*.
   - **Development Method** : *Custom Development* (ou *Smart Home* si
     Custom n'est pas dispo).
   - **Data Center** : celui qui correspond à votre région :
     - Europe → *Central Europe Data Center*
     - US West → *Western America Data Center*
     - US East → *Eastern America Data Center*
     - Chine → *China Data Center*
     - Inde → *India Data Center*
5. Cliquez sur **Create**.

Tuya vous demande quels produits API activer. Vérifiez que ceux-ci sont
cochés :

- **IoT Core**
- **Authorization** (parfois nommé *Authorization Token Management*)
- **Smart Home Devices Management**
- **Smart Home Family Management**
- **Smart Home Scene Linkage** (optionnel, pour le support futur des scènes)

Cliquez sur **Authorize**.

---

## 3. Récupérer Access ID et Access Secret

1. Dans votre projet, ouvrez l'onglet **Overview**.
2. Sous **Authorization Key**, copiez :
   - **Access ID / Client ID** → c'est votre **Access ID**.
   - **Access Secret / Client Secret** → c'est votre **Access Secret**.

> Traitez l'Access Secret comme un mot de passe. LumoBar le stocke dans
> le Keychain macOS, jamais en clair.

---

## 4. Lier votre compte Smart Life

Cette étape donne au projet cloud accès aux lampes que vous avez appairées
dans l'app mobile.

1. Ouvrez l'onglet **Devices** de votre projet.
2. Cliquez sur **Link Tuya App Account → Add App Account**.
3. Ouvrez Smart Life sur votre téléphone → onglet **Me** (Moi) → touchez
   l'icône de scan QR (en haut à droite) → scannez le QR code affiché sur le
   site Tuya IoT.
4. Confirmez dans l'app.

La page liste maintenant votre compte lié, avec son **UID**. Copiez-le.

---

## 5. Choisir le bon endpoint

LumoBar remplit automatiquement le champ endpoint quand vous choisissez
une région dans **Réglages**. La correspondance :

| Région | Endpoint |
| --- | --- |
| Europe | `https://openapi.tuyaeu.com` |
| US West | `https://openapi.tuyaus.com` |
| US East | `https://openapi-ueaz.tuyaus.com` |
| Chine | `https://openapi.tuyacn.com` |
| Inde | `https://openapi.tuyain.com` |

Si votre data center n'est pas dans la liste, choisissez **Custom** et
collez l'URL fournie par Tuya dans l'onglet **Overview** de votre projet.

---

## 6. Saisir tout ça dans LumoBar

1. Cliquez sur l'ampoule dans la barre de menu.
2. Ouvrez **Réglages**.
3. Collez :
   - Access ID
   - Access Secret
   - Région (LumoBar remplit l'endpoint)
   - UID
4. Cliquez sur **Enregistrer**.

Le popover bascule sur l'onglet **Lampes** et lance la synchro. En quelques
secondes vos lampes apparaissent avec un toggle d'allumage — et pour les
modèles RGB, un slider de luminosité et un sélecteur de couleur.

---

## Dépannage

### `Identifiants Tuya incomplets`

Un des quatre champs est vide. Rouvrez Réglages et vérifiez que :

- Access ID et Access Secret ne sont pas inversés.
- L'endpoint correspond au data center choisi à la création du projet.
- L'UID n'a pas d'espace en début ou en fin.

### `sign invalid` / HTTP 1004

Quasi systématiquement signe que votre **horloge système est désynchronisée**
(les signatures Tuya incluent un timestamp). Ouvrez **Réglages Système →
Général → Date et heure**, vérifiez que *Régler la date et l'heure
automatiquement* est activé.

### `permission deny` / HTTP 1106

Le projet cloud n'a pas la permission de parler à vos lampes. Rouvrez votre
projet sur le site Tuya IoT, allez dans **Service API → Authorize** et
vérifiez que tous les produits listés à l'étape 2 sont bien activés.

### Les lampes apparaissent mais ne répondent pas / ne changent pas de couleur

Ouvrez la lampe dans Smart Life et confirmez qu'elle répond. Si oui, notez
le modèle de la lampe et ouvrez une
[issue](https://github.com/petrfilip/LumoBar/issues) — certains
firmwares exposent des codes de capacités inhabituels que nous ne gérons
peut-être pas encore.

### Erreurs `token expired`

LumoBar gère le rafraîchissement de token automatiquement. Si l'erreur
persiste, cliquez à nouveau sur **Enregistrer** pour forcer un refresh du
client mis en cache.

### `device offline`

La lampe est hors-ligne côté Tuya. Coupez/rebranchez la lampe et patientez
une minute. LumoBar reflète la vue du cloud ; on ne peut pas joindre une
lampe que le cloud ne joint pas.

---

## FAQ

**LumoBar fonctionne-t-il sans internet ?**

Oui, partiellement : Hue et Yeelight fonctionnent entièrement en LAN local.
Tuya, LIFX et Govee passent par leur cloud respectif.

**Où est stocké mon Access Secret ?**

Dans le Keychain macOS sous le service `LampControl.Tuya`, compte
`tuya-access-secret`. Les autres réglages vivent dans
`~/Library/Application Support/LampControl/settings.json` en JSON brut.

**Puis-je utiliser plusieurs comptes Tuya ?**

Pas encore — l'abstraction multi-fournisseurs de la Phase 2 supportera
plusieurs comptes et plusieurs fournisseurs côte à côte.

**LumoBar supportera-t-il les lampes Bluetooth uniquement ?**

Seules les lampes visibles dans l'API Tuya Cloud sont accessibles. Les
lampes Bluetooth qui ne se synchronisent jamais avec le cloud sont hors
périmètre.

**Où signaler un bug ?**

[GitHub Issues](https://github.com/petrfilip/LumoBar/issues) — merci
d'indiquer la version macOS, la version LumoBar, et le modèle de la
lampe.

---

## Philips Hue

LumoBar parle directement à votre **bridge Hue** sur le réseau local —
aucune dépendance au cloud Hue.

### Étape 1 — Repérer le bridge

1. Branchez le bridge Hue sur votre box internet (câble Ethernet) et
   alimentez-le. La diode du milieu doit être allumée.
2. Vérifiez qu'il est sur le **même réseau Wi-Fi** que votre Mac.
3. Dans LumoBar, ouvrez **Réglages → Fournisseurs → Philips Hue → Détecter
   les bridges**. LumoBar interroge `discovery.meethue.com` et liste les
   bridges visibles. Sélectionnez le vôtre.

> Si la détection ne renvoie rien, saisissez l'IP manuellement (visible dans
> l'app Hue → Réglages → Mes appareils Hue → Bridge → Informations réseau).

### Étape 2 — Appairer LumoBar

1. **Appuyez physiquement sur le gros bouton rond** au centre du bridge Hue.
2. Dans les 30 secondes, cliquez sur **Connecter Hue** dans LumoBar.
3. Une clé d'application est générée et stockée dans le Keychain macOS sous le
   service `LampControl.Hue`.

Vos lampes Hue apparaissent dans l'onglet **Lampes**, avec couleur et
température compatible avec leurs capacités matérielles.

### Dépannage Hue

- **« Bridge Philips Hue non configuré »** — appuyez bien sur le bouton du
  bridge **avant** de cliquer sur Connecter. Recommencez.
- **Aucune lampe détectée** — ouvrez l'app Hue officielle, vérifiez que les
  ampoules apparaissent. Si non, ré-appairez-les dans l'app Hue d'abord.
- **Bridge introuvable sur le LAN** — débranchez/rebranchez le bridge,
  attendez la diode au milieu allumée fixe, et relancez la détection.

---

## LIFX

LIFX expose une API cloud officielle. Il vous faut un **token personnel**.

### Étape 1 — Générer un token

1. Connectez-vous sur <https://cloud.lifx.com/sign_in>.
2. Allez dans **Settings → Personal Access Tokens** (ou directement
   <https://cloud.lifx.com/settings>).
3. Cliquez sur **Generate New Token**, donnez-lui un nom (ex. `LumoBar`).
4. Copiez le token affiché — il ne sera plus jamais montré en clair.

### Étape 2 — Saisir dans LumoBar

1. **Réglages → Fournisseurs → LIFX**.
2. Collez le token dans **Token LIFX**.
3. **Enregistrer et synchroniser**.

Le token est stocké dans le Keychain macOS sous le service `LampControl.LIFX`.
Les lampes apparaissent dans l'onglet **Lampes**.

### Dépannage LIFX

- **HTTP 401 / token invalide** — le token a été révoqué ou mal copié.
  Régénérez-en un.
- **Aucune lampe** — vérifiez que vos ampoules sont bien synchronisées avec
  l'app LIFX officielle (donc visibles dans le cloud LIFX).
- **HTTP 429 (rate limit)** — l'API LIFX limite à ~120 requêtes/minute par
  token. LumoBar rafraîchit toutes les minutes ; si vous spammez les
  contrôles, attendez 30 secondes.

---

## Govee

Govee fournit une API HTTP officielle accessible via une **clé API**
demandée depuis l'app mobile.

### Étape 1 — Demander une clé API

1. Ouvrez l'app **Govee Home** sur iOS ou Android.
2. Allez dans **Mon profil (icône en bas à droite) → menu hamburger ☰ → À
   propos / About Us → Apply for API Key**.
3. Renseignez votre nom et un motif (« macOS menu bar app » suffit).
4. Vous recevez la clé par email sous quelques minutes (parfois quelques
   heures).

### Étape 2 — Saisir dans LumoBar

1. **Réglages → Fournisseurs → Govee**.
2. Collez la **clé API** reçue par email.
3. **Enregistrer et synchroniser**.

La clé est stockée dans le Keychain macOS sous le service `LampControl.Govee`.

### Dépannage Govee

- **HTTP 401 / 403** — la clé API n'est pas active ou a été révoquée. Refaites
  la demande dans l'app Govee Home.
- **HTTP 429** — la limite Govee est de **60 requêtes/minute** par clé.
  Espacez les actions ou attendez la prochaine synchronisation auto.
- **Lampe absente** — Govee n'expose qu'une partie de son catalogue via l'API
  publique. Si l'app Govee Home la pilote mais pas LumoBar, c'est que le
  modèle n'est pas dans la whitelist Govee Developer (ouvrez une issue avec
  le numéro de modèle, mais le contournement est côté Govee).

---

## Yeelight

Yeelight (Xiaomi) expose un protocole **JSON-RPC en LAN** sur le port 55443.
Aucun cloud, aucun token — mais il faut activer **« LAN Control »** sur
chaque ampoule.

### Étape 1 — Activer le mode développeur sur chaque lampe

1. Ouvrez l'app **Yeelight** (iOS / Android).
2. Sélectionnez votre ampoule.
3. Touchez l'icône réglages (⚙) en haut à droite.
4. Activez **LAN Control** (parfois nommé « Mode développeur » ou « Contrôle
   réseau local »).
5. Notez l'**adresse IP** affichée dans **Informations sur l'appareil**.

> À refaire pour chaque ampoule. Si LAN Control n'apparaît pas, mettez à jour
> le firmware de l'ampoule depuis l'app.

### Étape 2 — Saisir dans LumoBar

1. **Réglages → Fournisseurs → Yeelight**.
2. Saisissez l'**IP** (par exemple `192.168.1.42`) — vous pouvez ajouter `:port`
   si votre lampe écoute sur un port custom (rare).
3. Optionnel : un **nom** (sinon LumoBar utilise celui rapporté par la
   lampe).
4. **Ajouter et synchroniser**. Répétez pour chaque ampoule.

La liste est stockée en clair dans
`~/Library/Application Support/LampControl/yeelight-settings.json` (pas de
secret à protéger : il n'y a ni clé ni mot de passe).

### Dépannage Yeelight

- **« Délai dépassé »** — LAN Control est désactivé, ou Mac et lampe ne sont
  pas sur le même réseau (attention aux VLAN invités). Vérifiez avec :

  ```bash
  nc -vz 192.168.1.42 55443
  ```

- **Lampe hors ligne** — débranchez/rebranchez la lampe, attendez 30 secondes,
  cliquez sur **Synchroniser maintenant**.
- **L'IP a changé** — Yeelight prend une IP DHCP. Si votre routeur change le
  bail, supprimez l'ancienne entrée (icône poubelle) et ré-ajoutez avec la
  nouvelle IP. Mieux : réservez une IP dans votre routeur.

# LampControl

> Une seule app de barre de menu pour piloter vos ampoules **Philips Hue,
> LIFX, Tuya / Smart Life, Govee, Yeelight, Nanoleaf et WiZ** depuis macOS.
> Pilote aussi les **Ledvance Smart+ Wi-Fi** et les **Sylvania Smart Wi-Fi**
> via l'intégration Tuya (elles partagent le backend Smart Life). Native,
> légère, en verre liquide, et sécurisée par le Keychain.
>
> 🇬🇧 [Read this README in English](README.md)

[![Dernière release](https://img.shields.io/github/v/release/petrfilip/LampControl?label=release)](https://github.com/petrfilip/LampControl/releases/latest)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](https://www.apple.com/macos/)
[![Licence MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

LampControl vit dans votre barre de menu macOS. Un clic sur l'icône ampoule
suffit pour allumer vos lampes, changer la luminosité, choisir une couleur ou
appliquer une scène à un groupe — sans interrompre ce que vous êtes en train
de faire.

L'app gère **sept écosystèmes en parallèle** :

| Marque | Type d'accès | Internet ? |
| --- | --- | --- |
| Philips Hue | Bridge local (LAN) | Non |
| LIFX | Cloud (token personnel) | Oui |
| Tuya / Smart Life | Cloud (Access ID + Secret + UID) | Oui |
| Govee | Cloud (clé API Developer) | Oui |
| Yeelight | LAN direct (mode développeur) | Non |
| Nanoleaf | LAN local (token d'auth) | Non |
| WiZ | LAN direct (UDP) | Non |

**OEM compatibles (sans config supplémentaire)** : les ampoules Ledvance
Smart+ Wi-Fi et Sylvania Smart Wi-Fi utilisent le backend Tuya / Smart Life.
Appairez-les dans l'app Smart Life, puis elles apparaissent dans LampControl
sous l'intégration Tuya.

Activez-en autant que vous voulez — les lampes de tous les fournisseurs
configurés apparaissent dans une seule liste triée.

---

## Fonctionnalités

- 🪶 **App barre de menu légère** — pas d'icône Dock, pas d'Electron, ~5 Mo.
- 🌐 **Sept fournisseurs dans une seule app** — Hue, LIFX, Tuya, Govee, Yeelight, Nanoleaf, WiZ (couvre aussi Ledvance & Sylvania Smart Wi-Fi via Tuya).
- 💡 **Allumer, varier, recolorer** n'importe quelle ampoule compatible.
- 🎨 **Scènes groupées** — sélectionnez plusieurs lampes RGB et appliquez une
  même couleur.
- 🔁 **Synchro automatique** toutes les 60 secondes, en silence.
- 🔐 **Secrets stockés dans le Keychain** — tokens, clés API et clés bridge ne
  touchent jamais un fichier en clair.
- 🚀 **Auto-update via Sparkle** — un push sur `main`, les utilisateurs sont
  notifiés au prochain lancement.
- 🆓 Open source, licence MIT.

## Installation

### Option A — Télécharger le DMG

1. Récupérez le dernier DMG sur la
  [page Releases](https://github.com/petrfilip/LampControl/releases/latest).
2. Ouvrez `LampControl.dmg` et glissez `LampControl.app` dans `/Applications`.
3. **Au premier lancement — contourner Gatekeeper** (l'app est signée en
   ad-hoc tant qu'on n'a pas d'Apple Developer ID ; voir
   [limites connues](#limites-connues)). Sur macOS 14+ le simple clic droit
   → Ouvrir ne suffit plus :
   1. Double-cliquez sur `LampControl.app` une première fois. macOS affiche
      *« Apple n'a pas pu confirmer que LampControl ne contenait pas… »*.
      Cliquez sur **Terminé** — **pas** *Placer dans la corbeille*.
   2. Ouvrez **Réglages Système → Confidentialité et sécurité**.
   3. Descendez tout en bas, dans la section **Sécurité**. Vous verrez :
      *« LampControl a été bloquée pour protéger votre Mac. »* avec un
      bouton **Ouvrir quand même**.
   4. Cliquez sur **Ouvrir quand même** et authentifiez-vous (Touch ID
      ou mot de passe).
   5. Un nouveau dialog apparaît avec un bouton **Ouvrir** — cliquez
      dessus. L'app se lance et macOS retient votre choix.
4. L'icône ampoule apparaît dans votre barre de menu. Les mises à jour
   livrées via Sparkle ne re-déclenchent pas ce dialog — seul le tout
   premier lancement le fait.

### Option B — Compiler depuis les sources

```bash
git clone https://github.com/petrfilip/LampControl.git
cd LampControl
./scripts/build_app.sh
open dist/LampControl.app
```

Nécessite macOS 13+, les outils ligne de commande Xcode 15.4+, et Swift 5.9+.

## Démarrage rapide

1. Cliquez sur l'ampoule dans votre barre de menu.
2. Ouvrez **Réglages → Fournisseurs**.
3. Choisissez les marques que vous possédez et suivez la section dédiée du
   [guide de configuration](docs/CONFIGURATION.fr.md) :
   - **Tuya** — Access ID + Secret + UID + région (~5 min).
   - **Philips Hue** — détection auto du bridge, appui sur le bouton physique,
     clic sur *Connecter*.
   - **LIFX** — générez un token personnel sur
     [cloud.lifx.com/settings](https://cloud.lifx.com/settings) et collez-le.
   - **Govee** — demandez une clé API depuis l'app Govee Home (*À propos →
     Apply for API Key*).
   - **Yeelight** — activez *LAN Control* sur chaque ampoule dans l'app
     Yeelight, puis ajoutez son IP.
4. Les lampes apparaissent dans l'onglet **Lampes** dès qu'un fournisseur est
   connecté.

Le tutoriel bilingue complet se trouve dans
[docs/CONFIGURATION.fr.md](docs/CONFIGURATION.fr.md) (français) et
[docs/CONFIGURATION.md](docs/CONFIGURATION.md) (anglais).

## Mises à jour automatiques

LampControl utilise [Sparkle](https://sparkle-project.org/) pour les mises à
jour intégrées.

- Ouvrez **Réglages → Mises à jour** pour vérifier manuellement ou activer
  les vérifications/installations automatiques.
- Les mises à jour sont signées avec une clé EdDSA ; seules les releases
  signées par les mainteneurs s'installeront.
- Clic droit sur l'icône barre de menu pour accéder à **Check for Updates…**
  sans ouvrir le popover.

## Roadmap

- **Phase 1** : support Tuya, auto-update, doc bilingue, release publique. ✅
- **Phase 2** : abstraction multi-fournisseurs + Philips Hue, LIFX, Govee,
  Yeelight. ✅
- **Phase 4** : notarisation Apple, installation automatique au lancement,
  onboarding guidé.
- **Phase 5** : localisation (UI anglaise), pont HomeKit, automatisations.

## Limites connues

- 🔓 **Signature ad-hoc uniquement.** Tant qu'aucun Apple Developer ID payant
  n'est en place, Gatekeeper affiche un avertissement au premier lancement.
  Clic droit → *Ouvrir* une fois, macOS retient votre choix.
- 🇫🇷 Les libellés in-app sont actuellement en français ; la localisation
  complète est en route.

## Contribuer

Les PR sont les bienvenues. Merci de lire [CONTRIBUTING.md](CONTRIBUTING.md)
avant d'en ouvrir une.

## Licence

[MIT](LICENSE) © 2026 Hugo Informatique.

LampControl embarque [Sparkle](https://sparkle-project.org/), distribué sous
licence MIT.

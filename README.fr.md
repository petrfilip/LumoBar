# LumoBar

> Une seule app de barre de menu pour piloter vos ampoules **Philips Hue,
> LIFX, Tuya / Smart Life, Govee, Yeelight, Nanoleaf et WiZ** depuis macOS.
> Pilote aussi les **Ledvance Smart+ Wi-Fi** et les **Sylvania Smart Wi-Fi**
> via l'intégration Tuya (elles partagent le backend Smart Life). Native,
> légère, en verre liquide, sécurisée par le Keychain. Gratuite et open
> source, toutes les fonctionnalités débloquées.
>
> 🇬🇧 [Read this README in English](README.md)

[![Dernière release](https://img.shields.io/github/v/release/petrfilip/LumoBar?label=release)](https://github.com/petrfilip/LumoBar/releases/latest)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](https://www.apple.com/macos/)
[![Licence MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

LumoBar vit dans votre barre de menu macOS. Un clic sur l'icône ampoule
suffit pour allumer vos lampes, changer la luminosité, choisir une couleur ou
appliquer une scène à une pièce — sans interrompre ce que vous êtes en train
de faire.

> **LumoBar est un fork de [LampControl](https://github.com/hugoinformatique/LampControl)
> de Hugo Informatique.** Voir [Remerciements](#remerciements) et
> [Différences avec LampControl](#différences-avec-lampcontrol).

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
Appairez-les dans l'app Smart Life, puis elles apparaissent dans LumoBar
sous l'intégration Tuya.

Activez-en autant que vous voulez — les lampes de tous les fournisseurs
configurés apparaissent dans une seule liste.

---

## Fonctionnalités

- 🪶 **App barre de menu légère** — pas d'icône Dock, pas d'Electron, ~5 Mo.
- 🌐 **Sept fournisseurs dans une seule app** — Hue, LIFX, Tuya, Govee, Yeelight, Nanoleaf, WiZ.
- 💡 **Allumer, varier, recolorer et régler le blanc** de n'importe quelle ampoule compatible, en direct pendant le glissement.
- 🏠 **Pièces** — regroupez les lampes, repliez les pièces, réordonnez par glisser-déposer.
- 🎨 **Scènes** — scènes intégrées et personnalisées, capture de l'état actuel d'une pièce pour la restaurer plus tard.
- ⏰ **Automatisations** — programmez scènes, allumage/extinction et éclairage adaptatif à heure fixe.
- 🌅 **Éclairage adaptatif** — température et luminosité suivent un planning quotidien modifiable.
- 🎯 **Modes Concentration** — associez un mode Concentration de macOS à une scène via les automatisations Raccourcis (schéma d'URL `lampcontrol://`).
- 🔐 **Secrets stockés dans le Keychain** — tokens, clés API et clés bridge ne touchent jamais un fichier en clair.
- 🌍 **Interface en anglais, français, espagnol et tchèque.**
- 🚀 **Mises à jour intégrées via Sparkle**, signées EdDSA.
- 🆓 **Gratuite et open source** (MIT) — pas de compte, pas de limite de lampes, pas d'offre payante.

## Différences avec LampControl

LumoBar part de LampControl 1.3.3. Changements apportés par ce fork :

**Supprimé**
- 🔓 **L'offre Premium et l'activation de licence** — pièces, scènes,
  automatisations, éclairage adaptatif et modes Concentration sont accessibles
  à tous, quel que soit le nombre de lampes.
- ⌨️ **Les raccourcis clavier globaux.**

**Nouveau**
- **État Yeelight en direct** via notifications push — les changements faits
  dans d'autres apps ou à l'interrupteur apparaissent immédiatement.
- **Découverte des Yeelight sur le réseau**, qui suit aussi une ampoule quand
  son IP change.
- **Lumière blanche** — pastille blanche et préréglage *Blanc*, envoyés au
  mode température de couleur de la lampe.
- **Planning d'éclairage adaptatif modifiable**, et bouton adaptatif dans
  l'en-tête.
- **Les scènes intégrées deviennent des scènes normales** — modifiables,
  supprimables, et restaurables depuis les Réglages.
- **Réinitialisation complète des réglages** depuis les Réglages.
- **Lancement à l'ouverture de session.**
- **Icône de barre de menu teintée** de la couleur de la lampe active.
- **Couleur, luminosité et température en direct** pendant le glissement des
  curseurs.
- **Localisation tchèque** ; messages d'erreur et d'état localisés eux aussi.
- **Infobulles** pour les contrôles en icône seule.
- **Suite de tests unitaires.**

**Corrigé / amélioré**
- Yeelight : réponses associées par identifiant de requête, décodage de
  couleur correct, mode blanc conservé lors du changement de température,
  commandes fonctionnelles juste après la découverte, temporisation quand une
  ampoule coupe l'écoute push.
- Scènes : les scènes capturées / de pièce restaurent l'état d'alimentation et
  résistent à une lampe en échec ; modifier une scène capturée conserve ses
  instantanés.
- L'éclairage adaptatif convertit pourcentages / Kelvin vers l'échelle native
  de chaque lampe (p. ex. mireds Hue).
- Changer luminosité ou température allume une lampe éteinte ; les aperçus
  échoués sont annulés ; un état périmé n'écrase plus votre valeur ; plus de
  scintillement des curseurs.
- Les automatisations utilisent un seul minuteur annulable avec
  dédoublonnage fiable.
- Les identifiants de mode Concentration sont comparés sans tenir compte de la
  casse ; seuls les modes associés sont listés.
- Le popover s'ouvre sur l'écran dont la barre de menu a été cliquée, à la
  bonne taille, reste ancré à l'icône, et le bouton de fermeture ne quitte
  plus l'app.
- Pièces : l'état replié est conservé ; le glisser-déposer marche pour les
  lampes nouvelles et non assignées.
- Les Réglages n'exigent plus la configuration Tuya si vous utilisez d'autres
  fournisseurs.
- Sparkle ne démarre pas sans clé publique valide ; Sparkle passe en 2.9.5.

## Installation

### Option A — Télécharger le DMG

1. Récupérez le dernier DMG sur la
   [page Releases](https://github.com/petrfilip/LumoBar/releases/latest).
2. Ouvrez `LumoBar-<version>.dmg` et glissez `LumoBar.app` dans
   `/Applications`. Si LampControl était installée, quittez-la et supprimez
   `/Applications/LampControl.app` — LumoBar reprend vos réglages, lampes et
   secrets du Keychain.
3. **Au premier lancement — contourner Gatekeeper** (l'app est signée en
   ad-hoc, sans notarisation ; voir [limites connues](#limites-connues)).
   Sur macOS 14+ le simple clic droit → Ouvrir ne suffit plus :
   1. Double-cliquez sur `LumoBar.app` une première fois. macOS affiche
      *« Apple n'a pas pu confirmer que LumoBar ne contenait pas… »*.
      Cliquez sur **Terminé** — **pas** *Placer dans la corbeille*.
   2. Ouvrez **Réglages Système → Confidentialité et sécurité**.
   3. Descendez tout en bas, dans la section **Sécurité**. Vous verrez :
      *« LumoBar a été bloquée pour protéger votre Mac. »* avec un
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
git clone https://github.com/petrfilip/LumoBar.git
cd LumoBar
./scripts/build_app.sh
open dist/LumoBar.app
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
     Yeelight, puis laissez LumoBar la trouver sur le réseau.
4. Les lampes apparaissent dans l'onglet **Lampes** dès qu'un fournisseur est
   connecté.

Le guide complet se trouve dans
[docs/CONFIGURATION.fr.md](docs/CONFIGURATION.fr.md) (français) et
[docs/CONFIGURATION.md](docs/CONFIGURATION.md) (anglais).

## Mises à jour automatiques

LumoBar utilise [Sparkle](https://sparkle-project.org/) pour les mises à
jour intégrées.

- Ouvrez **Réglages → Mises à jour** pour vérifier manuellement ou activer
  les vérifications/installations automatiques.
- Les mises à jour sont signées avec une clé EdDSA ; seules les releases
  signées par ce fork s'installeront.
- Clic droit sur l'icône barre de menu pour accéder à **Check for Updates…**
  sans ouvrir le popover.

## Limites connues

- 🔓 **Signature ad-hoc uniquement.** L'app n'est pas notarisée, Gatekeeper
  affiche donc un avertissement au premier lancement (voir l'installation
  ci-dessus).
- 🔁 LumoBar garde le même identifiant de bundle que LampControl pour
  reprendre vos réglages existants. Les deux apps ne peuvent donc pas être
  installées côte à côte.

## Contribuer

Issues et PR bienvenues. Merci de lire [CONTRIBUTING.md](CONTRIBUTING.md)
d'abord.

## Remerciements

LumoBar existe grâce à **[Hugo Informatique](https://github.com/hugoinformatique)**,
qui a créé [LampControl](https://github.com/hugoinformatique/LampControl) et
l'a publiée sous licence MIT. L'architecture multi-fournisseurs, les
intégrations, l'interface en verre liquide et l'essentiel de ce que vous voyez
dans l'app sont leur travail. Merci de l'avoir construite et partagée
ouvertement ! 🙏

Pour soutenir le projet d'origine, rendez-vous sur
[LampControl](https://github.com/hugoinformatique/LampControl).

LumoBar embarque aussi [Sparkle](https://sparkle-project.org/) (licence MIT).

## Licence

[MIT](LICENSE) — © 2026 Hugo Informatique (LampControl d'origine),
© 2026 Petr Filip (modifications du fork LumoBar).

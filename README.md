# GitHub PR Bar

A small macOS menu bar app that shows your open GitHub pull requests, grouped by status.

## Requirements

- macOS 14 or newer
- Xcode or Command Line Tools with Swift 6 support
- GitHub CLI installed and authenticated

Install and authenticate GitHub CLI first:

```sh
brew install gh
gh auth login
```

The app reads pull requests through `gh api`, so it uses the same GitHub account and auth state as your local GitHub CLI.

## Install

Clone the repo, then run the installer from the repo root:

```sh
git clone git@github.com:karakanb/github-menubar.git
cd github-menubar
./scripts/install.sh
```

The installer:

- Builds the release binary with SwiftPM.
- Installs it to `~/.local/bin/GitHubPRBar`.
- Creates `~/Library/LaunchAgents/io.github.karakanb.githubmenubar.plist`.
- Starts the app immediately.
- Starts the app automatically on login after a restart.

Logs are written to `~/Library/Logs/GitHubPRBar/`.

## Update

Pull the latest code and rerun the installer:

```sh
git pull
./scripts/install.sh
```

## Uninstall

```sh
./scripts/uninstall.sh
```

## Manual Control

Restart the running app:

```sh
launchctl kickstart -k "gui/$(id -u)/io.github.karakanb.githubmenubar"
```

Stop it until the next login:

```sh
launchctl bootout "gui/$(id -u)/io.github.karakanb.githubmenubar"
```

Start it again:

```sh
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/io.github.karakanb.githubmenubar.plist"
```

## License

No license has been selected yet.

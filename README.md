# RE9 Adaptive Triggers Mod

You can enable the adaptive trigger mod before launching the game or while the game is already running.

## What this is

This mod is pretty simple, but it does the job. The whole thing is fully AI-generated / vibecoded, so yeah, it is a bit rough around the edges, but it works. Quick credit where it is due: I borrowed some code ideas and structure from [uzugu/GTFO_VR_Plugin](https://github.com/uzugu/GTFO_VR_Plugin).

## Download options

- Download the ZIP if you want the fastest option.
- Download the files individually if you want to inspect them before copying anything over.
- The ZIP is faster, but GitHub does not really let you preview what is inside a ZIP, so I also uploaded the files separately for convenience.

## How to install

1. Extract the mod archive.
2. Open RE9's local game files. In Steam, right-click Resident Evil 9 in your library, choose "Manage", and select "Browse local files".
3. Copy `PSVR2Bridge.exe` into the game root folder, next to `re9.exe`.
4. Open the `reframework` folder, then the `autorun` folder, and place both Lua files from the archive there.

## How to enable the mod

### Requirements

- PSVR2Toolkit must be installed and running
- SteamVR must be running when you follow the next steps

1. Launch `PSVR2Bridge.exe` from the game folder.
2. Confirm that the new window shows `[IPC] Handshake: Success`.

## Troubleshooting

If the window shows `[IPC] Connection failed: ConnectionRefused`, close it and make sure that:

- PSVR2Toolkit is installed and configured correctly
- SteamVR is running when you launch `PSVR2Bridge.exe`

Meitar Portable
===============
Based on Gesher

Extract the complete GesherPortable folder, then open Gesher.exe to open the
Control Center. Keep Gesher.exe, portable.marker, App and Data together.
You can drag an APK onto Gesher.exe to install and start it.

App contains the runtime. Data contains your installed Android apps, their data,
settings and logs. Close all Android apps and shut down the Gesher device before
moving the folder or safely ejecting a USB drive. Keep a backup of Data.

Android apps run with your Windows user's permissions; this is not a security
sandbox. Read security-notice.txt (or security-notice.he.txt) before installing
apps. Only install apps you trust.

WebView features need the Microsoft Edge WebView2 Runtime on the host computer.
The portable package does not install system prerequisites. Hardware features
depend on the computer and on the permissions you grant.

Portable mode does not add app shortcuts to the Windows Start menu, change file
associations or register app URL protocols. Internal Android intents still work.
Sign-in flows that return from an external browser through a custom URL scheme
need that scheme to be registered on the host; portable mode does not add it.
Windows notifications can still create per-user AppUserModelID metadata. Windows
and the apps can leave other host records, so portable mode is not a guarantee
that the computer will retain no traces.

The Control Center updater keeps the current portable runtime directory and Data.
To update manually with Setup, select portable mode and choose the existing App
directory (or the runtime directory of a flat portable installation). Back up Data
first. Never install the standard mode over a portable runtime directory.

License: Meitar is offered under the PolyForm Strict License 1.0.0
(noncommercial use only; no distribution, no changes, no new works based on it).
The parts that come from Gesher remain under the Apache License 2.0. See
App\licenses\GESHER-HAMEITARIM-LICENSE.txt and GESHER-APACHE-LICENSE-2.0.txt.

The original Gesher
-------------------
Meitar (until version 1.1.0: Gesher HaMeitarim) is based on Gesher, created by palmoni5, who started it in October 2026 and
wrote the overwhelming majority of it, with other contributors. On 25 November 2026 Gesher moved
to a proprietary license and its repository was closed. Meitar continues from its last
version released under the Apache License 2.0. Thank you to palmoni5 and every contributor.

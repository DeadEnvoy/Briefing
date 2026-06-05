# 2.1.0
**UI**
- Added years elapsed display for when more than 365 days have passed since the outbreak.

**FIXES**
- Fixed a bug where the new world start date was showing default GameTime values instead of the actual date.

**TECHNICAL**
- Adjusted how elapsed days are calculated.
- Expanded the set of recoverable player states.
- The briefing screen can no longer be skipped until text starts printing.
- Player key and movement locks were moved to the end of the function and given proper safety checks.
- Added incompatibility with [Safe User Login](https://steamcommunity.com/sharedfiles/filedetails/?id=3232993626).
- The changelog format was updated to Markdown.

# 2.0.5
- Localization has been updated.
- Minor fixes and improvements.

# 2.0.4
- The audio handling method has been changed.
- Added compatibility with Broadcast Voicer & Vehicle Heater Sound System.
- Fixed an issue where sound was not restored when "Pause game after briefing" was enabled.
- Applied quadratic interpolation for sound fading.

# 2.0.3
- Added compatibility with Moodle Framework.
- Sound handling is now correct, with smoother volume restoration.

# 2.0.2
- Added compatibility with Moodles in Lua.
- Added handling for cases where the game forcibly resumed time when zombies were nearby.
- Added a delay to properly initialize all game resources.
- Added mouse wheel handling during active briefing.

# 2.0.1
- All localization files migrated to the new format.

# 2.0.0
- Added typewriter sound.
- Added controller support.
- Added compatibility with 42.14 & [CLASSIFIED].
- Added multiplayer support (yep, don't be surprised).
- Mod logic has been completely rewritten and the project structure has been improved.
- "Knox County" has been replaced with "Knox Country" to match the official terminology.
- Added a "Pause game after briefing" option.
- Improved current location detection logic.
- Various fixes and improvements.

# 1.1.2
- The mod settings has been updated.
- Mod Load Order Sorter is now required.
- Minor fixes and improvements.

# 1.1.1
- Fixed incorrect settings initialization.

# 1.1.0
- Added option to change date and time format.
- Added option to display days survived instead of counting from outbreak date.
- Added ability to skip screen using ESC, spacebar, or mouse clicks.
- Added debug mode detection with corresponding option.

# 1.0.5
- Added "PauseStart" & "Pause on Start" mod compatibility.

# 1.0.4
- Fixed variable naming typo.
- Fixed music volume state assignment.

# 1.0.3
- Here are some more fixes...

# 1.0.2
- Fixed incorrect calculation when the TimeSinceApo sandbox option is modified.

# 1.0.1
- Added a typewriter effect for text.
- Adjusted the logic for calculating the outbreak's start day.
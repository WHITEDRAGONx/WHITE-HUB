# Permanent WHITE HUB address

Owner requested a versionless public URL. WHITE-HUB already exists as a separate
legacy repository (id 1200853879), while WHITE-HUB-V3 is the modular repository
(id 1232157515). No repository was renamed, deleted or replaced.

Legacy WHITE-HUB main rollback: aade7491fc2cbebfca24764028f3fa29b3ddc9d0.
Preserve WHITE-HUB.lua byte for byte. Add Loader.lua as a permanent public forwarder
and update README/CHANGELOG. It fetches only the existing modular main/Main.lua,
with a timestamp query. No dev loader or private component can be loaded by it.
Development branches, module URLs, backend and Render settings stay unchanged.
Public installation code now uses WHITE-HUB/main/Loader.lua, with no version name.
The old modular Main URL remains valid. No backend deployment or rename needed.

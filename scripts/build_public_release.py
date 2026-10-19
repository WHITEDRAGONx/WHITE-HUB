"""Build a whitelist-only public beta from dev without merging private history."""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PUBLIC_PREVIOUS = '652db568857e2c58c9fa3978ac0925db782e429d'
PUBLIC_DEV_BASE = 'e25ea522deec85758c1c641d55654e37414ec04d'
FILES = ('Webhook.lua', 'Movement.lua', 'ServerHop.lua', 'CombatFarm.lua',
         'StandFarm.lua', 'StandTransfer.lua', 'UIComponents.lua',
         'GameCatalog.lua', 'Settings.lua',
         'AutoPrestigeRuntime.lua', 'Farm.lua', 'AutoPrestige.lua')


def existing_public(path):
    return subprocess.check_output(['git', 'show', PUBLIC_PREVIOUS + ':' + path], cwd=ROOT).decode()


def preserve_public_additions(path, generated):
    """Apply the dev delta without losing later public UI/config additions."""
    base = subprocess.check_output(['git', 'show', PUBLIC_DEV_BASE + ':' + path], cwd=ROOT).decode()
    with tempfile.TemporaryDirectory(prefix='white-public-merge-') as directory:
        paths = [Path(directory) / name for name in ('current', 'base', 'generated')]
        for target, text in zip(paths, (existing_public(path), base, generated)):
            target.write_text(text)
        merged = subprocess.run(['git', 'merge-file', '-p', *map(str, paths)], capture_output=True, text=True)
        if merged.returncode != 0:
            raise RuntimeError('Public merge requires review: ' + path)
        return merged.stdout


def build():
    result = {name: (ROOT / name).read_text() for name in FILES}
    # Owner-authorized performance files retain the latest public sale guards in
    # dev; do not silently republish the old Merchant/pickup baseline.
    result['Inventory.lua'] = (ROOT / 'Inventory.lua').read_text()
    main = (ROOT / 'DevMain.lua').read_text()
    main = main[main.index('-- ====================='):]
    main = main.replace('dev/2026-10-10-autosell-compat/', 'main/')
    main = re.sub(r'    -- Retire the removed E1 scheduler.*?    end\n', '', main, count=1, flags=re.S)
    main = re.sub(r'^    \{ key = "WhiteAI",.*\n', '', main, flags=re.M)
    main = main.replace('"WhiteAI", ', '')
    main = re.sub(r'for _, name in ipairs\(\{[^\n]+\}\) do\n\s+local module = previous\[name\]', 'for _, module in pairs(previous) do', main, count=1)
    main = main.replace('WHITE HUB V3 running.', 'WHITE HUB V5 PUBLIC BETA running.')
    main = '-- WHITE HUB V5 PUBLIC BETA — owner-authorized release; Auto Prestige is experimental.\n' + main
    result['Main.lua'] = main
    ui = (ROOT / 'UI.lua').read_text()
    ui = re.sub(r'^local _whiteAI\s*= nil\n', '', ui, flags=re.M)
    ui = re.sub(r'^    _whiteAI\s*= Modules.WhiteAI\n', '', ui, flags=re.M)
    ui = re.sub(r'^    local AIPage\s*= MakePage\("AIPage"\)\n', '', ui, flags=re.M)
    ui = re.sub(r'^        \{ name="AI DEBUG", page=AIPage \},\n', '', ui, flags=re.M)
    start = ui.index('    -- =====================\n    -- WHITE AI DEBUG PAGE')
    end = ui.index('    -- =====================\n    -- CREDITS PAGE', start)
    ui = ui[:start] + ui[end:]
    ui = ui.replace('QuestPage,SettingsPage,AIPage}', 'QuestPage,SettingsPage}')
    ui = ui.replace('SILVER-V5-20261013-R4', 'SILVER-V5-PUBLIC-BETA-20261013-R4')
    result['UI.lua'] = preserve_public_additions('UI.lua', ui)
    config = (ROOT / 'Config.lua').read_text()
    config = re.sub(r'^    WhiteAI(?:Enabled|Endpoint) = .*\n', '', config, flags=re.M)
    result['Config.lua'] = preserve_public_additions('Config.lua', config)
    result['UIComponents.lua'] = result['UIComponents.lua'].replace(
        "local captions={", "local captions={\n ['Auto Prestige']='Auto prestige (BETA)',")
    for caption in (" ['COPY LATEST PROPOSAL LINK']='COPY PROPOSAL',", " ['SAVE HTTPS ENDPOINT']='SAVE ENDPOINT',", " ['WHITE AI V1 - DIAGNOSTICS']='AI DIAGNOSTICS',"):
        result['UIComponents.lua'] = result['UIComponents.lua'].replace(caption, '')
    result['StandTransfer.lua'] = result['StandTransfer.lua'].replace(
        'dev/2026-10-10-autosell-compat/DevMain.lua', 'main/Main.lua').replace(
        'Only our dev loader is queued.', 'Only our public loader is queued.')
    result['StandFarm.lua'] = result['StandFarm.lua'].replace('reload DevMain', 'reload Main')
    return result


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    if args.destination.resolve() == ROOT:
        parser.error('Use an isolated destination; never overwrite the dev checkout.')
    args.destination.mkdir(parents=True, exist_ok=True)
    for name, content in build().items():
        (args.destination / name).write_text(content)

"""Read unchanged component bodies after module packaging consolidation."""
from pathlib import Path
SECTIONS={
 'UICompact.lua':('UIComponents.lua','Compact'),
 'ChoiceUI.lua':('UIComponents.lua','Choice'),
 'StandV2UI.lua':('UIComponents.lua','Stand'),
 'CatalogRefresh.lua':('GameCatalog.lua','OnlineCatalog'),
 'PrestigeDialogue.lua':('AutoPrestigeRuntime.lua','Dialogue'),
}
def module_source(root,name):
 if name not in SECTIONS: return (Path(root)/name).read_text()
 file,section=SECTIONS[name]
 source=(Path(root)/file).read_text()
 start='-- BEGIN '+section+'\nlocal '+section+' = (function()\n'
 end='\nend)()\n-- END '+section
 return source.split(start,1)[1].split(end,1)[0]

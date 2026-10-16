import sys
from pathlib import Path
from urllib.parse import parse_qs, urlencode

import xbmc
import xbmcaddon
import xbmcgui
import xbmcplugin
import xbmcvfs

from catalogue import ROUTES, load_catalogue, select_games


def run():
    base, handle = sys.argv[0], int(sys.argv[1])
    query = parse_qs(sys.argv[2].lstrip('?'))
    route = query.get('route', [''])[0]
    profile = Path(xbmcvfs.translatePath(xbmcaddon.Addon().getAddonInfo('profile')))

    def url(**values):
        return base + '?' + urlencode(values)

    def item(label, target, folder=False, art=''):
        entry = xbmcgui.ListItem(label=label)
        entry.setArt({'icon': art or 'DefaultProgram.png', 'thumb': art, 'poster': art})
        xbmcplugin.addDirectoryItem(handle, target, entry, isFolder=folder)

    try:
        if route == 'launch':
            selected = query.get('id', [''])[0]
            if selected:
                games = load_catalogue(profile / 'catalogue.json')
                game = next((g for g in games if g['id'] == selected and not g['hidden']), None)
                if game is None:
                    raise ValueError('Game is no longer available in the catalogue')
            hook = profile / 'launch_playnite.py'
            if not hook.is_file():
                xbmcgui.Dialog().ok('Kodi Playnite Bridge', 'Playnite launch is not configured yet.')
            else:
                arguments = ',' + game['id'] if selected else ''
                xbmc.executebuiltin('RunScript("%s"%s)' % (str(hook).replace('"', ''), arguments))
            xbmcplugin.endOfDirectory(handle, succeeded=True, cacheToDisc=False)
            return
        xbmcplugin.setContent(handle, 'files')
        if not route:
            item('Open Playnite', url(route='launch'))
            for key, label in ROUTES.items():
                item(label, url(route=key), folder=True)
        else:
            games = select_games(load_catalogue(profile / 'catalogue.json'), route)
            for game in games:
                item(game['name'], url(route='launch', id=game['id']), art=game['art'])
            if not games:
                item('No games in this folder - open Playnite', url(route='launch'))
    except (OSError, ValueError, KeyError, TypeError) as error:
        xbmc.log('Kodi Playnite Bridge catalogue unavailable: ' + str(error), xbmc.LOGWARNING)
        item('Library unavailable - open Playnite', url(route='launch'))
    xbmcplugin.endOfDirectory(handle, succeeded=True, cacheToDisc=False)


if __name__ == '__main__':
    run()

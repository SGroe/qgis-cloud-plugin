# -*- coding: utf-8 -*-
"""
/***************************************************************************
 QgisCloudPlugin
                                 A QGIS plugin
 Publish maps on qgiscloud.com
                             -------------------
        begin                : 2011-04-04
        copyright            : (C) 2011 by Sourcepole
        email                : pka@sourcepole.ch
 ***************************************************************************/

/***************************************************************************
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 ***************************************************************************/
 This script initializes the plugin, making it known to QGIS.
"""
from __future__ import absolute_import
def name():
    return "QGIS Cloud Plugin"
def description():
    return "Publish maps and share data on qgiscloud.com"
def version():
    return "3.0.0"
def icon():
    return "icon.png"
def qgisMinimumVersion():
    return "2.14"
def qgisMaximumVersion():
    return "3.99"
def author():
  return "Sourcepole"
def classFactory(iface):
    from .qgiscloudplugin import QgisCloudPlugin
    return QgisCloudPlugin(iface, version())

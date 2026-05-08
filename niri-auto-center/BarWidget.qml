import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    readonly property var mainInstance: pluginApi?.mainInstance
    readonly property bool isRunning: mainInstance?.running ?? false
    readonly property bool isEnabled: mainInstance?.cfgEnabled ?? false

    readonly property string screenName: screen ? screen.name : ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)

    readonly property real contentWidth: {
        if (isVertical) return capsuleHeight;
        return indicator.implicitWidth + Style.marginM * 2;
    }
    readonly property real contentHeight: capsuleHeight

    implicitWidth: contentWidth
    implicitHeight: contentHeight

    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        radius: Style.radiusL
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        NIcon {
            id: indicator
            anchors.centerIn: parent
            icon: "focus-target"
            pointSize: Math.round(14 * Style.uiScaleRatio)
            color: mouseArea.containsMouse ? Color.mOnHover : Color.mOnSurface
            opacity: isEnabled ? 1.0 : 0.35
        }
    }

    // Status indicator dot
    Rectangle {
        anchors.bottom: visualCapsule.bottom
        anchors.horizontalCenter: visualCapsule.horizontalCenter
        anchors.bottomMargin: Style.marginXXXS
        width: Math.round(4 * Style.uiScaleRatio)
        height: Math.round(4 * Style.uiScaleRatio)
        radius: Math.round(2 * Style.uiScaleRatio)
        visible: isEnabled
        color: isRunning ? Color.mPrimary : Color.mSecondary
    }

    NPopupContextMenu {
        id: contextMenu

        model: {
            var items = [];
            items.push({
                "label": isEnabled
                    ? pluginApi?.tr("bar.disable")
                    : pluginApi?.tr("bar.enable"),
                "action": "toggle",
                "icon": isEnabled ? "player-pause" : "player-play"
            });
            items.push({
                "label": pluginApi?.tr("bar.settings"),
                "action": "widget-settings",
                "icon": "flask"
            });
            return items;
        }

        onTriggered: action => {
            contextMenu.close();
            PanelService.closeContextMenu(screen);

            if (action === "widget-settings") {
                BarService.openPluginSettings(screen, pluginApi.manifest);
            } else if (action === "toggle" && mainInstance) {
                mainInstance.toggle();
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                mainInstance?.toggle();
            } else if (mouse.button === Qt.RightButton) {
                PanelService.showContextMenu(contextMenu, root, screen);
            }
        }
    }
}

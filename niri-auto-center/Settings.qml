import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null

    readonly property var settings: pluginApi?.pluginSettings ?? ({})
    readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? ({})

    property bool valueEnabled: settings.enabled ?? defaults.enabled ?? true
    property int valueDebounceMs: settings.debounceMs ?? defaults.debounceMs ?? 100

    spacing: Style.marginM

    function saveSettings() {
        if (!pluginApi) return;
        pluginApi.pluginSettings.enabled = root.valueEnabled;
        pluginApi.pluginSettings.debounceMs = root.valueDebounceMs;
        pluginApi.saveSettings();
    }

    // ─── Enable / Disable ───
    NToggle {
        Layout.fillWidth: true
        label: pluginApi?.tr("settings.enabled")
        description: pluginApi?.tr("settings.enabled-desc")
        checked: root.valueEnabled
        onToggled: checked => {
            root.valueEnabled = checked;
            root.saveSettings();
        }
    }

    // ─── Debounce Delay ───
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NLabel {
            label: pluginApi?.tr("settings.debounce", {"value": root.valueDebounceMs})
            description: pluginApi?.tr("settings.debounce-desc")
        }

        NSlider {
            Layout.fillWidth: true
            from: 50
            to: 1000
            value: root.valueDebounceMs
            stepSize: 50
            onMoved: {
                root.valueDebounceMs = Math.round(value);
                root.saveSettings();
                pluginApi?.mainInstance?.restartDaemon();
            }
        }
    }

    // ─── Status ───
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM
        spacing: Style.marginM

        Rectangle {
            width: Math.round(8 * Style.uiScaleRatio)
            height: Math.round(8 * Style.uiScaleRatio)
            radius: Math.round(4 * Style.uiScaleRatio)
            color: {
                const st = pluginApi?.mainInstance?.status ?? "stopped";
                if (st === "running") return Color.mPrimary;
                if (st === "error") return Color.mError;
                return Color.mOutline;
            }
        }

        NText {
            text: {
                const st = pluginApi?.mainInstance?.status ?? "stopped";
                if (st === "running") return pluginApi?.tr("settings.status-running");
                if (st === "error") return pluginApi?.tr("settings.status-error");
                return pluginApi?.tr("settings.status-stopped");
            }
            Layout.fillWidth: true
        }
    }

    // ─── About ───
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM
        spacing: Style.marginXS

        NText {
            text: pluginApi?.tr("settings.about-title")
            font.bold: true
        }

        NText {
            text: pluginApi?.tr("settings.about-credit")
            opacity: 0.7
            pointSize: Style.fontSizeS
        }

        NText {
            text: pluginApi?.tr("settings.about-date", {"date": "2026-05-08"})
            opacity: 0.5
            pointSize: Style.fontSizeXS
        }

        NText {
            text: "v" + (pluginApi?.manifest?.version ?? "1.0.0")
            opacity: 0.5
            pointSize: Style.fontSizeXS
        }
    }
}

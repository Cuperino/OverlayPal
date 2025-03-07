//
// This file is part of OverlayPal ( https://github.com/michel-iwaniec/OverlayPal )
// Copyright (c) 2021 Michel Iwaniec.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import QtQuick 2.12
import QtQuick.Window 2.3
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.3
import QtQuick.Controls.Universal 2.0
import QtQuick.Extras 1.4
import QtQuick.Dialogs 1.1

import nes.overlay.optimiser 1.0

import "const.js" as Const
import "HardwarePalette.js" as HardwarePalette
import "version.js" as Version

Window {
    id: window
    visible: true
    width: 1820
    height: 984
    title: qsTr("OverlayPal (" + Version.VERSION_STRING + ") https://github.com/michel-iwaniec/OverlayPal")
    property var loaderProxy: null
    property var imgComponent: null

    Component.onCompleted: {
        // Adapt window to either a 1080p screen or a less-than-1080p-screen.
        // TODO: Scaling choice needs to be more flexible going forward.
        var activePortion = 0.915;
        var optimalWidth = 1920;
        var optimalHeight = 1080;
        var zoom = 3;
        var uiScale = 1.0;
        if(Screen.width < 1920)
        {
            optimalWidth = Screen.width;
            optimalHeight = Screen.height;
            zoom = 2;
            uiScale = 0.7;
        }
        width = optimalWidth * activePortion;
        height = optimalHeight * activePortion;
        // Set canvas sizes
        var w = 256 * zoom;
        var h = 240 * zoom;
        srcImageGroupBox.contentWidth = w;
        srcImageGroupBox.contentHeight = h;
        dstImageGroupBox.contentWidth = w;
        dstImageGroupBox.contentHeight = h;
        srcImageCanvas.zoom = zoom;
        dstImageCanvas.zoom = zoom;
        paletteGroupBox.contentHeight = h;
        // Set UI scale factor
        uiInteractionRow.scale = uiScale;
    }

    DropArea {
        id: dropArea;
        anchors.fill: parent
        onEntered: (drag) => {
            if(drag.hasUrls && drag.urls.length === 1)
            {
                drag.accepted = true;
            }
            else
            {
                drag.accepted = false;
            }
        }
        onDropped: (drop) => {
            loadImage(drop.urls[0]);
        }
    }

    OverlayPalGuiBackend {
        id: optimiser
        shiftX: 0
        shiftY: 0
        maxBackgroundPalettes: 4
        maxSpritePalettes: 4
        maxSpritesPerScanline: 8
        Component.onCompleted: {
            paletteTableView.hardwarePaletteRGB = optimiser.hardwarePaletteRGB();
        }

        onBackgroundColorChanged: {
            var bgColor = optimiser.backgroundColor;
            var hardwareColorsModel = bgColorComboBox.model;
            for(var i = 0; i < hardwareColorsModel.rowCount(); i++)
            {
                if(parseInt(hardwareColorsModel.data(hardwareColorsModel.index(i, 0)), 16) == bgColor)
                {
                    bgColorComboBox.currentIndex = i;
                }
            }
        }
        onShiftXChanged: xShiftSpinBox.value = shiftX
        onShiftYChanged: yShiftSpinBox.value = shiftY
        onInputImageChanged: {
            var img = Qt.resolvedUrl(optimiser.inputImageData());
            srcImageCanvas.paletteGroupImages[0] = img;
            srcImageCanvas.inputImageUpdated();
            if(optimiser.potentialHardwarePaletteIndexedImage)
            {
                // Indexed images give the option of remapping or not
                mapInputColorsCheckBox.enabled = true
            }
            else
            {
                // RGB images must always do remapping - disable checkbox
                mapInputColorsCheckBox.enabled = false
            }
        }
        onOutputImageChanged: {
            conversionBusy.running = false
            // Re-enable optimisation input controls
            convertImageButton.enabled = !autoConversionCheckBox.checked;
            inputImageGroupBox.enabled = true;
            shiftGroupBox.enabled = true;
            optimisationSettingsGroupBox.enabled = true;
            spriteModeComboBox.enabled = true;
            bgModeComboBox.enabled = true;
            // Set groupbox title to either success message or error string
            if(optimiser.conversionSuccessful)
            {
                var numBackgroundTiles = optimiser.numBackgroundTiles;
                var sprites = optimiser.debugSpritesOverlay();
                dstImageGroupBox.title = "Conversion successful." +
                                         "    BG tiles: " + numBackgroundTiles +
                                         "    Sprites: " + sprites.length;
            }
            else
            {
                dstImageGroupBox.title = "Conversion FAILED! Error: " + optimiser.conversionError;
            }

            // Get each palette as a layer using masks
            for(var i = 0; i < dstImageCanvas.showPaletteGroup.length; i++)
            {
                var img = Qt.resolvedUrl(optimiser.outputImageDataRGBA(1 << i, true));
                dstImageCanvas.paletteGroupImages[i] = img;
            }
            // Get backdrop
            dstImageCanvas.backdropImage = Qt.resolvedUrl(optimiser.outputImageDataRGBA(0x00, false));
            // Get debugging data
            dstImageCanvas.debugNumSourceColorsBackground = optimiser.debugNumSourceColorsBackground();
            dstImageCanvas.debugSourceColorsBackground = optimiser.debugSourceColorsBackground();
            dstImageCanvas.debugDestinationColorsBackground = optimiser.debugDestinationColorsBackground();
            dstImageCanvas.debugPaletteIndicesBackground = optimiser.debugPaletteIndicesBackground();
            dstImageCanvas.debugSprites = optimiser.debugSpritesOverlay();
            // Update dst image to reflect converted image grid
            dstImageCanvas.gridWidth = dstImageCanvas.debugPaletteIndicesBackground[0].length;
            dstImageCanvas.gridHeight = dstImageCanvas.debugPaletteIndicesBackground.length;
            dstImageCanvas.gridCellWidth = Const.NametablePixelWidth / dstImageCanvas.gridWidth;
            dstImageCanvas.gridCellHeight = Const.NametablePixelHeight / dstImageCanvas.gridHeight;
            dstImageCanvas.requestPaint();
            dstImageCanvas.inputImageUpdated();
            // Enable save/export now that output image is valid
            saveImageButton.enabled = true;
            exportImageButton.enabled = true;
        }

        function startImageConversionWrapper()
        {
            // Disable optimisation input controls while running
            convertImageButton.enabled = false;
            inputImageGroupBox.enabled = false;
            shiftGroupBox.enabled = false;
            optimisationSettingsGroupBox.enabled = false;
            spriteModeComboBox.enabled = false;
            bgModeComboBox.enabled = false;
            conversionBusy.running = true;
            dstImageGroupBox.title = "Conversion running...";
            optimiser.startImageConversion();
        }
    }

    Column {
        id: column
        x: 16
        y: 10

        Row {

            GroupBox {
                id: srcImageGroupBox
                padding: 6
                contentHeight: 720
                contentWidth: 768
                title: "Input Image"

                GridLayerCanvas {
                    id: srcImageCanvas
                    visible: true
                }
            }

            GroupBox {
                id: dstImageGroupBox
                padding: 6
                contentHeight: 720
                contentWidth: 768
                title: "Converted image"
                GridLayerCanvas {
                    id: dstImageCanvas
                    visible: true
                    // Busy indicator to show conversion progress
                    BusyIndicator {
                        id: conversionBusy
                        anchors.fill: dstImageCanvas
                        running: false
                    }
                }

            }

            GroupBox {
                id: paletteGroupBox
                width: 200
                padding: 6
                contentHeight: 720
                contentWidth: 128
                transformOrigin: Item.Center
                Layout.fillHeight: true
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                Layout.preferredHeight: 800
                Layout.preferredWidth: 140
                title: qsTr("Generated Palettes")

                TableView {
                    id: paletteTableView
                    x: 0
                    width: 128
                    height: 188
                    interactive: false
                    anchors.fill: parent
                    leftMargin: verticalHeader.implicitWidth
                    topMargin: horizontalHeader.implicitHeight
                    reuseItems: false
                    model: optimiser.paletteModel()
                    property var hardwarePaletteRGB: []

                    Row {
                        id: horizontalHeader
                        y: paletteTableView.contentY
                        z: 2
                        Repeater {
                            model: paletteTableView.columns > 0 ? paletteTableView.columns : 1
                            Label {
                                width: 32
                                height: 40
                                text: optimiser.paletteModel() ? optimiser.paletteModel().headerData(modelData, Qt.Horizontal) : ''
                                color: '#202020'
                                font.pixelSize: 16
                                padding: 8
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                background: Rectangle {
                                    color: "#FFFFFF"
                                    border.color: "#C0C0C0"
                                    border.width: 1
                                }
                            }
                        }
                    }

                    Column {
                        id: verticalHeader
                        x: paletteTableView.contentX
                        z: 2
                        Repeater {
                            model: paletteTableView.rows > 0 ? paletteTableView.rows : 1
                            Label {
                                width: 44
                                height: 32
                                text: optimiser.paletteModel() ? optimiser.paletteModel().headerData(modelData, Qt.Vertical) : ''
                                color: '#202020'
                                font.pixelSize: 16
                                padding: 8
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                background: Rectangle {
                                    color: "#FFFFFF"
                                    border.color: "#C0C0C0"
                                    border.width: 1
                                }
                            }
                        }
                    }

                    delegate: Rectangle {
                        id: cell
                        implicitWidth: 32
                        implicitHeight: 32
                        clip: true
                        border.color: "#808080"
                        border.width: 1
                        color: HardwarePalette.textPalToRGB(display, paletteTableView.hardwarePaletteRGB);
                        Label {
                            text: display
                            color: HardwarePalette.fgTextPalToRGB(display, paletteTableView.hardwarePaletteRGB);
                            font.pixelSize: 16
                            anchors.centerIn: parent
                        }
                    }
                }
            }
        }

        Row {
            id: uiInteractionRow
            height: 180
            anchors.left: parent.left
            transformOrigin: Item.TopLeft
            anchors.leftMargin: 0
            scale: 1.0

            GroupBox {
                id: inputImageGroupBox
                width: 300
                height: 200
                title: qsTr("Input")

                GridLayout {
                    x: 0
                    y: 2
                    rows: 4
                    columns: 2
                    rowSpacing: 0

                    Button {
                        id: loadImageButton
                        text: qsTr("Load PNG image...")
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: 141
                        property int inputImageIndex: 0
                        Component.onCompleted: {
                            loadImageButton.onClicked.connect(loadImageDialog.openDialog);
                        }
                    }

                    CheckBox {
                        id: trackInputImageCheckBox
                        text: qsTr("Track file")
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: 113
                        leftPadding: 0
                        onCheckStateChanged: optimiser.trackInputImage = trackInputImageCheckBox.checked;
                    }

                    CheckBox {
                        id: mapInputColorsCheckBox
                        text: qsTr("Color mapping")
                        leftPadding: 0
                        enabled: true
                        checked: true
                        onCheckStateChanged: {
                            optimiser.mapInputColors = checked
                            uniqueColorsCheckBox.enabled = checked
                        }
                    }

                    ComboBox {
                        id: paletteFlavorComboBox
                        currentIndex: -2
                        displayText: "pal: " + model.data(model.index(currentIndex, 0))
                        textRole: "display"
                        Layout.fillWidth: true
                        rightPadding: 0
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: 118
                        onCurrentIndexChanged: {
                            var model = paletteFlavorComboBox.model
                            optimiser.hardwarePaletteName = model.data(model.index(currentIndex, 0));
                            paletteTableView.hardwarePaletteRGB = optimiser.hardwarePaletteRGB();
                        }
                        Component.onCompleted: {
                            paletteFlavorComboBox.model = optimiser.hardwarePaletteNamesModel();
                        }
                    }

                    CheckBox {
                        id: uniqueColorsCheckBox
                        text: qsTr("Unique colors")
                        leftPadding: 0
                        enabled: true
                        checked: false
                        onCheckStateChanged: optimiser.uniqueColors = checked
                    }

                    Label {
                        id: uniqueColorsEmptyLabel
                        text: qsTr("")
                    }

                    Label {
                        id: bgColorLabel
                        text: qsTr("Background color 0")
                    }

                    ComboBox {
                        id: bgColorComboBox
                        currentIndex: -1
                        displayText: model.data(model.index(currentIndex, 0), Qt.DisplayRole)
                        onCurrentIndexChanged: {
                            var bgColor = parseInt(model.data(model.index(currentIndex, 0), Qt.DisplayRole), 16);
                            optimiser.backgroundColor = bgColor;
                        }
                        Layout.fillHeight: false
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: 118

                        contentItem: Text {
                            text: bgColorComboBox.displayText
                            color: bgColorComboBox.model.data(bgColorComboBox.model.index(bgColorComboBox.currentIndex, 0), Qt.ForegroundRole);
                            font: bgColorComboBox.font
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        delegate: ItemDelegate {
                            width: bgColorComboBox.width
                            contentItem: Text {
                                text: bgColorComboBox.model.data(bgColorComboBox.model.index(index, 0), Qt.DisplayRole);
                                color: bgColorComboBox.model.data(bgColorComboBox.model.index(index, 0), Qt.ForegroundRole);
                                font: bgColorComboBox.font
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                            }
                            background: Rectangle {
                                color: bgColorComboBox.model.data(bgColorComboBox.model.index(index, 0), Qt.BackgroundColorRole);
                            }
                        }

                        background: Rectangle {
                            color: bgColorComboBox.model.data(bgColorComboBox.model.index(bgColorComboBox.currentIndex, 0), Qt.BackgroundColorRole);
                        }

                        Component.onCompleted: {
                            bgColorComboBox.model = optimiser.inputImageColorsModel();
                        }
                    }
                }

            }

            GroupBox {
                id: shiftGroupBox
                x: 507
                width: 200
                height: 200
                padding: 12
                scale: 1
                title: qsTr("Image shift before convert")

                GridLayout {
                    height: 112
                    rowSpacing: -23
                    anchors.bottomMargin: 50
                    anchors.fill: parent
                    columnSpacing: 6
                    rows: 2
                    columns: 2

                    Label {
                        id: label6
                        width: 40
                        height: 40
                        text: qsTr("X")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pointSize: 16
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }

                    SpinBox {
                        id: xShiftSpinBox
                        x: 40
                        from: 0
                        to: 255
                        value: 0
                        leftPadding: 46
                        transformOrigin: Item.Center
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        wrap: true
                        validator: IntValidator {
                            bottom: -255
                            top: 255
                        }
                        valueFromText: function(text, locale) {
                            return (Number.fromLocaleString(locale, text) + 256) % 256;
                        }
                        onValueChanged: optimiser.shiftX = value
                        editable: true
                    }

                    Label {
                        id: label7
                        width: 40
                        height: 40
                        text: qsTr("Y")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pointSize: 16
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    }

                    SpinBox {
                        id: yShiftSpinBox
                        x: 40
                        from: 0
                        to: 239
                        value: 0
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        wrap: true
                        validator: IntValidator {
                            bottom: -239
                            top: 239
                        }
                        valueFromText: function(text, locale) {
                            return (Number.fromLocaleString(locale, text) + 240) % 240;
                        }
                        onValueChanged: optimiser.shiftY = value
                        editable: true
                    }
                }

                Button {
                    id: shiftAutoOptimalButton
                    x: 9
                    y: 122
                    width: 167
                    height: 40
                    text: qsTr("Autodetect optimal")
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 0
                    Component.onCompleted: {
                        shiftAutoOptimalButton.onClicked.connect(optimiser.findOptimalShift);
                    }
                }
            }

            GroupBox {
                id: optimisationSettingsGroupBox
                width: 270
                height: 200
                title: qsTr("Optimization settings")

                GridLayout {
                    x: 10
                    y: 5
                    rows: 3
                    columns: 2

                    Label {
                        id: maxBackgroundPalettesLabel
                        text: qsTr("Max Pal BG")
                    }

                    SpinBox {
                        id: maxBackgroundPalettesSpinBox
                        to: 4
                        value: 4
                        onValueChanged: {
                            optimiser.maxBackgroundPalettes = maxBackgroundPalettesSpinBox.value
                        }
                    }

                    Label {
                        id: maxSpritePalettesLabel
                        text: qsTr("Max Pal SPR")
                    }

                    SpinBox {
                        id: maxSpritePalettesSpinBox
                        to: 4
                        value: 4
                        onValueChanged: {
                            optimiser.maxSpritePalettes = maxSpritePalettesSpinBox.value
                        }
                    }

                    Label {
                        id: maxSpritesPerScanlineLabel
                        text: qsTr("Max SPR/line")
                    }

                    SpinBox {
                        id: maxSpritesPerScanlineSpinBox
                        to: 8
                        value: 8
                        onValueChanged: {
                            optimiser.maxSpritesPerScanline = maxSpritesPerScanlineSpinBox.value
                        }
                    }
                }
            }

            GroupBox {
                id: sizesModeGroupBox
                width: 160
                height: 200
                title: qsTr("Size mode")

                GridLayout {
                    y: 7
                    height: 85
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: 0
                    anchors.leftMargin: 0
                    rows: 2
                    columns: 2

                    Label {
                        id: spriteModeLabel
                        text: qsTr("SPR")
                    }

                    ComboBox {
                        id: spriteModeComboBox
                        width: 0
                        Layout.fillWidth: true
                        model: ["8x16", "8x8"]
                        Layout.fillHeight: false
                        Layout.preferredHeight: 40
                        Layout.preferredWidth: 90
                        onCurrentIndexChanged: {
                            optimiser.spriteHeight = (model[currentIndex] == "8x8" ? 8 : 16);
                        }
                        Component.onCompleted: {
                        }
                    }

                    Label {
                        id: bgModeLabel
                        text: qsTr("BG")
                    }

                    ComboBox {
                        id: bgModeComboBox
                        Layout.fillWidth: true
                        model: ["16x16", "8x8"]
                        Layout.fillHeight: false
                        Layout.preferredHeight: 40
                        Layout.preferredWidth: 90
                        onCurrentIndexChanged: {
                            var w = (model[currentIndex] == "8x8" ? 8 : 16);
                            var h = (model[currentIndex] == "8x8" ? 8 : 16);
                            srcImageCanvas.gridCellWidth = w;
                            srcImageCanvas.gridCellHeight = h;
                            srcImageCanvas.gridWidth = Const.NametablePixelWidth / w;
                            srcImageCanvas.gridHeight = Const.NametablePixelHeight / h;
                            srcImageCanvas.requestPaint();
                            optimiser.cellSize = Qt.size(w, h);
                        }
                        Component.onCompleted: {
                        }
                    }
                }
            }

            GroupBox {
                id: showHideColorsGroupBox
                width: 225
                height: 200
                title: qsTr("Show/hide palette colors")

                GridLayout {
                    width: 200
                    columnSpacing: 2
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.top: parent.top
                    anchors.topMargin: 16
                    rows: 4
                    columns: 2

                    CheckBox {
                        id: palette0_checkBox
                        text: qsTr("BG0")
                        Layout.fillWidth: true
                        Layout.preferredHeight: 21
                        Layout.preferredWidth: 74
                        checked: true
                        onClicked: {
                            dstImageCanvas.showPaletteGroup[0] = checked;
                            dstImageCanvas.requestPaint();
                        }
                    }

                    CheckBox {
                        id: palette4_checkBox
                        width: 128
                        text: qsTr("SPR0")
                        Layout.fillWidth: true
                        Layout.preferredHeight: 21
                        Layout.preferredWidth: 80
                        checked: true
                        onClicked: {
                            dstImageCanvas.showPaletteGroup[4] = checked;
                            dstImageCanvas.requestPaint();
                        }
                    }

                    CheckBox {
                        id: palette1_checkBox
                        text: qsTr("BG1")
                        Layout.fillWidth: true
                        Layout.preferredHeight: 21
                        Layout.preferredWidth: 74
                        checked: true
                        onClicked: {
                            dstImageCanvas.showPaletteGroup[1] = checked;
                            dstImageCanvas.requestPaint();
                        }
                    }

                    CheckBox {
                        id: palette5_checkBox
                        width: 128
                        text: qsTr("SPR1")
                        Layout.fillWidth: true
                        Layout.preferredHeight: 21
                        Layout.preferredWidth: 80
                        checked: true
                        onClicked: {
                            dstImageCanvas.showPaletteGroup[5] = checked;
                            dstImageCanvas.requestPaint();
                        }
                    }

                    CheckBox {
                        id: palette2_checkBox
                        text: qsTr("BG2")
                        Layout.fillWidth: true
                        Layout.preferredHeight: 21
                        Layout.preferredWidth: 74
                        checked: true
                        onClicked: {
                            dstImageCanvas.showPaletteGroup[2] = checked;
                            dstImageCanvas.requestPaint();
                        }
                    }

                    CheckBox {
                        id: palette6_checkBox
                        width: 128
                        text: qsTr("SPR2")
                        Layout.fillWidth: true
                        Layout.preferredHeight: 21
                        Layout.preferredWidth: 80
                        checked: true
                        onClicked: {
                            dstImageCanvas.showPaletteGroup[6] = checked;
                            dstImageCanvas.requestPaint();
                        }
                    }

                    CheckBox {
                        id: palette3_checkBox
                        text: qsTr("BG3")
                        Layout.fillWidth: true
                        Layout.preferredHeight: 21
                        Layout.preferredWidth: 74
                        checked: true
                        onClicked: {
                            dstImageCanvas.showPaletteGroup[3] = checked;
                            dstImageCanvas.requestPaint();
                        }
                    }

                    CheckBox {
                        id: palette7_checkBox
                        width: 128
                        text: qsTr("SPR3")
                        Layout.fillWidth: true
                        Layout.preferredHeight: 21
                        Layout.preferredWidth: 80
                        checked: true
                        onClicked: {
                            dstImageCanvas.showPaletteGroup[7] = checked;
                            dstImageCanvas.requestPaint();
                        }
                    }
                }
            }

            GroupBox {
                id: gridCellDebugGroupBox
                width: 360
                height: 200
                spacing: 6
                title: qsTr("Grid Cell Debug Mode")

                ButtonGroup { id: gridCellDebugButtonGroup }

                RadioButton {
                    id: gridCellOffRadioButton
                    x: 6
                    y: -9
                    text: qsTr("Off")
                    checked: true
                    ButtonGroup.group: gridCellDebugButtonGroup
                    onClicked: {
                        dstImageCanvas.cellDebugMode = 'off';
                    }

                    Connections {
                        target: gridCellOffRadioButton
                        function onClicked() {
                            dstImageCanvas.requestPaint()
                        }
                    }
                }

                RadioButton {
                    id: gridCellNumSrcColorsRadioButton
                    x: 6
                    y: 22
                    text: qsTr("Number of colors")
                    ButtonGroup.group: gridCellDebugButtonGroup
                    onClicked: {
                        dstImageCanvas.cellDebugMode = 'numSrcColors';
                    }
                }

                RadioButton {
                    id: gridCellSrcColorsRadioButton
                    x: 6
                    y: 52
                    text: qsTr("Palette colors")
                    ButtonGroup.group: gridCellDebugButtonGroup
                    onClicked: {
                        dstImageCanvas.cellDebugMode = 'srcColors';
                    }
                }

                RadioButton {
                    id: gridCellDstColorsRadioButton
                    x: 6
                    y: 83
                    text: qsTr("Palette indices")
                    ButtonGroup.group: gridCellDebugButtonGroup
                    onClicked: {
                        dstImageCanvas.cellDebugMode = 'dstColors';
                    }
                }

                RadioButton {
                    id: gridCellPaletteIndex
                    x: 6
                    y: 114
                    text: qsTr("Attributes")
                    Layout.preferredHeight: 25
                    Layout.preferredWidth: 94
                    ButtonGroup.group: gridCellDebugButtonGroup
                    onClicked: {
                        dstImageCanvas.cellDebugMode = 'paletteIndex';
                    }

                }

                ButtonGroup { id: bgOrSpritesButtonGroup }

                RadioButton {
                    id: bgDebugRadioButton
                    x: 206
                    y: -9
                    text: qsTr("Debug BG")
                    checked: true
                    ButtonGroup.group: bgOrSpritesButtonGroup
                    onClicked: {
                        dstImageCanvas.spriteDebugMode = false
                    }
                }

                RadioButton {
                    id: spritesDebugRadioButton
                    x: 206
                    y: 22
                    text: qsTr("Debug SPR")
                    ButtonGroup.group: bgOrSpritesButtonGroup
                    onClicked: {
                        dstImageCanvas.spriteDebugMode = true
                    }
                }
            }

            GroupBox {
                id: saveGroupBox
                width: 230
                height: 200
                title: qsTr("Output")
                enabled: false

                Button {
                    id: saveImageButton
                    x: 0
                    y: 88
                    width: 206
                    height: 32
                    text: qsTr("Save converted PNG...")
                    Component.onCompleted: {
                        saveImageButton.onClicked.connect(saveConvertedDialog.openDialog);
                    }
                    enabled: false
                }
                Button {
                    id: exportImageButton
                    x: 0
                    y: 124
                    width: 206
                    height: 32
                    text: qsTr("Export...")
                    Component.onCompleted: {
                        exportImageButton.onClicked.connect(exportConvertedDialog.openDialog);
                    }
                    enabled: false
                }
                RowLayout {
                    x: 0
                    y: 44
                    width: 184
                    height: 36
                    spacing: 8

                    Label {
                        id: label11
                        text: qsTr("Timeout")
                    }

                    SpinBox {
                        id: timeOutSpinBox
                        to: 999
                        value: 30
                        width: 140
                        height: 32
                        clip: false
                        scale: 1
                        wheelEnabled: true
                        editable: true
                        onValueChanged: optimiser.timeOut = value
                    }
                }

                RowLayout {
                    x: 0
                    y: 0
                    height: 36
                    spacing: 8

                    Button {
                        id: convertImageButton
                        y: 0
                        height: 32
                        text: qsTr("Convert")
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: 103
                        onClicked: {
                            optimiser.startImageConversionWrapper();
                        }
                    }

                    CheckBox {
                        id: autoConversionCheckBox
                        height: 32
                        text: qsTr("Auto")
                        antialiasing: true
                        onCheckedChanged: {
                            if(checked)
                            {
                                // Disable manual conversion button
                                convertImageButton.enabled = false
                                // Connect signals to start automatically
                                spriteModeComboBox.currentValueChanged.connect(optimiser.startImageConversionWrapper);
                                bgModeComboBox.currentValueChanged.connect(optimiser.startImageConversionWrapper);
                                xShiftSpinBox.valueModified.connect(optimiser.startImageConversionWrapper);
                                yShiftSpinBox.valueModified.connect(optimiser.startImageConversionWrapper);
                                maxBackgroundPalettesSpinBox.valueModified.connect(optimiser.startImageConversionWrapper);
                                maxSpritePalettesSpinBox.valueModified.connect(optimiser.startImageConversionWrapper);
                                maxSpritesPerScanlineSpinBox.valueModified.connect(optimiser.startImageConversionWrapper);
                                optimiser.shiftXChanged.connect(optimiser.startImageConversionWrapper);
                                optimiser.shiftYChanged.connect(optimiser.startImageConversionWrapper);
                                optimiser.inputImageChanged.connect(optimiser.startImageConversionWrapper);
                            }
                            else
                            {
                                // Re-enable manual conversion button
                                convertImageButton.enabled = true
                                // Disconnect signals to stop starting automatically
                                spriteModeComboBox.currentValueChanged.disconnect(optimiser.startImageConversionWrapper);
                                bgModeComboBox.currentValueChanged.disconnect(optimiser.startImageConversionWrapper);
                                xShiftSpinBox.valueModified.disconnect(optimiser.startImageConversionWrapper);
                                yShiftSpinBox.valueModified.disconnect(optimiser.startImageConversionWrapper);
                                maxBackgroundPalettesSpinBox.valueModified.disconnect(optimiser.startImageConversionWrapper);
                                maxSpritePalettesSpinBox.valueModified.disconnect(optimiser.startImageConversionWrapper);
                                maxSpritesPerScanlineSpinBox.valueModified.disconnect(optimiser.startImageConversionWrapper);
                                optimiser.shiftXChanged.disconnect(optimiser.startImageConversionWrapper);
                                optimiser.shiftYChanged.disconnect(optimiser.startImageConversionWrapper);
                                optimiser.inputImageChanged.disconnect(optimiser.startImageConversionWrapper);
                            }
                        }
                    }
                }

            }
        }
        MessageDialog {
            id: invalidImageMessageDialog
            title: "Error"
            text: "Image file format not recognized."
            icon: StandardIcon.Critical
            onAccepted: {
                visible = false;
            }
        }
        // Load input image dialog
        FileDialog {
            id: loadImageDialog
            visible: false
            title: "Load .png image"
            folder: shortcuts.home
            nameFilters: ["Image files (*.png *.bmp *.gif)"]
            selectExisting: true
            onAccepted: {
                visible = false;
                loadImage(fileUrls[0]);
            }
            onRejected: {
                visible = false
            }
            function openDialog()
            {
                visible = true
            }
        }
        // Save converted image dialog
        FileDialog {
            id: saveConvertedDialog
            visible: false
            title: "Save .png image"
            folder: shortcuts.home
            nameFilters: ["Indexed PNG (*.png)"]
            selectExisting: false
            onAccepted: {
                visible = false
                optimiser.saveOutputImage(fileUrls[0], getMask());
            }
            onRejected: {
                visible = false
            }
            function openDialog()
            {
                visible = true
            }
        }
        // Export converted image dialog
        FileDialog {
            id: exportConvertedDialog
            visible: false
            title: "Export RAW binary (NES) data"
            folder: shortcuts.home
            nameFilters: ["Nametable (*.nam)"]
            selectExisting: false
            onAccepted: {
                visible = false
                optimiser.exportOutputImage(fileUrls[0], getMask());
            }
            onRejected: {
                visible = false
            }
            function openDialog()
            {
                visible = true
            }
        }
    }
    // Load image from supplied filename
    function loadImage(filename)
    {
        var imageError = optimiser.validateInputImage(filename);
        if(imageError === "")
        {
            optimiser.inputImageFilename = filename;
            saveGroupBox.enabled = true;
        }
        else
        {
            invalidImageMessageDialog.visible = true;
        }
    }
    // Get mask to apply to save PNG/export
    function getMask()
    {
        // Apply current mask when exporting
        var maskArray = [palette0_checkBox.checked,
                         palette1_checkBox.checked,
                         palette2_checkBox.checked,
                         palette3_checkBox.checked,
                         palette4_checkBox.checked,
                         palette5_checkBox.checked,
                         palette6_checkBox.checked,
                         palette7_checkBox.checked];
        var mask = 0;
        for(var i = 0; i < maskArray.length; i++)
        {
            mask |= (Number(maskArray[i]) << i);
        }
        return mask;
    }
}

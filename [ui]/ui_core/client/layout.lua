UI.slots = {
    topLeft = {
        x = UI.safe.x,
        y = UI.safe.y,
    },
    topCenter = {
        x = UI.sw / 2,
        y = UI.safe.y,
    },
    topRight = {
        x = UI.sw - UI.safe.x,
        y = UI.safe.y,
    },

    alert = {
        x = UI.sw / 2,
        y = UI.sh * 0.1, -- képernyő közepén, felülről sh*0.1
    },

    leftCenter = {
        x = UI.safe.x,
        y = UI.sh / 2,
        minY = UI.sh - ui(200), -- radar hely
        w = ui(420),
    },

    bottomLeft = {
        x = UI.sw,
        y = UI.sh - UI.safe.y,
    },
    bottomCenter = {
        x = UI.sw / 2,
        y = UI.sh - UI.safe.y,
    },
    bottomRight = {
        x = UI.sw - UI.safe.x,
        y = UI.sh - UI.safe.y,
    },
}

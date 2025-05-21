import os
from qt import QPixmap, Qt

# Parameters
output_dir = "C:/Users/dstolz/My Drive/PROJECTS/NIHL ECM/Axial_350microns"
start_z = -0.100      # in mm
end_z = -7.650     # in mm
step = -0.350      # mm per slice
scale_factor = 2.0  # Increase resolution by scaling captured image

# Setup
layoutManager = slicer.app.layoutManager()
sliceWidget = layoutManager.sliceWidget("Red")
sliceLogic = sliceWidget.sliceLogic()

# Use Four-Up layout for scene capture
slicer.app.layoutManager().setLayout(slicer.vtkMRMLLayoutNode.SlicerLayoutFourUpView)

# Capture loop
z = start_z
i = 0
while z >= end_z:
    sliceLogic.SetSliceOffset(z)

    # Force render all views
    slicer.util.forceRenderAllViews()

    # Capture Four-Up view only (central widget)
    centralWidget = slicer.util.mainWindow().centralWidget()
    pixmap = QPixmap.grabWidget(centralWidget)

    # Scale captured image
    scaled_pixmap = pixmap.scaled(pixmap.width() * scale_factor,
                                  pixmap.height() * scale_factor,
                                  Qt.KeepAspectRatio,
                                  Qt.SmoothTransformation)

    filename = os.path.join(output_dir, f"scene_{i:03d}_z{z:.3f}mm.png")
    scaled_pixmap.save(filename)

    z += step
    i += 1

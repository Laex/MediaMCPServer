Media-MCP-Server - ONNX models (bin\models)
=============================================

This folder must contain ONNX models used by the MCP tool image_detect_objects.

Models used by MCP tools
------------------------

Object detection (YOLOX, COCO 80 classes):
  object_detection_yolox_2022nov.onnx   - image_detect_objects, image_annotate
  detection_yolox.onnx                  - alias / fallback

Face detection (YuNet):
  face_detection_yunet_2026may.onnx     - image_detect_faces, face_*, image_annotate

Face recognition (SFace):
  face_recognition_sface_2021dec.onnx   - face_compare, face_enroll, face_identify

Classification (MobileNetV2):
  classification.onnx                 - image_classify

Person segmentation:
  human_segmentation_pphumanseg_2023mar.onnx - image_segment_person

Text detection (PPOCR):
  text_detection_ppocr.onnx             - image_detect_text

Text detection (EAST):
  frozen_east_text_detection.pb       - image_detect_text_east

TrackerNano (in bin\ root, not models\):
  backbone.onnx, neckhead.onnx        - video_track_object

How to obtain models
--------------------

Option 0 — full install (recommended):

  cd "Media-MCP-Server"
  .\install.ps1

Option 1 — install / download script (recommended):

  cd MediaMCPServer
  .\install.ps1
  # or only models:
  .\scripts\download_models.ps1

  Downloads ONNX models directly from OpenCV Zoo and other public URLs into bin\models.

Option 2 — full dependency download:

  .\scripts\download_deps.ps1 -Force

  Downloads models, FFmpeg DLLs, and OpenCV runtime into bin\.

Option 3 — direct URLs (OpenCV Zoo, Git LFS via media.githubusercontent.com):

  object_detection_yolox_2022nov.onnx (~34 MB):
    https://media.githubusercontent.com/media/opencv/opencv_zoo/main/models/object_detection_yolox/object_detection_yolox_2022nov.onnx

  detection_yolox.onnx is a copy of the file above (same content, shorter name).

Option 4 — custom models directory (no copy into bin\models):

  Set environment variable before starting the server:
    OPENCV_MODELS_PATH=C:\path\to\models
  or
    MEDIA_MCP_MODELS_PATH=C:\path\to\models

  Point it to a folder that contains object_detection_yolox_2022nov.onnx
  and/or detection_yolox.onnx.

Other files in this folder
--------------------------
  download_models.ps1 fetches all models used by Media MCP Server (face detection,
  classification, segmentation, OCR, EAST, TrackerNano).

Sources
-------
  https://github.com/opencv/opencv_zoo
  https://github.com/opencv/opencv_zoo/tree/main/models/object_detection_yolox

Model lookup order in MediaMCPServer.exe
----------------------------------------
  1. OPENCV_MODELS_PATH or MEDIA_MCP_MODELS_PATH
  2. {exe directory}\models\
  3. Relative dev paths under OpenCV\OpenCV 5.0\bin\models (legacy layout)
  4. Walk up parent directories for OpenCV\OpenCV 5.0\bin\models

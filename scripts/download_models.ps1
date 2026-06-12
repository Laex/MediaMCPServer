param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot '_common.ps1')
. (Join-Path $PSScriptRoot '_download_common.ps1')

$manifest = Get-DepsManifest
$ModelsDir = Join-Path $BinDir 'models'
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
New-Item -ItemType Directory -Force -Path $ModelsDir | Out-Null

Write-Host "Media MCP Server - download ONNX models" -ForegroundColor White
Write-Host "Target: $ModelsDir" -ForegroundColor DarkGray

Write-DownloadStep 'OpenCV Zoo models'

$zoo = @(
    @{ Rel = 'models/face_detection_yunet/face_detection_yunet_2026may.onnx'; Name = 'face_detection_yunet_2026may.onnx' },
    @{ Rel = 'models/face_detection_yunet/face_detection_yunet_2023mar.onnx'; Name = 'face_detection_yunet_2023mar.onnx' },
    @{ Rel = 'models/face_recognition_sface/face_recognition_sface_2021dec.onnx'; Name = 'face_recognition_sface_2021dec.onnx' },
    @{ Rel = 'models/image_classification_mobilenet/image_classification_mobilenetv2_2022apr.onnx'; Name = 'image_classification_mobilenetv2_2022apr.onnx' },
    @{ Rel = 'models/object_detection_yolox/object_detection_yolox_2022nov.onnx'; Name = 'object_detection_yolox_2022nov.onnx' },
    @{ Rel = 'models/human_segmentation_pphumanseg/human_segmentation_pphumanseg_2023mar.onnx'; Name = 'human_segmentation_pphumanseg_2023mar.onnx' },
    @{ Rel = 'models/text_detection_ppocr/text_detection_en_ppocrv3_2023may.onnx'; Name = 'text_detection_en_ppocrv3_2023may.onnx' }
)

foreach ($item in $zoo) {
    Invoke-DownloadFile (Get-OpenCvZooUrl $item.Rel) (Join-Path $ModelsDir $item.Name) $item.Name -Force:$Force
}

Copy-Item (Join-Path $ModelsDir 'image_classification_mobilenetv2_2022apr.onnx') (Join-Path $ModelsDir 'classification.onnx') -Force
Copy-Item (Join-Path $ModelsDir 'object_detection_yolox_2022nov.onnx') (Join-Path $ModelsDir 'detection_yolox.onnx') -Force
Copy-Item (Join-Path $ModelsDir 'text_detection_en_ppocrv3_2023may.onnx') (Join-Path $ModelsDir 'text_detection_ppocr.onnx') -Force
Write-Host '  [link] classification.onnx, detection_yolox.onnx, text_detection_ppocr.onnx' -ForegroundColor DarkGray

Write-DownloadStep 'TrackerNano models'
Invoke-DownloadFile $manifest.opencv.trackerBackbone (Join-Path $BinDir 'backbone.onnx') 'TrackerNano backbone.onnx' -Force:$Force
Invoke-DownloadFile $manifest.opencv.trackerHead (Join-Path $BinDir 'neckhead.onnx') 'TrackerNano neckhead.onnx' -Force:$Force

Write-DownloadStep 'EAST text detector'
$eastPb = Join-Path $ModelsDir 'frozen_east_text_detection.pb'
if (-not ((Test-Path $eastPb) -and ((Get-Item $eastPb).Length -gt 1MB)) -or $Force) {
    Write-Host '  [get]  frozen_east_text_detection.pb' -ForegroundColor Yellow
    $eastTar = Join-Path $DepsCacheDir 'frozen_east_text_detection.tar.gz'
    New-Item -ItemType Directory -Force -Path $DepsCacheDir | Out-Null
    Invoke-DownloadFile $manifest.opencv.eastArchive $eastTar 'frozen_east_text_detection.tar.gz' -Force:$Force -MinBytes 1000000
    $tmp = Join-Path $env:TEMP 'mcp_east_extract'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Path $tmp | Out-Null
    tar -xzf $eastTar -C $tmp
    $found = Get-ChildItem -Path $tmp -Recurse -Filter 'frozen_east_text_detection.pb' | Select-Object -First 1
    if (-not $found) { throw 'frozen_east_text_detection.pb not found in archive' }
    Copy-Item $found.FullName $eastPb -Force
    Remove-Item $tmp -Recurse -Force
    Write-Host ("         -> {0:N0} bytes" -f (Get-Item $eastPb).Length) -ForegroundColor Green
} else {
    Write-Host ("  [skip] frozen_east_text_detection.pb ({0:N0} bytes)" -f (Get-Item $eastPb).Length) -ForegroundColor DarkGray
}

$readme = Join-Path $ProjectRoot 'docs\models-readme.txt'
if (Test-Path $readme) {
    Copy-Item $readme (Join-Path $ModelsDir 'readme.txt') -Force
}

Write-DownloadStep 'Done'

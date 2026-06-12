unit uOpenCVDnnTools;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Math,
  OpenCV5.Core, OpenCV5.Dnn, OpenCV5.Imgcodecs, OpenCV5.Objdetect, OpenCV5.Utils, OpenCV5.Types,
  uOpenCVHelpers;

type
  TOpenCVDnnTools = class
  public
    class procedure RegisterTools(Schema: TJSONArray);
    class function CallTool(const Name: string; Args: TJSONObject): TJSONObject;
  end;

implementation

class procedure TOpenCVDnnTools.RegisterTools(Schema: TJSONArray);
var
  Props: TJSONObject;
  P: TJSONObject;
  Item: TJSONObject;
begin
  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('imagePath', P);
  Item := TOpenCVHelpers.AddToolSchema('image_classify',
    'Classify an image using MobileNetV2 ONNX model. Returns classId and confidence.',
    Props, ['imagePath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('imagePath', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('outputPath', TJSONObject.Create.AddPair('type', 'string'));
  Item := TOpenCVHelpers.AddToolSchema('image_segment_person',
    'Segment a person silhouette from an image. Saves grayscale mask PNG.',
    Props, ['imagePath', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('imagePath', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('scoreThreshold', TJSONObject.Create.AddPair('type', 'number'));
  Item := TOpenCVHelpers.AddToolSchema('image_detect_text',
    'Detect text regions using PPOCR ONNX. Returns polygon coordinates per region.',
    Props, ['imagePath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('imagePath', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('scoreThreshold', TJSONObject.Create.AddPair('type', 'number'));
  Item := TOpenCVHelpers.AddToolSchema('image_detect_text_east',
    'Detect text regions using EAST model (.pb). Returns rotated bounding boxes.',
    Props, ['imagePath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('imagePath1', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('imagePath2', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('threshold', TJSONObject.Create.AddPair('type', 'number'));
  Item := TOpenCVHelpers.AddToolSchema('face_compare',
    'Compare two face images using SFace. Returns cosine distance (lower = more similar).',
    Props, ['imagePath1', 'imagePath2']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('imagePath', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('name', TJSONObject.Create.AddPair('type', 'string'));
  Item := TOpenCVHelpers.AddToolSchema('face_enroll',
    'Enroll a face from an image into the local face registry under a given name.',
    Props, ['imagePath', 'name']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('imagePath', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('threshold', TJSONObject.Create.AddPair('type', 'number'));
  Item := TOpenCVHelpers.AddToolSchema('face_identify',
    'Identify a face against enrolled persons. Returns best match name and distance.',
    Props, ['imagePath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Item := TOpenCVHelpers.AddToolSchema('face_list',
    'List all enrolled face names in the local registry.', Props, []);
  Schema.Add(Item);
end;

class function TOpenCVDnnTools.CallTool(const Name: string; Args: TJSONObject): TJSONObject;
var
  ImagePath, ImagePath1, ImagePath2, OutputPath, PersonName, ModelPath, Err: string;
  Img, Img1, Img2, Mask, Faces, Feature1, Feature2, Aligned, FaceRow: TCVMat;
  Model: TCVClassificationModel;
  SegModel: TCVSegmentationModel;
  TextModel: TCVTextDetectionDB;
  EastModel: TCVTextDetectionEAST;
  Det: TCVFaceDetectorYN;
  Rec: TCVFaceRecognizerSF;
  ClassId, I, N, Rows, Cols: Integer;
  ConfSingle: Single;
  Threshold, Dist, BestDist, ValDouble: Double;
  Polygons, Confidences, Boxes: TCVMat;
  Regions, PolyArr, BboxArr: TJSONArray;
  RegionItem: TJSONObject;
  BestName, DetPath, RecPath, FaceFile, BaseName: string;
  InputSize: TCVSize;
begin
  if Name = 'image_classify' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin
      Result.AddPair('error', 'imagePath is required');
      Exit;
    end;
    ModelPath := TOpenCVHelpers.ResolveModelPath('classification.onnx');
    if not FileExists(ModelPath) then
      ModelPath := TOpenCVHelpers.ResolveModelPath('image_classification_mobilenetv2_2022apr.onnx');
    if not FileExists(ModelPath) then
    begin
      Result.AddPair('error', 'Classification model not found');
      Exit;
    end;
    Img := TOpenCVHelpers.LoadImagePath(ImagePath, Err);
    if Img.empty then begin Result.AddPair('error', Err); Exit; end;
    Model := TCVClassificationModel.Create(PAnsiChar(PathToUTF8(ModelPath)), nil);
    Model.setInputSize(Img.cols, Img.rows);
    if not Model.classify(Img.Handle, ClassId, ConfSingle) then
      Result.AddPair('error', 'classify failed')
    else
    begin
      Result.AddPair('status', 'success');
      Result.AddPair('classId', TJSONNumber.Create(ClassId));
      Result.AddPair('confidence', TJSONNumber.Create(ConfSingle));
      Result.AddPair('model', ExtractFileName(ModelPath));
    end;
    Exit;
  end;

  if Name = 'image_segment_person' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    if not TOpenCVHelpers.RequireOutputPath(Args, 'output', OutputPath, Err) then
    begin Result.AddPair('error', Err); Exit; end;
    ModelPath := TOpenCVHelpers.ResolveModelPath('human_segmentation_pphumanseg_2023mar.onnx');
    if not FileExists(ModelPath) then
    begin Result.AddPair('error', 'Segmentation model not found'); Exit; end;
    Img := TOpenCVHelpers.LoadImagePath(ImagePath, Err);
    if Img.empty then begin Result.AddPair('error', Err); Exit; end;
    SegModel := TCVSegmentationModel.Create(PAnsiChar(PathToUTF8(ModelPath)), nil);
    SegModel.setInputSize(192, 192);
    Mask := TCVMat.Create_0(0, 0, CV_8UC1);
    if not SegModel.segment(Img.Handle, Mask.Handle) then
      Result.AddPair('error', 'segment failed')
    else
    begin
      TOpenCVHelpers.EnsureOutputDir(OutputPath);
      if imwritePath(OutputPath, Mask.Handle) then
      begin
        Result.AddPair('status', 'success');
        Result.AddPair('outputPath', OutputPath);
        Result.AddPair('width', TJSONNumber.Create(Mask.cols));
        Result.AddPair('height', TJSONNumber.Create(Mask.rows));
      end
      else
        Result.AddPair('error', 'Failed to save mask');
    end;
    Exit;
  end;

  if Name = 'image_detect_text' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    ModelPath := TOpenCVHelpers.ResolveModelPath('text_detection_ppocr.onnx');
    if not FileExists(ModelPath) then
      ModelPath := TOpenCVHelpers.ResolveModelPath('text_detection_en_ppocrv3_2023may.onnx');
    if not FileExists(ModelPath) then
    begin Result.AddPair('error', 'PPOCR model not found'); Exit; end;
    Threshold := TOpenCVHelpers.GetOptionalDouble(Args, 'scoreThreshold', 0.3);
    Img := TOpenCVHelpers.LoadImagePath(ImagePath, Err);
    if Img.empty then begin Result.AddPair('error', Err); Exit; end;
    TextModel := TCVTextDetectionDB.Create(PAnsiChar(PathToUTF8(ModelPath)), nil);
    TextModel.setInputSize(Img.cols, Img.rows);
    Polygons := TCVMat.Create_0(0, 8, CV_32F);
    Confidences := TCVMat.Create_0(0, 1, CV_32F);
    N := TextModel.detectText(Img.Handle, Polygons.Handle, Confidences.Handle, Threshold);
    Regions := TJSONArray.Create;
    for I := 0 to N - 1 do
    begin
      RegionItem := TJSONObject.Create;
      RegionItem.AddPair('confidence', TJSONNumber.Create(PSingle(Confidences.ptr(I, 0))^));
      PolyArr := TJSONArray.Create;
      PolyArr.Add(FloatToStr(PSingle(Polygons.ptr(I, 0))^));
      PolyArr.Add(FloatToStr(PSingle(Polygons.ptr(I, 1))^));
      PolyArr.Add(FloatToStr(PSingle(Polygons.ptr(I, 2))^));
      PolyArr.Add(FloatToStr(PSingle(Polygons.ptr(I, 3))^));
      PolyArr.Add(FloatToStr(PSingle(Polygons.ptr(I, 4))^));
      PolyArr.Add(FloatToStr(PSingle(Polygons.ptr(I, 5))^));
      PolyArr.Add(FloatToStr(PSingle(Polygons.ptr(I, 6))^));
      PolyArr.Add(FloatToStr(PSingle(Polygons.ptr(I, 7))^));
      RegionItem.AddPair('polygon', PolyArr);
      Regions.Add(RegionItem);
    end;
    Result.AddPair('status', 'success');
    Result.AddPair('regions', Regions);
    Result.AddPair('count', TJSONNumber.Create(N));
    Exit;
  end;

  if Name = 'image_detect_text_east' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    ModelPath := TOpenCVHelpers.ResolveModelPath('frozen_east_text_detection.pb');
    if not FileExists(ModelPath) then
    begin Result.AddPair('error', 'EAST model not found'); Exit; end;
    Threshold := TOpenCVHelpers.GetOptionalDouble(Args, 'scoreThreshold', 0.5);
    Img := TOpenCVHelpers.LoadImagePath(ImagePath, Err);
    if Img.empty then begin Result.AddPair('error', Err); Exit; end;
    EastModel := TCVTextDetectionEAST.Create(PAnsiChar(PathToUTF8(ModelPath)), nil);
    EastModel.setInputSize(320, 320);
    Boxes := TCVMat.Create_0(0, 5, CV_32F);
    Confidences := TCVMat.Create_0(0, 1, CV_32F);
    N := EastModel.detectText(Img.Handle, Boxes.Handle, Confidences.Handle, Threshold, 0.4);
    Regions := TJSONArray.Create;
    for I := 0 to N - 1 do
    begin
      RegionItem := TJSONObject.Create;
      RegionItem.AddPair('confidence', TJSONNumber.Create(PSingle(Confidences.ptr(I, 0))^));
      BboxArr := TJSONArray.Create;
      BboxArr.Add(FloatToStr(PSingle(Boxes.ptr(I, 0))^));
      BboxArr.Add(FloatToStr(PSingle(Boxes.ptr(I, 1))^));
      BboxArr.Add(FloatToStr(PSingle(Boxes.ptr(I, 2))^));
      BboxArr.Add(FloatToStr(PSingle(Boxes.ptr(I, 3))^));
      BboxArr.Add(FloatToStr(PSingle(Boxes.ptr(I, 4))^));
      RegionItem.AddPair('box', BboxArr);
      Regions.Add(RegionItem);
    end;
    Result.AddPair('status', 'success');
    Result.AddPair('regions', Regions);
    Result.AddPair('count', TJSONNumber.Create(N));
    Exit;
  end;

  if Name = 'face_compare' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath1', ImagePath1) then
    begin Result.AddPair('error', 'imagePath1 is required'); Exit; end;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath2', ImagePath2) then
    begin Result.AddPair('error', 'imagePath2 is required'); Exit; end;
    DetPath := TOpenCVHelpers.ResolveFaceDetectorPath;
    RecPath := TOpenCVHelpers.ResolveModelPath('face_recognition_sface_2021dec.onnx');
    if not FileExists(DetPath) or not FileExists(RecPath) then
    begin Result.AddPair('error', 'Face models not found'); Exit; end;
    Img1 := TOpenCVHelpers.LoadImagePath(ImagePath1, Err);
    if Img1.empty then begin Result.AddPair('error', 'imagePath1: ' + Err); Exit; end;
    Img2 := TOpenCVHelpers.LoadImagePath(ImagePath2, Err);
    if Img2.empty then begin Result.AddPair('error', 'imagePath2: ' + Err); Exit; end;
    Det := TCVFaceDetectorYN.Create(PAnsiChar(PathToUTF8(DetPath)), nil, TCVSize.Create(320, 320), 0.5, 0.3, 5000);
    Rec := TCVFaceRecognizerSF.Create(PAnsiChar(PathToUTF8(RecPath)), nil);
    Faces := TCVMat.Create_0(0, 0, CV_32FC1);
    Det.setInputSize(TCVSize.Create(Img1.cols, Img1.rows));
    if not TOpenCVHelpers.ExtractFirstFaceFeature(Det, Rec, Img1, Faces, Feature1) then
    begin Result.AddPair('error', 'No face in imagePath1'); Exit; end;
    Det.setInputSize(TCVSize.Create(Img2.cols, Img2.rows));
    if not TOpenCVHelpers.ExtractFirstFaceFeature(Det, Rec, Img2, Faces, Feature2) then
    begin Result.AddPair('error', 'No face in imagePath2'); Exit; end;
    Dist := Rec.match(Feature1.Handle, Feature2.Handle, FR_COSINE);
    Threshold := TOpenCVHelpers.GetOptionalDouble(Args, 'threshold', 0.363);
    Result.AddPair('status', 'success');
    Result.AddPair('distance', TJSONNumber.Create(Dist));
    Result.AddPair('match', TJSONBool.Create(Dist < Threshold));
    Result.AddPair('threshold', TJSONNumber.Create(Threshold));
    Exit;
  end;

  if Name = 'face_enroll' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    if not TOpenCVHelpers.RequireString(Args, 'name', PersonName) then
    begin Result.AddPair('error', 'name is required'); Exit; end;
    DetPath := TOpenCVHelpers.ResolveFaceDetectorPath;
    RecPath := TOpenCVHelpers.ResolveModelPath('face_recognition_sface_2021dec.onnx');
    Img := TOpenCVHelpers.LoadImagePath(ImagePath, Err);
    if Img.empty then begin Result.AddPair('error', Err); Exit; end;
    Det := TCVFaceDetectorYN.Create(PAnsiChar(PathToUTF8(DetPath)), nil, TCVSize.Create(320, 320), 0.5, 0.3, 5000);
    Rec := TCVFaceRecognizerSF.Create(PAnsiChar(PathToUTF8(RecPath)), nil);
    Faces := TCVMat.Create_0(0, 0, CV_32FC1);
    Det.setInputSize(TCVSize.Create(Img.cols, Img.rows));
    if not TOpenCVHelpers.ExtractFirstFaceFeature(Det, Rec, Img, Faces, Feature1) then
    begin Result.AddPair('error', 'No face found in image'); Exit; end;
    TOpenCVHelpers.SaveFaceFeature(PersonName, Feature1);
    Result.AddPair('status', 'success');
    Result.AddPair('name', PersonName);
    Result.AddPair('file', TPath.Combine(TOpenCVHelpers.FaceDataDir, PersonName + '.json'));
    Exit;
  end;

  if Name = 'face_identify' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    DetPath := TOpenCVHelpers.ResolveFaceDetectorPath;
    RecPath := TOpenCVHelpers.ResolveModelPath('face_recognition_sface_2021dec.onnx');
    Img := TOpenCVHelpers.LoadImagePath(ImagePath, Err);
    if Img.empty then begin Result.AddPair('error', Err); Exit; end;
    Det := TCVFaceDetectorYN.Create(PAnsiChar(PathToUTF8(DetPath)), nil, TCVSize.Create(320, 320), 0.5, 0.3, 5000);
    Rec := TCVFaceRecognizerSF.Create(PAnsiChar(PathToUTF8(RecPath)), nil);
    Faces := TCVMat.Create_0(0, 0, CV_32FC1);
    Det.setInputSize(TCVSize.Create(Img.cols, Img.rows));
    if not TOpenCVHelpers.ExtractFirstFaceFeature(Det, Rec, Img, Faces, Feature1) then
    begin Result.AddPair('error', 'No face found in image'); Exit; end;
    BestName := 'unknown';
    BestDist := MaxDouble;
    Threshold := TOpenCVHelpers.GetOptionalDouble(Args, 'threshold', 0.363);
    for FaceFile in TDirectory.GetFiles(TOpenCVHelpers.FaceDataDir, '*.json') do
    begin
      if TOpenCVHelpers.LoadFaceFeature(FaceFile, Feature2) then
      begin
        Dist := Rec.match(Feature1.Handle, Feature2.Handle, FR_COSINE);
        if Dist < BestDist then
        begin
          BestDist := Dist;
          BestName := TPath.GetFileNameWithoutExtension(FaceFile);
        end;
      end;
    end;
    Result.AddPair('status', 'success');
    Result.AddPair('name', BestName);
    Result.AddPair('distance', TJSONNumber.Create(BestDist));
    Result.AddPair('recognized', TJSONBool.Create((BestName <> 'unknown') and (BestDist < Threshold)));
    Exit;
  end;

  if Name = 'face_list' then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('status', 'success');
    Result.AddPair('faces', TOpenCVHelpers.ListEnrolledFaces);
    Exit;
  end;

  raise Exception.Create('DNN tool not found: ' + Name);
end;

end.

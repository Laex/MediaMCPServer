unit uOpenCVImgTools;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Math,
  OpenCV5.Core, OpenCV5.Imgcodecs, OpenCV5.Imgproc, OpenCV5.Objdetect, OpenCV5.Arith,
  OpenCV5.Dnn, OpenCV5.Helpers, OpenCV5.Types, OpenCV5.Utils,
  uOpenCVHelpers;

type
  TOpenCVImgTools = class
  public
    class procedure RegisterTools(Schema: TJSONArray);
    class function CallTool(const Name: string; Args: TJSONObject): TJSONObject;
  end;

implementation

class procedure TOpenCVImgTools.RegisterTools(Schema: TJSONArray);
var
  Props: TJSONObject;
  P: TJSONObject;
  Item: TJSONObject;
begin
  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('imagePath', P);
  Item := TOpenCVHelpers.AddToolSchema('image_read_qrcode', 'Read QR codes from an image.', Props, ['imagePath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('text', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('outputPath', P);
  Item := TOpenCVHelpers.AddToolSchema('image_encode_qrcode', 'Generate a QR code image from text.', Props, ['text', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('imagePath', P);
  Item := TOpenCVHelpers.AddToolSchema('image_read_barcode', 'Read barcodes from an image.', Props, ['imagePath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('imagePath', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('dictionaryId', P);
  Item := TOpenCVHelpers.AddToolSchema('image_detect_aruco', 'Detect ArUco markers in an image.', Props, ['imagePath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('imagePath', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('templatePath', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('outputPath', P);
  Item := TOpenCVHelpers.AddToolSchema('image_template_match', 'Find a template in an image using normalized cross-correlation.', Props, ['imagePath', 'templatePath', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('imagePath', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('outputPath', P);
  Item := TOpenCVHelpers.AddToolSchema('image_find_contours', 'Find contours and draw the largest one.', Props, ['imagePath', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('imagePath', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('outputPath', P);
  Item := TOpenCVHelpers.AddToolSchema('image_detect_edges', 'Detect edges using Canny algorithm.', Props, ['imagePath', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('imagePath', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('outputPath', P);
  Item := TOpenCVHelpers.AddToolSchema('image_detect_lines', 'Detect line segments using Hough transform.', Props, ['imagePath', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('imagePath', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('outputPath', P);
  Item := TOpenCVHelpers.AddToolSchema('image_detect_circles', 'Detect circles using Hough transform.', Props, ['imagePath', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('imagePath', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('outputPath', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('width', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('height', P);
  P := TJSONObject.Create; P.AddPair('type', 'number'); Props.AddPair('angle', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('cropX', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('cropY', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('cropWidth', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('cropHeight', P);
  Item := TOpenCVHelpers.AddToolSchema('image_transform',
    'Resize, crop, or rotate an image. Specify width/height, crop rect, and/or angle.',
    Props, ['imagePath', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('imagePath', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('outputPath', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('mode', P);
  P := TJSONObject.Create; P.AddPair('type', 'number'); Props.AddPair('scoreThreshold', P);
  Item := TOpenCVHelpers.AddToolSchema('image_annotate',
    'Annotate image with detections. Mode: objects, faces, or both.',
    Props, ['imagePath', 'outputPath']);
  Schema.Add(Item);
end;

class function TOpenCVImgTools.CallTool(const Name: string; Args: TJSONObject): TJSONObject;
var
  ImagePath, TemplatePath, OutputPath, Text, Err, Mode: string;
  Img, Template, Gray, TemplGray, ResultMat, OutImg, Binary, Edges, Lines, Circles: TCVMat;
  Contours: TCVMatVector;
  Detector: TCVQRCodeDetector;
  BarcodeDet: TCVBarcodeDetector;
  ArucoDet: TCVArucoDetector;
  Points, Corners, Ids, QR: TCVMat;
  Texts, Types: TStrings;
  Decoded: string;
  Ok: Boolean;
  I, N, MaxI, MaxLen, Len, Count, DictId: Integer;
  Pts: TArray<TCVPoint>;
  MinVal, MaxVal, Angle, ScoreThreshold: Double;
  MinLoc, MaxLoc: TCVPoint;
  MatchRect, CropRect: TCVRect;
  Width, Height, CropX, CropY, CropW, CropH: Integer;
  X1, Y1, X2, Y2, CX, CY, R: Integer;
  Row: array[0..3] of Single;
  P: ^Single;
  Regions, Codes, BboxArr: TJSONArray;
  CodeItem: TJSONObject;
  IdVal: Integer;
  PtX, PtY: Single;
  Center: TCVPoint2f;
  M: TCVMat;
  ModelPath, DetPath, ObjLabel: string;
  Model: TCVDetectionModel;
  ClassIds, Confidences, Boxes, Faces: TCVMat;
  Det: TCVFaceDetectorYN;
  DetCount, ClassId, X, Y, W, H: Integer;
  Conf: Single;
begin
  if Name = 'image_read_qrcode' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    Img := TOpenCVHelpers.LoadImagePath(ImagePath, Err);
    if Img.empty then begin Result.AddPair('error', Err); Exit; end;
    Points := TCVMat.Create_0(0, 0, CV_32FC2);
    Detector := TCVQRCodeDetector.Create;
    Ok := Detector.detectAndDecode(Img.Handle, Points.Handle, Decoded);
    Codes := TJSONArray.Create;
    if Ok then
    begin
      CodeItem := TJSONObject.Create;
      CodeItem.AddPair('text', Decoded);
      Codes.Add(CodeItem);
    end;
    Result.AddPair('status', 'success');
    Result.AddPair('codes', Codes);
    Result.AddPair('count', TJSONNumber.Create(Codes.Count));
    Exit;
  end;

  if Name = 'image_encode_qrcode' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'text', Text) then
    begin Result.AddPair('error', 'text is required'); Exit; end;
    if not TOpenCVHelpers.RequireOutputPath(Args, 'output', OutputPath, Err) then
    begin Result.AddPair('error', Err); Exit; end;
    QR := TCVMat.Create_0(0, 0, CV_8UC1);
    encodeQRCode(PAnsiChar(PathToUTF8(Text)), QR.Handle);
    TOpenCVHelpers.EnsureOutputDir(OutputPath);
    if imwritePath(OutputPath, QR.Handle) then
    begin
      Result.AddPair('status', 'success');
      Result.AddPair('outputPath', OutputPath);
      Result.AddPair('text', Text);
    end
    else
      Result.AddPair('error', 'Failed to save QR image');
    Exit;
  end;

  if Name = 'image_read_barcode' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    Img := TOpenCVHelpers.LoadImagePath(ImagePath, Err);
    if Img.empty then begin Result.AddPair('error', Err); Exit; end;
    BarcodeDet := TCVBarcodeDetector.Create;
    Texts := TStringList.Create;
    Types := TStringList.Create;
    try
      Ok := BarcodeDet.detectAndDecodeWithType(Img.Handle, nil, Texts, Types);
      Codes := TJSONArray.Create;
      for I := 0 to Texts.Count - 1 do
      begin
        CodeItem := TJSONObject.Create;
        CodeItem.AddPair('text', Texts[I]);
        if I < Types.Count then
          CodeItem.AddPair('type', Types[I]);
        Codes.Add(CodeItem);
      end;
      Result.AddPair('status', 'success');
      Result.AddPair('barcodes', Codes);
      Result.AddPair('count', TJSONNumber.Create(Codes.Count));
    finally
      Texts.Free;
      Types.Free;
    end;
    Exit;
  end;

  if Name = 'image_detect_aruco' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    DictId := TOpenCVHelpers.GetOptionalInt(Args, 'dictionaryId', DICT_4X4_50);
    Img := TOpenCVHelpers.LoadImagePath(ImagePath, Err);
    if Img.empty then begin Result.AddPair('error', Err); Exit; end;
    Gray := TCVMat.Create_0(0, 0, CV_8UC1);
    if Img.channels > 1 then
      cvtColor(Img.Handle, Gray.Handle, COLOR_BGR2GRAY, 0, 0)
    else
      Gray := Img.clone;
    Corners := TCVMat.Create_0(0, 0, CV_32FC2);
    Ids := TCVMat.Create_0(0, 0, CV_32SC1);
    ArucoDet := TCVArucoDetector.Create(DictId);
    Count := ArucoDet.detectMarkers(Gray.Handle, Corners.Handle, Ids.Handle);
    Regions := TJSONArray.Create;
    for I := 0 to Count - 1 do
    begin
      CodeItem := TJSONObject.Create;
      IdVal := PInteger(Ids.ptr(I, 0))^;
      CodeItem.AddPair('id', TJSONNumber.Create(IdVal));
      BboxArr := TJSONArray.Create;
      for N := 0 to 3 do
      begin
        PtX := PSingle(Corners.ptr(I, N))^;
        PtY := PSingle(PByte(Corners.ptr(I, N)) + SizeOf(Single))^;
        BboxArr.Add(FloatToStr(PtX));
        BboxArr.Add(FloatToStr(PtY));
      end;
      CodeItem.AddPair('corners', BboxArr);
      Regions.Add(CodeItem);
    end;
    Result.AddPair('status', 'success');
    Result.AddPair('markers', Regions);
    Result.AddPair('count', TJSONNumber.Create(Count));
    Exit;
  end;

  if Name = 'image_template_match' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    if not TOpenCVHelpers.RequireString(Args, 'templatePath', TemplatePath) then
    begin Result.AddPair('error', 'templatePath is required'); Exit; end;
    if not TOpenCVHelpers.RequireOutputPath(Args, 'output', OutputPath, Err) then
    begin Result.AddPair('error', Err); Exit; end;
    Img := imreadPath(ImagePath, IMREAD_COLOR);
    Template := imreadPath(TemplatePath, IMREAD_COLOR);
    if Img.empty or Template.empty then
    begin Result.AddPair('error', 'Failed to read image or template'); Exit; end;
    Gray := TCVMat.Create_0(0, 0, CV_8UC1);
    TemplGray := TCVMat.Create_0(0, 0, CV_8UC1);
    cvtColor(Img.Handle, Gray.Handle, COLOR_BGR2GRAY, 0, 0);
    cvtColor(Template.Handle, TemplGray.Handle, COLOR_BGR2GRAY, 0, 0);
    ResultMat := TCVMat.Create_0(0, 0, CV_32F);
    matchTemplate(Gray.Handle, TemplGray.Handle, ResultMat.Handle, TM_CCOEFF_NORMED, nil);
    minMaxLoc(ResultMat.Handle, MinVal, MaxVal, MinLoc, MaxLoc);
    OutImg := Img.clone;
    MatchRect := TCVRect.Create(MaxLoc.X, MaxLoc.Y, Template.cols, Template.rows);
    rectangle(OutImg.Handle, MatchRect, TCVScalar.Create(0, 255, 0), 2, LINE_8, 0);
    TOpenCVHelpers.EnsureOutputDir(OutputPath);
    if imwritePath(OutputPath, OutImg.Handle) then
    begin
      Result.AddPair('status', 'success');
      Result.AddPair('score', TJSONNumber.Create(MaxVal));
      BboxArr := TJSONArray.Create;
      BboxArr.Add(IntToStr(MaxLoc.X)); BboxArr.Add(IntToStr(MaxLoc.Y));
      BboxArr.Add(IntToStr(Template.cols)); BboxArr.Add(IntToStr(Template.rows));
      Result.AddPair('bbox', BboxArr);
      Result.AddPair('outputPath', OutputPath);
    end
    else
      Result.AddPair('error', 'Failed to save output');
    Exit;
  end;

  if Name = 'image_find_contours' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    if not TOpenCVHelpers.RequireOutputPath(Args, 'output', OutputPath, Err) then
    begin Result.AddPair('error', Err); Exit; end;
    Img := imreadPath(ImagePath, IMREAD_COLOR);
    if Img.empty then begin Result.AddPair('error', 'Failed to read image'); Exit; end;
    Gray := TCVMat.Create_0(0, 0, CV_8UC1);
    Binary := TCVMat.Create_0(0, 0, CV_8UC1);
    cvtColor(Img.Handle, Gray.Handle, COLOR_BGR2GRAY, 0, 0);
    GaussianBlur(Gray.Handle, Gray.Handle, TCVSize.Create(5, 5), 0, 0, 0, 0);
    threshold(Gray.Handle, Binary.Handle, 0, 255, THRESH_BINARY or THRESH_OTSU);
    Contours := TCVMatVector.Create;
    findContoursEx(Binary.Handle, Contours, nil, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE, TCVPoint.Create(0, 0));
    OutImg := Img.clone;
    N := Contours.Count;
    MaxI := -1; MaxLen := 0;
    for I := 0 to N - 1 do
    begin
      Pts := ContourToPoints(Contours.At(I));
      Len := Length(Pts);
      if Len > MaxLen then begin MaxLen := Len; MaxI := I; end;
    end;
    if MaxI >= 0 then
      drawContoursEx(OutImg.Handle, Contours, MaxI, TCVScalar.Create(0, 255, 0), 2);
    TOpenCVHelpers.EnsureOutputDir(OutputPath);
    imwritePath(OutputPath, OutImg.Handle);
    Result.AddPair('status', 'success');
    Result.AddPair('contourCount', TJSONNumber.Create(N));
    Result.AddPair('largestContourPoints', TJSONNumber.Create(MaxLen));
    Result.AddPair('outputPath', OutputPath);
    Exit;
  end;

  if Name = 'image_detect_edges' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    if not TOpenCVHelpers.RequireOutputPath(Args, 'output', OutputPath, Err) then
    begin Result.AddPair('error', Err); Exit; end;
    Img := imreadPath(ImagePath, IMREAD_COLOR);
    Gray := TCVMat.Create_0(0, 0, CV_8UC1);
    Edges := TCVMat.Create_0(0, 0, CV_8UC1);
    cvtColor(Img.Handle, Gray.Handle, COLOR_BGR2GRAY, 0, 0);
    Canny(Gray.Handle, Edges.Handle, 50, 150, 3, False);
    TOpenCVHelpers.EnsureOutputDir(OutputPath);
    imwritePath(OutputPath, Edges.Handle);
    Result.AddPair('status', 'success');
    Result.AddPair('outputPath', OutputPath);
    Exit;
  end;

  if Name = 'image_detect_lines' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    if not TOpenCVHelpers.RequireOutputPath(Args, 'output', OutputPath, Err) then
    begin Result.AddPair('error', Err); Exit; end;
    Img := imreadPath(ImagePath, IMREAD_COLOR);
    Gray := TCVMat.Create_0(0, 0, CV_8UC1);
    Edges := TCVMat.Create_0(0, 0, CV_8UC1);
    Lines := TCVMat.Create_0(0, 0, CV_32F);
    cvtColor(Img.Handle, Gray.Handle, COLOR_BGR2GRAY, 0, 0);
    Canny(Gray.Handle, Edges.Handle, 50, 150, 3, False);
    HoughLinesP(Edges.Handle, Lines.Handle, 1, Pi / 180, 50, 50, 10);
    OutImg := Img.clone;
    N := Lines.rows;
    Regions := TJSONArray.Create;
    for I := 0 to N - 1 do
    begin
      P := Lines.ptr(I, 0);
      Move(P^, Row[0], SizeOf(Row));
      X1 := Round(Row[0]); Y1 := Round(Row[1]); X2 := Round(Row[2]); Y2 := Round(Row[3]);
      line(OutImg.Handle, TCVPoint.Create(X1, Y1), TCVPoint.Create(X2, Y2), TCVScalar.Create(0, 0, 255), 2, LINE_8, 0);
      BboxArr := TJSONArray.Create;
      BboxArr.Add(IntToStr(X1)); BboxArr.Add(IntToStr(Y1)); BboxArr.Add(IntToStr(X2)); BboxArr.Add(IntToStr(Y2));
      CodeItem := TJSONObject.Create;
      CodeItem.AddPair('line', BboxArr);
      Regions.Add(CodeItem);
    end;
    TOpenCVHelpers.EnsureOutputDir(OutputPath);
    imwritePath(OutputPath, OutImg.Handle);
    Result.AddPair('status', 'success');
    Result.AddPair('lines', Regions);
    Result.AddPair('count', TJSONNumber.Create(N));
    Result.AddPair('outputPath', OutputPath);
    Exit;
  end;

  if Name = 'image_detect_circles' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    if not TOpenCVHelpers.RequireOutputPath(Args, 'output', OutputPath, Err) then
    begin Result.AddPair('error', Err); Exit; end;
    Img := imreadPath(ImagePath, IMREAD_COLOR);
    Gray := TCVMat.Create_0(0, 0, CV_8UC1);
    Circles := TCVMat.Create_0(0, 0, CV_32F);
    cvtColor(Img.Handle, Gray.Handle, COLOR_BGR2GRAY, 0, 0);
    GaussianBlur(Gray.Handle, Gray.Handle, TCVSize.Create(9, 9), 2, 2, 0, 0);
    HoughCircles(Gray.Handle, Circles.Handle, HOUGH_GRADIENT, 1, Gray.rows div 8, 100, 30, 1, 0);
    OutImg := Img.clone;
    Regions := TJSONArray.Create;
    N := Circles.cols;
    for I := 0 to N - 1 do
    begin
      CX := Round(PSingle(Circles.ptr(0, I))^);
      CY := Round(PSingle(Circles.ptr(1, I))^);
      R := Round(PSingle(Circles.ptr(2, I))^);
      circle(OutImg.Handle, TCVPoint.Create(CX, CY), R, TCVScalar.Create(0, 255, 0), 2, LINE_8, 0);
      CodeItem := TJSONObject.Create;
      CodeItem.AddPair('x', TJSONNumber.Create(CX));
      CodeItem.AddPair('y', TJSONNumber.Create(CY));
      CodeItem.AddPair('radius', TJSONNumber.Create(R));
      Regions.Add(CodeItem);
    end;
    TOpenCVHelpers.EnsureOutputDir(OutputPath);
    imwritePath(OutputPath, OutImg.Handle);
    Result.AddPair('status', 'success');
    Result.AddPair('circles', Regions);
    Result.AddPair('count', TJSONNumber.Create(N));
    Result.AddPair('outputPath', OutputPath);
    Exit;
  end;

  if Name = 'image_transform' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    if not TOpenCVHelpers.RequireOutputPath(Args, 'output', OutputPath, Err) then
    begin Result.AddPair('error', Err); Exit; end;
    Img := imreadPath(ImagePath, IMREAD_COLOR);
    if Img.empty then begin Result.AddPair('error', 'Failed to read image'); Exit; end;
    OutImg := Img;
    CropX := TOpenCVHelpers.GetOptionalInt(Args, 'cropX', 0);
    CropY := TOpenCVHelpers.GetOptionalInt(Args, 'cropY', 0);
    CropW := TOpenCVHelpers.GetOptionalInt(Args, 'cropWidth', 0);
    CropH := TOpenCVHelpers.GetOptionalInt(Args, 'cropHeight', 0);
    if (CropW > 0) and (CropH > 0) then
    begin
      CropRect := TCVRect.Create(CropX, CropY, CropW, CropH);
      OutImg := OutImg.rowRange(CropY, CropY + CropH).colRange(CropX, CropX + CropW).clone;
    end;
    Width := TOpenCVHelpers.GetOptionalInt(Args, 'width', 0);
    Height := TOpenCVHelpers.GetOptionalInt(Args, 'height', 0);
    if (Width > 0) and (Height > 0) then
    begin
      Img := TCVMat.Create_0(0, 0, CV_8UC3);
      resize(OutImg.Handle, Img.Handle, TCVSize.Create(Width, Height), 0, 0, INTER_LINEAR);
      OutImg := Img;
    end;
    Angle := TOpenCVHelpers.GetOptionalDouble(Args, 'angle', 0);
    if Abs(Angle) > 0.01 then
    begin
      Center := TCVPoint2f.Create(OutImg.cols / 2, OutImg.rows / 2);
      M := getRotationMatrix2D(Center, Angle, 1.0);
      Img := TCVMat.Create_0(0, 0, CV_8UC3);
      warpAffine(OutImg.Handle, Img.Handle, M.Handle, TCVSize.Create(OutImg.cols, OutImg.rows),
        INTER_LINEAR, BORDER_CONSTANT, TCVScalar.Create(0, 0, 0), 0);
      OutImg := Img;
    end;
    TOpenCVHelpers.EnsureOutputDir(OutputPath);
    if imwritePath(OutputPath, OutImg.Handle) then
    begin
      Result.AddPair('status', 'success');
      Result.AddPair('outputPath', OutputPath);
      Result.AddPair('width', TJSONNumber.Create(OutImg.cols));
      Result.AddPair('height', TJSONNumber.Create(OutImg.rows));
    end
    else
      Result.AddPair('error', 'Failed to save image');
    Exit;
  end;

  if Name = 'image_annotate' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath', ImagePath) then
    begin Result.AddPair('error', 'imagePath is required'); Exit; end;
    if not TOpenCVHelpers.RequireOutputPath(Args, 'output', OutputPath, Err) then
    begin Result.AddPair('error', Err); Exit; end;
    Mode := 'both';
    Args.TryGetValue('mode', Mode);
    ScoreThreshold := TOpenCVHelpers.GetOptionalDouble(Args, 'scoreThreshold', 0.25);
    Img := TOpenCVHelpers.LoadImagePath(ImagePath, Err);
    if Img.empty then begin Result.AddPair('error', Err); Exit; end;
    OutImg := Img.clone;
    if SameText(Mode, 'objects') or SameText(Mode, 'both') then
    begin
      ModelPath := TOpenCVHelpers.ResolveModelPath('object_detection_yolox_2022nov.onnx');
      if not FileExists(ModelPath) then
        ModelPath := TOpenCVHelpers.ResolveModelPath('detection_yolox.onnx');
      if FileExists(ModelPath) then
      begin
        Model := TCVDetectionModel.Create(PAnsiChar(PathToUTF8(ModelPath)), nil);
        Model.setInputSize(640, 640);
        ClassIds := TCVMat.Create_0(0, 1, CV_32S);
        Confidences := TCVMat.Create_0(0, 1, CV_32F);
        Boxes := TCVMat.Create_0(0, 4, CV_32S);
        DetCount := Model.detect(OutImg.Handle, ClassIds.Handle, Confidences.Handle, Boxes.Handle, Single(ScoreThreshold), 0.45);
        for I := 0 to DetCount - 1 do
        begin
          ClassId := PInteger(ClassIds.ptr(I, 0))^;
          X := PInteger(Boxes.ptr(I, 0))^;
          Y := PInteger(Boxes.ptr(I, 1))^;
          W := PInteger(Boxes.ptr(I, 2))^;
          H := PInteger(Boxes.ptr(I, 3))^;
          rectangle(OutImg.Handle, TCVRect.Create(X, Y, W, H), TCVScalar.Create(0, 255, 0), 2, LINE_8, 0);
          ObjLabel := 'id' + IntToStr(ClassId);
          putText(OutImg.Handle, PAnsiChar(AnsiString(ObjLabel)), TCVPoint.Create(X, Max(0, Y - 5)),
            FONT_HERSHEY_SIMPLEX, 0.5, TCVScalar.Create(0, 255, 0), 1, LINE_8, False);
        end;
      end;
    end;
    if SameText(Mode, 'faces') or SameText(Mode, 'both') then
    begin
      DetPath := TOpenCVHelpers.ResolveModelPath('face_detection_yunet_2026may.onnx');
      if FileExists(DetPath) then
      begin
        Det := TCVFaceDetectorYN.Create(PAnsiChar(PathToUTF8(DetPath)), nil,
          TCVSize.Create(OutImg.cols, OutImg.rows), 0.5, 0.3, 5000);
        Faces := TCVMat.Create_0(0, 0, CV_32FC1);
        if Det.detect(OutImg.Handle, Faces.Handle) > 0 then
          drawDetectedFaces(OutImg.Handle, Faces);
      end;
    end;
    TOpenCVHelpers.EnsureOutputDir(OutputPath);
    if imwritePath(OutputPath, OutImg.Handle) then
    begin
      Result.AddPair('status', 'success');
      Result.AddPair('outputPath', OutputPath);
      Result.AddPair('mode', Mode);
    end
    else
      Result.AddPair('error', 'Failed to save annotated image');
    Exit;
  end;

  raise Exception.Create('Image tool not found: ' + Name);
end;

end.

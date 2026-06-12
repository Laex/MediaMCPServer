unit uOpenCVVideoTools;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Math,
  OpenCV5.Core, OpenCV5.Imgcodecs, OpenCV5.Imgproc, OpenCV5.Videoio, OpenCV5.Video,
  OpenCV5.Tracking, OpenCV5.Arith, OpenCV5.Types, OpenCV5.Utils,
  uOpenCVHelpers;

type
  TOpenCVVideoTools = class
  public
    class procedure RegisterTools(Schema: TJSONArray);
    class function CallTool(const Name: string; Args: TJSONObject): TJSONObject;
  end;

implementation

uses
  Winapi.Windows;

function Fourcc(const C1, C2, C3, C4: AnsiChar): Integer;
begin
  Result := Integer(Byte(C1)) or (Integer(Byte(C2)) shl 8) or
    (Integer(Byte(C3)) shl 16) or (Integer(Byte(C4)) shl 24);
end;

class procedure TOpenCVVideoTools.RegisterTools(Schema: TJSONArray);
var
  Props: TJSONObject;
  P: TJSONObject;
  Item: TJSONObject;
begin
  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('cameraIndex', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('outputPath', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('durationMs', P);
  P := TJSONObject.Create; P.AddPair('type', 'number'); Props.AddPair('fps', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('width', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('height', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('backend', P);
  Item := TOpenCVHelpers.AddToolSchema('webcam_record_video',
    'Record video from a webcam for a specified duration (no GUI).',
    Props, ['outputPath', 'durationMs']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('cameraIndex', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('x', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('y', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('width', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('height', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('frameCount', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('outputPath', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('backend', P);
  Item := TOpenCVHelpers.AddToolSchema('video_track_object',
    'Track an object in a webcam stream using TrackerNano. Provide initial bbox and frame count.',
    Props, ['x', 'y', 'width', 'height', 'frameCount', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('imagePath1', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('imagePath2', P);
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('outputPath', P);
  Item := TOpenCVHelpers.AddToolSchema('image_optical_flow',
    'Compute dense optical flow between two images (Farneback). Saves flow visualization.',
    Props, ['imagePath1', 'imagePath2', 'outputPath']);
  Schema.Add(Item);
end;

class function TOpenCVVideoTools.CallTool(const Name: string; Args: TJSONObject): TJSONObject;
var
  OutputPath, ImagePath1, ImagePath2, BackendStr, Err: string;
  Cap: TCVVideoCapture;
  Writer: TCVVideoWriter;
  Frame, PrevGray, Gray, Flow, Magnitude, OutBgr: TCVMat;
  Tracker: TCVTrackerNano;
  Bbox: TCVRect;
  CameraIndex, DurationMs, Width, Height, FrameCount, I, FramesWritten: Integer;
  BackendId, X, Y, W, H: Integer;
  Fps: Double;
  FrameSize: TCVSize;
  FourccVal: Integer;
  StartTick, Elapsed: Cardinal;
  Img1, Img2: TCVMat;
  FlowMag: Double;
  Fx, Fy, Mag: Single;
  MeanVal, StdVal: TCVScalar;
  J: Integer;
  Tracks, BboxArr: TJSONArray;
  TrackItem: TJSONObject;
begin
  if Name = 'webcam_record_video' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireOutputPath(Args, 'video', OutputPath, Err) then
    begin Result.AddPair('error', Err); Exit; end;
    DurationMs := TOpenCVHelpers.GetOptionalInt(Args, 'durationMs', 3000);
    CameraIndex := TOpenCVHelpers.GetOptionalInt(Args, 'cameraIndex', 0);
    Width := TOpenCVHelpers.GetOptionalInt(Args, 'width', 640);
    Height := TOpenCVHelpers.GetOptionalInt(Args, 'height', 480);
    Fps := TOpenCVHelpers.GetOptionalDouble(Args, 'fps', 25);
    Args.TryGetValue('backend', BackendStr);
    BackendId := TOpenCVHelpers.ParseBackend(BackendStr);
    Cap := TCVVideoCapture.Create_2(CameraIndex, BackendId);
    try
      if not Cap.isOpened then
      begin Result.AddPair('error', 'Failed to open webcam'); Exit; end;
      Cap.setProp(CAP_PROP_FRAME_WIDTH, Width);
      Cap.setProp(CAP_PROP_FRAME_HEIGHT, Height);
      FrameSize := TCVSize.Create(Trunc(Cap.getProp(CAP_PROP_FRAME_WIDTH)),
        Trunc(Cap.getProp(CAP_PROP_FRAME_HEIGHT)));
      FourccVal := Fourcc('M', 'J', 'P', 'G');
      Writer := TCVVideoWriter.Create_1(PAnsiChar(PathToUTF8(OutputPath)), FourccVal, Fps, FrameSize, True);
      try
        if not Writer.isOpened then
        begin Result.AddPair('error', 'Cannot create video writer'); Exit; end;
        Frame := TCVMat.Create_0(0, 0, CV_8UC3);
        FramesWritten := 0;
        StartTick := GetTickCount;
        while Integer(GetTickCount - StartTick) < DurationMs do
        begin
          if not Cap.read(Frame) then
            Break;
          Writer.write(Frame.Handle);
          Inc(FramesWritten);
        end;
        Result.AddPair('status', 'success');
        Result.AddPair('outputPath', OutputPath);
        Result.AddPair('frames', TJSONNumber.Create(FramesWritten));
        Result.AddPair('durationMs', TJSONNumber.Create(DurationMs));
      finally
        Writer.Release;
      end;
    finally
      Cap.Release;
    end;
    Exit;
  end;

  if Name = 'video_track_object' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireOutputPath(Args, 'video', OutputPath, Err) then
    begin Result.AddPair('error', Err); Exit; end;
    X := TOpenCVHelpers.GetOptionalInt(Args, 'x', -1);
    Y := TOpenCVHelpers.GetOptionalInt(Args, 'y', -1);
    W := TOpenCVHelpers.GetOptionalInt(Args, 'width', -1);
    H := TOpenCVHelpers.GetOptionalInt(Args, 'height', -1);
    if (X < 0) or (Y < 0) or (W <= 0) or (H <= 0) then
    begin Result.AddPair('error', 'x, y, width, height are required'); Exit; end;
    FrameCount := TOpenCVHelpers.GetOptionalInt(Args, 'frameCount', 30);
    CameraIndex := TOpenCVHelpers.GetOptionalInt(Args, 'cameraIndex', 0);
    Args.TryGetValue('backend', BackendStr);
    BackendId := TOpenCVHelpers.ParseBackend(BackendStr);
    Cap := TCVVideoCapture.Create_2(CameraIndex, BackendId);
    try
      if not Cap.isOpened then
      begin Result.AddPair('error', 'Failed to open webcam'); Exit; end;
      Frame := TCVMat.Create_0(0, 0, CV_8UC3);
      if not Cap.read(Frame) or Frame.empty then
      begin Result.AddPair('error', 'Failed to read first frame'); Exit; end;
      Bbox := TCVRect.Create(X, Y, W, H);
      Tracker := TCVTrackerNano.Create;
      if Tracker.Handle = nil then
      begin Result.AddPair('error', 'TrackerNano failed (need backbone.onnx + neckhead.onnx in bin)'); Exit; end;
      Tracker.init(Frame.Handle, Bbox);
      FrameSize := TCVSize.Create(Frame.cols, Frame.rows);
      Writer := TCVVideoWriter.Create_1(PAnsiChar(PathToUTF8(OutputPath)), Fourcc('M', 'J', 'P', 'G'), 25, FrameSize, True);
      try
        Tracks := TJSONArray.Create;
        for I := 0 to FrameCount - 1 do
        begin
          if not Cap.read(Frame) or Frame.empty then
            Break;
          if not Tracker.update(Frame.Handle, Bbox) then
            Break;
          OpenCV5.Imgproc.rectangle(Frame.Handle, Bbox, TCVScalar.Create(0, 255, 0), 2, LINE_8, 0);
          Writer.write(Frame.Handle);
          TrackItem := TJSONObject.Create;
          BboxArr := TJSONArray.Create;
          BboxArr.Add(Bbox.X); BboxArr.Add(Bbox.Y);
          BboxArr.Add(Bbox.Width); BboxArr.Add(Bbox.Height);
          TrackItem.AddPair('frame', TJSONNumber.Create(I));
          TrackItem.AddPair('bbox', BboxArr);
          Tracks.Add(TrackItem);
        end;
        Result.AddPair('status', 'success');
        Result.AddPair('outputPath', OutputPath);
        Result.AddPair('tracks', Tracks);
        Result.AddPair('frameCount', TJSONNumber.Create(Tracks.Count));
      finally
        Writer.Release;
      end;
    finally
      Cap.Release;
    end;
    Exit;
  end;

  if Name = 'image_optical_flow' then
  begin
    Result := TJSONObject.Create;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath1', ImagePath1) then
    begin Result.AddPair('error', 'imagePath1 is required'); Exit; end;
    if not TOpenCVHelpers.RequireString(Args, 'imagePath2', ImagePath2) then
    begin Result.AddPair('error', 'imagePath2 is required'); Exit; end;
    if not TOpenCVHelpers.RequireOutputPath(Args, 'output', OutputPath, Err) then
    begin Result.AddPair('error', Err); Exit; end;
    Img1 := TOpenCVHelpers.LoadImagePath(ImagePath1, Err);
    if Img1.empty then begin Result.AddPair('error', 'imagePath1: ' + Err); Exit; end;
    Img2 := TOpenCVHelpers.LoadImagePath(ImagePath2, Err);
    if Img2.empty then begin Result.AddPair('error', 'imagePath2: ' + Err); Exit; end;
    if (Img1.cols <> Img2.cols) or (Img1.rows <> Img2.rows) then
    begin
      resize(Img2.Handle, Img2.Handle, TCVSize.Create(Img1.cols, Img1.rows), 0, 0, INTER_LINEAR);
    end;
    PrevGray := TCVMat.Create_0(0, 0, CV_8UC1);
    Gray := TCVMat.Create_0(0, 0, CV_8UC1);
    Flow := TCVMat.Create_0(0, 0, CV_32FC2);
    cvtColor(Img1.Handle, PrevGray.Handle, COLOR_BGR2GRAY, 0, 0);
    cvtColor(Img2.Handle, Gray.Handle, COLOR_BGR2GRAY, 0, 0);
    calcOpticalFlowFarneback(PrevGray.Handle, Gray.Handle, Flow.Handle, 0.5, 3, 15, 3, 5, 1.2, 0);
    Magnitude := TCVMat.Create_0(Img1.rows, Img1.cols, CV_8UC1);
    for I := 0 to Img1.rows - 1 do
      for J := 0 to Img1.cols - 1 do
      begin
        Fx := PSingle(Flow.ptr(I, J))^;
        Fy := PSingle(PByte(Flow.ptr(I, J)) + SizeOf(Single))^;
        Mag := Sqrt(Fx * Fx + Fy * Fy);
        PByte(Magnitude.ptr(I, J))^ := Byte(Min(255, Trunc(Mag * 20)));
      end;
    OutBgr := TCVMat.Create_0(0, 0, CV_8UC3);
    cvtColor(Magnitude.Handle, OutBgr.Handle, COLOR_GRAY2BGR, 0, 0);
    TOpenCVHelpers.EnsureOutputDir(OutputPath);
    imwritePath(OutputPath, OutBgr.Handle);
    meanStdDev(Magnitude.Handle, MeanVal, StdVal);
    FlowMag := MeanVal.V0;
    Result.AddPair('status', 'success');
    Result.AddPair('outputPath', OutputPath);
    Result.AddPair('meanMotion', TJSONNumber.Create(FlowMag));
    Exit;
  end;

  raise Exception.Create('Video tool not found: ' + Name);
end;

end.

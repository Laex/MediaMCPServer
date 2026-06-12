unit uOpenCVTools;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils,
  OpenCV5.Core, OpenCV5.Imgcodecs, OpenCV5.Dnn, OpenCV5.Objdetect, OpenCV5.Utils, OpenCV5.Types, OpenCV5.System, OpenCV5.Videoio;

type
  TOpenCVTools = class
  private
    const
      COCO_CLASSES: array[0..79] of string = (
        'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train', 'truck', 'boat', 'traffic light',
        'fire hydrant', 'stop sign', 'parking meter', 'bench', 'bird', 'cat', 'dog', 'horse', 'sheep', 'cow',
        'elephant', 'bear', 'zebra', 'giraffe', 'backpack', 'umbrella', 'handbag', 'tie', 'suitcase', 'frisbee',
        'skis', 'snowboard', 'sports ball', 'kite', 'baseball bat', 'baseball glove', 'skateboard', 'surfboard',
        'tennis racket', 'bottle', 'wine glass', 'cup', 'fork', 'knife', 'spoon', 'bowl', 'banana', 'apple',
        'sandwich', 'orange', 'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake', 'chair', 'couch',
        'potted plant', 'bed', 'dining table', 'toilet', 'tv', 'laptop', 'mouse', 'remote', 'keyboard', 'cell phone',
        'microwave', 'oven', 'toaster', 'sink', 'refrigerator', 'book', 'clock', 'vase', 'scissors', 'teddy bear',
        'hair drier', 'toothbrush'
      );
    class function ResolveModelPath(const ModelName: string): string; // delegates to TOpenCVHelpers
    class function GetClassName(ClassId: Integer): string;
    class function ProbeWebcamsFallback: TJSONArray;
  public
    class function DetectObjects(Args: TJSONObject): TJSONObject;
    class function DetectFaces(Args: TJSONObject): TJSONObject;
    class function WebcamList(Args: TJSONObject): TJSONObject;
    class function WebcamGrabFrame(Args: TJSONObject): TJSONObject;
  end;

implementation

uses
  Winapi.Windows, Winapi.ActiveX, System.Win.ComObj, uOpenCVHelpers;

const
  CLSID_SystemDeviceEnum: TGUID = '{62EC3E0B-077E-11D2-8A8D-00C04F8ECB83}';
  IID_ICreateDevEnum: TGUID = '{29840C25-D34F-11D1-883A-3C8F7838F6E4}';
  CLSID_VideoInputDeviceCategory: TGUID = '{860BB310-5D01-11d0-BD3B-00A0C911CE86}';
  IID_IPropertyBag: TGUID = '{55018901-265A-11D0-82D2-00A0C9223196}';

  CAP_PROP_BRIGHTNESS = 10;
  CAP_PROP_CONTRAST = 11;
  CAP_PROP_SATURATION = 12;
  CAP_PROP_HUE = 13;
  CAP_PROP_GAIN = 14;
  CAP_PROP_EXPOSURE = 15;

type
  IDShowPropertyBag = interface(IUnknown)
    ['{55018901-265A-11D0-82D2-00A0C9223196}']
    function Read(pszPropName: POleStr; out pVar: OleVariant; pErrorLog: Pointer): HResult; stdcall;
    function Write(pszPropName: POleStr; var pVar: OleVariant): HResult; stdcall;
  end;

  ICreateDevEnum = interface(IUnknown)
    ['{29840C25-D34F-11D1-883A-3C8F7838F6E4}']
    function CreateClassEnumerator(const clsidDeviceClass: TGUID;
      out ppEnumMoniker: IEnumMoniker; dwFlags: DWORD): HRESULT; stdcall;
  end;

class function TOpenCVTools.ProbeWebcamsFallback: TJSONArray;
var
  I: Integer;
  Cap: TCVVideoCapture;
  CamItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for I := 0 to 4 do
  begin
    Cap := TCVVideoCapture.Create_2(I, CAP_ANY);
    try
      if Cap.isOpened then
      begin
        CamItem := TJSONObject.Create;
        CamItem.AddPair('index', TJSONNumber.Create(I));
        CamItem.AddPair('name', 'Webcam #' + IntToStr(I));
        CamItem.AddPair('defaultWidth', TJSONNumber.Create(Cap.getProp(CAP_PROP_FRAME_WIDTH)));
        CamItem.AddPair('defaultHeight', TJSONNumber.Create(Cap.getProp(CAP_PROP_FRAME_HEIGHT)));
        Result.Add(CamItem);
      end;
    finally
      Cap.Release;
    end;
  end;
end;

class function TOpenCVTools.ResolveModelPath(const ModelName: string): string;
begin
  Result := TOpenCVHelpers.ResolveModelPath(ModelName);
end;

class function TOpenCVTools.GetClassName(ClassId: Integer): string;
begin
  if (ClassId >= 0) and (ClassId <= High(COCO_CLASSES)) then
    Result := COCO_CLASSES[ClassId]
  else
    Result := 'unknown';
end;

class function TOpenCVTools.DetectObjects(Args: TJSONObject): TJSONObject;
var
  ImagePath: string;
  ModelPath: string;
  Model: TCVDetectionModel;
  Img: TCVMat;
  ClassIds: TCVMat;
  Confidences: TCVMat;
  Boxes: TCVMat;
  DetectionsCount: Integer;
  I: Integer;
  ObjArray: TJSONArray;
  ObjItem: TJSONObject;
  BboxArray: TJSONArray;
  ClassId: Integer;
  Conf: Single;
  X, Y, W, H: Integer;
begin
  Result := TJSONObject.Create;

  if not Args.TryGetValue('imagePath', ImagePath) then
  begin
    Result.AddPair('error', 'imagePath argument is required');
    Exit;
  end;

  if not FileExists(ImagePath) then
  begin
    Result.AddPair('error', 'Image file not found: ' + ImagePath);
    Exit;
  end;

  ModelPath := ResolveModelPath('object_detection_yolox_2022nov.onnx');
  if not FileExists(ModelPath) then
    ModelPath := ResolveModelPath('detection_yolox.onnx');

  if not FileExists(ModelPath) then
  begin
    Result.AddPair('error', 'YOLOX detection model not found. Checked: ' + ModelPath);
    Exit;
  end;

  try
    // Initialize YOLOX detection model
    // OpenCV5.Utils.PathToUTF8 converts the wide string path to UTF-8
    Model := TCVDetectionModel.Create(PAnsiChar(PathToUTF8(ModelPath)), nil);
    if Model.Handle = nil then
    begin
      Result.AddPair('error', 'Failed to initialize DetectionModel: ' + string(getLastOpenCVError));
      Exit;
    end;

    // Load Image
    Img := imreadPath(ImagePath, IMREAD_COLOR);
    if Img.empty then
    begin
      Result.AddPair('error', 'Failed to load image via OpenCV: ' + ImagePath);
      Exit;
    end;

    // Setup input shape for YOLOX
    Model.setInputSize(640, 640);
    
    // Allocate outputs
    ClassIds := TCVMat.Create_0(0, 1, CV_32S);
    Confidences := TCVMat.Create_0(0, 1, CV_32F);
    Boxes := TCVMat.Create_0(0, 4, CV_32S);

    // Run object detection (Threshold: 0.25, NMS: 0.45)
    DetectionsCount := Model.detect(Img.Handle, ClassIds.Handle, Confidences.Handle, Boxes.Handle, 0.25, 0.45);
    if DetectionsCount < 0 then
    begin
      Result.AddPair('error', 'OpenCV detect function returned error code');
      Exit;
    end;

    ObjArray := TJSONArray.Create;
    
    for I := 0 to DetectionsCount - 1 do
    begin
      ClassId := PInteger(ClassIds.ptr(I, 0))^;
      Conf := PSingle(Confidences.ptr(I, 0))^;
      X := PInteger(Boxes.ptr(I, 0))^;
      Y := PInteger(Boxes.ptr(I, 1))^;
      W := PInteger(Boxes.ptr(I, 2))^;
      H := PInteger(Boxes.ptr(I, 3))^;

      ObjItem := TJSONObject.Create;
      ObjItem.AddPair('classId', TJSONNumber.Create(ClassId));
      ObjItem.AddPair('className', GetClassName(ClassId));
      ObjItem.AddPair('confidence', TJSONNumber.Create(Conf));
      
      BboxArray := TJSONArray.Create;
      BboxArray.Add(X);
      BboxArray.Add(Y);
      BboxArray.Add(W);
      BboxArray.Add(H);
      ObjItem.AddPair('bbox', BboxArray);

      ObjArray.Add(ObjItem);
    end;

    Result.AddPair('status', 'success');
    Result.AddPair('detections', ObjArray);
    Result.AddPair('count', TJSONNumber.Create(DetectionsCount));

  except
    on E: Exception do
    begin
      Result.AddPair('error', E.Message);
    end;
  end;
end;

class function TOpenCVTools.DetectFaces(Args: TJSONObject): TJSONObject;
var
  ImagePath, ModelPath: string;
  ScoreThreshold: Double;
  Img: TCVMat;
  Detector: TCVFaceDetectorYN;
  Faces: TCVMat;
  InputSize: TCVSize;
  FaceCount, I, L: Integer;
  FacesArray, BboxArray, LandmarksArray, PtArray: TJSONArray;
  FaceItem: TJSONObject;
  X, Y, W, H: Integer;
  Score: Single;
begin
  Result := TJSONObject.Create;

  if not Args.TryGetValue('imagePath', ImagePath) then
  begin
    Result.AddPair('error', 'imagePath argument is required');
    Exit;
  end;

  if not FileExists(ImagePath) then
  begin
    Result.AddPair('error', 'Image file not found: ' + ImagePath);
    Exit;
  end;

  ModelPath := ResolveModelPath('face_detection_yunet_2026may.onnx');
  if not FileExists(ModelPath) then
    ModelPath := ResolveModelPath('face_detection_yunet_2023mar.onnx');

  if not FileExists(ModelPath) then
  begin
    Result.AddPair('error', 'YuNet face detection model not found. ' + FaceDetectorModelMissingHint);
    Exit;
  end;

  ScoreThreshold := 0.5;
  Args.TryGetValue('scoreThreshold', ScoreThreshold);

  try
    Img := imreadPath(ImagePath, IMREAD_COLOR);
    if Img.empty then
    begin
      Result.AddPair('error', 'Failed to load image via OpenCV: ' + ImagePath);
      Exit;
    end;

    InputSize := TCVSize.Create(Img.cols, Img.rows);
    Detector := TCVFaceDetectorYN.Create(
      PAnsiChar(PathToUTF8(ModelPath)),
      nil,
      InputSize,
      ScoreThreshold,
      0.3,
      5000
    );
    if Detector.Handle = nil then
    begin
      Result.AddPair('error', 'Failed to initialize YuNet face detector: ' + string(getLastOpenCVError));
      Exit;
    end;

    Faces := TCVMat.Create_0(0, 0, CV_32FC1);
    FaceCount := Detector.detect(Img.Handle, Faces.Handle);
    if FaceCount < 0 then
    begin
      Result.AddPair('error', 'YuNet detect returned error code');
      Exit;
    end;

    FacesArray := TJSONArray.Create;
    for I := 0 to FaceCount - 1 do
    begin
      X := Trunc(ReadFaceFloat(Faces, I, FACE_IDX_X));
      Y := Trunc(ReadFaceFloat(Faces, I, FACE_IDX_Y));
      W := Trunc(ReadFaceFloat(Faces, I, FACE_IDX_W));
      H := Trunc(ReadFaceFloat(Faces, I, FACE_IDX_H));
      Score := ReadFaceFloat(Faces, I, FACE_IDX_SCORE);

      FaceItem := TJSONObject.Create;
      FaceItem.AddPair('confidence', TJSONNumber.Create(Score));

      BboxArray := TJSONArray.Create;
      BboxArray.Add(X);
      BboxArray.Add(Y);
      BboxArray.Add(W);
      BboxArray.Add(H);
      FaceItem.AddPair('bbox', BboxArray);

      LandmarksArray := TJSONArray.Create;
      for L := 0 to 4 do
      begin
        PtArray := TJSONArray.Create;
        PtArray.Add(Trunc(ReadFaceFloat(Faces, I, 4 + 2 * L)));
        PtArray.Add(Trunc(ReadFaceFloat(Faces, I, 5 + 2 * L)));
        LandmarksArray.Add(PtArray);
      end;
      FaceItem.AddPair('landmarks', LandmarksArray);

      FacesArray.Add(FaceItem);
    end;

    Result.AddPair('status', 'success');
    Result.AddPair('faces', FacesArray);
    Result.AddPair('count', TJSONNumber.Create(FaceCount));
    Result.AddPair('model', ExtractFileName(ModelPath));
  except
    on E: Exception do
    begin
      Result.AddPair('error', E.Message);
    end;
  end;
end;

class function TOpenCVTools.WebcamList(Args: TJSONObject): TJSONObject;
var
  CreateDevEnum: ICreateDevEnum;
  EnumMoniker: IEnumMoniker;
  Moniker: IMoniker;
  Fetched: LongInt;
  PropBag: IDShowPropertyBag;
  VariantName: OleVariant;
  Hr: HResult;
  CamerasArray: TJSONArray;
  CamItem: TJSONObject;
  CamIndex: Integer;
  FriendlyName: string;
  CoInitResult: HRESULT;
  Cap: TCVVideoCapture;
begin
  Result := TJSONObject.Create;
  try
    CamerasArray := TJSONArray.Create;
    CoInitResult := CoInitialize(nil);
    try
      try
        CreateDevEnum := CreateComObject(CLSID_SystemDeviceEnum) as ICreateDevEnum;
        Hr := CreateDevEnum.CreateClassEnumerator(CLSID_VideoInputDeviceCategory, EnumMoniker, 0);
        if Hr = S_OK then
        begin
          CamIndex := 0;
          while EnumMoniker.Next(1, Moniker, @Fetched) = S_OK do
          begin
            FriendlyName := 'Webcam #' + IntToStr(CamIndex);
            
            Hr := Moniker.BindToStorage(nil, nil, IID_IPropertyBag, PropBag);
            if Succeeded(Hr) then
            begin
              VariantName := '';
              if Succeeded(PropBag.Read('FriendlyName', VariantName, nil)) then
                FriendlyName := string(VariantName);
              PropBag := nil;
            end;
            
            CamItem := TJSONObject.Create;
            CamItem.AddPair('index', TJSONNumber.Create(CamIndex));
            CamItem.AddPair('name', FriendlyName);
            
            // Probe default resolution for this specific webcam
            Cap := TCVVideoCapture.Create_2(CamIndex, CAP_DSHOW);
            try
              if Cap.isOpened then
              begin
                CamItem.AddPair('defaultWidth', TJSONNumber.Create(Cap.getProp(CAP_PROP_FRAME_WIDTH)));
                CamItem.AddPair('defaultHeight', TJSONNumber.Create(Cap.getProp(CAP_PROP_FRAME_HEIGHT)));
              end
              else
              begin
                CamItem.AddPair('defaultWidth', TJSONNumber.Create(640));
                CamItem.AddPair('defaultHeight', TJSONNumber.Create(480));
              end;
            finally
              Cap.Release;
            end;
            
            CamerasArray.Add(CamItem);
            Inc(CamIndex);
            Moniker := nil;
          end;
        end
        else
        begin
          // If DirectShow returns S_FALSE (no devices) or other codes, try fallback
          FreeAndNil(CamerasArray);
          CamerasArray := ProbeWebcamsFallback;
        end;
      except
        on E: Exception do
        begin
          // If COM/DirectShow fails, fallback to traditional probing method
          if Assigned(CamerasArray) then
            FreeAndNil(CamerasArray);
          CamerasArray := ProbeWebcamsFallback;
        end;
      end;
    finally
      if (CoInitResult = S_OK) or (CoInitResult = S_FALSE) then
        CoUninitialize;
    end;
    
    Result.AddPair('status', 'success');
    Result.AddPair('cameras', CamerasArray);
  except
    on E: Exception do
    begin
      Result.AddPair('error', E.Message);
    end;
  end;
end;

class function TOpenCVTools.WebcamGrabFrame(Args: TJSONObject): TJSONObject;
var
  CameraIndex: Integer;
  CameraUrl: string;
  OutputPath: string;
  Err: string;
  Width, Height: Integer;
  BackendStr: string;
  BackendId: Integer;
  Cap: TCVVideoCapture;
  Frame: TCVMat;
  Success: Boolean;
  ValBrightness: Double;
  ValContrast: Double;
  ValExposure: Double;
  ValGain: Double;
begin
  Result := TJSONObject.Create;

  if not TOpenCVHelpers.RequireOutputPath(Args, 'captures', OutputPath, Err) then
  begin
    Result.AddPair('error', Err);
    Exit;
  end;

  if not Args.TryGetValue('cameraIndex', CameraIndex) then
    CameraIndex := 0;
    
  CameraUrl := '';
  Args.TryGetValue('cameraUrl', CameraUrl);
    
  Width := 0;
  Args.TryGetValue('width', Width);
  
  Height := 0;
  Args.TryGetValue('height', Height);
  
  BackendStr := '';
  Args.TryGetValue('backend', BackendStr);
  
  if SameText(BackendStr, 'dshow') then
    BackendId := CAP_DSHOW
  else if SameText(BackendStr, 'msmf') then
    BackendId := CAP_MSMF
  else
    BackendId := CAP_ANY;

  try
    if CameraUrl <> '' then
      Cap := TCVVideoCapture.Create_1(PAnsiChar(PathToUTF8(CameraUrl)), BackendId)
    else
      Cap := TCVVideoCapture.Create_2(CameraIndex, BackendId);
      
    try
      if not Cap.isOpened then
      begin
        if CameraUrl <> '' then
          Result.AddPair('error', Format('Failed to open camera URL: %s', [CameraUrl]))
        else
          Result.AddPair('error', Format('Failed to open webcam at index %d', [CameraIndex]));
        Exit;
      end;

      if Width > 0 then
        Cap.setProp(CAP_PROP_FRAME_WIDTH, Width);
      if Height > 0 then
        Cap.setProp(CAP_PROP_FRAME_HEIGHT, Height);
        
      if Args.TryGetValue('brightness', ValBrightness) then
        Cap.setProp(CAP_PROP_BRIGHTNESS, ValBrightness);
      if Args.TryGetValue('contrast', ValContrast) then
        Cap.setProp(CAP_PROP_CONTRAST, ValContrast);
      if Args.TryGetValue('exposure', ValExposure) then
        Cap.setProp(CAP_PROP_EXPOSURE, ValExposure);
      if Args.TryGetValue('gain', ValGain) then
        Cap.setProp(CAP_PROP_GAIN, ValGain);

      Frame := TCVMat.Create_0(0, 0, CV_8UC3);
      
      if not Cap.read(Frame) then
      begin
        Result.AddPair('error', 'Failed to read frame from webcam');
        Exit;
      end;

      Success := imwritePath(OutputPath, Frame.Handle);
      
      if Success then
      begin
        Result.AddPair('status', 'success');
        Result.AddPair('outputPath', OutputPath);
        Result.AddPair('width', TJSONNumber.Create(Cap.getProp(CAP_PROP_FRAME_WIDTH)));
        Result.AddPair('height', TJSONNumber.Create(Cap.getProp(CAP_PROP_FRAME_HEIGHT)));
      end
      else
      begin
        Result.AddPair('error', 'Failed to save grabbed frame to: ' + OutputPath);
      end;
    finally
      Cap.Release;
    end;
  except
    on E: Exception do
    begin
      Result.AddPair('error', E.Message);
    end;
  end;
end;

end.

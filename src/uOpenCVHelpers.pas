unit uOpenCVHelpers;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Math,
  OpenCV5.Core, OpenCV5.Types, OpenCV5.Objdetect, OpenCV5.Utils, OpenCV5.Videoio;

type
  TOpenCVHelpers = class
  public
    class function ResolveModelPath(const ModelName: string): string;
    class function ResolveFaceDetectorPath: string;
    class function MediaRootDir: string;
    class function MediaDir(const Category: string): string;
    class function FaceDataDir: string;
    class function ResolveOutputPath(const UserPath, Category: string): string;
    class function RequireOutputPath(Args: TJSONObject; const Category: string;
      out Value: string; out Error: string): Boolean;
    class procedure MigrateLegacyMedia;
    class function RequireString(Args: TJSONObject; const Key: string; out Value: string): Boolean;
    class function GetOptionalInt(Args: TJSONObject; const Key: string; const Default: Integer): Integer;
    class function GetOptionalDouble(Args: TJSONObject; const Key: string; const Default: Double): Double;
    class function ParseBackend(const BackendStr: string): Integer;
    class function LoadImagePath(const ImagePath: string; out Error: string): TCVMat;
    class procedure EnsureOutputDir(const OutputPath: string);
    class function MakeError(const Msg: string): TJSONObject;
    class function AddToolSchema(const Name, Description: string;
      const Properties: TJSONObject; const Required: TArray<string>): TJSONObject;
    class function ExtractFirstFaceFeature(const Det: TCVFaceDetectorYN; const Rec: TCVFaceRecognizerSF;
      const Frame, Faces: TCVMat; out Feature: TCVMat): Boolean;
    class procedure SaveFaceFeature(const PersonName: string; const Feature: TCVMat);
    class function LoadFaceFeature(const FilePath: string; out Feature: TCVMat): Boolean;
    class function ListEnrolledFaces: TJSONArray;
  end;

implementation

class function TOpenCVHelpers.ResolveModelPath(const ModelName: string): string;
var
  ExeDir, EnvPath, ParentDir: string;
  RelativeCandidates: array[0..5] of string;
  I: Integer;

  function TryModelsDir(const BaseDir: string; out ModelPath: string): Boolean;
  begin
    ModelPath := TPath.GetFullPath(TPath.Combine(TPath.Combine(BaseDir, 'models'), ModelName));
    Result := FileExists(ModelPath);
  end;
begin
  EnvPath := GetEnvironmentVariable('OPENCV_MODELS_PATH');
  if EnvPath = '' then
    EnvPath := GetEnvironmentVariable('MEDIA_MCP_MODELS_PATH');
  if EnvPath <> '' then
  begin
    Result := TPath.Combine(EnvPath, ModelName);
    if FileExists(Result) then
      Exit;
  end;

  ExeDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
  Result := TPath.Combine(TPath.Combine(ExeDir, 'models'), ModelName);
  if FileExists(Result) then
    Exit;

  RelativeCandidates[0] := '..\..\OpenCV\OpenCV 5.0\bin';
  RelativeCandidates[1] := '..\OpenCV\OpenCV 5.0\bin';
  RelativeCandidates[2] := '..\..\..\OpenCV\OpenCV 5.0\bin';
  RelativeCandidates[3] := '..\..\OpenCV 5.0\bin';
  RelativeCandidates[4] := '..\OpenCV 5.0\bin';
  RelativeCandidates[5] := '..\..\..\OpenCV 5.0\bin';
  for I := Low(RelativeCandidates) to High(RelativeCandidates) do
  begin
    if TryModelsDir(TPath.GetFullPath(TPath.Combine(ExeDir, RelativeCandidates[I])), Result) then
      Exit;
  end;

  ParentDir := ExeDir;
  for I := 1 to 6 do
  begin
    ParentDir := ExtractFilePath(ExcludeTrailingPathDelimiter(ParentDir));
    if ParentDir = '' then
      Break;
    if TryModelsDir(TPath.Combine(TPath.Combine(ParentDir, 'OpenCV'), 'OpenCV 5.0\bin'), Result) then
      Exit;
    if TryModelsDir(TPath.Combine(TPath.Combine(ParentDir, 'OpenCV 5.0'), 'bin'), Result) then
      Exit;
  end;

  Result := ModelName;
end;

class function TOpenCVHelpers.ResolveFaceDetectorPath: string;
begin
  Result := ResolveModelPath('face_detection_yunet_2026may.onnx');
  if FileExists(Result) then
    Exit;
  Result := ResolveModelPath('face_detection_yunet_2023mar.onnx');
end;

class function TOpenCVHelpers.MediaRootDir: string;
var
  EnvPath, ExeDir: string;
begin
  EnvPath := GetEnvironmentVariable('MEDIA_MCP_DATA_PATH');
  if EnvPath <> '' then
    Result := IncludeTrailingPathDelimiter(TPath.GetFullPath(EnvPath))
  else
  begin
    ExeDir := ExtractFilePath(ParamStr(0));
    Result := IncludeTrailingPathDelimiter(TPath.GetFullPath(TPath.Combine(ExeDir, '..\data\media')));
  end;
  ForceDirectories(Result);
end;

class function TOpenCVHelpers.MediaDir(const Category: string): string;
begin
  Result := IncludeTrailingPathDelimiter(TPath.Combine(MediaRootDir, Category));
  ForceDirectories(Result);
end;

class procedure TOpenCVHelpers.MigrateLegacyMedia;
var
  ExeDir, OldFaceDir, NewFaceDir, FileName, DestPath: string;
begin
  ExeDir := ExtractFilePath(ParamStr(0));
  OldFaceDir := IncludeTrailingPathDelimiter(TPath.Combine(ExeDir, 'face_data'));
  NewFaceDir := MediaDir('faces');
  if DirectoryExists(OldFaceDir) and (SameText(OldFaceDir, NewFaceDir) = False) then
  begin
    for FileName in TDirectory.GetFiles(OldFaceDir, '*.json') do
    begin
      DestPath := TPath.Combine(NewFaceDir, TPath.GetFileName(FileName));
      if not FileExists(DestPath) then
        TFile.Copy(FileName, DestPath);
    end;
  end;
end;

class function TOpenCVHelpers.FaceDataDir: string;
begin
  MigrateLegacyMedia;
  Result := MediaDir('faces');
end;

class function TOpenCVHelpers.ResolveOutputPath(const UserPath, Category: string): string;
begin
  if UserPath = '' then
    raise Exception.Create('outputPath is required');
  if TPath.IsPathRooted(UserPath) then
    Result := TPath.GetFullPath(UserPath)
  else
    Result := TPath.GetFullPath(TPath.Combine(MediaDir(Category), UserPath));
  EnsureOutputDir(Result);
end;

class function TOpenCVHelpers.RequireOutputPath(Args: TJSONObject; const Category: string;
  out Value: string; out Error: string): Boolean;
begin
  Result := RequireString(Args, 'outputPath', Value);
  if not Result then
  begin
    Error := 'outputPath is required';
    Exit;
  end;
  try
    Value := ResolveOutputPath(Value, Category);
    Error := '';
  except
    on E: Exception do
    begin
      Error := E.Message;
      Result := False;
    end;
  end;
end;

class function TOpenCVHelpers.RequireString(Args: TJSONObject; const Key: string; out Value: string): Boolean;
begin
  Result := Assigned(Args) and Args.TryGetValue(Key, Value) and (Value <> '');
end;

class function TOpenCVHelpers.GetOptionalInt(Args: TJSONObject; const Key: string; const Default: Integer): Integer;
begin
  if not Assigned(Args) or not Args.TryGetValue(Key, Result) then
    Result := Default;
end;

class function TOpenCVHelpers.GetOptionalDouble(Args: TJSONObject; const Key: string; const Default: Double): Double;
begin
  if not Assigned(Args) or not Args.TryGetValue(Key, Result) then
    Result := Default;
end;

class function TOpenCVHelpers.ParseBackend(const BackendStr: string): Integer;
begin
  if SameText(BackendStr, 'dshow') then
    Result := CAP_DSHOW
  else if SameText(BackendStr, 'msmf') then
    Result := CAP_MSMF
  else
    Result := CAP_ANY;
end;

class function TOpenCVHelpers.LoadImagePath(const ImagePath: string; out Error: string): TCVMat;
begin
  if not FileExists(ImagePath) then
  begin
    Error := 'Image file not found: ' + ImagePath;
    Exit(TCVMat.Create_0(0, 0, CV_8UC3));
  end;
  Result := imreadPath(ImagePath, IMREAD_COLOR);
  if Result.empty then
    Error := 'Failed to load image via OpenCV: ' + ImagePath;
end;

class procedure TOpenCVHelpers.EnsureOutputDir(const OutputPath: string);
begin
  ForceDirectories(ExtractFilePath(OutputPath));
end;

class function TOpenCVHelpers.MakeError(const Msg: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('error', Msg);
end;

class function TOpenCVHelpers.AddToolSchema(const Name, Description: string;
  const Properties: TJSONObject; const Required: TArray<string>): TJSONObject;
var
  Schema: TJSONObject;
  ReqArr: TJSONArray;
  ReqName: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', Name);
  Result.AddPair('description', Description);
  Schema := TJSONObject.Create;
  Schema.AddPair('type', 'object');
  Schema.AddPair('properties', Properties);
  if Length(Required) > 0 then
  begin
    ReqArr := TJSONArray.Create;
    for ReqName in Required do
      ReqArr.Add(ReqName);
    Schema.AddPair('required', ReqArr);
  end;
  Result.AddPair('inputSchema', Schema);
end;

class function TOpenCVHelpers.ExtractFirstFaceFeature(const Det: TCVFaceDetectorYN; const Rec: TCVFaceRecognizerSF;
  const Frame, Faces: TCVMat; out Feature: TCVMat): Boolean;
var
  FaceRow, Aligned: TCVMat;
begin
  Result := False;
  if Det.detect(Frame.Handle, Faces.Handle) <= 0 then
    Exit;
  FaceRow := Faces.row(0);
  Aligned := TCVMat.Create_0(0, 0, CV_8UC3);
  Feature := TCVMat.Create_0(0, 0, CV_32FC1);
  Rec.alignCrop(Frame.Handle, FaceRow.Handle, Aligned.Handle);
  Rec.feature(Aligned.Handle, Feature.Handle);
  Result := True;
end;

class procedure TOpenCVHelpers.SaveFaceFeature(const PersonName: string; const Feature: TCVMat);
var
  Root, FilePath: string;
  I, Total: Integer;
  Arr: TJSONArray;
  Obj: TJSONObject;
  List: TStringList;
begin
  Root := FaceDataDir;
  FilePath := TPath.Combine(Root, PersonName + '.json');
  Total := Feature.rows * Feature.cols;
  Arr := TJSONArray.Create;
  for I := 0 to Total - 1 do
    Arr.Add(FloatToStr(PSingle(Feature.ptr(0, I))^));
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('name', PersonName);
    Obj.AddPair('rows', TJSONNumber.Create(Feature.rows));
    Obj.AddPair('cols', TJSONNumber.Create(Feature.cols));
    Obj.AddPair('data', Arr);
    List := TStringList.Create;
    try
      List.Text := Obj.ToJSON;
      List.SaveToFile(FilePath, TEncoding.UTF8);
    finally
      List.Free;
    end;
  finally
    Obj.Free;
  end;
end;

class function TOpenCVHelpers.LoadFaceFeature(const FilePath: string; out Feature: TCVMat): Boolean;
var
  Text: string;
  Obj: TJSONObject;
  Data: TJSONArray;
  Rows, Cols, I: Integer;
  Val: Double;
begin
  Result := False;
  if not FileExists(FilePath) then
    Exit;
  Text := TFile.ReadAllText(FilePath, TEncoding.UTF8);
  Obj := TJSONObject.ParseJSONValue(Text) as TJSONObject;
  if Obj = nil then
    Exit;
  try
    if not Obj.TryGetValue<Integer>('rows', Rows) then
      Exit;
    if not Obj.TryGetValue<Integer>('cols', Cols) then
      Exit;
    if not Obj.TryGetValue<TJSONArray>('data', Data) then
      Exit;
    Feature := TCVMat.Create_0(Rows, Cols, CV_32FC1);
    for I := 0 to Min(Data.Count - 1, Rows * Cols - 1) do
    begin
      Val := StrToFloatDef(Data.Items[I].Value, 0);
      PSingle(Feature.ptr(0, I))^ := Single(Val);
    end;
    Result := True;
  finally
    Obj.Free;
  end;
end;

class function TOpenCVHelpers.ListEnrolledFaces: TJSONArray;
var
  Dir, FileName, BaseName: string;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  Dir := FaceDataDir;
  for FileName in TDirectory.GetFiles(Dir, '*.json') do
  begin
    BaseName := TPath.GetFileNameWithoutExtension(FileName);
    Item := TJSONObject.Create;
    Item.AddPair('name', BaseName);
    Item.AddPair('file', FileName);
    Result.Add(Item);
  end;
end;

end.

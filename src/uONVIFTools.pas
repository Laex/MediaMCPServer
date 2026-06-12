unit uONVIFTools;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.NetEncoding,
  ONVIF, ONVIF.Types, ONVIF.Device, ONVIF.Discovery, ONVIF.Demo,
  ONVIF.PTZ, ONVIF.Imaging;

type
  TONVIFTools = class
  private
    class function ExtractFromScope(const Scopes: TArray<string>; const Prefix: string): string;
  public
    class function DiscoverCameras(Args: TJSONObject): TJSONObject;
    class function GetStreamUri(Args: TJSONObject): TJSONObject;
    class function PTZMove(Args: TJSONObject): TJSONObject;
    class function PTZStop(Args: TJSONObject): TJSONObject;
    class function GetImagingSettings(Args: TJSONObject): TJSONObject;
    class function SetImagingSettings(Args: TJSONObject): TJSONObject;
  end;

implementation

class function TONVIFTools.ExtractFromScope(const Scopes: TArray<string>; const Prefix: string): string;
var
  S: string;
begin
  Result := '';
  for S in Scopes do
  begin
    if S.StartsWith(Prefix, True) then
    begin
      Result := S.Substring(Prefix.Length);
      try
        Result := TNetEncoding.URL.Decode(Result);
      except
        // Fallback if decoding fails
      end;
      Exit;
    end;
  end;
end;

class function TONVIFTools.DiscoverCameras(Args: TJSONObject): TJSONObject;
var
  ProbeArray: TProbeMatchArray;
  CameraArray: TJSONArray;
  CameraObj: TJSONObject;
  ScopeVal: string;
  ScopesArr: TJSONArray;
  I, J: Integer;
  CamName, CamModel: string;
begin
  Result := TJSONObject.Create;
  try
    // Run synchronous multicast probe (timeout 1.5 seconds)
    ProbeArray := ONVIFProbe;
    CameraArray := TJSONArray.Create;
    
    for I := 0 to High(ProbeArray) do
    begin
      CameraObj := TJSONObject.Create;
      CameraObj.AddPair('xaddr', ProbeArray[I].XAddrs);
      CameraObj.AddPair('xaddrV6', ProbeArray[I].XAddrsV6);
      
      // Parse scopes for friendly name and model
      CamName := ExtractFromScope(ProbeArray[I].Scopes, 'onvif://www.onvif.org/name/');
      CamModel := ExtractFromScope(ProbeArray[I].Scopes, 'onvif://www.onvif.org/hardware/');
      
      if CamName <> '' then
        CameraObj.AddPair('name', CamName)
      else
        CameraObj.AddPair('name', 'ONVIF IP Camera');
        
      if CamModel <> '' then
        CameraObj.AddPair('model', CamModel);

      // Add raw scopes for debugging / detailed queries
      ScopesArr := TJSONArray.Create;
      for J := 0 to High(ProbeArray[I].Scopes) do
      begin
        ScopeVal := ProbeArray[I].Scopes[J];
        ScopesArr.Add(ScopeVal);
      end;
      CameraObj.AddPair('scopes', ScopesArr);
      CameraArray.Add(CameraObj);
    end;
    
    Result.AddPair('cameras', CameraArray);
  except
    on E: Exception do
    begin
      Result.AddPair('error', E.Message);
    end;
  end;
end;

class function TONVIFTools.GetStreamUri(Args: TJSONObject): TJSONObject;
var
  CameraIp, Username, Password, NormalXAddr, Token: string;
  Device: TONVIFDevice;
  Uri: TStreamUri;
  Info: TDeviceInformation;
begin
  Result := TJSONObject.Create;
  
  if not Args.TryGetValue('cameraIp', CameraIp) then
  begin
    Result.AddPair('error', 'cameraIp argument is required');
    Exit;
  end;
  
  Args.TryGetValue('username', Username);
  Args.TryGetValue('password', Password);
  
  NormalXAddr := NormalizeDeviceXAddr(CameraIp);
  
  Device := TONVIFDevice.Create;
  try
    if Device.Connect(NormalXAddr, Username, Password) then
    begin
      Token := DefaultProfileToken(Device);
      if Token = '' then
      begin
        Result.AddPair('error', 'Connected to camera, but no video/media profiles were found.');
        Exit;
      end;
      
      Uri := Device.GetStreamUri(Token, 'RTP-Unicast', 'RTSP');
      Result.AddPair('rtspUri', Uri.Uri);
      
      // Include manufacturer and model info
      Info := Device.DeviceInfo;
      Result.AddPair('manufacturer', Info.Manufacturer);
      Result.AddPair('model', Info.Model);
      Result.AddPair('firmware', Info.FirmwareVersion);
      Result.AddPair('serialNumber', Info.SerialNumber);
    end
    else
    begin
      Result.AddPair('error', 'Failed to connect to ONVIF device service at: ' + NormalXAddr);
    end;
  finally
    Device.Free;
  end;
end;

class function TONVIFTools.PTZMove(Args: TJSONObject): TJSONObject;
var
  CameraIp, Username, Password, NormalXAddr: string;
  Pan, Tilt, Zoom: Double;
  TimeoutMs: Integer;
  Device: TONVIFDevice;
  ProfileToken: string;
  Velocity: TPTZVector;
  TimeoutStr: string;
  Success: Boolean;
begin
  Result := TJSONObject.Create;
  
  if not Args.TryGetValue('cameraIp', CameraIp) then
  begin
    Result.AddPair('error', 'cameraIp argument is required');
    Exit;
  end;
  
  Args.TryGetValue('username', Username);
  Args.TryGetValue('password', Password);
  
  Pan := 0.0;
  Args.TryGetValue('pan', Pan);
  
  Tilt := 0.0;
  Args.TryGetValue('tilt', Tilt);
  
  Zoom := 0.0;
  Args.TryGetValue('zoom', Zoom);
  
  TimeoutMs := 1000;
  Args.TryGetValue('timeoutMs', TimeoutMs);
  
  TimeoutStr := 'PT' + Format('%.3f', [TimeoutMs / 1000.0]) + 'S';
  TimeoutStr := TimeoutStr.Replace(',', '.');

  NormalXAddr := NormalizeDeviceXAddr(CameraIp);
  
  Device := TONVIFDevice.Create;
  try
    if Device.Connect(NormalXAddr, Username, Password) then
    begin
      ProfileToken := DefaultProfileToken(Device);
      if ProfileToken = '' then
      begin
        Result.AddPair('error', 'No profiles found on device.');
        Exit;
      end;
      
      Velocity.Pan := Pan;
      Velocity.Tilt := Tilt;
      Velocity.Zoom := Zoom;
      
      Success := ONVIFPTZContinuousMove(Device.PTZEndpoint, Username, Password, ProfileToken, Velocity, TimeoutStr).Success;
      if Success then
        Result.AddPair('status', 'success')
      else
        Result.AddPair('error', 'PTZ ContinuousMove SOAP request failed.');
    end
    else
      Result.AddPair('error', 'Failed to connect to ONVIF device.');
  finally
    Device.Free;
  end;
end;

class function TONVIFTools.PTZStop(Args: TJSONObject): TJSONObject;
var
  CameraIp, Username, Password, NormalXAddr: string;
  Device: TONVIFDevice;
  ProfileToken: string;
  Success: Boolean;
begin
  Result := TJSONObject.Create;
  
  if not Args.TryGetValue('cameraIp', CameraIp) then
  begin
    Result.AddPair('error', 'cameraIp argument is required');
    Exit;
  end;
  
  Args.TryGetValue('username', Username);
  Args.TryGetValue('password', Password);
  
  NormalXAddr := NormalizeDeviceXAddr(CameraIp);
  
  Device := TONVIFDevice.Create;
  try
    if Device.Connect(NormalXAddr, Username, Password) then
    begin
      ProfileToken := DefaultProfileToken(Device);
      if ProfileToken = '' then
      begin
        Result.AddPair('error', 'No profiles found on device.');
        Exit;
      end;
      
      Success := Device.PTZStop(ProfileToken);
      if Success then
        Result.AddPair('status', 'success')
      else
        Result.AddPair('error', 'PTZ Stop request failed.');
    end
    else
      Result.AddPair('error', 'Failed to connect to ONVIF device.');
  finally
    Device.Free;
  end;
end;

class function TONVIFTools.GetImagingSettings(Args: TJSONObject): TJSONObject;
var
  CameraIp, Username, Password, NormalXAddr: string;
  Device: TONVIFDevice;
  VideoSourceToken: string;
  Settings: TImagingSettings;
begin
  Result := TJSONObject.Create;
  
  if not Args.TryGetValue('cameraIp', CameraIp) then
  begin
    Result.AddPair('error', 'cameraIp argument is required');
    Exit;
  end;
  
  Args.TryGetValue('username', Username);
  Args.TryGetValue('password', Password);
  
  NormalXAddr := NormalizeDeviceXAddr(CameraIp);
  
  Device := TONVIFDevice.Create;
  try
    if Device.Connect(NormalXAddr, Username, Password) then
    begin
      VideoSourceToken := DefaultVideoSourceToken(Device);
      if VideoSourceToken = '' then
      begin
        Result.AddPair('error', 'No video source found on device.');
        Exit;
      end;
      
      Settings := Device.GetImagingSettings(VideoSourceToken);
      
      Result.AddPair('status', 'success');
      Result.AddPair('brightness', TJSONNumber.Create(Settings.Brightness));
      Result.AddPair('contrast', TJSONNumber.Create(Settings.Contrast));
      Result.AddPair('colorSaturation', TJSONNumber.Create(Settings.ColorSaturation));
      Result.AddPair('sharpness', TJSONNumber.Create(Settings.Sharpness));
    end
    else
      Result.AddPair('error', 'Failed to connect to ONVIF device.');
  finally
    Device.Free;
  end;
end;

class function TONVIFTools.SetImagingSettings(Args: TJSONObject): TJSONObject;
var
  CameraIp, Username, Password, NormalXAddr: string;
  Device: TONVIFDevice;
  VideoSourceToken: string;
  Settings: TImagingSettings;
  ValDouble: Double;
  Success: Boolean;
begin
  Result := TJSONObject.Create;
  
  if not Args.TryGetValue('cameraIp', CameraIp) then
  begin
    Result.AddPair('error', 'cameraIp argument is required');
    Exit;
  end;
  
  Args.TryGetValue('username', Username);
  Args.TryGetValue('password', Password);
  
  NormalXAddr := NormalizeDeviceXAddr(CameraIp);
  
  Device := TONVIFDevice.Create;
  try
    if Device.Connect(NormalXAddr, Username, Password) then
    begin
      VideoSourceToken := DefaultVideoSourceToken(Device);
      if VideoSourceToken = '' then
      begin
        Result.AddPair('error', 'No video source found on device.');
        Exit;
      end;
      
      Settings := Device.GetImagingSettings(VideoSourceToken);
      
      if Args.TryGetValue('brightness', ValDouble) then
        Settings.Brightness := ValDouble;
        
      if Args.TryGetValue('contrast', ValDouble) then
        Settings.Contrast := ValDouble;
        
      if Args.TryGetValue('colorSaturation', ValDouble) then
        Settings.ColorSaturation := ValDouble;
        
      if Args.TryGetValue('sharpness', ValDouble) then
        Settings.Sharpness := ValDouble;
        
      Success := Device.SetImagingSettings(VideoSourceToken, Settings);
      if Success then
        Result.AddPair('status', 'success')
      else
        Result.AddPair('error', 'Failed to set imaging settings.');
    end
    else
      Result.AddPair('error', 'Failed to connect to ONVIF device.');
  finally
    Device.Free;
  end;
end;

end.

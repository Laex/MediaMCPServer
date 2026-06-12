unit uMediaEngine;

interface

uses
  System.SysUtils, System.Classes, System.JSON;

type
  TMediaEngine = class
  public
    class function GetToolsSchema: TJSONArray;
    class function CallTool(const Name: string; Args: TJSONObject): TJSONObject;
  end;

implementation

uses
  uONVIFTools, uFFmpegTools, uOpenCVTools, uOpenCVDnnTools, uOpenCVImgTools, uOpenCVVideoTools;

class function TMediaEngine.GetToolsSchema: TJSONArray;
var
  Tool, Schema, Prop, ArgItem: TJSONObject;
  Required: TJSONArray;
begin
  Result := TJSONArray.Create;
  try
    // 1. camera_discover
    Tool := TJSONObject.Create;
    Tool.AddPair('name', 'camera_discover');
    Tool.AddPair('description', 'Discover local ONVIF IP cameras in the network.');
    Schema := TJSONObject.Create;
    Schema.AddPair('type', 'object');
    Schema.AddPair('properties', TJSONObject.Create);
    Tool.AddPair('inputSchema', Schema);
    Result.Add(Tool);

    // 2. camera_get_stream_uri
    Tool := TJSONObject.Create;
    Tool.AddPair('name', 'camera_get_stream_uri');
    Tool.AddPair('description', 'Get the RTSP stream URI for a discovered ONVIF camera.');
    Schema := TJSONObject.Create;
    Schema.AddPair('type', 'object');
    
    Prop := TJSONObject.Create;
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'The IP address of the ONVIF camera.');
    Prop.AddPair('cameraIp', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Optional username for camera authorization.');
    Prop.AddPair('username', ArgItem);

    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Optional password for camera authorization.');
    Prop.AddPair('password', ArgItem);

    Schema.AddPair('properties', Prop);
    
    Required := TJSONArray.Create;
    Required.Add('cameraIp');
    Schema.AddPair('required', Required);
    
    Tool.AddPair('inputSchema', Schema);
    Result.Add(Tool);

    TFFmpegTools.RegisterTools(Result);

    // 4. image_detect_objects
    Tool := TJSONObject.Create;
    Tool.AddPair('name', 'image_detect_objects');
    Tool.AddPair('description', 'Detect objects and faces in a JPEG image using OpenCV 5.0. Returns names and bounding boxes of detected objects.');
    Schema := TJSONObject.Create;
    Schema.AddPair('type', 'object');
    
    Prop := TJSONObject.Create;
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Absolute file path to the JPEG image to analyze.');
    Prop.AddPair('imagePath', ArgItem);

    Schema.AddPair('properties', Prop);
    
    Required := TJSONArray.Create;
    Required.Add('imagePath');
    Schema.AddPair('required', Required);
    
    Tool.AddPair('inputSchema', Schema);
    Result.Add(Tool);

    // 5. image_detect_faces
    Tool := TJSONObject.Create;
    Tool.AddPair('name', 'image_detect_faces');
    Tool.AddPair('description', 'Detect faces in a JPEG/PNG image using OpenCV YuNet. Returns bounding boxes, confidence scores, and 5 facial landmarks per face.');
    Schema := TJSONObject.Create;
    Schema.AddPair('type', 'object');

    Prop := TJSONObject.Create;

    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Absolute file path to the image to analyze.');
    Prop.AddPair('imagePath', ArgItem);

    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'number');
    ArgItem.AddPair('description', 'Optional minimum face confidence score from 0.0 to 1.0 (defaults to 0.5).');
    Prop.AddPair('scoreThreshold', ArgItem);

    Schema.AddPair('properties', Prop);

    Required := TJSONArray.Create;
    Required.Add('imagePath');
    Schema.AddPair('required', Required);

    Tool.AddPair('inputSchema', Schema);
    Result.Add(Tool);

    // 6. webcam_list
    Tool := TJSONObject.Create;
    Tool.AddPair('name', 'webcam_list');
    Tool.AddPair('description', 'List available local USB/integrated webcams connected to the computer by probing indices.');
    Schema := TJSONObject.Create;
    Schema.AddPair('type', 'object');
    Schema.AddPair('properties', TJSONObject.Create);
    Tool.AddPair('inputSchema', Schema);
    Result.Add(Tool);

    // 6. webcam_grab_frame
    Tool := TJSONObject.Create;
    Tool.AddPair('name', 'webcam_grab_frame');
    Tool.AddPair('description', 'Grab a frame from a local webcam by its index and save it as a JPEG image.');
    Schema := TJSONObject.Create;
    Schema.AddPair('type', 'object');
    
    Prop := TJSONObject.Create;
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'integer');
    ArgItem.AddPair('description', 'The index of the webcam (defaults to 0). Ignored if cameraUrl is provided.');
    Prop.AddPair('cameraIndex', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Optional RTSP URL or address of the camera. If provided, cameraIndex is ignored.');
    Prop.AddPair('cameraUrl', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Absolute path where the captured frame should be saved as a JPEG.');
    Prop.AddPair('outputPath', ArgItem);

    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'integer');
    ArgItem.AddPair('description', 'Optional preferred width resolution.');
    Prop.AddPair('width', ArgItem);

    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'integer');
    ArgItem.AddPair('description', 'Optional preferred height resolution.');
    Prop.AddPair('height', ArgItem);

     ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Optional capture backend: ''dshow'', ''msmf'', or ''any''.');
    Prop.AddPair('backend', ArgItem);

    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'number');
    ArgItem.AddPair('description', 'Optional brightness setting (0.0 to 1.0).');
    Prop.AddPair('brightness', ArgItem);

    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'number');
    ArgItem.AddPair('description', 'Optional contrast setting (0.0 to 1.0).');
    Prop.AddPair('contrast', ArgItem);

    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'number');
    ArgItem.AddPair('description', 'Optional exposure setting.');
    Prop.AddPair('exposure', ArgItem);

    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'number');
    ArgItem.AddPair('description', 'Optional gain setting.');
    Prop.AddPair('gain', ArgItem);

    Schema.AddPair('properties', Prop);
    
    Required := TJSONArray.Create;
    Required.Add('outputPath');
    Schema.AddPair('required', Required);
    
    Tool.AddPair('inputSchema', Schema);
    Result.Add(Tool);

    // 7. camera_ptz_move
    Tool := TJSONObject.Create;
    Tool.AddPair('name', 'camera_ptz_move');
    Tool.AddPair('description', 'Start continuous Pan/Tilt/Zoom move for an ONVIF camera.');
    Schema := TJSONObject.Create;
    Schema.AddPair('type', 'object');
    Prop := TJSONObject.Create;
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'The IP address of the ONVIF camera.');
    Prop.AddPair('cameraIp', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Optional username.');
    Prop.AddPair('username', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Optional password.');
    Prop.AddPair('password', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'number');
    ArgItem.AddPair('description', 'Optional Pan speed from -1.0 (left) to 1.0 (right).');
    Prop.AddPair('pan', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'number');
    ArgItem.AddPair('description', 'Optional Tilt speed from -1.0 (down) to 1.0 (up).');
    Prop.AddPair('tilt', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'number');
    ArgItem.AddPair('description', 'Optional Zoom speed from -1.0 (out) to 1.0 (in).');
    Prop.AddPair('zoom', ArgItem);

    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'integer');
    ArgItem.AddPair('description', 'Optional move duration in milliseconds (defaults to 1000).');
    Prop.AddPair('timeoutMs', ArgItem);
    
    Schema.AddPair('properties', Prop);
    Required := TJSONArray.Create;
    Required.Add('cameraIp');
    Schema.AddPair('required', Required);
    Tool.AddPair('inputSchema', Schema);
    Result.Add(Tool);

    // 8. camera_ptz_stop
    Tool := TJSONObject.Create;
    Tool.AddPair('name', 'camera_ptz_stop');
    Tool.AddPair('description', 'Stop any running Pan/Tilt/Zoom movement for an ONVIF camera.');
    Schema := TJSONObject.Create;
    Schema.AddPair('type', 'object');
    Prop := TJSONObject.Create;
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'The IP address of the ONVIF camera.');
    Prop.AddPair('cameraIp', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Optional username.');
    Prop.AddPair('username', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Optional password.');
    Prop.AddPair('password', ArgItem);
    
    Schema.AddPair('properties', Prop);
    Required := TJSONArray.Create;
    Required.Add('cameraIp');
    Schema.AddPair('required', Required);
    Tool.AddPair('inputSchema', Schema);
    Result.Add(Tool);

    // 9. camera_get_imaging_settings
    Tool := TJSONObject.Create;
    Tool.AddPair('name', 'camera_get_imaging_settings');
    Tool.AddPair('description', 'Get the current imaging settings (brightness, contrast, saturation, sharpness) for an ONVIF camera.');
    Schema := TJSONObject.Create;
    Schema.AddPair('type', 'object');
    Prop := TJSONObject.Create;
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'The IP address of the ONVIF camera.');
    Prop.AddPair('cameraIp', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Optional username.');
    Prop.AddPair('username', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Optional password.');
    Prop.AddPair('password', ArgItem);
    
    Schema.AddPair('properties', Prop);
    Required := TJSONArray.Create;
    Required.Add('cameraIp');
    Schema.AddPair('required', Required);
    Tool.AddPair('inputSchema', Schema);
    Result.Add(Tool);

    // 10. camera_set_imaging_settings
    Tool := TJSONObject.Create;
    Tool.AddPair('name', 'camera_set_imaging_settings');
    Tool.AddPair('description', 'Configure imaging settings (brightness, contrast, saturation, sharpness) for an ONVIF camera.');
    Schema := TJSONObject.Create;
    Schema.AddPair('type', 'object');
    Prop := TJSONObject.Create;
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'The IP address of the ONVIF camera.');
    Prop.AddPair('cameraIp', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Optional username.');
    Prop.AddPair('username', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'string');
    ArgItem.AddPair('description', 'Optional password.');
    Prop.AddPair('password', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'number');
    ArgItem.AddPair('description', 'Optional brightness setting.');
    Prop.AddPair('brightness', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'number');
    ArgItem.AddPair('description', 'Optional contrast setting.');
    Prop.AddPair('contrast', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'number');
    ArgItem.AddPair('description', 'Optional color saturation setting.');
    Prop.AddPair('colorSaturation', ArgItem);
    
    ArgItem := TJSONObject.Create;
    ArgItem.AddPair('type', 'number');
    ArgItem.AddPair('description', 'Optional sharpness setting.');
    Prop.AddPair('sharpness', ArgItem);
    
    Schema.AddPair('properties', Prop);
    Required := TJSONArray.Create;
    Required.Add('cameraIp');
    Schema.AddPair('required', Required);
    Tool.AddPair('inputSchema', Schema);
    Result.Add(Tool);

    TOpenCVDnnTools.RegisterTools(Result);
    TOpenCVImgTools.RegisterTools(Result);
    TOpenCVVideoTools.RegisterTools(Result);

  except
    on E: Exception do
    begin
      Result.Free;
      raise;
    end;
  end;
end;

class function TMediaEngine.CallTool(const Name: string; Args: TJSONObject): TJSONObject;
begin
  if Name = 'camera_discover' then
    Result := TONVIFTools.DiscoverCameras(Args)
  else if Name = 'camera_get_stream_uri' then
    Result := TONVIFTools.GetStreamUri(Args)
  else if (Name = 'video_grab_frame') or (Name = 'video_probe') or (Name = 'stream_test') or
          (Name = 'video_grab_frames') or (Name = 'video_thumbnail') or (Name = 'video_remux') or
          (Name = 'video_trim') or (Name = 'video_concat') or (Name = 'audio_extract') or
          (Name = 'video_record_segment') or (Name = 'video_scale') or (Name = 'video_filter') or
          (Name = 'video_detect_silence') or (Name = 'video_scene_detect') or
          (Name = 'video_metadata_read') then
    Result := TFFmpegTools.CallTool(Name, Args)
  else if Name = 'image_detect_objects' then
    Result := TOpenCVTools.DetectObjects(Args)
  else if Name = 'image_detect_faces' then
    Result := TOpenCVTools.DetectFaces(Args)
  else if Name = 'webcam_list' then
    Result := TOpenCVTools.WebcamList(Args)
  else if Name = 'webcam_grab_frame' then
    Result := TOpenCVTools.WebcamGrabFrame(Args)
  else if Name = 'camera_ptz_move' then
    Result := TONVIFTools.PTZMove(Args)
  else if Name = 'camera_ptz_stop' then
    Result := TONVIFTools.PTZStop(Args)
  else if Name = 'camera_get_imaging_settings' then
    Result := TONVIFTools.GetImagingSettings(Args)
  else if Name = 'camera_set_imaging_settings' then
    Result := TONVIFTools.SetImagingSettings(Args)
  else if (Name = 'image_classify') or (Name = 'image_segment_person') or
          (Name = 'image_detect_text') or (Name = 'image_detect_text_east') or
          (Name = 'face_compare') or (Name = 'face_enroll') or
          (Name = 'face_identify') or (Name = 'face_list') then
    Result := TOpenCVDnnTools.CallTool(Name, Args)
  else if (Name = 'image_read_qrcode') or (Name = 'image_encode_qrcode') or
          (Name = 'image_read_barcode') or (Name = 'image_detect_aruco') or
          (Name = 'image_template_match') or (Name = 'image_find_contours') or
          (Name = 'image_detect_edges') or (Name = 'image_detect_lines') or
          (Name = 'image_detect_circles') or (Name = 'image_transform') or
          (Name = 'image_annotate') then
    Result := TOpenCVImgTools.CallTool(Name, Args)
  else if (Name = 'webcam_record_video') or (Name = 'video_track_object') or
          (Name = 'image_optical_flow') then
    Result := TOpenCVVideoTools.CallTool(Name, Args)
  else
    raise Exception.Create('Tool not found: ' + Name);
end;

end.

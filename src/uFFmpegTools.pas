unit uFFmpegTools;

interface

uses
  System.SysUtils, System.Classes, System.JSON,
  uOpenCVHelpers, uFFmpegHelpers;

type
  TFFmpegTools = class
  public
    class procedure RegisterTools(Schema: TJSONArray);
    class function CallTool(const Name: string; Args: TJSONObject): TJSONObject;
    class function GrabFrame(Args: TJSONObject): TJSONObject;
  end;

implementation

class procedure TFFmpegTools.RegisterTools(Schema: TJSONArray);
var
  Props: TJSONObject;
  P: TJSONObject;
  Item: TJSONObject;
begin
  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('sourceUrl', P);
  Item := TOpenCVHelpers.AddToolSchema('video_probe',
    'Probe media file or stream: duration, codecs, resolution, fps, audio/video streams.',
    Props, ['sourceUrl']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  P := TJSONObject.Create; P.AddPair('type', 'string'); Props.AddPair('sourceUrl', P);
  P := TJSONObject.Create; P.AddPair('type', 'integer'); Props.AddPair('timeoutMs', P);
  Item := TOpenCVHelpers.AddToolSchema('stream_test',
    'Test if a media file or RTSP/HTTP stream is reachable. Returns latency and stream info.',
    Props, ['sourceUrl']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('sourceUrl', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('outputPath', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('timeOffsetMs', TJSONObject.Create.AddPair('type', 'integer'));
  Item := TOpenCVHelpers.AddToolSchema('video_grab_frame',
    'Extract a JPEG frame from a video file or RTSP stream. Relative outputPath goes to media/captures/.',
    Props, ['sourceUrl', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('sourceUrl', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('outputDir', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('timeOffsetMs', TJSONObject.Create.AddPair('type', 'integer'));
  Props.AddPair('intervalMs', TJSONObject.Create.AddPair('type', 'integer'));
  Props.AddPair('count', TJSONObject.Create.AddPair('type', 'integer'));
  Item := TOpenCVHelpers.AddToolSchema('video_grab_frames',
    'Extract multiple JPEG frames at intervals. Saves to media/captures/.',
    Props, ['sourceUrl', 'outputDir']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('sourceUrl', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('outputPath', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('timeOffsetMs', TJSONObject.Create.AddPair('type', 'integer'));
  Item := TOpenCVHelpers.AddToolSchema('video_thumbnail',
    'Create a thumbnail JPEG at a given time offset.',
    Props, ['sourceUrl', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('sourceUrl', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('outputPath', TJSONObject.Create.AddPair('type', 'string'));
  Item := TOpenCVHelpers.AddToolSchema('video_remux',
    'Remux media to another container without re-encoding. Output in media/video/.',
    Props, ['sourceUrl', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('sourceUrl', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('outputPath', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('startMs', TJSONObject.Create.AddPair('type', 'integer'));
  Props.AddPair('endMs', TJSONObject.Create.AddPair('type', 'integer'));
  Item := TOpenCVHelpers.AddToolSchema('video_trim',
    'Trim media by time range (stream copy).',
    Props, ['sourceUrl', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('inputPaths', TJSONObject.Create.AddPair('type', 'array'));
  Props.AddPair('outputPath', TJSONObject.Create.AddPair('type', 'string'));
  Item := TOpenCVHelpers.AddToolSchema('video_concat',
    'Concatenate multiple video files. Pass inputPaths as JSON array of file paths.',
    Props, ['inputPaths', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('sourceUrl', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('outputPath', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('sampleRate', TJSONObject.Create.AddPair('type', 'integer'));
  Item := TOpenCVHelpers.AddToolSchema('audio_extract',
    'Extract audio as PCM S16LE stereo raw audio. Output in media/output/.',
    Props, ['sourceUrl', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('sourceUrl', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('outputPath', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('durationMs', TJSONObject.Create.AddPair('type', 'integer'));
  Item := TOpenCVHelpers.AddToolSchema('video_record_segment',
    'Record a segment from RTSP or file for a given duration (stream copy).',
    Props, ['sourceUrl', 'outputPath', 'durationMs']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('sourceUrl', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('outputPath', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('width', TJSONObject.Create.AddPair('type', 'integer'));
  Props.AddPair('height', TJSONObject.Create.AddPair('type', 'integer'));
  Props.AddPair('maxDurationMs', TJSONObject.Create.AddPair('type', 'integer'));
  Item := TOpenCVHelpers.AddToolSchema('video_scale',
    'Scale video dimensions (remux/resize pipeline).',
    Props, ['sourceUrl', 'outputPath']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('sourceUrl', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('outputPath', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('filter', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('maxDurationMs', TJSONObject.Create.AddPair('type', 'integer'));
  Item := TOpenCVHelpers.AddToolSchema('video_filter',
    'Apply FFmpeg filter expression to video (e.g. scale=640:480, drawtext=...).',
    Props, ['sourceUrl', 'outputPath', 'filter']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('sourceUrl', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('noiseDb', TJSONObject.Create.AddPair('type', 'integer'));
  Props.AddPair('minSilenceMs', TJSONObject.Create.AddPair('type', 'integer'));
  Item := TOpenCVHelpers.AddToolSchema('video_detect_silence',
    'Detect silent segments in audio track by RMS threshold.',
    Props, ['sourceUrl']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('sourceUrl', TJSONObject.Create.AddPair('type', 'string'));
  Props.AddPair('threshold', TJSONObject.Create.AddPair('type', 'number'));
  Props.AddPair('maxScenes', TJSONObject.Create.AddPair('type', 'integer'));
  Item := TOpenCVHelpers.AddToolSchema('video_scene_detect',
    'Detect scene changes by frame difference.',
    Props, ['sourceUrl']);
  Schema.Add(Item);

  Props := TJSONObject.Create;
  Props.AddPair('sourceUrl', TJSONObject.Create.AddPair('type', 'string'));
  Item := TOpenCVHelpers.AddToolSchema('video_metadata_read',
    'Read container metadata tags (title, creation_time, etc.).',
    Props, ['sourceUrl']);
  Schema.Add(Item);
end;

class function TFFmpegTools.GrabFrame(Args: TJSONObject): TJSONObject;
var
  SourceUrl, OutputPath, Err: string;
  TimeOffsetMs: Integer;
begin
  Result := TJSONObject.Create;
  if not TFFmpegHelpers.RequireSource(Args, SourceUrl) then
  begin Result.AddPair('error', 'sourceUrl is required'); Exit; end;
  if not TOpenCVHelpers.RequireOutputPath(Args, 'captures', OutputPath, Err) then
  begin Result.AddPair('error', Err); Exit; end;
  if not Args.TryGetValue('timeOffsetMs', TimeOffsetMs) then
    TimeOffsetMs := 0;
  Result.Free;
  Result := TFFmpegHelpers.GrabFrame(SourceUrl, OutputPath, TimeOffsetMs);
end;

class function TFFmpegTools.CallTool(const Name: string; Args: TJSONObject): TJSONObject;
var
  SourceUrl, OutputPath, OutputDir, FilterExpr: string;
  TimeOffsetMs, IntervalMs, Count, StartMs, EndMs, DurationMs: Integer;
  TargetWidthPx, TargetHeightPx, MaxDurationMs, SampleRate, NoiseDb, MinSilenceMs, MaxScenes, TimeoutMs: Integer;
  Width, Height: Integer;
  Threshold: Double;
  InputPaths: TJSONArray;
  InputVal: TJSONValue;
  Err: string;
begin
  if Name = 'video_grab_frame' then
    Exit(GrabFrame(Args));

  if Name = 'video_concat' then
  begin
    if not TOpenCVHelpers.RequireOutputPath(Args, 'video', OutputPath, Err) then
    begin Result := TJSONObject.Create; Result.AddPair('error', Err); Exit; end;
    if not Args.TryGetValue('inputPaths', InputVal) or not (InputVal is TJSONArray) then
    begin Result := TJSONObject.Create; Result.AddPair('error', 'inputPaths array is required'); Exit; end;
    Exit(TFFmpegHelpers.Concat(InputVal as TJSONArray, OutputPath));
  end;

  if not TFFmpegHelpers.RequireSource(Args, SourceUrl) then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('error', 'sourceUrl is required');
    Exit;
  end;

  if Name = 'video_probe' then
    Exit(TFFmpegHelpers.Probe(SourceUrl))
  else if Name = 'stream_test' then
  begin
    if not Args.TryGetValue('timeoutMs', TimeoutMs) then TimeoutMs := 5000;
    Exit(TFFmpegHelpers.StreamTest(SourceUrl, TimeoutMs));
  end
  else if Name = 'video_grab_frames' then
  begin
    if not TOpenCVHelpers.RequireString(Args, 'outputDir', OutputDir) then
    begin Result := TJSONObject.Create; Result.AddPair('error', 'outputDir is required'); Exit; end;
    TimeOffsetMs := TOpenCVHelpers.GetOptionalInt(Args, 'timeOffsetMs', 0);
    IntervalMs := TOpenCVHelpers.GetOptionalInt(Args, 'intervalMs', 1000);
    Count := TOpenCVHelpers.GetOptionalInt(Args, 'count', 5);
    Exit(TFFmpegHelpers.GrabFrames(SourceUrl, OutputDir, TimeOffsetMs, IntervalMs, Count));
  end
  else if Name = 'video_thumbnail' then
  begin
    if not TOpenCVHelpers.RequireOutputPath(Args, 'captures', OutputPath, Err) then
    begin Result := TJSONObject.Create; Result.AddPair('error', Err); Exit; end;
    TimeOffsetMs := TOpenCVHelpers.GetOptionalInt(Args, 'timeOffsetMs', 0);
    Width := TOpenCVHelpers.GetOptionalInt(Args, 'width', 0);
    Height := TOpenCVHelpers.GetOptionalInt(Args, 'height', 0);
    Exit(TFFmpegHelpers.Thumbnail(SourceUrl, OutputPath, TimeOffsetMs, Width, Height));
  end
  else if Name = 'video_remux' then
  begin
    if not TOpenCVHelpers.RequireOutputPath(Args, 'video', OutputPath, Err) then
    begin Result := TJSONObject.Create; Result.AddPair('error', Err); Exit; end;
    Exit(TFFmpegHelpers.Remux(SourceUrl, OutputPath));
  end
  else if Name = 'video_trim' then
  begin
    if not TOpenCVHelpers.RequireOutputPath(Args, 'video', OutputPath, Err) then
    begin Result := TJSONObject.Create; Result.AddPair('error', Err); Exit; end;
    StartMs := TOpenCVHelpers.GetOptionalInt(Args, 'startMs', 0);
    EndMs := TOpenCVHelpers.GetOptionalInt(Args, 'endMs', 0);
    Exit(TFFmpegHelpers.Trim(SourceUrl, OutputPath, StartMs, EndMs));
  end
  else if Name = 'audio_extract' then
  begin
    if not TOpenCVHelpers.RequireOutputPath(Args, 'output', OutputPath, Err) then
    begin Result := TJSONObject.Create; Result.AddPair('error', Err); Exit; end;
    SampleRate := TOpenCVHelpers.GetOptionalInt(Args, 'sampleRate', 44100);
    Exit(TFFmpegHelpers.ExtractAudio(SourceUrl, OutputPath, SampleRate));
  end
  else if Name = 'video_record_segment' then
  begin
    if not TOpenCVHelpers.RequireOutputPath(Args, 'video', OutputPath, Err) then
    begin Result := TJSONObject.Create; Result.AddPair('error', Err); Exit; end;
    DurationMs := TOpenCVHelpers.GetOptionalInt(Args, 'durationMs', 10000);
    Exit(TFFmpegHelpers.RecordSegment(SourceUrl, OutputPath, DurationMs));
  end
  else if Name = 'video_scale' then
  begin
    if not TOpenCVHelpers.RequireOutputPath(Args, 'video', OutputPath, Err) then
    begin Result := TJSONObject.Create; Result.AddPair('error', Err); Exit; end;
    TargetWidthPx := TOpenCVHelpers.GetOptionalInt(Args, 'width', 640);
    TargetHeightPx := TOpenCVHelpers.GetOptionalInt(Args, 'height', 480);
    MaxDurationMs := TOpenCVHelpers.GetOptionalInt(Args, 'maxDurationMs', 30000);
    Exit(TFFmpegHelpers.ScaleVideo(SourceUrl, OutputPath, TargetWidthPx, TargetHeightPx, MaxDurationMs));
  end
  else if Name = 'video_filter' then
  begin
    if not TOpenCVHelpers.RequireOutputPath(Args, 'video', OutputPath, Err) then
    begin Result := TJSONObject.Create; Result.AddPair('error', Err); Exit; end;
    if not TOpenCVHelpers.RequireString(Args, 'filter', FilterExpr) then
    begin Result := TJSONObject.Create; Result.AddPair('error', 'filter is required'); Exit; end;
    MaxDurationMs := TOpenCVHelpers.GetOptionalInt(Args, 'maxDurationMs', 30000);
    Exit(TFFmpegHelpers.ApplyFilter(SourceUrl, OutputPath, FilterExpr, MaxDurationMs));
  end
  else if Name = 'video_detect_silence' then
  begin
    NoiseDb := TOpenCVHelpers.GetOptionalInt(Args, 'noiseDb', -30);
    MinSilenceMs := TOpenCVHelpers.GetOptionalInt(Args, 'minSilenceMs', 500);
    Exit(TFFmpegHelpers.DetectSilence(SourceUrl, NoiseDb, MinSilenceMs));
  end
  else if Name = 'video_scene_detect' then
  begin
    Threshold := TOpenCVHelpers.GetOptionalDouble(Args, 'threshold', 0.12);
    MaxScenes := TOpenCVHelpers.GetOptionalInt(Args, 'maxScenes', 80);
    Exit(TFFmpegHelpers.DetectScenes(SourceUrl, Threshold, MaxScenes));
  end
  else if Name = 'video_metadata_read' then
    Exit(TFFmpegHelpers.ReadMetadata(SourceUrl))
  else
    raise Exception.Create('FFmpeg tool not found: ' + Name);
end;

end.

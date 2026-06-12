unit uFFmpegHelpers;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Math,
  Winapi.Windows,
  ffmpeg_types, libavcodec, libavformat, libavutil, libswscale, libswresample,
  OpenCV5.Core, OpenCV5.Types, OpenCV5.Imgproc, OpenCV5.Imgcodecs, OpenCV5.Utils,
  uOpenCVHelpers, uFFmpegProbe, uFFmpegPath, uFFmpegCodecUtils;

type
  TFFmpegHelpers = class
  public
    class function RequireSource(Args: TJSONObject; out SourceUrl: string): Boolean;
    class function OpenInput(const SourceUrl: string; out FmtCtx: PAVFormatContext; out Error: string): Boolean;
    class procedure CloseInput(var FmtCtx: PAVFormatContext);
    class function FindBestStream(FmtCtx: PAVFormatContext; MediaType: AVMediaType): Integer;
    class function Probe(const SourceUrl: string): TJSONObject;
    class function StreamTest(const SourceUrl: string; TimeoutMs: Integer): TJSONObject;
    class function GrabFrame(const SourceUrl, OutputPath: string; TimeOffsetMs: Integer): TJSONObject;
    class function GrabFrames(const SourceUrl, OutputDir: string; TimeOffsetMs, IntervalMs, Count: Integer): TJSONObject;
    class function Thumbnail(const SourceUrl, OutputPath: string; TimeOffsetMs, Width, Height: Integer): TJSONObject;
    class function Remux(const SourceUrl, OutputPath: string): TJSONObject;
    class function Trim(const SourceUrl, OutputPath: string; StartMs, EndMs: Integer): TJSONObject;
    class function Concat(const InputPaths: TJSONArray; OutputPath: string): TJSONObject;
    class function ExtractAudio(const SourceUrl, OutputPath: string; SampleRate: Integer): TJSONObject;
    class function RecordSegment(const SourceUrl, OutputPath: string; DurationMs: Integer): TJSONObject;
    class function ScaleVideo(const SourceUrl, OutputPath: string; TargetWidthPx, TargetHeightPx, MaxDurationMs: Integer): TJSONObject;
    class function ApplyFilter(const SourceUrl, OutputPath, FilterExpr: string; MaxDurationMs: Integer): TJSONObject;
    class function DetectSilence(const SourceUrl: string; NoiseDb, MinSilenceMs: Integer): TJSONObject;
    class function DetectScenes(const SourceUrl: string; Threshold: Double; MaxScenes: Integer): TJSONObject;
    class function ReadMetadata(const SourceUrl: string): TJSONObject;
  private
    class function SaveFrameJpeg(FrameRGBA: PAVFrame; Width, Height: Integer; const OutputPath: string): Boolean;
    class function IsStreamSource(const SourceUrl: string): Boolean;
    class function SetupInputOptions(const SourceUrl: string; var Options: PAVDictionary): Boolean;
    class function DecodeFirstVideoFrame(FmtCtx: PAVFormatContext; VideoIdx: Integer; CodecCtx: PAVCodecContext;
      Pkt: PAVPacket; Frame: PAVFrame; out GotFrame: Boolean): Boolean;
    class function FramePixelSize(Frame: PAVFrame; CodecCtx: PAVCodecContext; CodecPar: PAVCodecParameters;
      out Width, Height: Integer): Boolean;
    class function FfUtf8Path(const S: string): UTF8String;
    class function OpenConcatInput(const ListPath: string; out FmtCtx: PAVFormatContext; out Error: string): Boolean;
    class function ConcatSequential(const InputPaths: TJSONArray; const OutputPath: string): TJSONObject;
    class function RemuxConcatList(const ListPath, OutputPath: string): TJSONObject;
    class function StreamCopySupported(ofmt, ifmt: PAVFormatContext): Boolean;
    class function StreamCopyErrorMsg(ofmt, ifmt: PAVFormatContext): string;
    class function TranscodeVideo(const SourceUrl, OutputPath: string; DstW, DstH, StartMs, EndMs,
      MaxDurationMs: Integer): TJSONObject;
    class function TrimTranscoded(const SourceUrl, OutputPath: string; StartMs, EndMs: Integer): TJSONObject;
    class function TranscodeScaled(const SourceUrl, OutputPath: string; DstW, DstH, MaxDurationMs: Integer): TJSONObject;
  end;

implementation

{$POINTERMATH ON}

function StreamAt(FmtCtx: PAVFormatContext; Index: Integer): PAVStream;
begin
  Result := PPtrIdx(FmtCtx.streams, Index);
end;

class function TFFmpegHelpers.RequireSource(Args: TJSONObject; out SourceUrl: string): Boolean;
begin
  Result := Assigned(Args) and Args.TryGetValue('sourceUrl', SourceUrl) and (SourceUrl <> '');
end;

class function TFFmpegHelpers.IsStreamSource(const SourceUrl: string): Boolean;
begin
  Result := SourceUrl.StartsWith('rtsp://', True) or SourceUrl.StartsWith('rtsps://', True) or
    SourceUrl.StartsWith('http://', True) or SourceUrl.StartsWith('https://', True);
end;

class function TFFmpegHelpers.SetupInputOptions(const SourceUrl: string; var Options: PAVDictionary): Boolean;
begin
  Result := False;
  if IsStreamSource(SourceUrl) then
  begin
    av_dict_set(Options, 'rtsp_transport', 'tcp', 0);
    av_dict_set(Options, 'stimeout', '5000000', 0);
    Result := True;
  end;
end;

class function TFFmpegHelpers.FfUtf8Path(const S: string): UTF8String;
begin
  Result := FFmpegUtf8Path(S);
end;

class function TFFmpegHelpers.StreamCopySupported(ofmt, ifmt: PAVFormatContext): Boolean;
var
  I: Integer;
  St: PAVStream;
  Par: PAVCodecParameters;
begin
  Result := Assigned(ofmt) and Assigned(ofmt.oformat) and Assigned(ifmt);
  if not Result then
    Exit;
  for I := 0 to ifmt.nb_streams - 1 do
  begin
    St := StreamAt(ifmt, I);
    Par := St.codecpar;
    if not Assigned(Par) then
      Continue;
    if (Par.codec_type <> AVMEDIA_TYPE_AUDIO) and
       (Par.codec_type <> AVMEDIA_TYPE_VIDEO) and
       (Par.codec_type <> AVMEDIA_TYPE_SUBTITLE) then
      Continue;
    if avformat_query_codec(ofmt.oformat, Par.codec_id, FF_COMPLIANCE_NORMAL) <= 0 then
      Exit(False);
  end;
end;

class function TFFmpegHelpers.StreamCopyErrorMsg(ofmt, ifmt: PAVFormatContext): string;
var
  I: Integer;
  St: PAVStream;
  Par: PAVCodecParameters;
  CodecName: string;
  Names: TStringList;
  OutFmt: string;
begin
  Names := TStringList.Create;
  try
    if Assigned(ofmt) and Assigned(ofmt.oformat) then
      OutFmt := string(AnsiString(ofmt.oformat.name))
    else
      OutFmt := 'unknown';
    for I := 0 to ifmt.nb_streams - 1 do
    begin
      St := StreamAt(ifmt, I);
      Par := St.codecpar;
      if not Assigned(Par) then
        Continue;
      if (Par.codec_type <> AVMEDIA_TYPE_AUDIO) and
         (Par.codec_type <> AVMEDIA_TYPE_VIDEO) and
         (Par.codec_type <> AVMEDIA_TYPE_SUBTITLE) then
        Continue;
      if avformat_query_codec(ofmt.oformat, Par.codec_id, FF_COMPLIANCE_NORMAL) <= 0 then
      begin
        CodecName := string(AnsiString(avcodec_get_name(Par.codec_id)));
        if Names.IndexOf(CodecName) < 0 then
          Names.Add(CodecName);
      end;
    end;
    if Names.Count = 0 then
      Result := 'Could not write header'
    else
      Result := Format('Output format "%s" does not support codec(s): %s. Use .avi output or video_scale for transcode.',
        [OutFmt, Names.CommaText]);
  finally
    Names.Free;
  end;
end;

class function TFFmpegHelpers.OpenConcatInput(const ListPath: string; out FmtCtx: PAVFormatContext; out Error: string): Boolean;
var
  Ret: Integer;
  Options: PAVDictionary;
  Utf8Src: UTF8String;
  ConcatFmt: PAVInputFormat;
begin
  Result := False;
  Error := '';
  Options := nil;
  FmtCtx := avformat_alloc_context();
  if not Assigned(FmtCtx) then
  begin
    Error := 'Failed to allocate format context';
    Exit;
  end;
  ConcatFmt := av_find_input_format('concat');
  if not Assigned(ConcatFmt) then
  begin
    Error := 'Concat demuxer not found';
    avformat_free_context(FmtCtx);
    FmtCtx := nil;
    Exit;
  end;
  av_dict_set(Options, 'safe', '0', 0);
  Utf8Src := FfUtf8Path(ListPath);
  Ret := avformat_open_input(FmtCtx, PAnsiChar(Utf8Src), ConcatFmt, Options);
  if Assigned(Options) then
    av_dict_free(Options);
  if Ret < 0 then
  begin
    Error := Format('Could not open concat list: %s (code %d)', [ListPath, Ret]);
    avformat_free_context(FmtCtx);
    FmtCtx := nil;
    Exit;
  end;
  if avformat_find_stream_info(FmtCtx, nil) < 0 then
  begin
    Error := 'Could not find stream information for concat list';
    avformat_close_input(FmtCtx);
    FmtCtx := nil;
    Exit;
  end;
  Result := True;
end;

class function TFFmpegHelpers.OpenInput(const SourceUrl: string; out FmtCtx: PAVFormatContext; out Error: string): Boolean;
var
  Ret: Integer;
  Options: PAVDictionary;
  Utf8Src: UTF8String;
begin
  Result := False;
  Error := '';
  Options := nil;
  FmtCtx := avformat_alloc_context();
  if not Assigned(FmtCtx) then
  begin
    Error := 'Failed to allocate format context';
    Exit;
  end;
  SetupInputOptions(SourceUrl, Options);
  Utf8Src := FfUtf8Path(SourceUrl);
  Ret := avformat_open_input(FmtCtx, PAnsiChar(Utf8Src), nil, Options);
  if Assigned(Options) then
    av_dict_free(Options);
  if Ret < 0 then
  begin
    Error := Format('Could not open source: %s (code %d)', [SourceUrl, Ret]);
    avformat_free_context(FmtCtx);
    FmtCtx := nil;
    Exit;
  end;
  if avformat_find_stream_info(FmtCtx, nil) < 0 then
  begin
    Error := 'Could not find stream information';
    avformat_close_input(FmtCtx);
    FmtCtx := nil;
    Exit;
  end;
  Result := True;
end;

class procedure TFFmpegHelpers.CloseInput(var FmtCtx: PAVFormatContext);
begin
  if Assigned(FmtCtx) then
    avformat_close_input(FmtCtx);
  FmtCtx := nil;
end;

class function TFFmpegHelpers.FindBestStream(FmtCtx: PAVFormatContext; MediaType: AVMediaType): Integer;
var
  Codec: PAVCodec;
begin
  Result := av_find_best_stream(FmtCtx, MediaType, -1, -1, Codec, 0);
end;

class function TFFmpegHelpers.FramePixelSize(Frame: PAVFrame; CodecCtx: PAVCodecContext; CodecPar: PAVCodecParameters;
  out Width, Height: Integer): Boolean;
begin
  Width := 0;
  Height := 0;
  if Assigned(Frame) then
  begin
    Width := Frame.width;
    Height := Frame.height;
  end;
  if ((Width <= 0) or (Height <= 0)) and Assigned(CodecPar) then
    VideoSizeFromParameters(CodecPar, Width, Height);
  if ((Width <= 0) or (Height <= 0)) and Assigned(CodecCtx) then
  begin
    Width := CodecCtx.width;
    Height := CodecCtx.height;
  end;
  Result := (Width > 0) and (Height > 0);
end;

class function TFFmpegHelpers.SaveFrameJpeg(FrameRGBA: PAVFrame; Width, Height: Integer; const OutputPath: string): Boolean;
var
  I: Integer;
  SrcPtr, DstPtr: PByte;
  Bgra, Bgr: TCVMat;
begin
  Result := False;
  if (Width <= 0) or (Height <= 0) or not Assigned(FrameRGBA) or not Assigned(FrameRGBA.data[0]) then
    Exit;
  Bgra := TCVMat.Create_0(Height, Width, CV_8UC4);
  try
    for I := 0 to Height - 1 do
    begin
      SrcPtr := PByte(NativeInt(FrameRGBA.data[0]) + NativeInt(FrameRGBA.linesize[0]) * I);
      DstPtr := PByte(Bgra.ptr(I, 0));
      Move(SrcPtr^, DstPtr^, Width * 4);
    end;
    Bgr := TCVMat.Create_0(0, 0, CV_8UC3);
    try
      cvtColor(Bgra.Handle, Bgr.Handle, COLOR_BGRA2BGR, 0, 0);
      TOpenCVHelpers.EnsureOutputDir(OutputPath);
      Result := imwritePath(OutputPath, Bgr.Handle);
    finally
      Bgr.Release;
    end;
  finally
    Bgra.Release;
  end;
end;

class function TFFmpegHelpers.DecodeFirstVideoFrame(FmtCtx: PAVFormatContext; VideoIdx: Integer; CodecCtx: PAVCodecContext;
  Pkt: PAVPacket; Frame: PAVFrame; out GotFrame: Boolean): Boolean;
var
  Ret: Integer;
begin
  GotFrame := False;
  Result := False;
  while av_read_frame(FmtCtx, Pkt) >= 0 do
  begin
    try
      if Pkt.stream_index <> VideoIdx then
        Continue;
      Ret := avcodec_send_packet(CodecCtx, Pkt);
      if Ret < 0 then
        Continue;
      Ret := avcodec_receive_frame(CodecCtx, Frame);
      if Ret < 0 then
        Continue;
      GotFrame := True;
      Result := True;
      Exit;
    finally
      av_packet_unref(Pkt);
    end;
  end;
end;

class function TFFmpegHelpers.Probe(const SourceUrl: string): TJSONObject;
var
  Err: string;
  Info, DurObj: TJSONObject;
  DurVal: Int64;
begin
  Result := TJSONObject.Create;
  Info := TMediaInfo.ProbeSource(SourceUrl, Err);
  if Info = nil then
  begin
    Result.AddPair('error', Err);
    Exit;
  end;
  try
    Result.AddPair('status', 'success');
    Result.AddPair('probe', Info.Clone as TJSONObject);
    if Info.TryGetValue<TJSONObject>('duration', DurObj) and DurObj.TryGetValue<Int64>('value', DurVal) then
      Result.AddPair('durationMs', TJSONNumber.Create(DurVal div 1000));
  finally
    Info.Free;
  end;
end;

class function TFFmpegHelpers.StreamTest(const SourceUrl: string; TimeoutMs: Integer): TJSONObject;
var
  FmtCtx: PAVFormatContext;
  Err: string;
  StartTick: Cardinal;
  VideoIdx, AudioIdx: Integer;
begin
  Result := TJSONObject.Create;
  StartTick := GetTickCount;
  if not OpenInput(SourceUrl, FmtCtx, Err) then
  begin
    Result.AddPair('error', Err);
    Result.AddPair('reachable', TJSONBool.Create(False));
    Exit;
  end;
  try
    VideoIdx := FindBestStream(FmtCtx, AVMEDIA_TYPE_VIDEO);
    AudioIdx := FindBestStream(FmtCtx, AVMEDIA_TYPE_AUDIO);
    Result.AddPair('status', 'success');
    Result.AddPair('reachable', TJSONBool.Create(True));
    Result.AddPair('latencyMs', TJSONNumber.Create(GetTickCount - StartTick));
    Result.AddPair('hasVideo', TJSONBool.Create(VideoIdx >= 0));
    Result.AddPair('hasAudio', TJSONBool.Create(AudioIdx >= 0));
    Result.AddPair('format', string(AnsiString(FmtCtx.iformat.name)));
    if FmtCtx.duration <> AV_NOPTS_VALUE then
      Result.AddPair('durationMs', TJSONNumber.Create(FmtCtx.duration div (AV_TIME_BASE div 1000)));
  finally
    CloseInput(FmtCtx);
  end;
end;

class function TFFmpegHelpers.GrabFrame(const SourceUrl, OutputPath: string; TimeOffsetMs: Integer): TJSONObject;
var
  FmtCtx: PAVFormatContext;
  Err: string;
  ResolvedPath: string;
  VideoIdx: Integer;
  St: PAVStream;
  Dec: PAVCodec;
  CodecCtx: PAVCodecContext;
  Pkt: PAVPacket;
  Frame, FrameRGBA: PAVFrame;
  ScaleCtx: PSwsContext;
  SeekTime: Int64;
  GotFrame: Boolean;
  Width, Height: Integer;
  PixFmt: AVPixelFormat;
begin
  Result := TJSONObject.Create;
  ResolvedPath := TOpenCVHelpers.ResolveOutputPath(OutputPath, 'captures');
  if not OpenInput(SourceUrl, FmtCtx, Err) then
  begin
    Result.AddPair('error', Err);
    Exit;
  end;
  CodecCtx := nil;
  Pkt := nil;
  Frame := nil;
  FrameRGBA := nil;
  ScaleCtx := nil;
  try
    VideoIdx := FindBestStream(FmtCtx, AVMEDIA_TYPE_VIDEO);
    if VideoIdx < 0 then
    begin
      Result.AddPair('error', 'No video stream found');
      Exit;
    end;
    St := StreamAt(FmtCtx, VideoIdx);
    Dec := avcodec_find_decoder(St.codecpar.codec_id);
    if not Assigned(Dec) then
    begin
      Result.AddPair('error', 'Decoder not found');
      Exit;
    end;
    CodecCtx := avcodec_alloc_context3(Dec);
    avcodec_parameters_to_context(CodecCtx, St.codecpar);
    if avcodec_open2(CodecCtx, Dec, nil) < 0 then
    begin
      Result.AddPair('error', 'Failed to open decoder');
      Exit;
    end;
    if (TimeOffsetMs > 0) and not IsStreamSource(SourceUrl) then
    begin
      if (St.time_base.num > 0) and (St.time_base.den > 0) then
      begin
        SeekTime := Int64(TimeOffsetMs) * Int64(St.time_base.den) div (1000 * Int64(St.time_base.num));
        av_seek_frame(FmtCtx, VideoIdx, SeekTime, AVSEEK_FLAG_BACKWARD);
        avcodec_flush_buffers(CodecCtx);
      end;
    end;
    Frame := av_frame_alloc();
    Pkt := av_packet_alloc();
    if not DecodeFirstVideoFrame(FmtCtx, VideoIdx, CodecCtx, Pkt, Frame, GotFrame) or not GotFrame then
    begin
      Result.AddPair('error', 'Could not decode frame');
      Exit;
    end;
    if not FramePixelSize(Frame, CodecCtx, St.codecpar, Width, Height) then
    begin
      Result.AddPair('error', 'Invalid frame dimensions');
      Exit;
    end;
    FrameRGBA := av_frame_alloc();
    if av_image_alloc(@FrameRGBA.data[0], @FrameRGBA.linesize[0], Width, Height, AV_PIX_FMT_RGB32, 1) < 0 then
    begin
      Result.AddPair('error', 'Failed to allocate RGB buffer');
      Exit;
    end;
    if Frame.format >= 0 then
      PixFmt := AVPixelFormat(Frame.format)
    else if St.codecpar.format >= 0 then
      PixFmt := AVPixelFormat(St.codecpar.format)
    else
      PixFmt := AV_PIX_FMT_YUV420P;
    ScaleCtx := sws_getContext(Width, Height, PixFmt, Width, Height, AV_PIX_FMT_RGB32, SWS_BICUBIC, nil, nil, nil);
    if not Assigned(ScaleCtx) then
    begin
      Result.AddPair('error', 'Failed to create scaler');
      Exit;
    end;
    sws_scale(ScaleCtx, @Frame.data, @Frame.linesize, 0, Height, @FrameRGBA.data, @FrameRGBA.linesize);
    if not SaveFrameJpeg(FrameRGBA, Width, Height, ResolvedPath) then
    begin
      Result.AddPair('error', 'Failed to save JPEG');
      Exit;
    end;
    Result.AddPair('status', 'success');
    Result.AddPair('outputPath', ResolvedPath);
    Result.AddPair('width', TJSONNumber.Create(Width));
    Result.AddPair('height', TJSONNumber.Create(Height));
    Result.AddPair('timeOffsetMs', TJSONNumber.Create(TimeOffsetMs));
  finally
    if Assigned(Pkt) then av_packet_free(Pkt);
    if Assigned(CodecCtx) then avcodec_free_context(CodecCtx);
    if Assigned(Frame) then av_frame_free(Frame);
    if Assigned(FrameRGBA) then
    begin
      if Assigned(FrameRGBA.data[0]) then av_freep(@FrameRGBA.data[0]);
      av_frame_free(FrameRGBA);
    end;
    if Assigned(ScaleCtx) then sws_freeContext(ScaleCtx);
    CloseInput(FmtCtx);
  end;
end;

class function TFFmpegHelpers.GrabFrames(const SourceUrl, OutputDir: string; TimeOffsetMs, IntervalMs, Count: Integer): TJSONObject;
var
  I, Offset: Integer;
  FramePath, DirPath: string;
  One: TJSONObject;
  Paths: TJSONArray;
  ErrMsg: string;
begin
  Result := TJSONObject.Create;
  if Count <= 0 then Count := 1;
  if IntervalMs <= 0 then IntervalMs := 1000;
  DirPath := TOpenCVHelpers.ResolveOutputPath(OutputDir, 'captures');
  if TPath.GetExtension(DirPath) <> '' then
    DirPath := ExtractFilePath(DirPath);
  ForceDirectories(DirPath);
  Paths := TJSONArray.Create;
  try
    for I := 0 to Count - 1 do
    begin
      Offset := TimeOffsetMs + I * IntervalMs;
      FramePath := TPath.Combine(DirPath, Format('frame_%04d.jpg', [I]));
      One := GrabFrame(SourceUrl, FramePath, Offset);
      try
        if One.TryGetValue('error', ErrMsg) then
        begin
          Result.AddPair('error', Format('Frame %d failed: %s', [I, ErrMsg]));
          Exit;
        end;
        Paths.Add(TPath.GetFullPath(FramePath));
      finally
        One.Free;
      end;
      if IsStreamSource(SourceUrl) then
        Break;
    end;
    Result.AddPair('status', 'success');
    Result.AddPair('outputDir', DirPath);
    Result.AddPair('frames', Paths);
    Result.AddPair('count', TJSONNumber.Create(Paths.Count));
  except
    Paths.Free;
    raise;
  end;
end;

class function TFFmpegHelpers.Thumbnail(const SourceUrl, OutputPath: string; TimeOffsetMs, Width, Height: Integer): TJSONObject;
var
  Status: string;
begin
  Result := GrabFrame(SourceUrl, OutputPath, TimeOffsetMs);
  if Result.TryGetValue('status', Status) and (Status = 'success') then
    Result.AddPair('thumbnail', TJSONBool.Create(True));
end;

class function TFFmpegHelpers.RemuxConcatList(const ListPath, OutputPath: string): TJSONObject;
var
  ifmt, ofmt: PAVFormatContext;
  pkt: AVPacket;
  stream_mapping: PInteger;
  i, stream_index: Integer;
  in_stream, out_stream: PAVStream;
  Err: string;
  ResolvedPath: string;
  Utf8Out: UTF8String;
  OutOpts: PAVDictionary;
begin
  Result := TJSONObject.Create;
  ResolvedPath := TOpenCVHelpers.ResolveOutputPath(OutputPath, 'video');
  if not OpenConcatInput(ListPath, ifmt, Err) then
  begin
    Result.AddPair('error', Err);
    Exit;
  end;
  ofmt := nil;
  stream_mapping := nil;
  OutOpts := nil;
  try
    Utf8Out := FfUtf8Path(ResolvedPath);
    if avformat_alloc_output_context2(ofmt, nil, nil, PAnsiChar(Utf8Out)) < 0 then
    begin
      Result.AddPair('error', 'Could not create output context');
      Exit;
    end;
    if not StreamCopySupported(ofmt, ifmt) then
    begin
      Result.AddPair('error', StreamCopyErrorMsg(ofmt, ifmt));
      Exit;
    end;
    stream_mapping := av_mallocz_array(ifmt.nb_streams, SizeOf(Integer));
    stream_index := 0;
    for i := 0 to ifmt.nb_streams - 1 do
    begin
      in_stream := StreamAt(ifmt, i);
      if (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_AUDIO) and
         (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_VIDEO) and
         (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_SUBTITLE) then
      begin
        stream_mapping[i] := -1;
        Continue;
      end;
      stream_mapping[i] := stream_index;
      Inc(stream_index);
      out_stream := avformat_new_stream(ofmt, nil);
      avcodec_parameters_copy(out_stream.codecpar, in_stream.codecpar);
      out_stream.codecpar.codec_tag.tag := 0;
    end;
    if (ofmt.oformat.flags and AVFMT_NOFILE) = 0 then
      if avio_open(ofmt.pb, PAnsiChar(Utf8Out), AVIO_FLAG_WRITE) < 0 then
      begin
        Result.AddPair('error', 'Could not open output file');
        Exit;
      end;
    av_dict_set(OutOpts, PAnsiChar(AnsiString('movflags')), PAnsiChar(AnsiString('faststart')), 0);
    if avformat_write_header(ofmt, @OutOpts) < 0 then
    begin
      Result.AddPair('error', StreamCopyErrorMsg(ofmt, ifmt));
      Exit;
    end;
    if Assigned(OutOpts) then
      av_dict_free(OutOpts);
    OutOpts := nil;
    while av_read_frame(ifmt, @pkt) >= 0 do
    begin
      in_stream := StreamAt(ifmt, pkt.stream_index);
      if (pkt.stream_index >= ifmt.nb_streams) or (stream_mapping[pkt.stream_index] < 0) then
      begin
        av_packet_unref(pkt);
        Continue;
      end;
      pkt.stream_index := stream_mapping[pkt.stream_index];
      out_stream := StreamAt(ofmt, pkt.stream_index);
      av_packet_rescale_ts(@pkt, in_stream.time_base, out_stream.time_base);
      pkt.pos := -1;
      av_interleaved_write_frame(ofmt, @pkt);
      av_packet_unref(pkt);
    end;
    av_write_trailer(ofmt);
    Result.AddPair('status', 'success');
    Result.AddPair('outputPath', ResolvedPath);
  finally
    if Assigned(stream_mapping) then av_free(stream_mapping);
    if Assigned(ofmt) then
    begin
      if (ofmt.oformat <> nil) and ((ofmt.oformat.flags and AVFMT_NOFILE) = 0) then
        avio_closep(ofmt.pb);
      avformat_free_context(ofmt);
    end;
    CloseInput(ifmt);
  end;
end;

class function TFFmpegHelpers.Remux(const SourceUrl, OutputPath: string): TJSONObject;
var
  ifmt, ofmt: PAVFormatContext;
  pkt: AVPacket;
  stream_mapping: PInteger;
  i, ret, stream_index: Integer;
  in_stream, out_stream: PAVStream;
  Err: string;
  ResolvedPath: string;
  Utf8Out: UTF8String;
  OutOpts: PAVDictionary;
begin
  Result := TJSONObject.Create;
  ResolvedPath := TOpenCVHelpers.ResolveOutputPath(OutputPath, 'video');
  if not OpenInput(SourceUrl, ifmt, Err) then
  begin
    Result.AddPair('error', Err);
    Exit;
  end;
  ofmt := nil;
  stream_mapping := nil;
  OutOpts := nil;
  try
    Utf8Out := FfUtf8Path(ResolvedPath);
    if avformat_alloc_output_context2(ofmt, nil, nil, PAnsiChar(Utf8Out)) < 0 then
    begin
      Result.AddPair('error', 'Could not create output context');
      Exit;
    end;
    if not StreamCopySupported(ofmt, ifmt) then
    begin
      Result.AddPair('error', StreamCopyErrorMsg(ofmt, ifmt));
      Exit;
    end;
    stream_mapping := av_mallocz_array(ifmt.nb_streams, SizeOf(Integer));
    stream_index := 0;
    for i := 0 to ifmt.nb_streams - 1 do
    begin
      in_stream := StreamAt(ifmt, i);
      if (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_AUDIO) and
         (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_VIDEO) and
         (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_SUBTITLE) then
      begin
        stream_mapping[i] := -1;
        Continue;
      end;
      stream_mapping[i] := stream_index;
      Inc(stream_index);
      out_stream := avformat_new_stream(ofmt, nil);
      avcodec_parameters_copy(out_stream.codecpar, in_stream.codecpar);
      out_stream.codecpar.codec_tag.tag := 0;
    end;
    if (ofmt.oformat.flags and AVFMT_NOFILE) = 0 then
      if avio_open(ofmt.pb, PAnsiChar(Utf8Out), AVIO_FLAG_WRITE) < 0 then
      begin
        Result.AddPair('error', 'Could not open output file');
        Exit;
      end;
    av_dict_set(OutOpts, PAnsiChar(AnsiString('movflags')), PAnsiChar(AnsiString('faststart')), 0);
    if avformat_write_header(ofmt, @OutOpts) < 0 then
    begin
      Result.AddPair('error', StreamCopyErrorMsg(ofmt, ifmt));
      Exit;
    end;
    if Assigned(OutOpts) then
      av_dict_free(OutOpts);
    OutOpts := nil;
    while av_read_frame(ifmt, @pkt) >= 0 do
    begin
      in_stream := StreamAt(ifmt, pkt.stream_index);
      if (pkt.stream_index >= ifmt.nb_streams) or (stream_mapping[pkt.stream_index] < 0) then
      begin
        av_packet_unref(pkt);
        Continue;
      end;
      pkt.stream_index := stream_mapping[pkt.stream_index];
      out_stream := StreamAt(ofmt, pkt.stream_index);
      av_packet_rescale_ts(@pkt, in_stream.time_base, out_stream.time_base);
      pkt.pos := -1;
      av_interleaved_write_frame(ofmt, @pkt);
      av_packet_unref(pkt);
    end;
    av_write_trailer(ofmt);
    Result.AddPair('status', 'success');
    Result.AddPair('outputPath', ResolvedPath);
  finally
    if Assigned(stream_mapping) then av_free(stream_mapping);
    if Assigned(ofmt) then
    begin
      if (ofmt.oformat <> nil) and ((ofmt.oformat.flags and AVFMT_NOFILE) = 0) then
        avio_closep(ofmt.pb);
      avformat_free_context(ofmt);
    end;
    CloseInput(ifmt);
  end;
end;

class function TFFmpegHelpers.Trim(const SourceUrl, OutputPath: string; StartMs, EndMs: Integer): TJSONObject;
var
  ifmt, ofmt: PAVFormatContext;
  pkt: AVPacket;
  stream_mapping: PInteger;
  i, stream_index: Integer;
  in_stream, out_stream: PAVStream;
  Err: string;
  ResolvedPath: string;
  StartUs: Int64;
  Utf8Out: UTF8String;
  OutOpts: PAVDictionary;
  MsBase: AVRational;
  Fallback: TJSONObject;
begin
  Result := TJSONObject.Create;
  ResolvedPath := TOpenCVHelpers.ResolveOutputPath(OutputPath, 'video');
  if EndMs <= 0 then EndMs := MaxInt div 1000;
  if not OpenInput(SourceUrl, ifmt, Err) then
  begin
    Result.AddPair('error', Err);
    Exit;
  end;
  ofmt := nil;
  stream_mapping := nil;
  OutOpts := nil;
  StartUs := Int64(StartMs) * 1000;
  MsBase := av_make_q(1, 1000);
  try
    Utf8Out := FfUtf8Path(ResolvedPath);
    if avformat_alloc_output_context2(ofmt, nil, nil, PAnsiChar(Utf8Out)) < 0 then
    begin
      Result.AddPair('error', 'Could not create output context');
      Exit;
    end;
    if not StreamCopySupported(ofmt, ifmt) then
    begin
      avformat_free_context(ofmt);
      ofmt := nil;
      Fallback := TrimTranscoded(SourceUrl, ResolvedPath, StartMs, EndMs);
      Result.Free;
      Result := Fallback;
      Exit;
    end;
    stream_mapping := av_mallocz_array(ifmt.nb_streams, SizeOf(Integer));
    stream_index := 0;
    for i := 0 to ifmt.nb_streams - 1 do
    begin
      in_stream := StreamAt(ifmt, i);
      if (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_AUDIO) and
         (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_VIDEO) and
         (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_SUBTITLE) then
      begin
        stream_mapping[i] := -1;
        Continue;
      end;
      stream_mapping[i] := stream_index;
      Inc(stream_index);
      out_stream := avformat_new_stream(ofmt, nil);
      avcodec_parameters_copy(out_stream.codecpar, in_stream.codecpar);
      out_stream.codecpar.codec_tag.tag := 0;
    end;
    if (ofmt.oformat.flags and AVFMT_NOFILE) = 0 then
      if avio_open(ofmt.pb, PAnsiChar(Utf8Out), AVIO_FLAG_WRITE) < 0 then
      begin
        Result.AddPair('error', 'Could not open output file');
        Exit;
      end;
    av_dict_set(OutOpts, PAnsiChar(AnsiString('movflags')), PAnsiChar(AnsiString('faststart')), 0);
    if avformat_write_header(ofmt, @OutOpts) < 0 then
    begin
      Result.AddPair('error', StreamCopyErrorMsg(ofmt, ifmt));
      Exit;
    end;
    if Assigned(OutOpts) then
      av_dict_free(OutOpts);
    OutOpts := nil;
    if StartMs > 0 then
      av_seek_frame(ifmt, -1, StartUs, AVSEEK_FLAG_BACKWARD);
    while av_read_frame(ifmt, @pkt) >= 0 do
    begin
      if (pkt.stream_index < 0) or (pkt.stream_index >= ifmt.nb_streams) then
      begin
        av_packet_unref(pkt);
        Continue;
      end;
      in_stream := StreamAt(ifmt, pkt.stream_index);
      if pkt.pts <> AV_NOPTS_VALUE then
      begin
        if av_compare_ts(pkt.pts, in_stream.time_base, StartMs, MsBase) < 0 then
        begin
          av_packet_unref(pkt);
          Continue;
        end;
        if av_compare_ts(pkt.pts, in_stream.time_base, EndMs, MsBase) >= 0 then
        begin
          av_packet_unref(pkt);
          Break;
        end;
      end;
      if stream_mapping[pkt.stream_index] < 0 then
      begin
        av_packet_unref(pkt);
        Continue;
      end;
      pkt.stream_index := stream_mapping[pkt.stream_index];
      out_stream := StreamAt(ofmt, pkt.stream_index);
      av_packet_rescale_ts(@pkt, in_stream.time_base, out_stream.time_base);
      pkt.pos := -1;
      av_interleaved_write_frame(ofmt, @pkt);
      av_packet_unref(pkt);
    end;
    av_write_trailer(ofmt);
    Result.AddPair('status', 'success');
    Result.AddPair('outputPath', ResolvedPath);
    Result.AddPair('startMs', TJSONNumber.Create(StartMs));
    Result.AddPair('endMs', TJSONNumber.Create(EndMs));
  finally
    if Assigned(OutOpts) then av_dict_free(OutOpts);
    if Assigned(stream_mapping) then av_free(stream_mapping);
    if Assigned(ofmt) then
    begin
      if (ofmt.oformat <> nil) and ((ofmt.oformat.flags and AVFMT_NOFILE) = 0) then
        avio_closep(ofmt.pb);
      avformat_free_context(ofmt);
    end;
    CloseInput(ifmt);
  end;
end;

class function TFFmpegHelpers.ConcatSequential(const InputPaths: TJSONArray; const OutputPath: string): TJSONObject;
var
  ifmt, ofmt: PAVFormatContext;
  pkt: AVPacket;
  stream_mapping: PInteger;
  stream_offset: array of Int64;
  i, file_idx, stream_index, out_idx: Integer;
  in_stream, out_stream: PAVStream;
  SrcPath, Err, ResolvedPath: string;
  OutStreamCount: Integer;
  Utf8Out: UTF8String;
  OutOpts: PAVDictionary;
  FirstFile: Boolean;
begin
  Result := TJSONObject.Create;
  ResolvedPath := TOpenCVHelpers.ResolveOutputPath(OutputPath, 'video');
  ifmt := nil;
  ofmt := nil;
  stream_mapping := nil;
  OutOpts := nil;
  FirstFile := True;
  try
    for file_idx := 0 to InputPaths.Count - 1 do
    begin
      SrcPath := InputPaths.Items[file_idx].Value;
      if not OpenInput(SrcPath, ifmt, Err) then
      begin
        Result.AddPair('error', Format('Input %d: %s', [file_idx, Err]));
        Exit;
      end;
      if FirstFile then
      begin
        Utf8Out := FfUtf8Path(ResolvedPath);
        if avformat_alloc_output_context2(ofmt, nil, nil, PAnsiChar(Utf8Out)) < 0 then
        begin
          Result.AddPair('error', 'Could not create output context');
          Exit;
        end;
        if not StreamCopySupported(ofmt, ifmt) then
        begin
          Result.AddPair('error', StreamCopyErrorMsg(ofmt, ifmt));
          Exit;
        end;
        stream_mapping := av_mallocz_array(ifmt.nb_streams, SizeOf(Integer));
        stream_index := 0;
        for i := 0 to ifmt.nb_streams - 1 do
        begin
          in_stream := StreamAt(ifmt, i);
          if (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_AUDIO) and
             (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_VIDEO) and
             (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_SUBTITLE) then
          begin
            stream_mapping[i] := -1;
            Continue;
          end;
          stream_mapping[i] := stream_index;
          Inc(stream_index);
          out_stream := avformat_new_stream(ofmt, nil);
          avcodec_parameters_copy(out_stream.codecpar, in_stream.codecpar);
          out_stream.codecpar.codec_tag.tag := 0;
        end;
        OutStreamCount := stream_index;
        SetLength(stream_offset, OutStreamCount);
        for i := 0 to OutStreamCount - 1 do
          stream_offset[i] := 0;
        if (ofmt.oformat.flags and AVFMT_NOFILE) = 0 then
          if avio_open(ofmt.pb, PAnsiChar(Utf8Out), AVIO_FLAG_WRITE) < 0 then
          begin
            Result.AddPair('error', 'Could not open output file');
            Exit;
          end;
        av_dict_set(OutOpts, PAnsiChar(AnsiString('movflags')), PAnsiChar(AnsiString('faststart')), 0);
        if avformat_write_header(ofmt, @OutOpts) < 0 then
        begin
          Result.AddPair('error', StreamCopyErrorMsg(ofmt, ifmt));
          Exit;
        end;
        if Assigned(OutOpts) then
          av_dict_free(OutOpts);
        OutOpts := nil;
        FirstFile := False;
      end
      else
      begin
        stream_index := 0;
        for i := 0 to ifmt.nb_streams - 1 do
          if stream_mapping[i] >= 0 then
            Inc(stream_index);
        if stream_index <> OutStreamCount then
        begin
          Result.AddPair('error', Format('Input %d has incompatible stream layout', [file_idx]));
          Exit;
        end;
      end;
      while av_read_frame(ifmt, @pkt) >= 0 do
      begin
        if (pkt.stream_index < 0) or (pkt.stream_index >= ifmt.nb_streams) then
        begin
          av_packet_unref(pkt);
          Continue;
        end;
        out_idx := stream_mapping[pkt.stream_index];
        if out_idx < 0 then
        begin
          av_packet_unref(pkt);
          Continue;
        end;
        in_stream := StreamAt(ifmt, pkt.stream_index);
        out_stream := StreamAt(ofmt, out_idx);
        av_packet_rescale_ts(@pkt, in_stream.time_base, out_stream.time_base);
        if pkt.pts <> AV_NOPTS_VALUE then
          pkt.pts := pkt.pts + stream_offset[out_idx];
        if pkt.dts <> AV_NOPTS_VALUE then
          pkt.dts := pkt.dts + stream_offset[out_idx];
        pkt.stream_index := out_idx;
        pkt.pos := -1;
        av_interleaved_write_frame(ofmt, @pkt);
        if pkt.pts <> AV_NOPTS_VALUE then
          if pkt.pts + 1 > stream_offset[out_idx] then
            stream_offset[out_idx] := pkt.pts + 1;
        av_packet_unref(pkt);
      end;
      if (ifmt.duration <> AV_NOPTS_VALUE) and (file_idx < InputPaths.Count - 1) then
      begin
        for i := 0 to ifmt.nb_streams - 1 do
        begin
          out_idx := stream_mapping[i];
          if out_idx >= 0 then
          begin
            in_stream := StreamAt(ifmt, i);
            out_stream := StreamAt(ofmt, out_idx);
            stream_offset[out_idx] := stream_offset[out_idx] +
              av_rescale_q(ifmt.duration, av_make_q(1, AV_TIME_BASE), out_stream.time_base);
          end;
        end;
      end;
      CloseInput(ifmt);
      ifmt := nil;
    end;
    av_write_trailer(ofmt);
    Result.AddPair('status', 'success');
    Result.AddPair('outputPath', ResolvedPath);
    Result.AddPair('inputCount', TJSONNumber.Create(InputPaths.Count));
  finally
    if Assigned(OutOpts) then av_dict_free(OutOpts);
    if Assigned(stream_mapping) then av_free(stream_mapping);
    if Assigned(ofmt) then
    begin
      if (ofmt.oformat <> nil) and ((ofmt.oformat.flags and AVFMT_NOFILE) = 0) then
        avio_closep(ofmt.pb);
      avformat_free_context(ofmt);
    end;
    if Assigned(ifmt) then
      CloseInput(ifmt);
  end;
end;

class function TFFmpegHelpers.Concat(const InputPaths: TJSONArray; OutputPath: string): TJSONObject;
var
  ResolvedPath: string;
begin
  Result := TJSONObject.Create;
  ResolvedPath := TOpenCVHelpers.ResolveOutputPath(OutputPath, 'video');
  if (InputPaths = nil) or (InputPaths.Count = 0) then
  begin
    Result.AddPair('error', 'inputPaths array is required');
    Exit;
  end;
  if InputPaths.Count = 1 then
  begin
    Result.Free;
    Result := Remux(InputPaths.Items[0].Value, ResolvedPath);
    Exit;
  end;
  Result.Free;
  Result := ConcatSequential(InputPaths, OutputPath);
end;

class function TFFmpegHelpers.ExtractAudio(const SourceUrl, OutputPath: string; SampleRate: Integer): TJSONObject;
var
  FmtCtx: PAVFormatContext;
  Err: string;
  AudioIdx: Integer;
  St: PAVStream;
  Dec: PAVCodec;
  CodecCtx: PAVCodecContext;
  Swr: PSwrContext;
  SwrInited: Boolean;
  Pkt: PAVPacket;
  Frame: PAVFrame;
  OutBuf: TBytes;
  OutFile: TFileStream;
  OutSamples: PByte;
  OutLinesize: Integer;
  OutCount, DataSize, I: Integer;
  InLayout, OutLayout: AVChannelLayout;
  InLayoutOk, OutLayoutOk: Boolean;
  ResolvedPath: string;
begin
  Result := TJSONObject.Create;
  ResolvedPath := TOpenCVHelpers.ResolveOutputPath(OutputPath, 'output');
  if SampleRate <= 0 then SampleRate := 44100;
  if not OpenInput(SourceUrl, FmtCtx, Err) then
  begin
    Result.AddPair('error', Err);
    Exit;
  end;
  CodecCtx := nil;
  Pkt := nil;
  Frame := nil;
  OutFile := nil;
  Swr := nil;
  SwrInited := False;
  InLayoutOk := False;
  OutLayoutOk := False;
  try
    AudioIdx := FindBestStream(FmtCtx, AVMEDIA_TYPE_AUDIO);
    if AudioIdx < 0 then
    begin
      Result.AddPair('error', 'No audio stream found');
      Exit;
    end;
    St := StreamAt(FmtCtx, AudioIdx);
    Dec := avcodec_find_decoder(St.codecpar.codec_id);
    if not Assigned(Dec) then
    begin
      Result.AddPair('error', 'Audio decoder not found');
      Exit;
    end;
    CodecCtx := avcodec_alloc_context3(Dec);
    avcodec_parameters_to_context(CodecCtx, St.codecpar);
    if avcodec_open2(CodecCtx, Dec, nil) < 0 then
    begin
      Result.AddPair('error', 'Failed to open audio decoder');
      Exit;
    end;
    FillChar(InLayout, SizeOf(InLayout), 0);
    if av_channel_layout_copy(InLayout, @St.codecpar.ch_layout) < 0 then
    begin
      Result.AddPair('error', 'Failed to copy input channel layout');
      Exit;
    end;
    InLayoutOk := True;
    av_channel_layout_default(OutLayout, 2);
    OutLayoutOk := True;
    if swr_alloc_set_opts2(Swr, @OutLayout, AV_SAMPLE_FMT_S16, SampleRate,
      @InLayout, CodecCtx.sample_fmt, CodecCtx.sample_rate, 0, nil) < 0 then
    begin
      Result.AddPair('error', 'Failed to allocate audio resampler');
      Exit;
    end;
    if swr_init(Swr) < 0 then
    begin
      Result.AddPair('error', 'Failed to initialize audio resampler');
      Exit;
    end;
    SwrInited := True;
    Pkt := av_packet_alloc();
    Frame := av_frame_alloc();
    TOpenCVHelpers.EnsureOutputDir(ResolvedPath);
    OutFile := TFileStream.Create(ResolvedPath, fmCreate);
    OutFile.Size := 44;
    while av_read_frame(FmtCtx, Pkt) >= 0 do
    begin
      if Pkt.stream_index <> AudioIdx then
      begin
        av_packet_unref(Pkt);
        Continue;
      end;
      if avcodec_send_packet(CodecCtx, Pkt) >= 0 then
        while avcodec_receive_frame(CodecCtx, Frame) >= 0 do
        begin
          if not SwrInited then
            Continue;
          OutCount := swr_get_out_samples(Swr, Frame.nb_samples);
          if OutCount <= 0 then
            Continue;
          SetLength(OutBuf, OutCount * 4);
          OutSamples := @OutBuf[0];
          if swr_convert(Swr, @OutSamples, OutCount, @Frame.data[0], Frame.nb_samples) < 0 then
            Continue;
          DataSize := OutCount * 2 * 2;
          if DataSize > 0 then
            OutFile.Write(OutBuf[0], DataSize);
        end;
      av_packet_unref(Pkt);
    end;
    Result.AddPair('status', 'success');
    Result.AddPair('outputPath', ResolvedPath);
    Result.AddPair('sampleRate', TJSONNumber.Create(SampleRate));
    Result.AddPair('format', 'pcm_s16le_stereo');
  finally
    if Assigned(OutFile) then OutFile.Free;
    if Assigned(Swr) then swr_free(Swr);
    if OutLayoutOk then av_channel_layout_uninit(OutLayout);
    if InLayoutOk then av_channel_layout_uninit(InLayout);
    if Assigned(Pkt) then av_packet_free(Pkt);
    if Assigned(Frame) then av_frame_free(Frame);
    if Assigned(CodecCtx) then avcodec_free_context(CodecCtx);
    CloseInput(FmtCtx);
  end;
end;

class function TFFmpegHelpers.RecordSegment(const SourceUrl, OutputPath: string; DurationMs: Integer): TJSONObject;
var
  ifmt, ofmt: PAVFormatContext;
  pkt: AVPacket;
  stream_mapping: PInteger;
  i, stream_index: Integer;
  in_stream, out_stream: PAVStream;
  Err: string;
  ResolvedPath: string;
  StartTick: Cardinal;
  Utf8Out: UTF8String;
begin
  Result := TJSONObject.Create;
  ResolvedPath := TOpenCVHelpers.ResolveOutputPath(OutputPath, 'video');
  if DurationMs <= 0 then DurationMs := 10000;
  if not OpenInput(SourceUrl, ifmt, Err) then
  begin
    Result.AddPair('error', Err);
    Exit;
  end;
  ofmt := nil;
  stream_mapping := nil;
  StartTick := GetTickCount;
  try
    Utf8Out := FfUtf8Path(ResolvedPath);
    if avformat_alloc_output_context2(ofmt, nil, nil, PAnsiChar(Utf8Out)) < 0 then
    begin
      Result.AddPair('error', 'Could not create output context');
      Exit;
    end;
    stream_mapping := av_mallocz_array(ifmt.nb_streams, SizeOf(Integer));
    stream_index := 0;
    for i := 0 to ifmt.nb_streams - 1 do
    begin
      in_stream := StreamAt(ifmt, i);
      if (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_AUDIO) and
         (in_stream.codecpar.codec_type <> AVMEDIA_TYPE_VIDEO) then
      begin
        stream_mapping[i] := -1;
        Continue;
      end;
      stream_mapping[i] := stream_index;
      Inc(stream_index);
      out_stream := avformat_new_stream(ofmt, nil);
      avcodec_parameters_copy(out_stream.codecpar, in_stream.codecpar);
      out_stream.codecpar.codec_tag.tag := 0;
    end;
    if (ofmt.oformat.flags and AVFMT_NOFILE) = 0 then
      if avio_open(ofmt.pb, PAnsiChar(Utf8Out), AVIO_FLAG_WRITE) < 0 then
      begin
        Result.AddPair('error', 'Could not open output file');
        Exit;
      end;
    avformat_write_header(ofmt, nil);
    while (Integer(GetTickCount - StartTick) < DurationMs) and (av_read_frame(ifmt, @pkt) >= 0) do
    begin
      if stream_mapping[pkt.stream_index] < 0 then
      begin
        av_packet_unref(pkt);
        Continue;
      end;
      in_stream := StreamAt(ifmt, pkt.stream_index);
      pkt.stream_index := stream_mapping[pkt.stream_index];
      out_stream := StreamAt(ofmt, pkt.stream_index);
      av_packet_rescale_ts(@pkt, in_stream.time_base, out_stream.time_base);
      av_interleaved_write_frame(ofmt, @pkt);
      av_packet_unref(pkt);
    end;
    av_write_trailer(ofmt);
    Result.AddPair('status', 'success');
    Result.AddPair('outputPath', ResolvedPath);
    Result.AddPair('durationMs', TJSONNumber.Create(DurationMs));
  finally
    if Assigned(stream_mapping) then av_free(stream_mapping);
    if Assigned(ofmt) then
    begin
      if Assigned(ofmt.pb) then avio_closep(ofmt.pb);
      avformat_free_context(ofmt);
    end;
    CloseInput(ifmt);
  end;
end;

class function TFFmpegHelpers.TranscodeVideo(const SourceUrl, OutputPath: string; DstW, DstH, StartMs, EndMs,
  MaxDurationMs: Integer): TJSONObject;
var
  ifmt, ofmt: PAVFormatContext;
  Err, ResolvedPath: string;
  Utf8Out: UTF8String;
  VideoIdx, AudioIdx: Integer;
  Dec, Enc: PAVCodec;
  DecCtx, EncCtx: PAVCodecContext;
  InVStream, OutVStream, OutAStream: PAVStream;
  Pkt, EncPkt: PAVPacket;
  Frame, ScaledFrame: PAVFrame;
  SwsCtx: PSwsContext;
  OutOpts: PAVDictionary;
  MsBase: AVRational;
  SrcW, SrcH: Integer;
  ScalerReady: Boolean;
  StartUs: Int64;
  InStream: PAVStream;
  TranscodeStartTick: Cardinal;
begin
  Result := TJSONObject.Create;
  ResolvedPath := TOpenCVHelpers.ResolveOutputPath(OutputPath, 'video');
  if DstW <= 0 then DstW := 640;
  if DstH <= 0 then DstH := 480;
  TranscodeStartTick := GetTickCount;
  if not OpenInput(SourceUrl, ifmt, Err) then
  begin
    Result.AddPair('error', Err);
    Exit;
  end;
  VideoIdx := FindBestStream(ifmt, AVMEDIA_TYPE_VIDEO);
  if VideoIdx < 0 then
  begin
    Result.AddPair('error', 'No video stream');
    CloseInput(ifmt);
    Exit;
  end;
  AudioIdx := FindBestStream(ifmt, AVMEDIA_TYPE_AUDIO);
  InVStream := StreamAt(ifmt, VideoIdx);
  DecCtx := nil;
  EncCtx := nil;
  Pkt := nil;
  Frame := nil;
  ScaledFrame := nil;
  SwsCtx := nil;
  ofmt := nil;
  OutOpts := nil;
  MsBase := av_make_q(1, 1000);
  StartUs := Int64(StartMs) * 1000;
  try
    Dec := avcodec_find_decoder(InVStream.codecpar.codec_id);
    if not Assigned(Dec) then
    begin
      Result.AddPair('error', 'Video decoder not found');
      Exit;
    end;
    DecCtx := avcodec_alloc_context3(Dec);
    avcodec_parameters_to_context(DecCtx, InVStream.codecpar);
    if avcodec_open2(DecCtx, Dec, nil) < 0 then
    begin
      Result.AddPair('error', 'Could not open video decoder');
      Exit;
    end;
    if StartMs > 0 then
    begin
      av_seek_frame(ifmt, -1, StartUs, AVSEEK_FLAG_BACKWARD);
      avcodec_flush_buffers(DecCtx);
    end;

    Utf8Out := FfUtf8Path(ResolvedPath);
    if avformat_alloc_output_context2(ofmt, nil, nil, PAnsiChar(Utf8Out)) < 0 then
    begin
      Result.AddPair('error', 'Could not create output context');
      Exit;
    end;

    Enc := avcodec_find_encoder_by_name('libx264');
    if not Assigned(Enc) then
      Enc := avcodec_find_encoder(AV_CODEC_ID_H264);
    if not Assigned(Enc) then
    begin
      Result.AddPair('error', 'H.264 encoder not found');
      Exit;
    end;
    OutVStream := avformat_new_stream(ofmt, nil);
    EncCtx := avcodec_alloc_context3(Enc);
    ConfigureVideoEncoder(EncCtx, DstW, DstH, 25, 1);
    if (EncCtx^.width <= 0) or (EncCtx^.height <= 0) then
    begin
      Result.AddPair('error', Format('Invalid encoder size %dx%d', [EncCtx^.width, EncCtx^.height]));
      Exit;
    end;
    if Enc.id = AV_CODEC_ID_H264 then
      av_opt_set(EncCtx^.priv_data, 'preset', 'veryfast', 0);
    if (ofmt.oformat.flags and AVFMT_GLOBALHEADER) <> 0 then
      EncCtx^.flags := EncCtx^.flags or AV_CODEC_FLAG_GLOBAL_HEADER;
    if avcodec_open2(EncCtx, Enc, nil) < 0 then
    begin
      Result.AddPair('error', 'Could not open H.264 encoder');
      Exit;
    end;
    avcodec_parameters_from_context(OutVStream.codecpar, EncCtx);
    OutVStream.codecpar.codec_tag.tag := 0;
    OutVStream.time_base := EncCtx^.time_base;

    OutAStream := nil;
    if AudioIdx >= 0 then
    begin
      OutAStream := avformat_new_stream(ofmt, nil);
      avcodec_parameters_copy(OutAStream.codecpar, StreamAt(ifmt, AudioIdx).codecpar);
      OutAStream.codecpar.codec_tag.tag := 0;
      OutAStream.time_base := StreamAt(ifmt, AudioIdx).time_base;
    end;

    if (ofmt.oformat.flags and AVFMT_NOFILE) = 0 then
      if avio_open(ofmt.pb, PAnsiChar(Utf8Out), AVIO_FLAG_WRITE) < 0 then
      begin
        Result.AddPair('error', 'Could not open output file');
        Exit;
      end;
    av_dict_set(OutOpts, PAnsiChar(AnsiString('movflags')), PAnsiChar(AnsiString('faststart')), 0);
    if avformat_write_header(ofmt, @OutOpts) < 0 then
    begin
      Result.AddPair('error', 'Could not write header');
      Exit;
    end;
    if Assigned(OutOpts) then
      av_dict_free(OutOpts);
    OutOpts := nil;
    Pkt := av_packet_alloc();
    Frame := av_frame_alloc();
    ScaledFrame := av_frame_alloc();
    EncPkt := av_packet_alloc();
    ScalerReady := False;

    while av_read_frame(ifmt, Pkt) >= 0 do
    begin
      if (MaxDurationMs > 0) and (StartMs <= 0) and
         (Integer(GetTickCount - TranscodeStartTick) > MaxDurationMs + 10000) then
      begin
        av_packet_unref(Pkt);
        Break;
      end;
      InStream := StreamAt(ifmt, Pkt.stream_index);
      if Pkt.pts <> AV_NOPTS_VALUE then
      begin
        if (StartMs > 0) and (av_compare_ts(Pkt.pts, InStream.time_base, StartMs, MsBase) < 0) then
        begin
          av_packet_unref(Pkt);
          Continue;
        end;
        if (EndMs > 0) and (av_compare_ts(Pkt.pts, InStream.time_base, EndMs, MsBase) >= 0) then
        begin
          av_packet_unref(Pkt);
          Break;
        end;
        if (MaxDurationMs > 0) and (StartMs <= 0) and
           (av_compare_ts(Pkt.pts, InStream.time_base, MaxDurationMs, MsBase) >= 0) then
        begin
          av_packet_unref(Pkt);
          Break;
        end;
        if (MaxDurationMs > 0) and (StartMs > 0) and
           (av_compare_ts(Pkt.pts, InStream.time_base, StartMs + MaxDurationMs, MsBase) >= 0) then
        begin
          av_packet_unref(Pkt);
          Break;
        end;
      end;

      if (AudioIdx >= 0) and (Pkt.stream_index = AudioIdx) then
      begin
        Pkt.stream_index := OutAStream.index;
        av_packet_rescale_ts(Pkt, StreamAt(ifmt, AudioIdx).time_base, OutAStream.time_base);
        Pkt.pos := -1;
        av_interleaved_write_frame(ofmt, Pkt);
        av_packet_unref(Pkt);
        Continue;
      end;

      if Pkt.stream_index <> VideoIdx then
      begin
        av_packet_unref(Pkt);
        Continue;
      end;

      if avcodec_send_packet(DecCtx, Pkt) < 0 then
      begin
        av_packet_unref(Pkt);
        Continue;
      end;
      av_packet_unref(Pkt);

      while avcodec_receive_frame(DecCtx, Frame) >= 0 do
      begin
        if (MaxDurationMs > 0) and (StartMs <= 0) and (EndMs <= 0) and
           (Integer(GetTickCount - TranscodeStartTick) > MaxDurationMs + 10000) then
          Break;
        if not ScalerReady then
        begin
          if not FramePixelSize(Frame, DecCtx, InVStream.codecpar, SrcW, SrcH) then
            Continue;
          SwsCtx := sws_getContext(SrcW, SrcH, AVPixelFormat(Frame.format),
            DstW, DstH, AV_PIX_FMT_YUV420P, SWS_BICUBIC, nil, nil, nil);
          if not Assigned(SwsCtx) then
            Continue;
          ScaledFrame.format := Integer(AV_PIX_FMT_YUV420P);
          ScaledFrame.width := DstW;
          ScaledFrame.height := DstH;
          av_frame_get_buffer(ScaledFrame, 32);
          ScalerReady := True;
        end;
        sws_scale(SwsCtx, @Frame.data, @Frame.linesize, 0, Frame.height,
          @ScaledFrame.data, @ScaledFrame.linesize);
        ScaledFrame.pts := Frame.pts;
        if avcodec_send_frame(EncCtx, ScaledFrame) < 0 then
          Continue;
        while avcodec_receive_packet(EncCtx, EncPkt) >= 0 do
        begin
          av_packet_rescale_ts(EncPkt, EncCtx^.time_base, OutVStream.time_base);
          EncPkt.stream_index := OutVStream.index;
          EncPkt.pos := -1;
          av_interleaved_write_frame(ofmt, EncPkt);
          av_packet_unref(EncPkt);
        end;
      end;
    end;

    avcodec_send_frame(EncCtx, nil);
    while avcodec_receive_packet(EncCtx, EncPkt) >= 0 do
    begin
      av_packet_rescale_ts(EncPkt, EncCtx^.time_base, OutVStream.time_base);
      EncPkt.stream_index := OutVStream.index;
      EncPkt.pos := -1;
      av_interleaved_write_frame(ofmt, EncPkt);
      av_packet_unref(EncPkt);
    end;

    av_write_trailer(ofmt);
    Result.AddPair('status', 'success');
    Result.AddPair('outputPath', ResolvedPath);
    Result.AddPair('width', TJSONNumber.Create(DstW));
    Result.AddPair('height', TJSONNumber.Create(DstH));
    if StartMs > 0 then
      Result.AddPair('startMs', TJSONNumber.Create(StartMs));
    if EndMs > 0 then
      Result.AddPair('endMs', TJSONNumber.Create(EndMs));
    if MaxDurationMs > 0 then
      Result.AddPair('maxDurationMs', TJSONNumber.Create(MaxDurationMs));
  finally
    if Assigned(OutOpts) then av_dict_free(OutOpts);
    if Assigned(EncPkt) then av_packet_free(EncPkt);
    if Assigned(SwsCtx) then sws_freeContext(SwsCtx);
    if Assigned(ScaledFrame) then av_frame_free(ScaledFrame);
    if Assigned(Frame) then av_frame_free(Frame);
    if Assigned(Pkt) then av_packet_free(Pkt);
    if Assigned(EncCtx) then avcodec_free_context(EncCtx);
    if Assigned(DecCtx) then avcodec_free_context(DecCtx);
    if Assigned(ofmt) then
    begin
      if (ofmt.oformat <> nil) and ((ofmt.oformat.flags and AVFMT_NOFILE) = 0) then
        avio_closep(ofmt.pb);
      avformat_free_context(ofmt);
    end;
    CloseInput(ifmt);
  end;
end;

class function TFFmpegHelpers.TranscodeScaled(const SourceUrl, OutputPath: string; DstW, DstH, MaxDurationMs: Integer): TJSONObject;
begin
  Result := TranscodeVideo(SourceUrl, OutputPath, DstW, DstH, 0, 0, MaxDurationMs);
end;

class function TFFmpegHelpers.TrimTranscoded(const SourceUrl, OutputPath: string; StartMs, EndMs: Integer): TJSONObject;
var
  FmtCtx: PAVFormatContext;
  Err: string;
  VideoIdx: Integer;
  St: PAVStream;
  W, H: Integer;
  Status: string;
begin
  if EndMs <= 0 then
    EndMs := MaxInt div 1000;
  if not OpenInput(SourceUrl, FmtCtx, Err) then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('error', Err);
    Exit;
  end;
  try
    VideoIdx := FindBestStream(FmtCtx, AVMEDIA_TYPE_VIDEO);
    if VideoIdx < 0 then
    begin
      Result := TJSONObject.Create;
      Result.AddPair('error', 'No video stream');
      Exit;
    end;
    St := StreamAt(FmtCtx, VideoIdx);
    if not VideoSizeFromParameters(St.codecpar, W, H) then
    begin
      W := 640;
      H := 480;
    end;
  finally
    CloseInput(FmtCtx);
  end;
  Result := TranscodeVideo(SourceUrl, OutputPath, W, H, StartMs, EndMs, 0);
  if Result.TryGetValue('status', Status) and (Status = 'success') then
    Result.AddPair('transcoded', TJSONBool.Create(True));
end;

class function TFFmpegHelpers.ScaleVideo(const SourceUrl, OutputPath: string; TargetWidthPx, TargetHeightPx, MaxDurationMs: Integer): TJSONObject;
begin
  if TargetWidthPx <= 0 then TargetWidthPx := 640;
  if TargetHeightPx <= 0 then TargetHeightPx := 480;
  Result := ApplyFilter(SourceUrl, OutputPath, Format('scale=%d:%d', [TargetWidthPx, TargetHeightPx]), MaxDurationMs);
end;

class function TFFmpegHelpers.ApplyFilter(const SourceUrl, OutputPath, FilterExpr: string; MaxDurationMs: Integer): TJSONObject;
var
  FilterVal, ScalePart: string;
  ColonPos, W, H: Integer;
begin
  if FilterExpr = '' then
  begin
    Result := TJSONObject.Create;
    Result.AddPair('error', 'filter is required');
    Exit;
  end;
  if FilterExpr.StartsWith('scale=', True) then
  begin
    ScalePart := Copy(FilterExpr, 7, MaxInt);
    ColonPos := Pos(':', ScalePart);
    if ColonPos > 0 then
    begin
      W := StrToIntDef(Copy(ScalePart, 1, ColonPos - 1), 0);
      H := StrToIntDef(Copy(ScalePart, ColonPos + 1, MaxInt), 0);
      if (W > 0) and (H > 0) then
        Exit(TranscodeScaled(SourceUrl, OutputPath, W, H, MaxDurationMs)); // W/H: parsed target size
    end;
  end;
  Result := Remux(SourceUrl, OutputPath);
  if Result.TryGetValue('status', FilterVal) and (FilterVal = 'success') then
  begin
    Result.AddPair('filter', FilterExpr);
    Result.AddPair('maxDurationMs', TJSONNumber.Create(MaxDurationMs));
    Result.AddPair('warning', 'Only scale=W:H is transcoded; other filters are remuxed unchanged');
  end;
end;

class function TFFmpegHelpers.DetectSilence(const SourceUrl: string; NoiseDb, MinSilenceMs: Integer): TJSONObject;
var
  FmtCtx: PAVFormatContext;
  Err: string;
  AudioIdx: Integer;
  CodecCtx: PAVCodecContext;
  Dec: PAVCodec;
  St: PAVStream;
  Pkt: PAVPacket;
  Frame: PAVFrame;
  Segments: TJSONArray;
  SegItem: TJSONObject;
  InSilence: Boolean;
  SilenceStartMs: Integer;
  PtsMs: Integer;
  SumSq: Double;
  I, N, Ch: Integer;
  Sample: SmallInt;
  P: PSmallInt;
  Rms, Threshold: Double;
begin
  Result := TJSONObject.Create;
  if NoiseDb = 0 then NoiseDb := -30;
  if MinSilenceMs <= 0 then MinSilenceMs := 500;
  Threshold := Power(10, NoiseDb / 20.0);
  if not OpenInput(SourceUrl, FmtCtx, Err) then
  begin
    Result.AddPair('error', Err);
    Exit;
  end;
  CodecCtx := nil;
  Pkt := nil;
  Frame := nil;
  Segments := TJSONArray.Create;
  InSilence := False;
  try
    AudioIdx := FindBestStream(FmtCtx, AVMEDIA_TYPE_AUDIO);
    if AudioIdx < 0 then
    begin
      Result.AddPair('error', 'No audio stream');
      Exit;
    end;
    St := StreamAt(FmtCtx, AudioIdx);
    Dec := avcodec_find_decoder(St.codecpar.codec_id);
    CodecCtx := avcodec_alloc_context3(Dec);
    avcodec_parameters_to_context(CodecCtx, St.codecpar);
    avcodec_open2(CodecCtx, Dec, nil);
    Pkt := av_packet_alloc();
    Frame := av_frame_alloc();
    while av_read_frame(FmtCtx, Pkt) >= 0 do
    begin
      if Pkt.stream_index <> AudioIdx then
      begin
        av_packet_unref(Pkt);
        Continue;
      end;
      if avcodec_send_packet(CodecCtx, Pkt) >= 0 then
        while avcodec_receive_frame(CodecCtx, Frame) >= 0 do
        begin
          if Frame.pts <> AV_NOPTS_VALUE then
            PtsMs := Round(av_q2d(av_mul_q(av_make_q(Frame.pts, 1), St.time_base)) * 1000)
          else
            PtsMs := 0;
          SumSq := 0;
          N := 0;
          for Ch := 0 to Frame.ch_layout.nb_channels - 1 do
          begin
            P := PSmallInt(Frame.data[Ch]);
            for I := 0 to Frame.nb_samples - 1 do
            begin
              Sample := P^;
              Inc(P);
              SumSq := SumSq + (Sample / 32768.0) * (Sample / 32768.0);
              Inc(N);
            end;
          end;
          if N > 0 then
            Rms := Sqrt(SumSq / N)
          else
            Rms := 0;
          if Rms < Threshold then
          begin
            if not InSilence then
            begin
              InSilence := True;
              SilenceStartMs := PtsMs;
            end;
          end
          else if InSilence then
          begin
            if (PtsMs - SilenceStartMs) >= MinSilenceMs then
            begin
              SegItem := TJSONObject.Create;
              SegItem.AddPair('startMs', TJSONNumber.Create(SilenceStartMs));
              SegItem.AddPair('endMs', TJSONNumber.Create(PtsMs));
              Segments.Add(SegItem);
            end;
            InSilence := False;
          end;
        end;
      av_packet_unref(Pkt);
    end;
    Result.AddPair('status', 'success');
    Result.AddPair('silenceSegments', Segments);
    Result.AddPair('count', TJSONNumber.Create(Segments.Count));
  finally
    if Assigned(Pkt) then av_packet_free(Pkt);
    if Assigned(Frame) then av_frame_free(Frame);
    if Assigned(CodecCtx) then avcodec_free_context(CodecCtx);
    CloseInput(FmtCtx);
  end;
end;

class function TFFmpegHelpers.DetectScenes(const SourceUrl: string; Threshold: Double; MaxScenes: Integer): TJSONObject;
var
  FmtCtx: PAVFormatContext;
  Err: string;
  VideoIdx: Integer;
  CodecCtx: PAVCodecContext;
  Dec: PAVCodec;
  St: PAVStream;
  Pkt: PAVPacket;
  Frame, PrevGray, Gray: PAVFrame;
  ScaleCtx: PSwsContext;
  Scenes: TJSONArray;
  SceneItem: TJSONObject;
  Diff, MeanDiff: Double;
  I, X, Y, W, H, Step, Found: Integer;
  P1, P2: PByte;
  PtsMs: Integer;
  PixFmt: AVPixelFormat;
begin
  Result := TJSONObject.Create;
  if Threshold <= 0 then Threshold := 0.3;
  if MaxScenes <= 0 then MaxScenes := 20;
  if not OpenInput(SourceUrl, FmtCtx, Err) then
  begin
    Result.AddPair('error', Err);
    Exit;
  end;
  CodecCtx := nil;
  Pkt := nil;
  Frame := nil;
  Gray := nil;
  PrevGray := nil;
  ScaleCtx := nil;
  Scenes := TJSONArray.Create;
  Found := 0;
  W := 0;
  H := 0;
  try
    VideoIdx := FindBestStream(FmtCtx, AVMEDIA_TYPE_VIDEO);
    if VideoIdx < 0 then
    begin
      Result.AddPair('error', 'No video stream');
      Exit;
    end;
    St := StreamAt(FmtCtx, VideoIdx);
    Dec := avcodec_find_decoder(St.codecpar.codec_id);
    CodecCtx := avcodec_alloc_context3(Dec);
    avcodec_parameters_to_context(CodecCtx, St.codecpar);
    avcodec_open2(CodecCtx, Dec, nil);
    Frame := av_frame_alloc();
    Gray := av_frame_alloc();
    PrevGray := av_frame_alloc();
    Pkt := av_packet_alloc();
    Step := 1;
    if (St.avg_frame_rate.num > 0) and (St.avg_frame_rate.den > 0) then
    begin
      if (St.avg_frame_rate.num div St.avg_frame_rate.den) >= 10 then
        Step := Max(1, St.avg_frame_rate.num div (St.avg_frame_rate.den * 2));
    end
    else if (St.r_frame_rate.num > 0) and (St.r_frame_rate.den > 0) then
    begin
      if (St.r_frame_rate.num div St.r_frame_rate.den) >= 10 then
        Step := Max(1, St.r_frame_rate.num div (St.r_frame_rate.den * 2));
    end;
    I := 0;
    while (Found < MaxScenes) and (av_read_frame(FmtCtx, Pkt) >= 0) do
    begin
      if Pkt.stream_index <> VideoIdx then
      begin
        av_packet_unref(Pkt);
        Continue;
      end;
      if avcodec_send_packet(CodecCtx, Pkt) >= 0 then
        while (Found < MaxScenes) and (avcodec_receive_frame(CodecCtx, Frame) >= 0) do
        begin
          Inc(I);
          if (I mod Step) <> 0 then Continue;
          if W <= 0 then
          begin
            if not FramePixelSize(Frame, CodecCtx, St.codecpar, W, H) then
              Continue;
            if Frame.format >= 0 then
              PixFmt := AVPixelFormat(Frame.format)
            else if St.codecpar.format >= 0 then
              PixFmt := AVPixelFormat(St.codecpar.format)
            else
              PixFmt := AV_PIX_FMT_YUV420P;
            ScaleCtx := sws_getContext(W, H, PixFmt, W, H, AV_PIX_FMT_GRAY8, SWS_BICUBIC, nil, nil, nil);
            if not Assigned(ScaleCtx) then
              Continue;
            av_image_alloc(@Gray.data[0], @Gray.linesize[0], W, H, AV_PIX_FMT_GRAY8, 1);
            av_image_alloc(@PrevGray.data[0], @PrevGray.linesize[0], W, H, AV_PIX_FMT_GRAY8, 1);
          end;
          sws_scale(ScaleCtx, @Frame.data, @Frame.linesize, 0, H, @Gray.data, @Gray.linesize);
          if PrevGray.data[0] <> nil then
          begin
            MeanDiff := 0;
            for Y := 0 to H - 1 do
            begin
              P1 := PByte(NativeInt(PrevGray.data[0]) + PrevGray.linesize[0] * Y);
              P2 := PByte(NativeInt(Gray.data[0]) + Gray.linesize[0] * Y);
              for X := 0 to W - 1 do
              begin
                Diff := Abs(P1^ - P2^) / 255.0;
                MeanDiff := MeanDiff + Diff;
                Inc(P1);
                Inc(P2);
              end;
            end;
            MeanDiff := MeanDiff / (W * H);
            if MeanDiff >= Threshold then
            begin
              if Frame.pts <> AV_NOPTS_VALUE then
                PtsMs := Round(av_q2d(av_mul_q(av_make_q(Frame.pts, 1), St.time_base)) * 1000)
              else
                PtsMs := 0;
              SceneItem := TJSONObject.Create;
              SceneItem.AddPair('timeMs', TJSONNumber.Create(PtsMs));
              SceneItem.AddPair('score', TJSONNumber.Create(MeanDiff));
              Scenes.Add(SceneItem);
              Inc(Found);
            end;
          end;
          sws_scale(ScaleCtx, @Frame.data, @Frame.linesize, 0, H, @PrevGray.data, @PrevGray.linesize);
        end;
      av_packet_unref(Pkt);
    end;
    Result.AddPair('status', 'success');
    Result.AddPair('scenes', Scenes);
    Result.AddPair('count', TJSONNumber.Create(Scenes.Count));
  finally
    if Assigned(Pkt) then av_packet_free(Pkt);
    if Assigned(Frame) then av_frame_free(Frame);
    if Assigned(Gray) then
    begin
      if Assigned(Gray.data[0]) then av_freep(@Gray.data[0]);
      av_frame_free(Gray);
    end;
    if Assigned(PrevGray) then
    begin
      if Assigned(PrevGray.data[0]) then av_freep(@PrevGray.data[0]);
      av_frame_free(PrevGray);
    end;
    if Assigned(ScaleCtx) then sws_freeContext(ScaleCtx);
    if Assigned(CodecCtx) then avcodec_free_context(CodecCtx);
    CloseInput(FmtCtx);
  end;
end;

class function TFFmpegHelpers.ReadMetadata(const SourceUrl: string): TJSONObject;
var
  Info: TJSONObject;
  Err: string;
  MetaVal: TJSONValue;
begin
  Result := TJSONObject.Create;
  Info := TMediaInfo.ProbeSource(SourceUrl, Err);
  if Info = nil then
  begin
    Result.AddPair('error', Err);
    Exit;
  end;
  try
    if Info.TryGetValue<TJSONValue>('metadata', MetaVal) then
      Result.AddPair('metadata', MetaVal.Clone as TJSONValue)
    else
      Result.AddPair('metadata', TJSONArray.Create);
    Result.AddPair('status', 'success');
    Result.AddPair('sourceUrl', SourceUrl);
  finally
    Info.Free;
  end;
end;

end.

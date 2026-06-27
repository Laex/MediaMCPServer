unit uMCPRuntime;

interface

procedure ConfigureMediaLogging;

implementation

uses
  System.SysUtils, Winapi.Windows,
  libavutil;

var
  FFmpegLogHookInstalled: Boolean = False;

procedure SilentAvLog(p: Pointer; lvl: Integer; fmt: PAnsiChar; vl: PVA_LIST); cdecl;
begin
  // Suppress FFmpeg log output (keeps MCP stdio stdout clean).
end;

procedure MediaAvLogToStderr(p: Pointer; lvl: Integer; fmt: PAnsiChar; vl: PVA_LIST); cdecl;
var
  Line: array [0 .. 1023] of AnsiChar;
  PrintPrefix: Integer;
  Utf8: TBytes;
  Written: DWORD;
  Text: string;
begin
  PrintPrefix := 1;
  av_log_format_line(p, lvl, fmt, vl, @Line, SizeOf(Line), PrintPrefix);
  Text := Trim(string(AnsiString(Line)));
  if Text = '' then
    Exit;
  Utf8 := TEncoding.UTF8.GetBytes(Text + #10);
  if Length(Utf8) > 0 then
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), Utf8[0], Length(Utf8), Written, nil);
end;

procedure ConfigureMediaLogging;
begin
  if GetEnvironmentVariable('OPENCV_LOG_LEVEL') = '' then
    SetEnvironmentVariable('OPENCV_LOG_LEVEL', 'ERROR');

  if FFmpegLogHookInstalled then
    Exit;
  try
    av_log_set_level(AV_LOG_ERROR);
    if GetEnvironmentVariable('MEDIA_MCP_DEBUG') <> '' then
      av_log_set_callback(@MediaAvLogToStderr)
    else
      av_log_set_callback(@SilentAvLog);
    FFmpegLogHookInstalled := True;
  except
    // libavutil may be unavailable before runtime DLLs are deployed.
  end;
end;

end.

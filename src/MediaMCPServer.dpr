program MediaMCPServer;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uMCPConfig in 'uMCPConfig.pas',
  uMCPHandler in 'uMCPHandler.pas',
  uMCPHttpServer in 'uMCPHttpServer.pas',
  uMCPServer in 'uMCPServer.pas',
  uMediaEngine in 'uMediaEngine.pas',
  uONVIFTools in 'uONVIFTools.pas',
  uFFmpegProbe in 'uFFmpegProbe.pas',
  uFFmpegHelpers in 'uFFmpegHelpers.pas',
  uFFmpegTools in 'uFFmpegTools.pas',
  uOpenCVHelpers in 'uOpenCVHelpers.pas',
  uOpenCVTools in 'uOpenCVTools.pas',
  uOpenCVDnnTools in 'uOpenCVDnnTools.pas',
  uOpenCVImgTools in 'uOpenCVImgTools.pas',
  uOpenCVVideoTools in 'uOpenCVVideoTools.pas';

var
  Config: TMCPConfig;
  StdioServer: TMCPServer;
  HttpServer: TMCPHttpServer;

begin
  try
    // OpenCV TrackerNano and some DNN helpers resolve backbone.onnx relative to CWD.
    SetCurrentDir(ExtractFilePath(ParamStr(0)));
    Config := TMCPConfig.Load;
    if Config.Transport = mtHttp then
    begin
      HttpServer := TMCPHttpServer.Create(Config);
      try
        HttpServer.Run;
      finally
        HttpServer.Free;
      end;
    end
    else
    begin
      StdioServer := TMCPServer.Create;
      try
        StdioServer.Run;
      finally
        StdioServer.Free;
      end;
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'FATAL ERROR: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
end.

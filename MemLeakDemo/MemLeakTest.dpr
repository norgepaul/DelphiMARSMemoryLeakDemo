program MemLeakTest;

{$APPTYPE CONSOLE}

{$R *.res}

// The MARS_TEST is the only one which generates a meory leak and only on Linux.
// See the comments in MemLeak.Server.Resource for more info.
{$DEFINE MARS_TEST}
{.$DEFINE HTTP_SERVER_TEST}
{.$DEFINE THREAD_TEST}
{.$DEFINE NO_THREAD_TEST}
{.$DEFINE INDY_TEST}

// Adds a fix for the Linux AnsiCompareText bug - it does not fix this issue.
{.$DEFINE MEM_LEAK_FIX}

// When defined, MARS will use Delphi Cross Socket instead of Indy
{.$DEFINE USE_MARS_DCS}

uses
  System.Classes
  ,System.SysUtils
  ,System.Threading
  ,MemLeak.Utils in 'MemLeak.Utils.pas'
  ,MemLeak.Server.Resource in 'MemLeak.Server.Resource.pas'

{$IFDEF HTTP_SERVER_TEST}
  ,IdHTTPServer
  ,IdContext
  ,IdCustomHTTPServer
{$ENDIF}

{$IFDEF INDY_TEST}
  ,IdTask
  ,IdThread
{$ENDIF}

{$IFDEF MARS_TEST}
{$IFDEF USE_MARS_DCS}
  ,MARS.http.Server.DCS
{$ELSE}
  ,MARS.http.Server.Indy
{$ENDIF}
  ,MARS.Core.Engine
  ,MARS.Core.URL
  ,MARS.JOSEJWT.Token
  ,MARS.Core.RequestAndResponse.Interfaces
  ,MARS.Core.MessageBodyWriter
  ,MARS.Core.MessageBodyWriters
  ,MARS.Data.MessageBodyWriters
{$ENDIF}

{$IFDEF MEM_LEAK_FIX}
{$IFDEF LINUX64}
  ,System.Internal.ICU
{$ENDIF}
{$ENDIF}
;

{$IFDEF MEM_LEAK_FIX}
{$IFDEF LINUX64}
procedure __etp(ExitCode: Integer);
begin
  if IsICUAvailable then
    ClearCollatorCache;
end;
{$ENDIF}
{$ENDIF}

{$REGION 'Local test classes'}
{$IFDEF INDY_TEST}
type
  TTestTask = class(TIdTask)
  public
    function Run: boolean; override;
  end;

  function TTestTask.Run: boolean;
  var
    LList: TStringList;
  begin
    // This will execute repeatedly until the task is terminated.
    LList := TStringList.Create;
    try
      LList.Add('Foobar');
      sleep(100);
    finally
      FreeAndNil(LList);
    end;

    Writeln('TestTask.Run done');
    result := true;
  end;
{$ENDIF}

{$IFDEF HTTP_SERVER_TEST}
type
  TLeakHTTPServer = class(TIdHTTPServer)
  protected
    procedure DoCommandGet(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo); override;
  end;

procedure TLeakHTTPServer.DoCommandGet(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  S: TStringList;
begin
  inherited;

  S := TMemLeakUtils.CreateStringList;
  try
    sleep(3000);
  finally
    S.Free;
  end;
end;
{$ENDIF}
{$ENDREGION}

begin
{$IFDEF MEM_LEAK_FIX}
{$IFDEF LINUX64}
  EndThreadProc := __etp;
{$ENDIF}
{$ENDIF}

{$IFDEF MARS_TEST}
  var FMarsServer: {$IFDEF USE_MARS_DCS}TMARShttpServerDCS{$ELSE}TMARShttpServerIndy{$ENDIF};
  var FMarsEngine: TMARSEngine;

  FMarsEngine := TMARSEngine.Create;
  FMarsEngine.BasePath := '';
  FMarsServer := {$IFDEF USE_MARS_DCS}TMARShttpServerDCS{$ELSE}TMARShttpServerIndy{$ENDIF}.Create(FMarsEngine);
  FMarsEngine.AddApplication('MemLeakTest', '/rest', ['MemLeak.Server.*'], '');
  FMarsEngine.Port := 4000;
  FMarsEngine.BeforeHandleRequest :=
    function(const AEngine: TMARSEngine; const AURL: TMARSURL
    ; const ARequest: IMARSRequest;
       const AResponse: IMARSResponse; var Handled: Boolean): Boolean
    begin
      Result := True;

      if (SameText(AURL.Document, 'favicon.ico')) or
         (SameText(AURL.Document, 'robots.txt')) then
      begin
        Result := False;

        Handled := True;
      end;
    end;

  FMarsServer.DefaultPort := FMarsEngine.Port;
  FMarsServer.Active := True;
{$ENDIF}

{$REGION 'Additional local tests - none have memory leak'}
{$IFDEF HTTP_SERVER_TEST}
  var HTTPServer := TLeakHTTPServer.Create(nil);
  HTTPServer.DefaultPort := 4000;
  HTTPServer.Active := True;
{$ENDIF}

{$IFDEF THREAD_TEST}
  var Task: ITask;
  var i: Integer;
  for i := 1 to 10 do
  begin
    Writeln(format('Create %d', [i]));

    Task := TTask.Create(
      procedure
      var
        n: Integer;
        S: TStringList;
      begin
        S := TMemLeakUtils.CreateStringList;
        try
          sleep(3000);
        finally
          S.Free;
        end;
      end
    );
    Task.Start;

    sleep(10000);
  end;
{$ENDIF}

{$IFDEF NO_THREAD_TEST}
  var i, n: Integer;
  var S: TStringList;
  for i := 1 to 10 do
  begin
    Writeln(format('Create %d', [i]));

    S := TMemLeakUtils.CreateStringList;
    try
      sleep(3000);

      Writeln(format('Free %d', [i]));
    finally
      S.Free;
    end;

    sleep(2000);
  end;
{$ENDIF}
{$ENDREGION}

{$IFDEF INDY_TEST}
  ReportMemoryLeaksOnShutdown := true;

  //while true do
  begin
    Writeln('Started thread');

    var
      LThread := TIdThreadWithTask.Create(TTestTask.Create(nil), 'TestTask');
    try
      LThread.Start;
      sleep(1000);
      LThread.TerminateAndWaitFor;
    finally
      FreeAndNil(LThread);
    end;
  end;
{$ENDIF}

  Write('Press any key to quit');
  Readln;
end.

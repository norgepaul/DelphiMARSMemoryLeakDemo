program MemLeakTest;

{$APPTYPE CONSOLE}

{$R *.res}

// ThIS TEST generates a meory leak and only on Linux.
// See the comments in MemLeak.Server.Resource for more info.

// Adds a fix for the Linux AnsiCompareText bug - it does not fix this issue.
{.$DEFINE MEM_LEAK_FIX}

uses
  System.Classes
  ,System.SysUtils
  ,System.Threading
  ,MemLeak.Utils in 'MemLeak.Utils.pas'
  ,MemLeak.Server.Resource in 'MemLeak.Server.Resource.pas'
  ,MARS.http.Server.Indy
  ,MARS.Core.Engine
  ,MARS.Core.URL
  ,MARS.JOSEJWT.Token
  ,MARS.Core.RequestAndResponse.Interfaces
  ,MARS.Core.MessageBodyWriter
  ,MARS.Core.MessageBodyWriters
  ,MARS.Data.MessageBodyWriters
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

begin
{$IFDEF MEM_LEAK_FIX}
{$IFDEF LINUX64}
  EndThreadProc := __etp;
{$ENDIF}
{$ENDIF}

  var FMarsServer: TMARShttpServerIndy;
  var FMarsEngine: TMARSEngine;

  FMarsEngine := TMARSEngine.Create;
  FMarsEngine.BasePath := '';
  FMarsServer := TMARShttpServerIndy.Create(FMarsEngine);
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

  Write('Press any key to quit');
  Readln;
end.
